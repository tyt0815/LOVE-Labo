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
$taskMovement = invokeLaboRequest @{command = 'script.create'; project = $taskProject; name = 'Movement'}
$taskMovementCode = @'
-- labo-script: script
local Movement = {properties = {speed = {type = "number", default = 10}, started = {type = "boolean", default = false}}}
function Movement.beginPlay(self) self.started = true end
function Movement.update(self, dt) self.owner.transform.x = self.owner.transform.x + self.speed * dt end
return Movement
'@
invokeLaboRequest @{command = 'script.set-source'; project = $taskProject; class = $taskMovement.assetId; source = $taskMovementCode} | Out-Null
$taskPointer = invokeLaboRequest @{command = 'script.create'; project = $taskProject; name = 'Click'; parent = 'Pointer'}
$taskPointerCode = @'
-- labo-script: script
local Click = {extends = "Pointer", properties = {clicks = {type = "number", default = 0}, released = {type = "boolean", default = false}}}
function Click.onPointerDown(self) self.clicks = self.clicks + 1; return true end
function Click.onPointerUp(self) self.released = true; return true end
return Click
'@
invokeLaboRequest @{command = 'script.set-source'; project = $taskProject; class = $taskPointer.assetId; source = $taskPointerCode} | Out-Null
$taskPrefab = invokeLaboRequest @{command = 'prefab.create'; project = $taskProject; name = 'PF_Player'}
invokeLaboRequest @{command = 'prefab.script.add'; project = $taskProject; prefab = $taskPrefab.assetId; source = $taskMovement.assetId; script = 'movement'} | Out-Null
invokeLaboRequest @{command = 'prefab.script.add'; project = $taskProject; prefab = $taskPrefab.assetId; source = $taskPointer.assetId; script = 'pointer'} | Out-Null
invokeLaboRequest @{command = 'prefab.script.move'; project = $taskProject; prefab = $taskPrefab.assetId; script = 'pointer'; index = 1} | Out-Null
$taskChild = invokeLaboRequest @{command = 'prefab.child.add'; project = $taskProject; prefab = $taskPrefab.assetId; name = 'Visual'}
$taskShape = invokeLaboRequest @{command = 'script.create'; project = $taskProject; name = 'Shape'}
$taskShapeCode = @'
-- labo-script: script
local Shape = {properties = {drawn = {type = "boolean", default = false}}}
function Shape.draw(self) self.drawn = true; love.graphics.setColor(1, 0.5, 0.2, 1); love.graphics.rectangle("fill", -10, -10, 20, 20) end
function Shape.getLocalBounds(self) return -10, -10, 20, 20 end
return Shape
'@
invokeLaboRequest @{command = 'script.set-source'; project = $taskProject; class = $taskShape.assetId; source = $taskShapeCode} | Out-Null
invokeLaboRequest @{command = 'prefab.script.add'; project = $taskProject; prefab = $taskPrefab.assetId; node = $taskChild.node; source = $taskShape.assetId; script = 'shape'} | Out-Null
$taskLevel = invokeLaboRequest @{command = 'level.create'; project = $taskProject; name = 'L_Start'}
invokeLaboRequest @{command = 'project.set-default'; project = $taskProject; level = $taskLevel.assetId} | Out-Null
invokeLaboRequest @{command = 'instance.add'; project = $taskProject; prefab = $taskPrefab.assetId} | Out-Null
$taskValidation = invokeLaboRequest @{command = 'project.validate'; project = $taskProject}
if (-not $taskValidation.valid) { throw ($taskValidation.errors | ConvertTo-Json -Depth 8) }
$taskSimulation = invokeLaboRequest @{command = 'level.simulate'; project = $taskProject; frames = 2; dt = 0.5}
if ($taskSimulation.instances[1].transform.x -ne 10 -or -not $taskSimulation.instances[1].scripts.movement.started) { throw 'Script simulation failed' }
$taskInput = invokeLaboRequest @{command = 'level.pointer'; project = $taskProject; space = 'screen'; events = @(@{kind = 'down'; x = 640; y = 360}, @{kind = 'up'; x = 2000; y = 2000})}
if ($taskInput.instances[1].scripts.pointer.clicks -ne 1 -or -not $taskInput.instances[1].scripts.pointer.released) { throw 'Script pointer capture failed' }
$taskGame = Join-Path $taskDirectory 'Game.love'
invokeLaboRequest @{command = 'export'; project = $taskProject; output = $taskGame} | Out-Null
$taskReportPath = Join-Path $taskDirectory 'game-report.json'
$taskProcess = Start-Process -FilePath (Join-Path $loveDirectory 'lovec.exe') `
    -ArgumentList @(('"' + $taskGame + '"'), '--verify-game', ('"' + $taskReportPath + '"'), '--verify-pointer') `
    -WorkingDirectory $taskDirectory -WindowStyle Hidden -PassThru
if (-not $taskProcess.WaitForExit(60000)) { $taskProcess.Kill(); throw 'Game verification timed out' }
$taskReport = Get-Content -LiteralPath $taskReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($taskProcess.ExitCode -ne 0 -or -not $taskReport.ok -or $taskReport.editorLoaded -or $taskReport.objects -ne 3) { throw 'Standalone game failed' }
if (-not $taskReport.instances[1].scripts.movement.started -or $taskReport.instances[1].scripts.pointer.clicks -ne 1 -or -not $taskReport.instances[1].scripts.pointer.released -or -not $taskReport.instances[2].scripts.shape.drawn) { throw 'Standalone script lifecycle draw and pointer failed' }
if (Test-Path -LiteralPath (Join-Path $taskProject 'Sources')) { throw 'Unexpected Sources root' }
Write-Output "Attached scripts, hierarchy, Camera, CLI simulation, pointer and standalone Export verified: $taskDirectory"
