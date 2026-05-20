# Shared

共享核心放置所有版本共用的模型、協議、離線同步、附件與 UI 基礎設計。

原則：功能分流，但資料與協議不能分裂。

## Current implementation

- `LinkGuardV03Core/`：Swift package，提供 v0.3 shared framework skeleton。
- Xcode app project 之後應引用此 package，而不是各自複製模型。
