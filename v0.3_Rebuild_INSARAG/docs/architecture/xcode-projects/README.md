# Xcode Projects

v0.3 的 Xcode project 採分開建立。

## Current state

目前每個 app project 都只是空殼：沒有 target、沒有 scheme。Swift framework skeleton 先放在 `shared/LinkGuardV03Core`，供後續 target 引用。

## Projects

- `apps/mac/LinkGuard-UCC/LinkGuard-UCC.xcodeproj`
- `apps/mac/LinkGuard-SCC/LinkGuard-SCC.xcodeproj`
- `apps/ios/LinkGuard-VO/LinkGuard-VO.xcodeproj`
- `apps/ios/LinkGuard-TE/LinkGuard-TE.xcodeproj`
- `apps/ios/LinkGuard-TL/LinkGuard-TL.xcodeproj`
- `apps/ios/LinkGuard-EMT/LinkGuard-EMT.xcodeproj`
- `apps/ipad/LinkGuard-SCC/LinkGuard-SCC-iPad.xcodeproj`
- `apps/ipad/LinkGuard-TL/LinkGuard-TL-iPad.xcodeproj`
- `apps/ipad/LinkGuard-EMT/LinkGuard-EMT-iPad.xcodeproj`

## Next step later

下一階段才建立 target、scheme、bundle id、icon、capabilities 與 shared package reference。
