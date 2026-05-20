package com.linkguard.hq.ui

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

// =====================================================
//  HQ 全域戰術背景 — 漸層 + 細網格 + 緩慢掃描線 + Vignette
// =====================================================

@Composable
fun HQTacticalBackdrop(modifier: Modifier = Modifier, accent: Color = NV.green) {
    val infinite = rememberInfiniteTransition(label = "hq-backdrop")
    val scanY by infinite.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(8000, easing = LinearEasing), RepeatMode.Restart),
        label = "scan"
    )

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(
                Brush.radialGradient(
                    colors = listOf(
                        Color(0xFF0A1A0E),
                        Color(0xFF050B07),
                        Color(0xFF000000)
                    ),
                    radius = 1800f
                )
            )
    ) {
        Canvas(modifier = Modifier.fillMaxSize()) {
            val grid = 40f
            val gridColor = accent.copy(alpha = 0.040f)
            var x = 0f
            while (x < size.width) {
                drawLine(gridColor, Offset(x, 0f), Offset(x, size.height), strokeWidth = 1f)
                x += grid
            }
            var y = 0f
            while (y < size.height) {
                drawLine(gridColor, Offset(0f, y), Offset(size.width, y), strokeWidth = 1f)
                y += grid
            }
            val sy = scanY * size.height
            drawRect(
                brush = Brush.verticalGradient(
                    colors = listOf(
                        Color.Transparent,
                        accent.copy(alpha = 0.06f),
                        Color.Transparent
                    ),
                    startY = sy - 100f,
                    endY = sy + 100f
                ),
                topLeft = Offset(0f, sy - 100f),
                size = Size(size.width, 200f)
            )
            drawRect(
                brush = Brush.radialGradient(
                    colors = listOf(
                        Color.Transparent,
                        Color.Black.copy(alpha = 0.50f)
                    ),
                    center = Offset(size.width / 2f, size.height / 2f),
                    radius = size.width.coerceAtLeast(size.height) * 0.7f
                )
            )
        }
    }
}
