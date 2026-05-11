package com.linkguard.app.ui.screens

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
import com.linkguard.app.R
import com.linkguard.app.ui.theme.NV
import kotlinx.coroutines.delay
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

// =====================================================
//  Field 啟動畫面 — Tactical HUD 風格
//  多層背景 + Logo 光暈 + HUD Bar + 狀態燈陣列
// =====================================================

internal data class SplashLight(val label: String, val activatedAt: Float)

private val FIELD_LIGHTS = listOf(
    SplashLight("TCP", 0.20f),
    SplashLight("MESH", 0.40f),
    SplashLight("LORA", 0.60f),
    SplashLight("GPS", 0.80f),
    SplashLight("READY", 0.95f)
)

@Composable
fun SplashScreen(onComplete: () -> Unit) {
    SplashScaffold(
        title = "LINKGUARD",
        subtitleLine = "FIELD RESCUE NODE  ·  EMT v1.0",
        bottomTag = "v0.1 · FIELD RESCUE",
        steps = listOf(
            0.15f to "SCANNING FREQUENCIES",
            0.35f to "CONNECTING DEVICES",
            0.55f to "LOADING PROTOCOLS",
            0.75f to "ESTABLISHING MESH",
            0.92f to "SYSTEM READY",
            1.0f to "LAUNCHING"
        ),
        statusLights = FIELD_LIGHTS,
        sysCode = "SYS-LG-FIELD",
        onComplete = onComplete
    )
}

// =====================================================
//  共用 Splash 主體 (Field & HQ 共用)
// =====================================================
@Composable
internal fun SplashScaffold(
    title: String,
    subtitleLine: String,
    bottomTag: String,
    steps: List<Pair<Float, String>>,
    statusLights: List<SplashLight>,
    sysCode: String,
    onComplete: () -> Unit
) {
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
        initialValue = 1f,
        targetValue = 1.03f,
        animationSpec = infiniteRepeatable(tween(2400, easing = EaseInOut), RepeatMode.Reverse),
        label = "breathe"
    )
    val haloAlpha by infinite.animateFloat(
        initialValue = 0.30f,
        targetValue = 0.60f,
        animationSpec = infiniteRepeatable(tween(2400, easing = EaseInOut), RepeatMode.Reverse),
        label = "halo"
    )
    val bracketAlpha by infinite.animateFloat(
        initialValue = 0.50f,
        targetValue = 0.90f,
        animationSpec = infiniteRepeatable(tween(1800, easing = EaseInOut), RepeatMode.Reverse),
        label = "bracket"
    )
    val scanY by infinite.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(3600, easing = LinearEasing), RepeatMode.Restart),
        label = "scan"
    )

    LaunchedEffect(Unit) {
        for ((target, text) in steps) {
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
        TacticalBackground(scanY = scanY)

        CornerBrackets(
            modifier = Modifier
                .fillMaxSize()
                .alpha(bracketAlpha * contentAlpha)
        )

        TopHudBar(
            time = nowText,
            sysCode = sysCode,
            modifier = Modifier
                .align(Alignment.TopCenter)
                .alpha(contentAlpha)
        )

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
                    contentDescription = "LinkGuard Logo",
                    contentScale = ContentScale.Fit,
                    modifier = Modifier
                        .size(132.dp)
                        .scale(breathe)
                )
            }

            Spacer(modifier = Modifier.height(8.dp))
            Text(
                title,
                fontSize = 30.sp,
                fontWeight = FontWeight.Bold,
                fontFamily = FontFamily.Monospace,
                color = NV.green,
                letterSpacing = 8.sp
            )
            Spacer(modifier = Modifier.height(12.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(width = 28.dp, height = 1.dp).background(NV.green.copy(alpha = 0.4f)))
                Spacer(Modifier.width(10.dp))
                Text(
                    subtitleLine,
                    fontSize = 10.sp,
                    fontFamily = FontFamily.Monospace,
                    color = NV.green.copy(alpha = 0.55f),
                    letterSpacing = 2.5.sp
                )
                Spacer(Modifier.width(10.dp))
                Box(Modifier.size(width = 28.dp, height = 1.dp).background(NV.green.copy(alpha = 0.4f)))
            }
            Spacer(modifier = Modifier.height(28.dp))
            StatusLightRow(lights = statusLights, progress = progress)
        }

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
            CustomProgressBar(progress = progress)
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
            bottomTag,
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
private fun TacticalBackground(scanY: Float) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(
                Brush.radialGradient(
                    colors = listOf(
                        Color(0xFF0E1A14),
                        Color(0xFF050A07),
                        Color(0xFF000000)
                    ),
                    radius = 1200f
                )
            )
    )
    Canvas(modifier = Modifier.fillMaxSize()) {
        val grid = 36f
        val gridColor = Color(0xFF2EA043).copy(alpha = 0.05f)
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
                    Color(0xFF2EA043).copy(alpha = 0.10f),
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
private fun TopHudBar(time: String, sysCode: String, modifier: Modifier = Modifier) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp, vertical = 18.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(6.dp).clip(CircleShape).background(NV.green))
            Spacer(Modifier.width(6.dp))
            Text(
                sysCode,
                fontSize = 9.sp,
                fontFamily = FontFamily.Monospace,
                color = NV.green.copy(alpha = 0.6f),
                letterSpacing = 1.5.sp
            )
        }
        Text(
            "SECURE LINK",
            fontSize = 9.sp,
            fontFamily = FontFamily.Monospace,
            color = NV.green.copy(alpha = 0.4f),
            letterSpacing = 3.sp
        )
        Text(
            time,
            fontSize = 9.sp,
            fontFamily = FontFamily.Monospace,
            color = NV.green.copy(alpha = 0.6f),
            letterSpacing = 1.5.sp
        )
    }
}

@Composable
private fun StatusLightRow(lights: List<SplashLight>, progress: Float) {
    Row(
        horizontalArrangement = Arrangement.spacedBy(18.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        lights.forEach { light ->
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

@Composable
private fun CustomProgressBar(progress: Float) {
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
}

@Composable
private fun CornerBrackets(modifier: Modifier = Modifier) {
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
