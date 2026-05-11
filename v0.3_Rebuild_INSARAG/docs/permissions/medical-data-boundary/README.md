# Medical Data Boundary

EMT 版獨立的核心原因是醫療資料邊界不同。

## EMT can access

- START 分級
- 傷患編號
- 生命徵象
- 傷勢照片
- 後送狀態
- 醫院容量
- CCP 與醫療站資料

## Non-medical roles should not see by default

- 完整生命徵象歷程
- 個別傷患詳細照片
- 醫療註記
- 後送醫療優先順序細節

## Shared view

非醫療角色可看彙整狀態，例如紅黃綠黑數量、後送等待數、醫療站容量，不看完整醫療細節。
