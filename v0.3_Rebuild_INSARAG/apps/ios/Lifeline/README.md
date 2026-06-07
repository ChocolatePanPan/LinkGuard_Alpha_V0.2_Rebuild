# Lifeline

`Lifeline` 是配合 `Lifeline-HQ` 指揮端的 iPhone companion app。`Lifeline-HQ` 目前由 `apps/mac/LinkGuard-UCC/LinkGuard-UCC.xcodeproj` 這個既有 UCC project 產生。

## Source of truth

- UCC module source：`shared/LinkGuardV03Core/Sources/LinkGuardV03Core/CommandConsoleCatalog.swift`
- iPhone UI：`Lifeline/LifelineApp.swift`
- Shared dependency：`LinkGuardV03Core`

`Lifeline` 不複製 UCC module list，而是直接讀取 `CommandConsoleCatalog.uccModules`。目前 UCC catalog 是 v0.2-compatible 的 12 模組版本，沒有 INSARAG / international coordination module。

## Product naming

- iPhone app display name：`Lifeline`
- HQ display name：`Lifeline-HQ`
- HQ project：`apps/mac/LinkGuard-UCC/LinkGuard-UCC.xcodeproj`

## Build

Open `Lifeline.xcodeproj` and build the `Lifeline` scheme for an iPhone simulator or iPhone device.
