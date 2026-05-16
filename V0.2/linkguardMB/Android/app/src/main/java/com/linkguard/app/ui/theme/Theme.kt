package com.linkguard.app.ui.theme

import android.app.Activity
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat

/**
 * 外觀模式偏好。
 *  - System: 跟隨系統（預設）
 *  - Light : 強制淺色
 *  - Dark  : 強制深色
 */
enum class ThemeMode {
    System, Light, Dark, NightVision;

    companion object {
        fun fromPref(value: String?): ThemeMode = when (value) {
            "light"        -> Light
            "dark"         -> Dark
            "night_vision" -> NightVision
            else           -> System
        }
    }

    fun toPref(): String = when (this) {
        System      -> "system"
        Light       -> "light"
        Dark        -> "dark"
        NightVision -> "night_vision"
    }
}

private val DarkColorScheme = darkColorScheme(
    primary           = NV.green,
    onPrimary         = NV.textOnColor,
    secondary         = NV.command,
    onSecondary       = NV.textOnColor,
    tertiary          = NV.info,
    background        = DarkPalette.bg,
    onBackground      = DarkPalette.textPrimary,
    surface           = DarkPalette.surface,
    onSurface         = DarkPalette.textPrimary,
    surfaceVariant    = DarkPalette.card,
    onSurfaceVariant  = DarkPalette.textSecondary,
    outline           = DarkPalette.cardBorder,
    error             = DarkPalette.danger,
    onError           = DarkPalette.textOnColor,
)

private val LightColorScheme = lightColorScheme(
    primary           = NV.green,
    onPrimary         = NV.textOnColor,
    secondary         = NV.command,
    onSecondary       = NV.textOnColor,
    tertiary          = LightPalette.info,
    background        = LightPalette.bg,
    onBackground      = LightPalette.textPrimary,
    surface           = LightPalette.surface,
    onSurface         = LightPalette.textPrimary,
    surfaceVariant    = LightPalette.card,
    onSurfaceVariant  = LightPalette.textSecondary,
    outline           = LightPalette.cardBorder,
    error             = LightPalette.danger,
    onError           = LightPalette.textOnColor,
)

/**
 * LinkGuard 主題包裝器。
 *
 * 依 EightShapes 文章建議：
 *   1. 使用語義 token（NV）跨元件套用
 *   2. 切換時整組 palette 一次替換，不逐處改色
 *   3. status bar 同步染色（避免出現「分隔線」斷層）
 */
@Composable
fun LinkGuardTheme(
    mode: ThemeMode = ThemeMode.System,
    content: @Composable () -> Unit
) {
    val systemDark = isSystemInDarkTheme()
    val useDark = when (mode) {
        ThemeMode.System      -> systemDark
        ThemeMode.Light       -> false
        ThemeMode.Dark        -> true
        ThemeMode.NightVision -> true
    }

    val palette = when (mode) {
        ThemeMode.NightVision -> NightVisionPalette
        else -> if (useDark) DarkPalette else LightPalette
    }
    val colorScheme = if (useDark) DarkColorScheme else LightColorScheme

    // 切換 NV 動態 palette；依 mode 觸發 → 進入新模式時所有讀取 NV.xxx 的 Composable recompose
    LaunchedEffect(mode) {
        applyPalette(palette)
    }

    // status bar 顏色同步（依文章「Backgrounds-on-backgrounds」避免層次斷裂）
    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            val window = (view.context as? Activity)?.window ?: return@SideEffect
            window.statusBarColor = palette.bg.toArgb()
            // NightVision 永遠使用深色狀態列圖示
            WindowCompat.getInsetsController(window, view)
                .isAppearanceLightStatusBars = !useDark
        }
    }

    MaterialTheme(
        colorScheme = colorScheme,
        shapes = NVShapes,
        content = content
    )
}
