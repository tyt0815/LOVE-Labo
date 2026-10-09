[CmdletBinding()]
param([string]$loveDirectory = 'C:\Program Files\LOVE')
$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
& (Join-Path $PSScriptRoot 'packageEditor.ps1') -loveDirectory $loveDirectory -verify
$taskDirectory = Join-Path $taskRoot ('build\cli-export-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $taskDirectory | Out-Null
$taskCli = Join-Path $taskRoot 'build\windows\Labo-cli.exe'
$taskUtf8 = New-Object Text.UTF8Encoding($false)
function invokeLaboRequest($taskRequest) {
    $taskRequestPath = Join-Path $taskDirectory 'request.json'
    [IO.File]::WriteAllText($taskRequestPath, ($taskRequest | ConvertTo-Json -Depth 8), $taskUtf8)
    $taskResponseText = & $taskCli --cli --request $taskRequestPath
    $taskResponse = ($taskResponseText -join "`n") | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or -not $taskResponse.ok) { throw $taskResponse.error }
    return $taskResponse.result
}
$taskCreated = invokeLaboRequest @{command = 'project.create'; parent = $taskDirectory; name = 'AgentGame'}
$taskProject = $taskCreated.project
$taskComponent = invokeLaboRequest @{command = 'class.create'; project = $taskProject; name = 'Visual'; parent = 'SpriteComponent'}
$taskComponentCode = @'
-- labo-script: component
local Visual = {extends = "SpriteComponent", properties = {strength = {type = "number", default = 5, group = "Appearance"}}}
function Visual.beginPlay(self) self.owner.properties.componentBegun = true end
function Visual.update(self, dt) self.owner.properties.componentTicks = (self.owner.properties.componentTicks or 0) + 1 end
return Visual
'@
[IO.File]::WriteAllText((Join-Path $taskProject 'Sources\Visual.lua'), $taskComponentCode, $taskUtf8)
$taskChildComponent = invokeLaboRequest @{command = 'class.create'; project = $taskProject; name = 'ChildVisual'; parent = $taskComponent.assetId}
$taskShape = invokeLaboRequest @{command = 'class.create'; project = $taskProject; name = 'Shape'; parent = 'RenderComponent'}
$taskShapeCode = @'
-- labo-script: component
local Shape = {extends = "RenderComponent"}
function Shape.draw(self, context)
    self.owner.properties.customDrawCalled = true
    love.graphics.setColor(1, 0.5, 0.2, 1); love.graphics.rectangle("fill", -5, -5, 10, 10)
end
function Shape.getLocalBounds(self) return -5, -5, 10, 10 end
return Shape
'@
[IO.File]::WriteAllText((Join-Path $taskProject 'Sources\Shape.lua'), $taskShapeCode, $taskUtf8)
$taskClass = invokeLaboRequest @{command = 'class.create'; project = $taskProject; name = 'NewClass'; type = 'lobject'}
# 생성은 CLI로, 게임 동작 코드는 에이전트와 동일하게 프로젝트 소스에 작성한다.
$taskCode = @'
-- labo-script: lobject
local Engine = require("Engine")
local NewClass = {properties = {
    speed = {type = "number", default = 10},
    enabled = {type = "boolean", default = true},
    title = {type = "string", default = "Agent"},
    target = {type = "object", default = false},
    projectile = {type = "prefab", default = false}
}}
function NewClass.build(self)
    local mount = self:addComponent("mount", Engine.SceneComponent, {x = 10})
    mount:addComponent("sprite", "__COMPONENT_ID__", {y = 3})
    mount:addComponent("shape", "__SHAPE_ID__", {x = 25, rotation = 45, scaleX = 2})
end
function NewClass.beginPlay(self, world)
    self.properties.started = true
    if self.properties.projectile ~= false then
        self.spawned = assert(world:spawnLObject(self.properties.projectile, {x = 20, y = 30}))
    end
end
function NewClass.update(self, dt) self.properties.ticks = (self.properties.ticks or 0) + 1 end
return NewClass
'@
$taskCode = $taskCode.Replace('__COMPONENT_ID__', $taskChildComponent.assetId)
$taskCode = $taskCode.Replace('__SHAPE_ID__', $taskShape.assetId)
[IO.File]::WriteAllText((Join-Path $taskProject 'Sources\NewClass.lua'), $taskCode, $taskUtf8)
Add-Type -AssemblyName System.Drawing
$taskBitmap = New-Object Drawing.Bitmap(16, 16)
$taskGraphics = [Drawing.Graphics]::FromImage($taskBitmap)
try {
    $taskGraphics.Clear([Drawing.Color]::CornflowerBlue)
    $taskBitmap.Save((Join-Path $taskProject 'Assets\Sprite.png'), [Drawing.Imaging.ImageFormat]::Png)
} finally { $taskGraphics.Dispose(); $taskBitmap.Dispose() }
$taskPrefab = invokeLaboRequest @{command = 'prefab.create'; project = $taskProject; name = 'NewPrefab'; class = $taskClass.assetId}
$taskInfo = invokeLaboRequest @{command = 'project.info'; project = $taskProject}
$taskImage = $taskInfo.assets.'Assets/Sprite.png'.id
invokeLaboRequest @{command = 'prefab.set'; project = $taskProject; prefab = $taskPrefab.assetId; property = 'sprite.image'; value = $taskImage} | Out-Null
$taskChildClass = invokeLaboRequest @{command = 'class.create'; project = $taskProject; name = 'ChildClass'; parent = $taskClass.assetId}
$taskChildPrefab = invokeLaboRequest @{command = 'prefab.create'; project = $taskProject; name = 'ChildPrefab'; class = $taskPrefab.assetId}
invokeLaboRequest @{command = 'prefab.set'; project = $taskProject; prefab = $taskChildPrefab.assetId; property = 'speed'; value = 25} | Out-Null
$taskInherited = invokeLaboRequest @{command = 'prefab.get'; project = $taskProject; prefab = $taskChildPrefab.assetId}
if ($taskInherited.values.speed -ne 25 -or $taskInherited.values.'sprite.image' -ne $taskImage) { throw 'Prefab inheritance does not preserve parent values' }
$taskLevelClass = invokeLaboRequest @{command = 'class.create'; project = $taskProject; name = 'NewLevel'; type = 'level'}
$taskLevel = invokeLaboRequest @{command = 'level.create'; project = $taskProject; name = 'NewLevel'; class = $taskLevelClass.assetId}
invokeLaboRequest @{command = 'project.set-default'; project = $taskProject; level = $taskLevel.assetId} | Out-Null
$taskFirst = invokeLaboRequest @{command = 'instance.add'; project = $taskProject; prefab = $taskPrefab.assetId; x = 100; y = 200}
$taskSecond = invokeLaboRequest @{command = 'instance.add'; project = $taskProject; prefab = $taskChildPrefab.assetId; x = -100; y = -200}
$taskId = $taskFirst.data.authoringId
if ($taskFirst.data.name -ne 'NewPrefab 1') { throw 'Prefab instance name was not assigned' }
$taskParented = invokeLaboRequest @{command = 'instance.reparent'; project = $taskProject; instance = $taskSecond.data.authoringId; parent = $taskId}
if ($taskParented.data.parentAuthoringId -ne $taskId) { throw 'Cli object parenting failed' }
invokeLaboRequest @{command = 'instance.set'; project = $taskProject; instance = $taskId; property = 'speed'; value = 42} | Out-Null
invokeLaboRequest @{command = 'instance.set'; project = $taskProject; instance = $taskId; property = 'enabled'; value = $false} | Out-Null
invokeLaboRequest @{command = 'instance.set'; project = $taskProject; instance = $taskId; property = 'title'; value = 'Cli game'} | Out-Null
invokeLaboRequest @{command = 'instance.set'; project = $taskProject; instance = $taskId; property = 'target'; value = $taskSecond.data.authoringId} | Out-Null
invokeLaboRequest @{command = 'instance.set'; project = $taskProject; instance = $taskId; property = 'projectile'; value = $taskChildPrefab.assetId} | Out-Null
invokeLaboRequest @{command = 'instance.set'; project = $taskProject; instance = $taskId; property = 'sprite.x'; value = 11} | Out-Null
$taskGamePath = Join-Path $taskDirectory 'Game.love'
invokeLaboRequest @{command = 'export'; project = $taskProject; output = $taskGamePath} | Out-Null
$taskGameReportPath = Join-Path $taskDirectory 'game-report.json'
$taskGameProcess = Start-Process -FilePath (Join-Path $loveDirectory 'lovec.exe') `
    -ArgumentList @(('"' + $taskGamePath + '"'), '--verify-game', ('"' + $taskGameReportPath + '"')) `
    -WorkingDirectory $taskDirectory -WindowStyle Hidden -PassThru
if (-not $taskGameProcess.WaitForExit(60000)) { $taskGameProcess.Kill(); throw 'Exported game verification timed out' }
$taskGameReport = Get-Content -LiteralPath $taskGameReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($taskGameProcess.ExitCode -ne 0 -or -not $taskGameReport.ok -or $taskGameReport.editorLoaded) { throw "Exported game failed: $($taskGameReport.error)" }
if ($taskGameReport.objects -ne 3 -or $taskGameReport.properties[0].speed -ne 42 -or $taskGameReport.properties[0].enabled -ne $false `
    -or -not $taskGameReport.properties[0].started -or $taskGameReport.properties[0].ticks -ne 1 `
    -or -not $taskGameReport.properties[0].componentBegun -or $taskGameReport.properties[0].componentTicks -ne 1 `
    -or -not $taskGameReport.properties[0].customDrawCalled `
    -or $taskGameReport.properties[0].target.instance -ne $taskSecond.data.authoringId `
    -or $taskGameReport.properties[1].speed -ne 25 -or $taskGameReport.properties[2].speed -ne 25 `
    -or -not $taskGameReport.properties[2].started -or $taskGameReport.properties[2].ticks -ne 1) { throw 'Exported game state does not match Cli edits' }
Add-Type -AssemblyName System.IO.Compression.FileSystem
$taskArchive = [IO.Compression.ZipFile]::OpenRead($taskGamePath)
try {
    if (@($taskArchive.Entries | Where-Object { $_.FullName -match '^(editor|tests)/' }).Count) { throw 'Editor or test code included in game export' }
} finally { $taskArchive.Dispose() }
# 시작·update·이미지 디코딩 실패도 프로세스 크래시 대신 진단 결과를 반환한다.
$taskImagePath = Join-Path $taskProject 'Assets\Sprite.png'
$taskOriginalImage = [IO.File]::ReadAllBytes($taskImagePath)
try {
    foreach ($taskFailure in @('beginPlay', 'update', 'Render')) {
        [IO.File]::WriteAllText((Join-Path $taskProject 'Sources\NewClass.lua'), $taskCode, $taskUtf8)
        [IO.File]::WriteAllBytes($taskImagePath, $taskOriginalImage)
        if ($taskFailure -eq 'beginPlay') {
            $taskBrokenCode = $taskCode.Replace('self.properties.started = true', 'error("expected beginPlay failure")')
            [IO.File]::WriteAllText((Join-Path $taskProject 'Sources\NewClass.lua'), $taskBrokenCode, $taskUtf8)
        } elseif ($taskFailure -eq 'update') {
            $taskBrokenCode = $taskCode.Replace('self.properties.ticks = (self.properties.ticks or 0) + 1', 'error("expected update failure")')
            [IO.File]::WriteAllText((Join-Path $taskProject 'Sources\NewClass.lua'), $taskBrokenCode, $taskUtf8)
        } else { [IO.File]::WriteAllText($taskImagePath, 'invalid image bytes', $taskUtf8) }
        $taskFailureGame = Join-Path $taskDirectory ($taskFailure + '.love')
        invokeLaboRequest @{command = 'export'; project = $taskProject; output = $taskFailureGame} | Out-Null
        $taskFailureReport = Join-Path $taskDirectory ($taskFailure + '-report.json')
        $taskFailedProcess = Start-Process -FilePath (Join-Path $loveDirectory 'lovec.exe') `
            -ArgumentList @(('"' + $taskFailureGame + '"'), '--verify-game', ('"' + $taskFailureReport + '"')) `
            -WorkingDirectory $taskDirectory -WindowStyle Hidden -PassThru
        if (-not $taskFailedProcess.WaitForExit(60000)) { $taskFailedProcess.Kill(); throw "$taskFailure containment timed out" }
        $taskFailedResult = Get-Content -LiteralPath $taskFailureReport -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($taskFailedProcess.ExitCode -ne 1 -or $taskFailedResult.ok -or -not $taskFailedResult.error) { throw "$taskFailure was not contained" }
    }
} finally {
    [IO.File]::WriteAllText((Join-Path $taskProject 'Sources\NewClass.lua'), $taskCode, $taskUtf8)
    [IO.File]::WriteAllBytes($taskImagePath, $taskOriginalImage)
}
# 패키지 안의 다른 레벨을 ID로 읽고 update 프레임 종료 후 World를 교체한다.
$taskNextLevel = invokeLaboRequest @{command = 'level.create'; project = $taskProject; name = 'L_Next'}
invokeLaboRequest @{command = 'instance.add'; project = $taskProject; level = $taskNextLevel.assetId; prefab = $taskChildPrefab.assetId; x = 300; y = 400} | Out-Null
$taskTransitionCode = @'
local NewLevel = {}
function NewLevel.update(self, dt)
    assert(self:openLevel("__LEVEL_ID__"))
end
return NewLevel
'@
[IO.File]::WriteAllText((Join-Path $taskProject 'Sources\NewLevel.lua'), $taskTransitionCode.Replace('__LEVEL_ID__', $taskNextLevel.assetId), $taskUtf8)
$taskTransitionGame = Join-Path $taskDirectory 'Transition.love'
invokeLaboRequest @{command = 'export'; project = $taskProject; output = $taskTransitionGame} | Out-Null
$taskTransitionReportPath = Join-Path $taskDirectory 'transition-report.json'
$taskTransitionProcess = Start-Process -FilePath (Join-Path $loveDirectory 'lovec.exe') `
    -ArgumentList @(('"' + $taskTransitionGame + '"'), '--verify-game', ('"' + $taskTransitionReportPath + '"')) `
    -WorkingDirectory $taskDirectory -WindowStyle Hidden -PassThru
if (-not $taskTransitionProcess.WaitForExit(60000)) { $taskTransitionProcess.Kill(); throw 'Level transition verification timed out' }
$taskTransitionReport = Get-Content -LiteralPath $taskTransitionReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($taskTransitionProcess.ExitCode -ne 0 -or -not $taskTransitionReport.ok -or $taskTransitionReport.editorLoaded `
    -or $taskTransitionReport.levelReference -ne $taskNextLevel.assetId -or $taskTransitionReport.objects -ne 1 `
    -or $taskTransitionReport.properties[0].speed -ne 25 -or -not $taskTransitionReport.properties[0].started) {
    throw 'Standalone game level transition failed'
}
Write-Output "Cli creation, editing, hierarchy, references, Export and level transition verified: $taskDirectory"
