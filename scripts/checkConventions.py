from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent.parent
LUA_STRINGS = re.compile(r'--\[(=*)\[.*?\]\1\]|\[(=*)\[.*?\]\2\]|--[^\n]*|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'', re.S)
ENTRY_FILES = {"main.lua", "conf.lua"}
EXTERNAL_MODULES = {"ffi", "bit", "utf8"}
EXTERNAL_IDENTIFIERS = {"_G", "_VERSION"}

def luaCode(content):
    return LUA_STRINGS.sub(lambda match: (" " if match.group(0).startswith("--") else "0") + "\n" * match.group(0).count("\n"), content)

def checkFile(path):
    content = path.read_text(encoding="utf-8-sig")
    relative = path.relative_to(ROOT).as_posix()
    issues = []
    if path.suffix == ".lua":
        if relative.startswith("src/") and path.name not in ENTRY_FILES and not re.fullmatch(r"[A-Z][A-Za-z0-9]*", path.stem):
            issues.append("module filename must be PascalCase")
        code = luaCode(content)
        for match in re.finditer(r"\bfunction\s+([\w.:]+)\s*\(", code):
            name = re.split(r"[.:]", match.group(1))[-1]
            if not name.startswith("__") and not re.fullmatch(r"[a-z][A-Za-z0-9]*", name):
                issues.append("function must be camelCase: " + name)
        for name in re.findall(r"\b([A-Za-z_][A-Za-z0-9_]*)\s*=\s*function\b", code):
            if not name.startswith("__") and not re.fullmatch(r"[a-z][A-Za-z0-9]*", name):
                issues.append("callback must be camelCase: " + name)
        for name in sorted(set(re.findall(r"\b[a-z][A-Za-z0-9]*_[A-Za-z0-9_]+\b", code))):
            issues.append("identifier must be camelCase: " + name)
        for name in sorted(set(re.findall(r"\b_[a-zA-Z][A-Za-z0-9_]*\b", code))):
            if name not in EXTERNAL_IDENTIFIERS:
                issues.append("private identifier must be camelCase: " + name)
        # LÖVE ZIP 내부에서는 파일명 대소문자도 require 계약의 일부다.
        for module in re.findall(r"require\([\"']([^\"']+)[\"']\)", content):
            if module in EXTERNAL_MODULES:
                continue
            base = ROOT if module.startswith("tests.") else ROOT / "src"
            target = base / (module.replace(".", "/") + ".lua")
            if not target.is_file():
                issues.append("missing module: " + module)
            elif target.name not in [entry.name for entry in target.parent.iterdir()]:
                issues.append("module case mismatch: " + module)
    for lineNumber, line in enumerate(content.splitlines(), 1):
        indentation = line[:len(line) - len(line.lstrip())]
        if "\t" in indentation or len(indentation) % 4:
            issues.append("indentation must use four spaces: line " + str(lineNumber))
    for issue in issues:
        print(relative + ": " + issue)
    return len(issues)

def main():
    paths = list((ROOT / "src").rglob("*.lua")) + list((ROOT / "tests").rglob("*.lua"))
    paths += list((ROOT / "scripts").glob("*.py")) + list((ROOT / "scripts").glob("*.ps1"))
    issues = sum(checkFile(path) for path in paths)
    print(str(len(paths)) + " files checked, " + str(issues) + " convention violations")
    return 1 if issues else 0

if __name__ == "__main__":
    sys.exit(main())
