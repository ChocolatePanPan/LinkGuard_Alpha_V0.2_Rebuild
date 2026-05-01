import os, re

# This matches the _send_to_tcp function block we found
SEND_TO_TCP_PATTERN = re.compile(
    r"\n*def _send_to_tcp\(msg: dict\):\n(?:.|\n)*?print\(f\"Failed to send to TCP: \{e\}\"\)\n",
    re.DOTALL
)

for file in os.listdir("."):
    if file.endswith(".py") and file not in ("utils.py", "refactor_tcp.py"):
        with open(file, "r", encoding="utf-8") as f:
            content = f.read()

        original = content
        
        # Remove definition
        content = SEND_TO_TCP_PATTERN.sub("\n\n", content)
        
        if original != content:
            # Replace calls
            content = content.replace("_send_to_tcp(", "send_to_tcp(")
            
            # Add import
            import_statement = "from utils import send_to_tcp"
            if "from utils import " in content:
                content = content.replace("from utils import ", "from utils import send_to_tcp, ")
            else:
                lines = content.split("\n")
                last_idx = -1
                for i, l in enumerate(lines):
                    if l.startswith("import ") or l.startswith("from "):
                        last_idx = i
                
                if last_idx != -1:
                    lines.insert(last_idx + 1, import_statement)
                else:
                    lines.insert(0, import_statement)
                content = "\n".join(lines)
                
            with open(file, "w", encoding="utf-8") as f:
                f.write(content)
            print(f"Refactored {file}")
