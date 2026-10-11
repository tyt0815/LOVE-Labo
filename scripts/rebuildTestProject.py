"""빈 위치에 CLI로 부착 스크립트 예제 프로젝트를 만든다. 기존 프로젝트는 덮어쓰지 않는다."""
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOVE = Path("C:/Program Files/LOVE/lovec.exe")

def main():
    project = ROOT / "tests/TestProject"
    if project.exists():
        raise SystemExit("TestProject already exists; move it aside before rebuilding")
    requestPath = ROOT / "build/sample-project-request.json"
    requestPath.parent.mkdir(exist_ok=True)
    def runCli(command, **fields):
        request = dict(command=command, project=str(project), **fields)
        requestPath.write_text(json.dumps(request, ensure_ascii=False), encoding="utf-8")
        process = subprocess.run([str(LOVE), "src", "--cli", "--request", str(requestPath)], cwd=ROOT, text=True, encoding="utf-8", capture_output=True)
        lines = [line for line in process.stdout.splitlines() if line.startswith("{")]
        result = json.loads(lines[-1]) if lines else {}
        if process.returncode or not result.get("ok"):
            raise RuntimeError(result.get("error") or process.stdout or process.stderr)
        return result["result"]
    runCli("project.create", parent=str(project.parent), name="TestProject")
    source = runCli("script.create", name="NewClass")["assetId"]
    code = '''-- labo-script: script
local NewClass = {privateValue = 123, properties = {
    speed = {type = "number", default = 100, group = "Movement"},
    title = {type = "string", default = "Example"},
    enabled = {type = "boolean", default = true},
    target = {type = "object", default = false},
    otherScript = {type = "script", default = false},
    projectile = {type = "prefab", default = false}
}}
function NewClass.beginPlay(self, world)
    self.hiddenCounter = 0
    if self.projectile ~= false then
        self.spawned = assert(world:spawnLObject(self.projectile, {x = 200, y = 0}))
    end
end
function NewClass.update(self, dt)
    self.hiddenCounter = self.hiddenCounter + 1
    if self.enabled then self.owner.transform.x = self.owner.transform.x + self.speed * dt end
end
return NewClass
'''
    runCli("script.set-source", **{"class": source, "source": code})
    imagePath = ROOT / "build/sample-image.png"
    # 외부 의존성 없이 64×64 예제 PNG를 만든다.
    import struct
    import zlib
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    pixels = b"".join(b"\0" + bytes((25, 165, 240, 255)) * 64 for _ in range(64))
    imagePath.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 64, 64, 8, 6, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(pixels)) + chunk(b"IEND", b""))
    image = runCli("asset.import", input=str(imagePath), name="ExampleSprite.png")["assetId"]
    bullet = runCli("prefab.create", name="PF_Bullet")["assetId"]
    runCli("prefab.script.add", prefab=bullet, source="Sprite", script="sprite")
    runCli("prefab.set", prefab=bullet, property="sprite.image", value=image)
    prefab = runCli("prefab.create", name="NewPrefab")["assetId"]
    runCli("prefab.script.add", prefab=prefab, source=source, script="behavior")
    runCli("prefab.script.add", prefab=prefab, source="Sprite", script="sprite")
    runCli("prefab.set", prefab=prefab, property="sprite.image", value=image)
    child = runCli("prefab.child.add", prefab=prefab, name="VisualChild")["node"]
    runCli("prefab.script.add", prefab=prefab, node=child, source="Sprite", script="sprite")
    runCli("prefab.set", prefab=prefab, node=child, property="sprite.image", value=image)
    runCli("prefab.set", prefab=prefab, node=child, property="$transform.x", value=100)
    runCli("prefab.set", prefab=prefab, property="behavior.target", value=child)
    runCli("prefab.set", prefab=prefab, property="behavior.otherScript", value={"authoringId": 2, "script": "sprite"})
    runCli("prefab.set", prefab=prefab, property="behavior.projectile", value=bullet)
    level = runCli("level.create", name="L_Start")["assetId"]
    runCli("project.set-default", level=level)
    runCli("instance.add", prefab=prefab, x=0, y=0)
    validation = runCli("project.validate")
    if not validation["valid"]:
        raise RuntimeError(validation)
    simulation = runCli("level.simulate", frames=1, dt=0.1)
    print("Rebuilt TestProject via CLI: " + str(len(simulation["instances"])) + " runtime objects")

if __name__ == "__main__":
    main()
