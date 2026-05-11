package com.linkguard.hq.ui

import androidx.compose.animation.core.*
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.linkguard.hq.R
import kotlinx.coroutines.delay
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

// =====================================================
//  HQ 啟動畫面 — Tactical Command HUD 風格
// =====================================================

private data class HQLight(val label: String, val activatedAt: Float)

private val HQ_LIGHTS = listOf(
    HQLight("TCP", 0.20f),
    HQLight("MESH", 0.40f),
    HQLight("AI", 0.60f),
    HQLight("DB", 0.80f),
    HQLight("READY", 0.95f)
)

private val HQ_STEPS = listOf(
    0.15f to "BOOTING COMMAND CONSOLE",
    0.35f to "STARTING TCP SERVER",
    0.55f to "ESTABLISHING MESH",
    0.75f to "CONNECTING AI BACKEND",
    0.92f to "SYSTEM READY",
    1.0f to "LAUNCHING"
)

@Composable
fun HQSplashScreen(onComplete: () -> Unit) {
    var progress by remember { mutableFloatStateOf(0f) }
    var subtitleText by remember { mutableStateOf("INITIALIZING") }
    var nowText by remember { mutableStateOf(currentTimeStamp()) }

    val contentAlpha by animateFloatAsState(
        targetValue = if (progress > 0.02f) 1f else 0f,
        animationSpec = tween(800, easing = FastOutSlowInEasing),
        label = "contentAlpha"
    )

    val infinite = rememberInfiniteTransition(label = "amb")
    val breathe by infinite.animateFloat(
        1f, 1.03f,
        infiniteRepeatable(tween(2400, easing = EaseInOut), RepeatMode.Reverse),
        label = "breathe"
    )
    val haloAlpha by infinite.animateFloat(
        0.30f, 0.65f,
        infiniteRepeatable(tween(2400, easing = EaseInOut), RepeatMode.Reverse),
        label = "halo"
    )
    val bracketAlpha by infinite.animateFloat(
        0.50f, 0.90f,
        infiniteRepeatable(tween(1800, easing = EaseInOut), RepeatMode.Reverse),
        label = "bracket"
    )
    val scanY by infinite.animateFloat(
        0f, 1f,
        infiniteRepeatable(tween(3600, easing = LinearEasing), RepeatMode.Restart),
        label = "scan"
    )

    LaunchedEffect(Unit) {
        for ((target, text) in HQ_STEPS) {
            subtitleText = text
            while (progress < target) {
                progress = (progress + 0.012f).coerceAtMost(target)
                delay(22)
            }
            delay(160)
        }
        delay(350)
        onComplete()
    }
    LaunchedEffect(Unit) {
        while (true) {
            nowText = currentTimeStamp()
            delay(1000)
        }
    }

    Box(modifier = Modifier.fillMaxSize()) {
        HQTacticalBackground(scanY = scanY)

        HQCornerBrackets(
            modifier = Modifier
                .fillMaxSize()
                .alpha(bracketAlpha * contentAlpha)
        )

        // 頂部 HUD 列
        Row(
            modifier = Modifier
                .align(Alignment.TopCenter)
                .fillMaxWidth()
                .padding(horizontal = 24.dp, vertical = 18.dp)
                .alpha(contentAlpha),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(6.dp).clip(CircleShape).background(NV.green))
                Spacer(Modifier.width(6.dp))
                Text(
                    "SYS-LG-HQ-001",
                    fontSize = 9.sp,
                    fontFamily = FontFamily.Monospace,
                    color = NV.green.copy(alpha = 0.6f),
                    letterSpacing = 1.5.sp
                )
            }
            Text(
                "COMMAND CHANNEL",
                fontSize = 9.sp,
                fontFamily = FontFamily.Monospace,
                color = NV.green.copy(alpha = 0.4f),
                letterSpacing = 3.sp
            )
            Text(
                nowText,
                fontSize = 9.sp,
                fontFamily = FontFamily.Monospace,
                color = NV.green.copy(alpha = 0.6f),
                letterSpacing = 1.5.sp
            )
        }

        // 中央主體
        Column(
            modifier = Modifier
                .fillMaxSize()
                .alpha(contentAlpha),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            Box(contentAlignment = Alignment.Center, modifier = Modifier.size(220.dp)) {
                Box(
                    modifier = Modifier
                        .size(180.dp)
                        .blur(48.dp)
                        .alpha(haloAlpha)
                        .background(
                            brush = Brush.radialGradient(
                                colors = listOf(NV.green, NV.green.copy(alpha = 0f)),
                                radius = 220f
                            ),
                            shape = CircleShape
                        )
                )
                Image(
                    painter = painterResource(id = R.drawable.logo),
                    contentDescription = "LinkGuard HQ Logo",
                    contentScale = ContentScale.Fit,
                    modifier = Modifier
                        .size(132.dp)
                        .scale(breathe)
                )
            }

            Spacer(modifier = Modifier.height(8.dp))
            Text(
                "LINKGUARD HQ",
                fontSize = 28.sp,
                fontWeight = FontWeight.Bold,
                fontFamily = FontFamily.Monospace,
                color = NV.green,
                letterSpacing = 7.sp
            )
            Spacer(modifier = Modifier.height(12.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(width = 28.dp, height = 1.dp).background(NV.green.copy(alpha = 0.4f)))
                Spacer(Modifier.width(10.dp))
                Text(
                    "COMMAND CONSOLE  ·  RESCUE OPERATIONS",
                    fontSize = 10.sp,
                    fontFamily = FontFamily.Monospace,
                    color = NV.green.copy(alpha = 0.55f),
                    letterSpacing = 2.5.sp
                )
                Spacer(Modifier.width(10.dp))
                Box(Modifier.size(width = 28.dp, height = 1.dp).background(NV.green.copy(alpha = 0.4f)))
            }
            Spacer(modifier = Modifier.height(28.dp))
            // 狀態燈
            Row(
                horizontalArrangement = Arrangement.spacedBy(18.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                HQ_LIGHTS.forEach { light ->
                    val active = progress >= light.activatedAt
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Box(
                            Modifier
                                .size(6.dp)
                                .clip(CircleShape)
                                .background(if (active) NV.green else NV.green.copy(alpha = 0.15f))
                        )
                        Spacer(Modifier.width(5.dp))
                        Text(
                            light.label,
                            fontSize = 9.sp,
                            fontFamily = FontFamily.Monospace,
                            color = if (active) NV.green.copy(alpha = 0.85f)
                                    else NV.green.copy(alpha = 0.25f),
                            letterSpacing = 1.5.sp
                        )
                    }
                }
            }
        }

        // 底部進度
        Column(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .fillMaxWidth()
                .padding(horizontal = 36.dp, vertical = 56.dp)
                .alpha(contentAlpha),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    "▸ $subtitleText",
                    fontSize = 11.sp,
                    fontFamily = FontFamily.Monospace,
                    color = NV.green.copy(alpha = 0.85f),
                    letterSpacing = 1.5.sp
                )
                Text(
                    "${(progress * 100).toInt().toString().padStart(3, '0')}%",
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Bold,
                    fontFamily = FontFamily.Monospace,
                    color = NV.green,
                    letterSpacing = 1.sp
                )
            }
            Spacer(modifier = Modifier.height(8.dp))
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(3.dp)
                    .clip(RoundedCornerShape(1.5.dp))
                    .background(NV.green.copy(alpha = 0.10f))
            ) {
                Box(
                    modifier = Modifier
                        .fillMaxHeight()
                        .fillMaxWidth(progress)
                        .background(
                            Brush.horizontalGradient(
                                colors = listOf(NV.green.copy(alpha = 0.6f), NV.green)
                            )
                        )
                )
            }
            Spacer(modifier = Modifier.height(6.dp))
            Text(
                "BOOT SEQUENCE",
                fontSize = 9.sp,
                fontFamily = FontFamily.Monospace,
                color = NV.green.copy(alpha = 0.4f),
                letterSpacing = 4.sp
            )
        }

        Text(
            "v0.1 · COMMAND HQ",
            fontSize = 9.sp,
            fontFamily = FontFamily.Monospace,
            color = NV.green.copy(alpha = 0.35f),
            letterSpacing = 1.5.sp,
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .padding(end = 18.dp, bottom = 14.dp)
                .alpha(contentAlpha)
        )
    }
}

@Composable
private fun HQTacticalBackground(scanY: Float) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(
                Brush.radialGradient(
                    colors = listOf(
                        Color(0xFF0A1A0E),
                        Color(0xFF030806),
                        Color(0xFF000000)
                    ),
                    radius = 1400f
                )
            )
    )
    Canvas(modifier = Modifier.fillMaxSize()) {
        val grid = 36f
        val gridColor = Color(0xFF14B840).copy(alpha = 0.06f)
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
                    Color(0xFF14B840).copy(alpha = 0.12f),
                    Color.Transparent
                ),
                startY = sy - 80f,
                endY = sy + 80f
            ),
            topLeft = Offset(0f, sy - 80f),
            size = Size(size.width, 160f)
        )
    }
}

@Composable
private fun HQCornerBrackets(modifier: Modifier = Modifier) {
    val pad = 22.dp
    val len = 30.dp
    val thick = 1.5.dp
    val color = NV.green

    Box(modifier = modifier) {
        Box(modifier = Modifier.align(Alignment.TopStart).padding(start = pad, top = pad).size(len)) {
            Box(Modifier.align(Alignment.TopStart).size(len, thick).background(color))
            Box(Modifier.align(Alignment.TopStart).size(thick, len).background(color))
        }
        Box(modifier = Modifier.align(Alignment.TopEnd).padding(end = pad, top = pad).size(len)) {
            Box(Modifier.align(Alignment.TopEnd).size(len, thick).background(color))
            Box(Modifier.align(Alignment.TopEnd).size(thick, len).background(color))
        }
        Box(modifier = Modifier.align(Alignment.BottomStart).padding(start = pad, bottom = pad).size(len)) {
            Box(Modifier.align(Alignment.BottomStart).size(len, thick).background(color))
            Box(Modifier.align(Alignment.BottomStart).size(thick, len).background(color))
        }
        Box(modifier = Modifier.align(Alignment.BottomEnd).padding(end = pad, bottom = pad).size(len)) {
            Box(Modifier.align(Alignment.BottomEnd).size(len, thick).background(color))
            Box(Modifier.align(Alignment.BottomEnd).size(thick, len).background(color))
        }
    }
}

private fun currentTimeStamp(): String =
    SimpleDateFormat("yyyy.MM.dd HH:mm:ss", Locale.US).format(Date())
