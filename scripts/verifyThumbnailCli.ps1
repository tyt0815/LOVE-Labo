[CmdletBinding()]
param([string]$loveDirectory = 'C:\Program Files\LOVE')
$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$taskExecutable = Join-Path $loveDirectory 'lovec.exe'
$taskDirectory = Join-Path $taskRoot ('build\thumbnail-cli-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $taskDirectory | Out-Null
$taskUtf8 = New-Object Text.UTF8Encoding($false)
function invokeThumbnailRequest($taskRequest) {
    $taskRequestPath = Join-Path $taskDirectory 'request.json'
    [IO.File]::WriteAllText($taskRequestPath, ($taskRequest | ConvertTo-Json -Depth 12), $taskUtf8)
    $taskResponseText = & $taskExecutable (Join-Path $taskRoot 'src') --cli --request $taskRequestPath
    $taskResponse = ($taskResponseText -join "`n") | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or -not $taskResponse.ok) { throw $taskResponse.error }
    return $taskResponse.result
}
$taskProject = (invokeThumbnailRequest @{command = 'project.create'; parent = $taskDirectory; name = 'ThumbnailGame'}).project
$taskScript = invokeThumbnailRequest @{command = 'script.create'; project = $taskProject; name = 'Visual'}
$taskSource = @'
local Visual = {properties = {width = {type = "number", default = 20}}}
function Visual.load() error("Thumbnail must not run load") end
function Visual.update() error("Thumbnail must not run update") end
function Visual.getLocalBounds(self) return -self.width / 2, -10, self.width, 20 end
function Visual.draw(self) love.graphics.setColor(1, 0, 0, 1); love.graphics.rectangle("fill", -self.width / 2, -10, self.width, 20) end
return Visual
'@
invokeThumbnailRequest @{command = 'script.set-source'; project = $taskProject; script = $taskScript.assetId; source = $taskSource} | Out-Null
$taskPrefab = invokeThumbnailRequest @{command = 'prefab.create'; project = $taskProject; name = 'PF_Visual'}
# 저장 API를 거치지 않고 외부 도구가 작성한 새 Prefab을 재현한다.
$taskPrefabPath = Join-Path $taskProject 'Assets\PF_Visual.prefab'
$taskData = @{formatVersion = 4; scripts = @(@{id = [guid]::NewGuid().ToString(); name = 'Visual'; source = $taskScript.assetId}); overrides = @{}}
[IO.File]::WriteAllText($taskPrefabPath, ($taskData | ConvertTo-Json -Depth 12), $taskUtf8)
$taskFirst = invokeThumbnailRequest @{command = 'asset.thumbnail'; project = $taskProject; asset = $taskPrefab.assetId}
if (-not $taskFirst.generated -or $taskFirst.lifecycleExecuted -or -not (Test-Path -LiteralPath $taskFirst.output)) { throw 'Missing-cache thumbnail generation failed' }
$taskSecond = invokeThumbnailRequest @{command = 'asset.thumbnail'; project = $taskProject; asset = $taskPrefab.assetId}
if ($taskSecond.generated -or $taskSecond.lifecycleExecuted) { throw 'Thumbnail cache reuse failed' }
invokeThumbnailRequest @{command = 'script.set-source'; project = $taskProject; script = $taskScript.assetId; source = $taskSource.Replace('default = 20', 'default = 40')} | Out-Null
$taskChanged = invokeThumbnailRequest @{command = 'asset.thumbnail'; project = $taskProject; asset = $taskPrefab.assetId}
if (-not $taskChanged.generated -or $taskChanged.lifecycleExecuted) { throw 'Stale-cache thumbnail generation failed' }
$taskPreview = invokeThumbnailRequest @{command = 'asset.preview'; project = $taskProject; asset = $taskPrefab.assetId; output = (Join-Path $taskDirectory 'preview.png')}
if ($taskPreview.lifecycleExecuted -or -not (Test-Path -LiteralPath $taskPreview.output)) { throw 'CLI preview graphics initialization failed' }
# 이미지 에셋도 Preview.new에서 그래픽 컨텍스트가 필요하다.
$taskImage = invokeThumbnailRequest @{command = 'asset.import'; project = $taskProject; input = $taskPreview.output; folder = 'Assets'}
$taskImagePreview = invokeThumbnailRequest @{command = 'asset.preview'; project = $taskProject; asset = $taskImage.assetId; output = (Join-Path $taskDirectory 'image-preview.png')}
if (-not (Test-Path -LiteralPath $taskImagePreview.output)) { throw 'CLI image preview failed' }
Write-Output "Missing/stale thumbnail generation, reuse and Prefab/image previews verified in separate CLI processes: $taskDirectory"
