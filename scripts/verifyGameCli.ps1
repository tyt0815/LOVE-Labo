[CmdletBinding()]
param([string]$editorExecutable, [string]$loveDirectory = 'C:\Program Files\LOVE')
$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $editorExecutable) { $editorExecutable = Join-Path $taskRoot 'build/windows/Labo-cli.exe' }
$taskEditor = [IO.Path]::GetFullPath($editorExecutable)
$taskFolder = Join-Path $taskRoot ('build/verification-game-cli-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $taskFolder | Out-Null
$taskUtf8 = New-Object Text.UTF8Encoding($false)
$taskRequest = Join-Path $taskFolder 'request.json'
function Invoke-LaboRequest($request) {
    [IO.File]::WriteAllText($taskRequest, ($request | ConvertTo-Json -Depth 12), $taskUtf8)
    $taskResponse = & $taskEditor --cli --request $taskRequest
    if ($LASTEXITCODE -ne 0) { throw ($taskResponse -join "`n") }
    $taskDecoded = ($taskResponse -join "`n") | ConvertFrom-Json
    if (-not $taskDecoded.ok) { throw $taskDecoded.error }
    return $taskDecoded.result
}
$taskProject = Invoke-LaboRequest @{command = 'project.create'; parent = $taskFolder; name = 'CLI 게임 예제'}
$taskProjectPath = $taskProject.project
$taskExample = Invoke-LaboRequest @{command = 'project.examples-cli'; project = $taskProjectPath}
$taskProbe = Invoke-LaboRequest @{command = 'script.create'; project = $taskProjectPath; name = 'CliProbe'}
$taskProbeSource = @'
return {commands = {probe = {run = function()
    return {window = love.window and love.window.isOpen() or false, audio = love.audio ~= nil,
        editor = package.loaded["editor.EditorApp"] ~= nil, world = package.loaded["core.World"] ~= nil}
end}}}
'@
$null = Invoke-LaboRequest @{command = 'script.set-source'; project = $taskProjectPath; class = $taskProbe.assetId; source = $taskProbeSource}
$taskScriptPath = Join-Path $taskProjectPath 'Tools/Build.lua'
$taskScript = [IO.File]::ReadAllText($taskScriptPath)
$taskScript = $taskScript.Replace('    builder:packageGame()', '    builder:packageGame()' + "`n" + '    builder:packageCli("Probe.exe", {entry = "Assets/CliProbe.lua"})')
[IO.File]::WriteAllText($taskScriptPath, $taskScript, $taskUtf8)
$taskOutput = Join-Path $taskFolder 'Distribution/Game.love'
$taskBuild = Invoke-LaboRequest @{command = 'export'; project = $taskProjectPath; level = $taskExample.level; output = $taskOutput}
$taskDistribution = Split-Path -Parent $taskOutput
$taskCli = Join-Path $taskDistribution 'Game-cli.exe'
$taskContent = Join-Path $taskDistribution 'Content'
$taskProbeResult = (& (Join-Path $taskDistribution 'Probe.exe') probe | ConvertFrom-Json)
if ($LASTEXITCODE -ne 0 -or -not $taskProbeResult.ok) { throw 'Probe CLI failed' }
foreach ($taskFlag in @('window', 'audio', 'editor', 'world')) {
    if ($taskProbeResult.result.$taskFlag) { throw "CLI unexpectedly initialized $taskFlag" }
}
$taskSchema = (& $taskCli schema | ConvertFrom-Json)
if ($LASTEXITCODE -ne 0 -or -not $taskSchema.result.commands.add.parameters.lane) { throw 'Missing command schema' }
$taskAdded = (& $taskCli add --workspace $taskContent --beat 4 --lane 3 | ConvertFrom-Json)
if ($LASTEXITCODE -ne 0 -or $taskAdded.result.notes -ne 2) { throw 'CLI content mutation failed' }
$taskInvalid = (& $taskCli add --workspace $taskContent --beat 4 --lane 9 | ConvertFrom-Json)
if ($LASTEXITCODE -ne 1 -or $taskInvalid.ok) { throw 'Invalid command did not return failure exit code' }
$taskInspect = (& $taskCli inspect --workspace $taskContent | ConvertFrom-Json)
if ($LASTEXITCODE -ne 0 -or $taskInspect.result.data.notes.Count -ne 2) { throw 'Invalid command changed the content file' }
# 잘못된 호스트 옵션과 응답 저장 실패도 stdout JSON 계약을 유지한다.
[IO.File]::WriteAllText($taskRequest, '{"command":"help","result":true}', $taskUtf8)
$taskBadOption = (& $taskCli --request $taskRequest | ConvertFrom-Json)
if ($LASTEXITCODE -ne 1 -or $taskBadOption.ok -or -not $taskBadOption.error) { throw 'Invalid host option lost its JSON error response' }
$taskBadOutput = (& $taskCli help --result (Join-Path $taskFolder 'Missing/result.json') | ConvertFrom-Json)
if ($LASTEXITCODE -ne 1 -or $taskBadOutput.ok -or -not $taskBadOutput.error) { throw 'Response write failure lost its JSON error response' }
$taskEvents = Join-Path $taskFolder 'events.json'
[IO.File]::WriteAllText($taskEvents, '[{"name":"keypressed","args":["r","r",false],"dt":0},{"name":"keypressed","args":["left","left",false],"dt":0},{"name":"keypressed","args":["s","s",false],"dt":0}]', $taskUtf8)
$taskReport = Join-Path $taskFolder 'game.json'
$taskGame = Start-Process -FilePath (Join-Path $loveDirectory 'lovec.exe') -ArgumentList @(('"' + $taskOutput + '"'), '--workspace', ('"' + $taskContent + '"'), '--verify-game', ('"' + $taskReport + '"'), '--verify-events', ('"' + $taskEvents + '"')) -WindowStyle Hidden -PassThru
if (-not $taskGame.WaitForExit(60000)) { $taskGame.Kill(); throw 'Game verification timed out' }
$taskGameReport = Get-Content -LiteralPath $taskReport -Raw -Encoding UTF8 | ConvertFrom-Json
if ($taskGame.ExitCode -ne 0 -or -not $taskGameReport.ok -or $taskGameReport.editorLoaded) { throw 'Standalone game failed' }
$taskInspect = (& $taskCli inspect --workspace $taskContent | ConvertFrom-Json)
if ($LASTEXITCODE -ne 0 -or $taskInspect.result.data.notes[0].lane -ne 1) { throw 'Game editor and CLI did not share saved content' }
$taskSummary = @{ok = $true; probe = $taskProbeResult.result; commands = $taskSchema.result.commands; notes = $taskInspect.result.data.notes; build = $taskBuild}
[IO.File]::WriteAllText((Join-Path $taskFolder 'report.json'), ($taskSummary | ConvertTo-Json -Depth 12), $taskUtf8)
Write-Output "Verified game CLI, shared content editor, headless startup and failure exit code: $taskFolder/report.json"
