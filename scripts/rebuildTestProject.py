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
    runCli("project.examples")
    runCli("project.set-default", level="Assets/L_ApiExamples.level")
    validation = runCli("project.validate")
    if not validation["valid"]:
        raise RuntimeError(validation)
    simulation = runCli("level.simulate", frames=1, dt=0.1)
    print("Rebuilt TestProject via CLI: " + str(len(simulation["instances"])) + " runtime objects")

if __name__ == "__main__":
    main()
