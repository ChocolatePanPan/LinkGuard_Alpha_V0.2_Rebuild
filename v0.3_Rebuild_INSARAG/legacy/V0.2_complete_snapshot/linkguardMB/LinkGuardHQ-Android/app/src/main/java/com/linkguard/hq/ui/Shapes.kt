package com.linkguard.hq.ui

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp

// =====================================================
//  HQ NVShapes — 全圓角設計系統 (Material 3 Expressive)
// =====================================================
val NVShapes = Shapes(
    extraSmall = RoundedCornerShape(8.dp),
    small      = RoundedCornerShape(16.dp),
    medium     = RoundedCornerShape(20.dp),
    large      = RoundedCornerShape(24.dp),
    extraLarge = RoundedCornerShape(28.dp),
)

object NVShape {
    val pill   = RoundedCornerShape(percent = 50)
    val card   = RoundedCornerShape(24.dp)
    val field  = RoundedCornerShape(16.dp)
    val dialog = RoundedCornerShape(28.dp)
    val sheet  = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp)
    val image  = RoundedCornerShape(20.dp)
    val badge  = RoundedCornerShape(8.dp)
    val button = RoundedCornerShape(20.dp)
}

private val HQColorScheme = darkColorScheme(
    primary          = NV.green,
    onPrimary        = NV.textOnColor,
    secondary        = NV.command,
    onSecondary      = NV.textOnColor,
    tertiary         = NV.info,
    background       = NV.bg,
    onBackground     = NV.white,
    surface          = NV.surface,
    onSurface        = NV.white,
    surfaceVariant   = NV.card,
    onSurfaceVariant = NV.textSecondary,
    outline          = NV.cardBorder,
    error            = NV.danger,
    onError          = NV.textOnColor,
)

@Composable
fun LinkGuardHQTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = HQColorScheme,
        shapes = NVShapes,
        content = content
    )
}
