import os, re

NOW_ISO_PATTERN = re.compile(
    r"\n*(TZ_TW = timezone\(timedelta\(hours=8\)\)\n)?\n*def now_iso\(\) -> str:\n\s+(?:\"\"\".*?\"\"\"\n\s+)?return datetime\.now\(TZ_TW\)\.isoformat\(\)\n",
    re.DOTALL
)

for file in os.listdir("."):
    if file.endswith(".py") and file not in ("utils.py", "refactor_iso.py") and "tests" not in file:
        with open(file, "r", encoding="utf-8") as f:
            content = f.read()

        original = content
        
        # Remove definition
        content = NOW_ISO_PATTERN.sub("\n\n", content)
        
        if original != content:
            # Add import
            lines = content.split("\n")
            last_idx = -1
            for i, l in enumerate(lines):
                if l.startswith("import ") or l.startswith("from "):
                    last_idx = i
            
            if last_idx != -1:
                lines.insert(last_idx + 1, "from utils import now_iso")
            else:
                lines.insert(0, "from utils import now_iso")
                
            content = "\n".join(lines)
            with open(file, "w", encoding="utf-8") as f:
                f.write(content)
            print(f"Refactored {file}")
