import os, re

GET_LOCAL_IP_PATTERN = re.compile(
    r"\n*def _?get_local_ip\(\) -> str:\n.*?return \"127\.0\.0\.1\"\n",
    re.DOTALL
)

for file in os.listdir("."):
    if file.endswith(".py") and file not in ("utils.py", "refactor_ip.py"):
        with open(file, "r", encoding="utf-8") as f:
            content = f.read()

        original = content
        
        # Remove definition
        content = GET_LOCAL_IP_PATTERN.sub("\n\n", content)
        
        if original != content:
            # Replace calls
            content = content.replace("_get_local_ip(", "get_local_ip(")
            
            # Add import
            import_statement = "from utils import get_local_ip"
            if "from utils import " in content:
                content = content.replace("from utils import ", "from utils import get_local_ip, ")
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
