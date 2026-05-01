package com.linkguard.app.ui.theme

import androidx.compose.ui.graphics.Color

object NV {
    // 基礎色盤 — 深色主題，柔和層次
    val green       = Color(0xFF2EA043)   // 柔和綠，不刺眼
    val greenFaint  = Color(0xFF0D2818)   // 綠色底色
    val bg          = Color(0xFF0D1117)   // 深藍灰底，取代純黑

    // 語義色彩 — 降飽和柔和版
    val danger      = Color(0xFFDA3633)   // 柔和紅
    val warning     = Color(0xFFD29922)   // 暖黃
    val heartRate   = Color(0xFFCF5B5B)   // 心率紅
    val info        = Color(0xFF1AADA0)   // 青綠
    val simulation  = Color(0xFF8957E5)   // 柔紫
    val command     = Color(0xFF4B8BEC)   // 明亮藍
    val team        = Color(0xFF2D9CDB)   // 天藍
    val reinforce   = Color(0xFFE07D20)   // 暖橙
    val textOnColor = Color(0xFFFFFFFF)

    // 導航群組色彩
    val groupOps      = Color(0xFFDA3633)   // 行動群組（紅）
    val groupComms    = Color(0xFF4B8BEC)   // 通訊群組（藍）
    val groupSupport  = Color(0xFF2EA043)   // 後勤群組（綠）
    val groupTools    = Color(0xFF8957E5)   // 工具群組（紫）

    // 高對比模式（WCAG AA — 陽光下使用）
    val hcBg          = Color(0xFF000000)
    val hcText        = Color(0xFFFFFFFF)
    val hcGreen       = Color(0xFF4ADE80)
    val hcDanger      = Color(0xFFFF6B6B)
    val hcWarning     = Color(0xFFFFD93D)
    val hcBlue        = Color(0xFF6CB4EE)

    // UI 層次色
    val card        = Color(0xFF161B22)   // 卡片底色（可辨別）
    val cardBorder  = Color(0xFF30363D)   // 邊框（清楚可見）
    val surface     = Color(0xFF1C2128)   // 次層面（NavigationRail 等）
    val divider     = Color(0xFF21262D)   // 分隔線
    val blue        = Color(0xFF4B8BEC)   // 與 command 同步
    val textPrimary = Color(0xFFE6EDF3)   // 主文字（非純白，減少刺眼）
    val textSecondary = Color(0xFF8B949E) // 副文字（暖灰）
    val white       = Color(0xFFE6EDF3)   // 對齊 textPrimary，取代純白
}
