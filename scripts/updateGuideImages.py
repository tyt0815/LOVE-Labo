"""실제 화면 PNG 원본을 보관하고 번호·원 표시 SVG를 생성한다."""
import argparse
import base64
import json
from pathlib import Path
import shutil
import sys

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("source", type=Path)
parser.add_argument("--only", nargs="+", help="갱신할 캡처 이름. 생략하면 전체")
args = parser.parse_args()
source = args.source.resolve()
report = json.loads((source / "report.json").read_text(encoding="utf-8"))
target = root / "docs" / "guide" / "images"
original = target / "original"
original.mkdir(parents=True, exist_ok=True)
selected = set(args.only or report["images"])
assert selected <= set(report["images"]), "Unknown capture name"
for name in report["images"]:
    if name not in selected: continue
    shutil.copyfile(source / (name + ".png"), original / (name + ".png"))
    shutil.copyfile(source / (name + ".png"), target / (name + ".png"))

marks = {
    "runtime-inspector": ("runtime-inspector", [(645, 54, 80, 19, "1"), (148, 280, 130, 200, "2"), (1215, 282, 202, 180, "3")]),
    "performance-window": ("performance-window", [(580, 151, 250, 18, "1"), (630, 224, 290, 42, "2"), (620, 400, 280, 60, "3")]),
    "recovery-drafts": ("recovery-drafts", [(720, 470, 205, 75, "1"), (835, 612, 38, 20, "2")]),
    "project-startup": ("project-startup", [(1214, 154, 205, 16, "1"), (1214, 183, 205, 16, "2")]),
    "build-export": ("build-export", [(730, 377, 236, 19, "1"), (784, 429, 200, 20, "2"), (784, 477, 200, 20, "3")]),
    "build-results": ("build-results", [(720, 377, 213, 22, "1"), (720, 463, 213, 65, "2"), (803, 620, 60, 18, "3")]),
    "game-cli-editor": ("game-cli-editor", [(649, 200, 310, 22, "1"), (649, 238, 310, 17, "2"), (616, 418, 270, 80, "3")]),
    "travel-b": ("travel-b", [(460, 143, 150, 17, "1"), (646, 227, 220, 18, "2"), (646, 435, 270, 20, "3")]),
    "ui-anchor-picker": ("ui-anchor-picker", [(1215, 370, 200, 35, "1"), (1294, 508, 83, 136, "2")]),
    "window-controls": ("sprite-details", [(1371, 16, 67, 13, "1"), (720, 16, 300, 13, "2"), (3, 280, 3, 100, "3")]),
    "background-picker": ("background-picker", [(1124, 282, 120, 120, "1"), (1352, 342, 56, 82, "2"), (1068, 485, 66, 18, "3")]),
    "scene-background": ("scene-background", [(922, 90, 54, 18, "1")]),
    "project-browser-create": ("project-browser-create", [(1344, 72, 65, 23, "1"), (1256, 843, 48, 23, "2")]),
    "project-browser": ("project-browser", [(325, 206, 92, 98, "1"), (720, 785, 687, 34, "2"), (1250, 843, 160, 24, "3")]),
    "project-inspector-menu": ("project-inspector-menu", [(206, 50, 135, 19, "1")]),
    "script-context": ("script-context", [(1145, 242, 88, 17, "1"), (1145, 272, 88, 17, "2"), (1145, 302, 88, 17, "3")]),
    "asset-repair-picker": ("asset-repair-picker", [(370, 130, 17, 17, "1"), (720, 220, 290, 25, "2"), (964, 832, 36, 19, "3")]),
    "editor-overview": ("level-details", [(150, 260, 90, 175, "1"), (670, 280, 240, 160, "2"), (1240, 260, 140, 170, "3"), (620, 690, 360, 130, "4")]),
    "level-details": ("level-details", [(1210, 149, 210, 19, "1")]),
    "camera-details": ("camera-details", [(645, 313, 320, 180, "1"), (1215, 290, 200, 48, "2")]),
    "view-details": ("view-details", [(1215, 487, 200, 17, "1")]),
    "script-enabled": ("script-enabled", [(1350, 263, 33, 22, "1")]),
    "script-disabled": ("script-disabled", [(1350, 263, 33, 22, "1")]),
    "sprite-details": ("sprite-details", [(1215, 227, 200, 17, "1"), (1215, 275, 200, 31, "2")]),
    "project-details": ("project-details", [(1080, 87, 82, 17, "1"), (1215, 313, 200, 65, "2"), (1398, 52, 28, 17, "3")]),
}
annotationCount = 0
for name, (image, annotations) in marks.items():
    if args.only and image not in selected: continue
    annotationCount += 1
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
print(f'{len(selected)} screenshots and {annotationCount} annotated images updated')
