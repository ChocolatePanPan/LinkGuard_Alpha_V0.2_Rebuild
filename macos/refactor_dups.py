import os
import re

UTILS_IMPORT = "from utils import now_iso, get_local_ip, send_to_tcp\n"

# Remove now_iso definition
NOW_ISO_PATTERN = re.compile(
    r"(TZ_TW = timezone\(timedelta\(hours=8\)\)\n)?\n*def now_iso\(\) -> str:\n\s+(?:\"\"\".*?\"\"\"\n\s+)?return datetime\.now\(TZ_TW\)\.isoformat\(\)\n",
    re.DOTALL
)

GET_LOCAL_IP_PATTERN = re.compile(
    r"\n*def _?get_local_ip\(\) -> str:\n(?:.|\n)*?return \"127\.0\.0\.1\"\n",
    re.DOTALL
)

SEND_TO_TCP_PATTERN = re.compile(
    r"\n*def _send_to_tcp\(msg: dict\):\n(?:.|\n)*?print\(f\"Failed to send to TCP: \{e\}\"\)\n",
    re.DOTALL
)

for file in os.listdir("win11"):
    if file.endswith(".py") and file not in ("utils.py", "refactor_dups.py") and "tests" not in file:
        path = os.path.join("win11", file)
        with open(path, "r", encoding="utf-8") as f:
            content = f.read()

        original = content
        
        content = NOW_ISO_PATTERN.sub("\n", content)
        content = GET_LOCAL_IP_PATTERN.sub("\n", content)
        content = SEND_TO_TCP_PATTERN.sub("\n", content)
        
        # Add import
        if original != content:
            # Replace references
            content = content.re.sub(r"\b_get_local_ip\(", "get_local_ip(", content)
            content = content.re.sub(r"\b_send_to_tcp\(", "send_to_tcp(", content)
            
            # Find last import
            lines = content.split('\n')
            last_import = -1
            for i, line in enumerate(lines):
                if line.startswith("import ") or line.startswith("from "):
                    last_import = i
            if last_import != -1:
                lines.insert(last_import + 1, "from utils import now_iso, get_local_ip, send_to_tcp")
            else:
                lines.insert(0, "from utils import now_iso, get_local_ip, send_to_tcp")
            content = '\n'.join(lines)
            
            with open(path, "w", encoding="utf-8") as f:
                f.write(content)
            print(f"Refactored {file}")
