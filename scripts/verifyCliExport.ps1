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
    projectile = {type = "lobjectTemplate", default = false}
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
$taskLevel = invokeLaboRequest @{command = 'level.create'; empty = $true; project = $taskProject; name = 'NewLevel'; class = $taskLevelClass.assetId}
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
invokeLaboRequest @{command = 'instance.set'; project = $taskProject; instance = $taskId; property = 'projectile'; value = $taskClass.assetId} | Out-Null
$taskLuaGamePath = Join-Path $taskDirectory 'LuaTemplate.love'
invokeLaboRequest @{command = 'export'; project = $taskProject; output = $taskLuaGamePath} | Out-Null
$taskLuaReportPath = Join-Path $taskDirectory 'lua-template-report.json'
$taskLuaProcess = Start-Process -FilePath (Join-Path $loveDirectory 'lovec.exe') `
    -ArgumentList @(('"' + $taskLuaGamePath + '"'), '--verify-game', ('"' + $taskLuaReportPath + '"')) `
    -WorkingDirectory $taskDirectory -WindowStyle Hidden -PassThru
if (-not $taskLuaProcess.WaitForExit(60000)) { $taskLuaProcess.Kill(); throw 'Lua template verification timed out' }
$taskLuaReport = Get-Content -LiteralPath $taskLuaReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($taskLuaProcess.ExitCode -ne 0 -or -not $taskLuaReport.ok -or $taskLuaReport.editorLoaded `
    -or $taskLuaReport.objects -ne 3 -or $taskLuaReport.properties[2].speed -ne 10 `
    -or -not $taskLuaReport.properties[2].started) { throw 'Standalone Lua template spawn failed' }
invokeLaboRequest @{command = 'instance.set'; project = $taskProject; instance = $taskId; property = 'projectile'; value = $taskChildPrefab.assetId} | Out-Null
# 레벨 오브젝트의 자손과 내부 참조를 캡처하여 별도 레벨·독립 게임에서도 복원한다.
invokeLaboRequest @{command = 'instance.set'; project = $taskProject; instance = $taskId; property = 'projectile'; value = $false} | Out-Null
$taskHierarchyPrefab = invokeLaboRequest @{command = 'prefab.create'; project = $taskProject; name = 'PF_Hierarchy'; instance = $taskId}
$taskHierarchyLevel = invokeLaboRequest @{command = 'level.create'; empty = $true; project = $taskProject; name = 'L_Hierarchy'}
$taskHierarchyRoot = invokeLaboRequest @{command = 'instance.add'; project = $taskProject; level = $taskHierarchyLevel.assetId; prefab = $taskHierarchyPrefab.assetId; x = 300; y = 400}
$taskHierarchyData = invokeLaboRequest @{command = 'level.get'; project = $taskProject; level = $taskHierarchyLevel.assetId}
if ($taskHierarchyData.data.lobjects.Count -ne 2 -or $taskHierarchyData.data.lobjects[1].parentAuthoringId -ne $taskHierarchyRoot.data.authoringId) { throw 'Cli hierarchy materialization failed' }
$taskHierarchyGamePath = Join-Path $taskDirectory 'Hierarchy.love'
invokeLaboRequest @{command = 'export'; project = $taskProject; level = $taskHierarchyLevel.assetId; output = $taskHierarchyGamePath} | Out-Null
$taskHierarchyReportPath = Join-Path $taskDirectory 'hierarchy-report.json'
$taskHierarchyProcess = Start-Process -FilePath (Join-Path $loveDirectory 'lovec.exe') `
    -ArgumentList @(('"' + $taskHierarchyGamePath + '"'), '--verify-game', ('"' + $taskHierarchyReportPath + '"')) `
    -WorkingDirectory $taskDirectory -WindowStyle Hidden -PassThru
if (-not $taskHierarchyProcess.WaitForExit(60000)) { $taskHierarchyProcess.Kill(); throw 'Hierarchy verification timed out' }
$taskHierarchyReport = Get-Content -LiteralPath $taskHierarchyReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($taskHierarchyProcess.ExitCode -ne 0 -or -not $taskHierarchyReport.ok -or $taskHierarchyReport.editorLoaded `
    -or $taskHierarchyReport.objects -ne 2 -or $taskHierarchyReport.properties[0].speed -ne 42 `
    -or $taskHierarchyReport.properties[1].speed -ne 25 -or -not $taskHierarchyReport.properties[1].started `
    -or $taskHierarchyReport.properties[0].target.instance -ne $taskHierarchyData.data.lobjects[1].authoringId) { throw 'Standalone hierarchy and internal references failed' }
invokeLaboRequest @{command = 'instance.set'; project = $taskProject; instance = $taskId; property = 'projectile'; value = $taskChildPrefab.assetId} | Out-Null
# 저장된 레벨에 구체화 자손이 남아 있어도 최신 Prefab에 없는 가지는 게임에서 제거한다.
$taskHierarchyPrefabPath = Join-Path $taskProject 'Assets\PF_Hierarchy.prefab'
$taskHierarchyPrefabBytes = [IO.File]::ReadAllBytes($taskHierarchyPrefabPath)
try {
    $taskPrunedPrefab = Get-Content -LiteralPath $taskHierarchyPrefabPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $taskPrunedPrefab.children = @(); $taskPrunedPrefab.bindings = @()
    [IO.File]::WriteAllText($taskHierarchyPrefabPath, ($taskPrunedPrefab | ConvertTo-Json -Depth 16), $taskUtf8)
    $taskPrunedGamePath = Join-Path $taskDirectory 'PrunedHierarchy.love'
    invokeLaboRequest @{command = 'export'; project = $taskProject; level = $taskHierarchyLevel.assetId; output = $taskPrunedGamePath} | Out-Null
    $taskPrunedReportPath = Join-Path $taskDirectory 'pruned-hierarchy-report.json'
    $taskPrunedProcess = Start-Process -FilePath (Join-Path $loveDirectory 'lovec.exe') `
        -ArgumentList @(('"' + $taskPrunedGamePath + '"'), '--verify-game', ('"' + $taskPrunedReportPath + '"')) `
        -WorkingDirectory $taskDirectory -WindowStyle Hidden -PassThru
    if (-not $taskPrunedProcess.WaitForExit(60000)) { $taskPrunedProcess.Kill(); throw 'Pruned hierarchy verification timed out' }
    $taskPrunedReport = Get-Content -LiteralPath $taskPrunedReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($taskPrunedProcess.ExitCode -ne 0 -or -not $taskPrunedReport.ok -or $taskPrunedReport.editorLoaded `
        -or $taskPrunedReport.objects -ne 1 -or $taskPrunedReport.properties[0].speed -ne 42 `
        -or -not $taskPrunedReport.properties[0].started) { throw 'Standalone game retained stale Prefab children' }
} finally { [IO.File]::WriteAllBytes($taskHierarchyPrefabPath, $taskHierarchyPrefabBytes) }
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
$taskNextLevel = invokeLaboRequest @{command = 'level.create'; empty = $true; project = $taskProject; name = 'L_Next'}
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
# 패키징된 CLI의 확장 명령을 외부 프로젝트에서 연속 실행한다.
$taskHelp = & $taskCli --cli help | ConvertFrom-Json
if (-not $taskHelp.ok -or $taskHelp.result.commands -notcontains 'prefab.child.add' -or $taskHelp.result.commands -notcontains 'class.set-source') { throw 'Extended CLI discovery failed' }
invokeLaboRequest @{command = 'folder.create'; project = $taskProject; folder = 'Assets'; name = 'CliTools'} | Out-Null
$taskToolsPrefab = invokeLaboRequest @{command = 'prefab.create'; project = $taskProject; name = 'PF_Tools'; class = $taskClass.assetId}
$taskToolsChild = invokeLaboRequest @{command = 'prefab.child.add'; project = $taskProject; prefab = $taskToolsPrefab.assetId; template = $taskChildPrefab.assetId}
invokeLaboRequest @{command = 'prefab.child.rename'; project = $taskProject; prefab = $taskToolsPrefab.assetId; node = $taskToolsChild.node; name = 'Weapon'} | Out-Null
invokeLaboRequest @{command = 'prefab.set'; project = $taskProject; prefab = $taskToolsPrefab.assetId; node = $taskToolsChild.node; property = 'speed'; value = 77} | Out-Null
invokeLaboRequest @{command = 'prefab.reset'; project = $taskProject; prefab = $taskToolsPrefab.assetId; node = $taskToolsChild.node; property = 'speed'} | Out-Null
$taskToolsValues = invokeLaboRequest @{command = 'prefab.get'; project = $taskProject; prefab = $taskToolsPrefab.assetId; node = $taskToolsChild.node}
if ($taskToolsValues.values.speed -ne 25) { throw 'Nested CLI defaults differ from the Inspector' }
invokeLaboRequest @{command = 'prefab.set'; project = $taskProject; prefab = $taskToolsPrefab.assetId; property = 'target'; value = $taskToolsChild.node} | Out-Null
invokeLaboRequest @{command = 'prefab.reset'; project = $taskProject; prefab = $taskToolsPrefab.assetId; property = 'target'} | Out-Null
invokeLaboRequest @{command = 'prefab.set-parent'; project = $taskProject; prefab = $taskToolsPrefab.assetId; node = $taskToolsChild.node; parent = $false} | Out-Null
invokeLaboRequest @{command = 'prefab.child.remove'; project = $taskProject; prefab = $taskToolsPrefab.assetId; node = $taskToolsChild.node} | Out-Null
$taskBuiltinChild = invokeLaboRequest @{command = 'prefab.child.add'; project = $taskProject; prefab = $taskToolsPrefab.assetId}
if ($taskBuiltinChild.nodes.Count -ne 2 -or $taskBuiltinChild.node -eq $taskToolsChild.node) { throw 'CLI removal path was reused by a new child' }
invokeLaboRequest @{command = 'asset.move'; project = $taskProject; asset = $taskToolsPrefab.assetId; destination = 'Assets/CliTools/PF_Tools.prefab'} | Out-Null
$taskToolsCopy = invokeLaboRequest @{command = 'asset.copy'; project = $taskProject; asset = $taskToolsPrefab.assetId; folder = 'Assets/CliTools'; name = 'PF_Copy.prefab'}
invokeLaboRequest @{command = 'asset.rename'; project = $taskProject; asset = $taskToolsCopy.assetId; name = 'PF_Renamed'} | Out-Null
invokeLaboRequest @{command = 'asset.delete'; project = $taskProject; asset = $taskToolsCopy.assetId} | Out-Null
$taskToolsLevel = invokeLaboRequest @{command = 'level.create'; empty = $true; project = $taskProject; name = 'L_Tools'}
$taskToolsRoot = invokeLaboRequest @{command = 'instance.add'; project = $taskProject; level = $taskToolsLevel.assetId; template = $taskToolsPrefab.assetId}
invokeLaboRequest @{command = 'instance.duplicate'; project = $taskProject; level = $taskToolsLevel.assetId; instances = @($taskToolsRoot.data.authoringId)} | Out-Null
$taskToolsInstances = invokeLaboRequest @{command = 'instance.list'; project = $taskProject; level = $taskToolsLevel.assetId}
if ($taskToolsInstances.instances.Count -ne 4) { throw 'Packaged CLI did not duplicate all descendants' }
invokeLaboRequest @{command = 'instance.delete'; project = $taskProject; level = $taskToolsLevel.assetId; instances = @($taskToolsRoot.data.authoringId)} | Out-Null
invokeLaboRequest @{command = 'instance.add'; project = $taskProject; level = $taskToolsLevel.assetId; name = 'Empty'} | Out-Null
invokeLaboRequest @{command = 'level.validate'; project = $taskProject; level = $taskToolsLevel.assetId} | Out-Null
$taskToolsClass = invokeLaboRequest @{command = 'class.get'; project = $taskProject; class = $taskClass.assetId}
invokeLaboRequest @{command = 'class.set-source'; project = $taskProject; class = $taskClass.assetId; source = $taskToolsClass.source; revision = $taskToolsClass.revision} | Out-Null
$taskValidation = invokeLaboRequest @{command = 'project.validate'; project = $taskProject}
if (-not $taskValidation.valid) { throw ($taskValidation.errors | ConvertTo-Json -Depth 8) }
$taskPointerClass = invokeLaboRequest @{command = 'class.create'; project = $taskProject; name = 'Clickable'; parent = 'PointerComponent'}
$taskPointerCode = @'
local Clickable = {extends = "PointerComponent"}
function Clickable.onPointerDown(self, event) self.owner.properties.clicks = self.owner.properties.clicks + 1; return true end
function Clickable.onPointerUp(self, event) self.owner.properties.released = true end
return Clickable
'@
invokeLaboRequest @{command = 'class.set-source'; project = $taskProject; class = $taskPointerClass.assetId; source = $taskPointerCode} | Out-Null
$taskButtonClass = invokeLaboRequest @{command = 'class.create'; project = $taskProject; name = 'InputButton'; type = 'lobject'}
$taskButtonCode = @'
local InputButton = {properties = {clicks = {type = "number", default = 0}, released = {type = "boolean", default = false}}}
function InputButton.build(self) self:addComponent("pointer", "__POINTER_CLASS__") end
return InputButton
'@
invokeLaboRequest @{command = 'class.set-source'; project = $taskProject; class = $taskButtonClass.assetId; source = $taskButtonCode.Replace('__POINTER_CLASS__', $taskPointerClass.assetId)} | Out-Null
$taskPointerLevel = invokeLaboRequest @{command = 'level.create'; empty = $true; project = $taskProject; name = 'L_Pointer'}
invokeLaboRequest @{command = 'instance.add'; project = $taskProject; level = $taskPointerLevel.assetId; template = $taskButtonClass.assetId} | Out-Null
$taskPointerResult = invokeLaboRequest @{command = 'level.pointer'; project = $taskProject; level = $taskPointerLevel.assetId; events = @(@{kind = 'down'; x = 0; y = 0}, @{kind = 'up'; x = 1000; y = 1000})}
if (-not $taskPointerResult.events[0].consumed -or $taskPointerResult.instances[0].properties.clicks -ne 1 -or -not $taskPointerResult.instances[0].properties.released) { throw 'Packaged CLI pointer dispatch failed' }
$taskPointerGame = Join-Path $taskDirectory 'Pointer.love'
invokeLaboRequest @{command = 'export'; project = $taskProject; level = $taskPointerLevel.assetId; output = $taskPointerGame} | Out-Null
$taskPointerReport = Join-Path $taskDirectory 'pointer-report.json'
$taskPointerProcess = Start-Process -FilePath (Join-Path $loveDirectory 'lovec.exe') `
    -ArgumentList @(('"' + $taskPointerGame + '"'), '--verify-game', ('"' + $taskPointerReport + '"'), '--verify-pointer') `
    -WorkingDirectory $taskDirectory -WindowStyle Hidden -PassThru
if (-not $taskPointerProcess.WaitForExit(60000)) { $taskPointerProcess.Kill(); throw 'Exported pointer input timed out' }
$taskPointerGameResult = Get-Content -LiteralPath $taskPointerReport -Raw -Encoding UTF8 | ConvertFrom-Json
if ($taskPointerProcess.ExitCode -ne 0 -or -not $taskPointerGameResult.ok -or $taskPointerGameResult.editorLoaded `
    -or $taskPointerGameResult.properties[0].clicks -ne 1 -or -not $taskPointerGameResult.properties[0].released) { throw 'Standalone game pointer callbacks failed' }
$taskCameraClass = invokeLaboRequest @{command = 'class.create'; project = $taskProject; name = 'CameraActor'; type = 'lobject'}
$taskCameraCode = @'
local Engine = require("Engine")
local CameraActor = {}
function CameraActor.build(self) self:setRootComponent("camera", Engine.CameraComponent, {viewWidth = 400, viewHeight = 200, zoom = 2}) end
return CameraActor
'@
invokeLaboRequest @{command = 'class.set-source'; project = $taskProject; class = $taskCameraClass.assetId; source = $taskCameraCode} | Out-Null
$taskUiClass = invokeLaboRequest @{command = 'class.create'; project = $taskProject; name = 'UiActor'; type = 'lobject'}
$taskUiCode = @'
local Engine = require("Engine")
local UiActor = {properties = {clicks = {type = "number", default = 0}, released = {type = "boolean", default = false}}}
function UiActor.build(self)
    self:setRootComponent("canvas", Engine.CanvasComponent)
    self:addComponent("pointer", "__POINTER_CLASS__")
end
return UiActor
'@
invokeLaboRequest @{command = 'class.set-source'; project = $taskProject; class = $taskUiClass.assetId; source = $taskUiCode.Replace('__POINTER_CLASS__', $taskPointerClass.assetId)} | Out-Null
$taskCameraLevel = invokeLaboRequest @{command = 'level.create'; empty = $true; project = $taskProject; name = 'L_Camera'}
invokeLaboRequest @{command = 'instance.add'; project = $taskProject; level = $taskCameraLevel.assetId; template = $taskCameraClass.assetId; x = 100; y = 50} | Out-Null
invokeLaboRequest @{command = 'instance.add'; project = $taskProject; level = $taskCameraLevel.assetId; template = $taskUiClass.assetId} | Out-Null
invokeLaboRequest @{command = 'instance.add'; project = $taskProject; level = $taskCameraLevel.assetId; template = $taskButtonClass.assetId; x = 100; y = 50} | Out-Null
$taskView = invokeLaboRequest @{command = 'level.view'; project = $taskProject; level = $taskCameraLevel.assetId; width = 800; height = 600; x = 100; y = 50}
if ($taskView.scale -ne 4 -or $taskView.projected.x -ne 400 -or $taskView.projected.y -ne 300 -or $taskView.canvases[0].width -ne 800) { throw 'Packaged camera and Canvas query failed' }
$taskScreenPointer = invokeLaboRequest @{command = 'level.pointer'; project = $taskProject; level = $taskCameraLevel.assetId; space = 'screen'; width = 800; height = 600; x = 400; y = 300}
if ($taskScreenPointer.instances[1].properties.clicks -ne 1 -or $taskScreenPointer.instances[2].properties.clicks -ne 0) { throw 'Canvas did not consume input above world' }
$taskCameraGame = Join-Path $taskDirectory 'Camera.love'
invokeLaboRequest @{command = 'export'; project = $taskProject; level = $taskCameraLevel.assetId; output = $taskCameraGame} | Out-Null
$taskCameraReport = Join-Path $taskDirectory 'camera-report.json'
$taskCameraProcess = Start-Process -FilePath (Join-Path $loveDirectory 'lovec.exe') `
    -ArgumentList @(('"' + $taskCameraGame + '"'), '--verify-game', ('"' + $taskCameraReport + '"'), '--verify-pointer') `
    -WorkingDirectory $taskDirectory -WindowStyle Hidden -PassThru
if (-not $taskCameraProcess.WaitForExit(60000)) { $taskCameraProcess.Kill(); throw 'Exported Camera verification timed out' }
$taskCameraGameResult = Get-Content -LiteralPath $taskCameraReport -Raw -Encoding UTF8 | ConvertFrom-Json
if ($taskCameraProcess.ExitCode -ne 0 -or -not $taskCameraGameResult.ok -or $taskCameraGameResult.view.x -ne 100 -or $taskCameraGameResult.view.y -ne 50 `
    -or $taskCameraGameResult.properties[1].clicks -ne 1 -or -not $taskCameraGameResult.properties[1].released -or $taskCameraGameResult.properties[2].clicks -ne 0) { throw 'Standalone Camera and Canvas input failed' }
$taskDefaultLevel = invokeLaboRequest @{command = 'level.create'; project = $taskProject; name = 'L_DefaultCamera'}
$taskDefaultData = invokeLaboRequest @{command = 'level.get'; project = $taskProject; level = $taskDefaultLevel.assetId}
if ($taskDefaultData.data.lobjects.Count -ne 1 -or $taskDefaultData.data.mainCamera.component -ne 'camera') { throw 'Default Camera creation failed' }
$taskDefaultSecond = invokeLaboRequest @{command = 'instance.add'; project = $taskProject; level = $taskDefaultLevel.assetId; template = $taskDefaultData.data.lobjects[0].definitionReference; x = 100; y = 50}
invokeLaboRequest @{command = 'level.set-camera'; project = $taskProject; level = $taskDefaultLevel.assetId; instance = $taskDefaultSecond.data.authoringId; component = 'camera'} | Out-Null
$taskDefaultView = invokeLaboRequest @{command = 'level.view'; project = $taskProject; level = $taskDefaultLevel.assetId}
if ($taskDefaultView.camera.authoringId -ne $taskDefaultSecond.data.authoringId) { throw 'Saved Main Camera query failed' }
$taskDefaultGame = Join-Path $taskDirectory 'DefaultCamera.love'
invokeLaboRequest @{command = 'export'; project = $taskProject; level = $taskDefaultLevel.assetId; output = $taskDefaultGame} | Out-Null
$taskDefaultReport = Join-Path $taskDirectory 'default-camera-report.json'
$taskDefaultProcess = Start-Process -FilePath (Join-Path $loveDirectory 'lovec.exe') `
    -ArgumentList @(('"' + $taskDefaultGame + '"'), '--verify-game', ('"' + $taskDefaultReport + '"')) `
    -WorkingDirectory $taskDirectory -WindowStyle Hidden -PassThru
if (-not $taskDefaultProcess.WaitForExit(60000)) { $taskDefaultProcess.Kill(); throw 'Default Camera Export timed out' }
$taskDefaultResult = Get-Content -LiteralPath $taskDefaultReport -Raw -Encoding UTF8 | ConvertFrom-Json
if ($taskDefaultProcess.ExitCode -ne 0 -or -not $taskDefaultResult.ok -or $taskDefaultResult.view.x -ne 100 -or $taskDefaultResult.view.y -ne 50) { throw 'Export did not use saved Main Camera' }
if (-not (Test-Path -LiteralPath (Join-Path $taskProject 'AGENTS.md')) -or -not (Test-Path -LiteralPath (Join-Path $taskProject 'Docs\EngineGuide.md'))) { throw 'Project AI instructions are missing' }
Write-Output "Cli, Export, Camera, Canvas and saved Main Camera verified: $taskDirectory"
