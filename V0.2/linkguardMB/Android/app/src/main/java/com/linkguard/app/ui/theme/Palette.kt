package com.linkguard.app.ui.theme

import androidx.compose.ui.graphics.Color

/**
 * Palette — 對應 EightShapes《Light & Dark Color Modes in Design Systems》
 * 將「會隨明暗模式變動」的 token 集中為一個 immutable 結構。
 *
 * 分類（依該文章）:
 *   - Background layers: bg / surface / card
 *   - Borders / separators: cardBorder / divider
 *   - Text: textPrimary / textSecondary / textOnColor
 *   - Feedback (mode-tuned): danger / warning / info / heartRate
 *
 * 品牌色 / 群組色 / 高對比模式（hcXxx）保持「mode-invariant」，
 * 不放進 Palette，仍由 [NV] 直接持有 const 色值。
 */
data class Palette(
    // Backgrounds
    val bg: Color,
    val surface: Color,
    val card: Color,
    // Borders
    val cardBorder: Color,
    val divider: Color,
    // Text
    val textPrimary: Color,
    val textSecondary: Color,
    val textOnColor: Color,
    // Feedback (mode-tuned)
    val danger: Color,
    val warning: Color,
    val info: Color,
    val heartRate: Color
)

/** 深色模式 — 沿用既有 GitHub Dark 色票（與 iOS 對齊） */
val DarkPalette = Palette(
    bg            = Color(0xFF0D1117),
    surface       = Color(0xFF1C2128),
    card          = Color(0xFF161B22),
    cardBorder    = Color(0xFF30363D),
    divider       = Color(0xFF21262D),
    textPrimary   = Color(0xFFE6EDF3),
    textSecondary = Color(0xFF8B949E),
    textOnColor   = Color(0xFFFFFFFF),
    danger        = Color(0xFFDA3633),
    warning       = Color(0xFFD29922),
    info          = Color(0xFF1AADA0),
    heartRate     = Color(0xFFCF5B5B)
)

/**
 * 淺色模式 — GitHub Light 風格。
 * 注意（依文章「Backgrounds-on-backgrounds」段）：
 *   bg = #F6F8FA、card = #FFFFFF；卡片必須有 1dp 實心 cardBorder 才看得出層次。
 *   feedback 色在白底需提高對比、降低亮度（warning 黃在白底改用棕黃）。
 */
val LightPalette = Palette(
    bg            = Color(0xFFF6F8FA),
    surface       = Color(0xFFFFFFFF),
    card          = Color(0xFFFFFFFF),
    cardBorder    = Color(0xFFD0D7DE),
    divider       = Color(0xFFE1E4E8),
    textPrimary   = Color(0xFF1F2328),
    textSecondary = Color(0xFF57606A),
    textOnColor   = Color(0xFFFFFFFF),
    danger        = Color(0xFFCF222E),
    warning       = Color(0xFF9A6700),
    info          = Color(0xFF0969DA),
    heartRate     = Color(0xFFD1242F)
)
