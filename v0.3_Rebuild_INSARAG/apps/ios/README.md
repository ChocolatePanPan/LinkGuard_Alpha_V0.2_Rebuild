# iOS Apps

iOS 端提供可單手操作的現場 companion app。

## Buildable targets

- `Lifeline`：iPhone app，配合 `LinkGuard-UCC` 的 `CommandConsoleCatalog.uccModules`。目前固定讀 shared core 的 12 個 v0.2-compatible UCC 模組，呈現總覽、模組清單、現場回報與 Lifeline-HQ 同步頁。

`Lifeline` 只依賴 `LinkGuardV03Core`，避免複製 UCC module catalog。若 UCC catalog 變更，iPhone 端會在下一次 build 時跟著更新。
