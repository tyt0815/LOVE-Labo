[CmdletBinding()]
param(
    [string]$loveDirectory = 'C:\Program Files\LOVE',
    [string]$outputDirectory,
    [switch]$verify
)

$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$taskSource = Join-Path $taskRoot 'src'
if (-not $outputDirectory) { $outputDirectory = Join-Path $taskRoot 'build\windows' }
$taskOutput = [IO.Path]::GetFullPath($outputDirectory)
$taskLove = [IO.Path]::GetFullPath($loveDirectory)
if ($taskOutput -eq $taskRoot -or $taskRoot.StartsWith($taskOutput.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'OutputDirectory must not be the repository root or its parent.'
}
foreach ($taskRequired in @('love.exe', 'lovec.exe', 'love.dll', 'lua51.dll', 'license.txt')) {
    if (-not (Test-Path -LiteralPath (Join-Path $taskLove $taskRequired) -PathType Leaf)) {
        throw "Missing LÖVE runtime file: $taskRequired"
    }
}
$taskVersion = (Get-Item -LiteralPath (Join-Path $taskLove 'love.exe')).VersionInfo.ProductVersion
if ($taskVersion -ne '11.5') { throw "LÖVE 11.5 is required; found: $taskVersion" }
New-Item -ItemType Directory -Path $taskOutput -Force | Out-Null
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

# 배포 대상 목록을 명시하여 테스트·샘플 프로젝트·문서를 제외한다.
$taskFiles = @('main.lua', 'conf.lua', 'Engine.lua')
foreach ($taskFolder in @('core', 'editor', 'project', 'runtime')) {
    $taskFiles += Get-ChildItem -LiteralPath (Join-Path $taskSource $taskFolder) -Recurse -File -Filter '*.lua' |
        ForEach-Object { $_.FullName.Substring($taskSource.Length + 1).Replace('\', '/') }
}
$taskFiles += @('editor/fonts/NanumSquareRoundR.ttf', 'editor/fonts/NanumSquareRoundB.ttf', 'editor/fonts/OFL.txt')
$taskArchivePath = Join-Path $taskOutput 'Labo.love'
$taskTemporaryArchive = Join-Path $taskOutput ('archive-' + [guid]::NewGuid().ToString('N') + '.tmp')
$taskArchive = [IO.Compression.ZipFile]::Open($taskTemporaryArchive, [IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($taskRelative in ($taskFiles | Sort-Object -Unique)) {
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($taskArchive,
            (Join-Path $taskSource $taskRelative), $taskRelative, [IO.Compression.CompressionLevel]::Optimal) | Out-Null
    }
} finally { $taskArchive.Dispose() }
Move-Item -LiteralPath $taskTemporaryArchive -Destination $taskArchivePath -Force

# 셸의 문자열 변환 없이 실행 파일과 ZIP을 바이트 스트림으로 결합한다.
foreach ($taskLauncher in @(@('love.exe', 'Labo.exe'), @('lovec.exe', 'Labo-cli.exe'))) {
    $taskStream = [IO.File]::Create((Join-Path $taskOutput $taskLauncher[1]))
    try {
        foreach ($taskPart in @((Join-Path $taskLove $taskLauncher[0]), $taskArchivePath)) {
            $taskInput = [IO.File]::OpenRead($taskPart)
            try { $taskInput.CopyTo($taskStream) } finally { $taskInput.Dispose() }
        }
    } finally { $taskStream.Dispose() }
}
$taskExecutable = Join-Path $taskOutput 'Labo.exe'
Get-ChildItem -LiteralPath $taskLove -Filter '*.dll' -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $taskOutput $_.Name) -Force
}
Copy-Item -LiteralPath (Join-Path $taskLove 'license.txt') -Destination (Join-Path $taskOutput 'license-love.txt') -Force
Copy-Item -LiteralPath (Join-Path $taskSource 'editor/fonts/OFL.txt') -Destination (Join-Path $taskOutput 'license-fonts.txt') -Force

# 다시 패키징해도 사용자가 수정한 설정·테마는 덮어쓰지 않는다.
$taskSettings = Join-Path $taskOutput 'settings.json'
if (-not (Test-Path -LiteralPath $taskSettings)) {
    Copy-Item -LiteralPath (Join-Path $taskSource 'editor/settings.json') -Destination $taskSettings
}
$taskThemes = Join-Path $taskOutput 'themes'
New-Item -ItemType Directory -Path $taskThemes -Force | Out-Null
Get-ChildItem -LiteralPath (Join-Path $taskSource 'editor/themes') -Filter '*.json' -File | ForEach-Object {
    $taskThemePath = Join-Path $taskThemes $_.Name
    if (-not (Test-Path -LiteralPath $taskThemePath)) { Copy-Item -LiteralPath $_.FullName -Destination $taskThemePath }
}

$taskManifest = @{ version = 1; loveVersion = '11.5'; files = @($taskFiles | Sort-Object -Unique); executable = 'Labo.exe' }
$taskUtf8 = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText((Join-Path $taskOutput 'package-manifest.json'), ($taskManifest | ConvertTo-Json -Depth 4), $taskUtf8)
Write-Output "Packaged: $taskExecutable"

if ($verify) {
    $taskVerification = Join-Path (Split-Path -Parent $taskOutput) ('verification-' + [guid]::NewGuid().ToString('N'))
    $taskProcess = Start-Process -FilePath $taskExecutable -ArgumentList @('--verify-package', ('"' + $taskVerification + '"')) `
        -WorkingDirectory (Split-Path -Parent $taskOutput) -WindowStyle Hidden -PassThru
    if (-not $taskProcess.WaitForExit(60000)) {
        $taskProcess.Kill()
        throw 'Package verification timed out after 60 seconds.'
    }
    $taskReportPath = Join-Path $taskVerification 'report.json'
    if (-not (Test-Path -LiteralPath $taskReportPath)) { throw "Verification did not produce a report: $taskReportPath" }
    $taskReport = Get-Content -LiteralPath $taskReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($taskProcess.ExitCode -ne 0 -or -not $taskReport.ok) { throw "Package verification failed: $($taskReport.error)" }
    Write-Output "Verified $($taskReport.checks.Count) checks: $taskReportPath"
}
