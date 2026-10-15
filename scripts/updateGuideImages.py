"""실제 화면 PNG 원본을 보관하고 번호·원 표시 SVG를 생성한다."""
import base64
import json
from pathlib import Path
import shutil
import sys

root = Path(__file__).resolve().parents[1]
source = Path(sys.argv[1]).resolve()
report = json.loads((source / "report.json").read_text(encoding="utf-8"))
target = root / "docs" / "guide" / "images"
original = target / "original"
original.mkdir(parents=True, exist_ok=True)
for name in report["images"]:
    shutil.copyfile(source / (name + ".png"), original / (name + ".png"))
    shutil.copyfile(source / (name + ".png"), target / (name + ".png"))

marks = {
    "project-browser-create": ("project-browser-create", [(1344, 56, 65, 23, "1"), (1256, 843, 48, 23, "2")]),
    "project-browser": ("project-browser", [(325, 190, 92, 98, "1"), (720, 785, 687, 34, "2"), (1250, 843, 160, 24, "3")]),
    "script-context": ("script-context", [(1195, 275, 86, 17, "1"), (1195, 305, 86, 17, "2"), (1368, 259, 18, 17, "3")]),
    "asset-repair-picker": ("asset-repair-picker", [(370, 130, 17, 17, "1"), (720, 220, 290, 25, "2"), (964, 832, 36, 19, "3")]),
    "editor-overview": ("level-details", [(150, 260, 90, 175, "1"), (670, 280, 240, 160, "2"), (1240, 260, 140, 170, "3"), (620, 690, 360, 130, "4")]),
    "level-details": ("level-details", [(1335, 215, 20, 19, "1"), (1365, 215, 20, 19, "2"), (1400, 215, 20, 19, "3")]),
    "camera-details": ("camera-details", [(670, 313, 320, 180, "1"), (1240, 355, 170, 55, "2")]),
    "sprite-details": ("sprite-details", [(1235, 259, 170, 17, "1"), (1235, 420, 165, 52, "2")]),
    "project-details": ("project-details", [(1340, 77, 88, 17, "1"), (1235, 300, 170, 97, "2"), (1398, 52, 28, 17, "3")]),
}
for name, (image, annotations) in marks.items():
    data = base64.b64encode((original / (image + ".png")).read_bytes()).decode("ascii")
    svg = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{report["width"]}" height="{report["height"]}" viewBox="0 0 {report["width"]} {report["height"]}">',
        f'<image width="100%" height="100%" href="data:image/png;base64,{data}"/>']
    for x, y, rx, ry, number in annotations:
        svg.append(f'<ellipse cx="{x}" cy="{y}" rx="{rx}" ry="{ry}" fill="none" stroke="#ea316e" stroke-width="4"/>')
        bx, by = x - rx + 12, y - ry + 12
        svg.append(f'<circle cx="{bx}" cy="{by}" r="15" fill="#ea316e" stroke="white" stroke-width="2"/>')
        svg.append(f'<text x="{bx}" y="{by + 6}" text-anchor="middle" fill="white" font-family="Arial,sans-serif" font-size="19" font-weight="bold">{number}</text>')
    svg.append('</svg>')
    (target / (name + ".svg")).write_text("\n".join(svg), encoding="utf-8")
print(f'{len(report["images"])} screenshots and {len(marks)} annotated images updated')
