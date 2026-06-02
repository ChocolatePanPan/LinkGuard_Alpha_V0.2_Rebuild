package com.linkguard.app.ui.components

import androidx.compose.animation.core.*
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import com.linkguard.app.ui.theme.NV

// =====================================================
//  全域戰術背景 — 漸層 + 細網格 + 緩慢掃描線 + Vignette
//  放在 Box 最底層,讓上方 Scaffold/Surface 透明繼承
//
//  showEffect: false → 關閉掃描動畫與暗角（省電 / 個人偏好）
//  自動偵測淺色模式並切換背景漸層，避免深色背景蓋掉 LightPalette
// =====================================================

@Composable
fun TacticalBackdrop(
    modifier: Modifier = Modifier,
    accent: Color = NV.green,
    showEffect: Boolean = true
) {
    // 偵測淺色模式：LightPalette.bg.red ≈ 0.965，深色 ≈ 0.05，夜視 ≈ 0.01
    val isLight = NV.bg.red > 0.5f

    val infinite = rememberInfiniteTransition(label = "backdrop")
    val scanY by infinite.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(8000, easing = LinearEasing), RepeatMode.Restart),
        label = "scan"
    )

    val bgBrush = if (isLight) {
        // 淺色模式：用語義 token，保留輕微徑向層次
        Brush.radialGradient(
            colors = listOf(NV.surface, NV.bg, NV.bg),
            radius = 1800f
        )
    } else {
        // 深色 / 夜視：保留原戰術綠黑色調
        Brush.radialGradient(
            colors = listOf(
                Color(0xFF0F1A12),
                Color(0xFF080D0A),
                Color(0xFF000000)
            ),
            radius = 1800f
        )
    }

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(bgBrush)
    ) {
        Canvas(modifier = Modifier.fillMaxSize()) {
            // 細網格（淺色模式用 cardBorder，深色用 accent 微透明）
            val grid = 40f
            val gridColor = if (isLight) NV.cardBorder.copy(alpha = 0.45f) else accent.copy(alpha = 0.035f)
            var x = 0f
            while (x < size.width) {
                drawLine(gridColor, Offset(x, 0f), Offset(x, size.height), strokeWidth = 0.5f)
                x += grid
            }
            var y = 0f
            while (y < size.height) {
                drawLine(gridColor, Offset(0f, y), Offset(size.width, y), strokeWidth = 0.5f)
                y += grid
            }

            if (showEffect) {
                // 緩慢掃描線
                val sy = scanY * size.height
                drawRect(
                    brush = Brush.verticalGradient(
                        colors = listOf(
                            Color.Transparent,
                            accent.copy(alpha = if (isLight) 0.07f else 0.05f),
                            Color.Transparent
                        ),
                        startY = sy - 100f,
                        endY = sy + 100f
                    ),
                    topLeft = Offset(0f, sy - 100f),
                    size = Size(size.width, 200f)
                )
                // Vignette 暗角（淺色模式不需要）
                if (!isLight) drawRect(
                    brush = Brush.radialGradient(
                        colors = listOf(
                            Color.Transparent,
                            Color.Black.copy(alpha = 0.45f)
                        ),
                    center = Offset(size.width / 2f, size.height / 2f),
                    radius = size.width.coerceAtLeast(size.height) * 0.7f
                )
            )
            } // if (showEffect)
        }
    }
}
