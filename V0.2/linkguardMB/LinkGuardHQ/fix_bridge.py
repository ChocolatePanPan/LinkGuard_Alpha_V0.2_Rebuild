import re
with open("LinkGuardHQ/HQCommandServer.swift", "r") as f:
    text = f.read()

# match anything like `backendBridge?.forwardXYZ(...)`
# or `self.backendBridge?.forwardXYZ(...)` or `self?.backendBridge?.forwardXYZ(...)`
pattern = r"((?:self\??\.)?backendBridge\?\.forward[A-Za-z0-9_]+\s*\([^)]+\))"
# We want to wrap it in Task { @MainActor in ... }
text = re.sub(pattern, r"Task { @MainActor in \1 }", text)

with open("LinkGuardHQ/HQCommandServer.swift", "w") as f:
    f.write(text)
