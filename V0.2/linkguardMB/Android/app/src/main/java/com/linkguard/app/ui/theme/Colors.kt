package com.linkguard.app.ui.theme

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color

/**
 * NV — LinkGuard 設計系統色 token。
 *
 * 重構自原本固定 dark-only 色票，改為依 EightShapes 文章建議：
 *   - mode-variant tokens（背景 / 文字 / 邊框 / 反饋色）→ 透過 [currentPalette] 動態取得
 *   - mode-invariant tokens（品牌色 / 群組色 / 高對比模式色）→ 維持固定 const
 *
 * `currentPalette` 為 Compose State；切換時所有讀取 NV.bg / NV.textPrimary 等的
 * Composable 會自動 recompose。非 Composable 程式碼（ViewModel）讀取也能拿到當前值，
 * 只是不會 reactive，這在現有用法（status pair 顏色）為可接受副作用。
 */
object NV {
    // ===== Mode-variant（隨 light/dark palette 切換） =====
    internal var currentPalette by mutableStateOf(DarkPalette)

    val bg: Color            get() = currentPalette.bg
    val surface: Color       get() = currentPalette.surface
    val card: Color          get() = currentPalette.card
    val cardBorder: Color    get() = currentPalette.cardBorder
    val divider: Color       get() = currentPalette.divider
    val textPrimary: Color   get() = currentPalette.textPrimary
    val textSecondary: Color get() = currentPalette.textSecondary
    val textOnColor: Color   get() = currentPalette.textOnColor
    val danger: Color        get() = currentPalette.danger
    val warning: Color       get() = currentPalette.warning
    val info: Color          get() = currentPalette.info
    val heartRate: Color     get() = currentPalette.heartRate

    /** 與 textPrimary 同義（既有 callers 期望「白文字」語意） */
    val white: Color         get() = currentPalette.textPrimary

    // ===== Mode-invariant（品牌 / 群組 / 高對比，跨模式統一） =====

    // 品牌主色（綠）— 兩模式共用，飽和度足夠且符合 WCAG AA on both
    val green       = Color(0xFF2EA043)
    val greenFaint  = Color(0xFF0D2818)

    // 行動 / 命令 / 團隊 / 增援 / 模擬 — 維持品牌語意，跨模式共用
    val simulation  = Color(0xFF8957E5)
    val command     = Color(0xFF4B8BEC)
    val team        = Color(0xFF2D9CDB)
    val reinforce   = Color(0xFFE07D20)
    val blue        = Color(0xFF4B8BEC)   // 與 command 同步

    // 導航群組色彩
    val groupOps      = Color(0xFFDA3633)
    val groupComms    = Color(0xFF4B8BEC)
    val groupSupport  = Color(0xFF2EA043)
    val groupTools    = Color(0xFF8957E5)

    // 高對比模式（WCAG AA — 陽光下使用，獨立於 light/dark 切換）
    val hcBg          = Color(0xFF000000)
    val hcText        = Color(0xFFFFFFFF)
    val hcGreen       = Color(0xFF4ADE80)
    val hcDanger      = Color(0xFFFF6B6B)
    val hcWarning     = Color(0xFFFFD93D)
    val hcBlue        = Color(0xFF6CB4EE)
}

/** 由 [LinkGuardTheme] 呼叫以套用對應 palette。 */
internal fun applyPalette(palette: Palette) {
    NV.currentPalette = palette
}
