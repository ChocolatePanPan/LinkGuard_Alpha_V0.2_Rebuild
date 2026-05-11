with open("LinkGuardHQ/HQPhotoServer.swift", "r") as f:
    text = f.read()

text = text.replace("""    private func broadcastPhotoNotification()
        DispatchQueue.main.async { self.receivedCount += 1 } {""", """    private func broadcastPhotoNotification() {""")
with open("LinkGuardHQ/HQPhotoServer.swift", "w") as f:
    f.write(text)
