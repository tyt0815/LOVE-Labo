[CmdletBinding(SupportsShouldProcess = $true)]
param([switch]$Apply, [string[]]$Keep = @())
$ErrorActionPreference = 'Stop'
$cleanupRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../build'))
if (-not (Test-Path -LiteralPath $cleanupRoot)) { return }
if ((Get-Item -LiteralPath $cleanupRoot -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'build must not be a link' }
$cleanupPrefix = $cleanupRoot.TrimEnd('\') + '\'
$cleanupTests = '^(AttachedTest_Build|AttachedTest_Architecture|AttachedTest_PlayTools|AttachedTest_Review|AttachedTest_Conditions|AttachedTest|Scopes|CatalogTest|PluginTest|PreviewTest_Boundaries|PreviewTest|DebugTest|AssetPlacement|Lifecycle|PublicUi|BrowserReadOnly|Browser|BrowserMode|Rendering|CreateFailure|CodeEditor|PauseTest|LegacyView|Identity)(?:_\d+)+$'
$cleanupArtifacts = '^(game-cli|build-cli|verification|guide|public|camera|ui|script|order|api|review|create|cli-export|carry|save|identity|window|session)-'
# 이전 버전 관리 작업에서 생성한 이름만 허용하고 같은 이름의 폴더는 제외한다.
$cleanupFiles = '^(version-tests\.log|version-docs\.log|version-packaged\.json|version-cleanup-preview\.log|commit-package-cleanup\.patch)$'
$cleanupCount = 0
foreach ($cleanupEntry in Get-ChildItem -LiteralPath $cleanupRoot -Force) {
    if ($cleanupEntry.Name -notmatch $cleanupTests -and $cleanupEntry.Name -notmatch $cleanupArtifacts -and
        ($cleanupEntry.PSIsContainer -or $cleanupEntry.Name -notmatch $cleanupFiles)) { continue }
    if ($Keep -contains $cleanupEntry.Name -or $cleanupEntry.Name -eq 'verification-latest') { continue }
    $cleanupPath = [IO.Path]::GetFullPath($cleanupEntry.FullName)
    if (-not $cleanupPath.StartsWith($cleanupPrefix, [StringComparison]::OrdinalIgnoreCase) -or
        [IO.Path]::GetDirectoryName($cleanupPath) -ne $cleanupRoot) { throw "Unsafe cleanup target: $cleanupPath" }
    # 재귀 삭제 전에 하위 링크도 거절해 링크 대상의 사용자 데이터로 진행하지 않는다.
    if ($cleanupEntry.Attributes -band [IO.FileAttributes]::ReparsePoint) { Write-Warning "Skipped link: $cleanupPath"; continue }
    if ($cleanupEntry.PSIsContainer) {
        $cleanupPending = New-Object 'System.Collections.Generic.Stack[string]'
        $cleanupPending.Push($cleanupPath)
        $cleanupHasLink = $false
        while ($cleanupPending.Count -gt 0 -and -not $cleanupHasLink) {
            foreach ($cleanupChild in Get-ChildItem -LiteralPath $cleanupPending.Pop() -Force) {
                if ($cleanupChild.Attributes -band [IO.FileAttributes]::ReparsePoint) { $cleanupHasLink = $true; break }
                if ($cleanupChild.PSIsContainer) { $cleanupPending.Push($cleanupChild.FullName) }
            }
        }
        if ($cleanupHasLink) { Write-Warning "Skipped directory containing links: $cleanupPath"; continue }
    }
    $cleanupCount++
    if ($Apply) {
        if ($PSCmdlet.ShouldProcess($cleanupPath, 'Remove generated build artifact')) { Remove-Item -LiteralPath $cleanupPath -Recurse -Force }
    } else { Write-Output $cleanupPath }
}
Write-Output "Generated artifacts selected: $cleanupCount; applied: $Apply"
