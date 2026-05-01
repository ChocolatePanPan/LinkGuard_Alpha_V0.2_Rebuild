package com.linkguard.hq.ui

import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Campaign
import androidx.compose.material.icons.filled.DeleteSweep
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Send
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.linkguard.hq.viewmodel.HQViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.TimeUnit

// =====================================================
//  HQ ↔ AI 自由對話頁
// =====================================================

internal data class HQAIMessage(
    val role: String,                // "user" | "assistant"
    val content: String,
    val timestamp: Long = System.currentTimeMillis(),
    val model: String? = null,
    val elapsedMs: Int? = null,
    val isError: Boolean = false
)

@Composable
fun HQAITab(viewModel: HQViewModel) {
    val backendHost by viewModel.backendBridge.backendHost.collectAsState()
    val backendConnected by viewModel.isBackendConnected.collectAsState()

    var messages by remember { mutableStateOf<List<HQAIMessage>>(emptyList()) }
    var draft by remember { mutableStateOf("") }
    var isSending by remember { mutableStateOf(false) }
    var autoBroadcast by remember { mutableStateOf(true) }
    val listState = rememberLazyListState()
    val scope = rememberCoroutineScope()

    // 新訊息 → 自動滾到底
    LaunchedEffect(messages.size) {
        if (messages.isNotEmpty()) listState.animateScrollToItem(messages.size - 1)
    }

    fun sendMessage() {
        val text = draft.trim()
        if (text.isEmpty() || isSending) return
        if (backendHost.isBlank()) {
            messages = messages + HQAIMessage(
                role = "assistant",
                content = "尚未連線至後端 AI 伺服器,請先在連線頁面連接。",
                isError = true
            )
            return
        }
        val userMsg = HQAIMessage(role = "user", content = text)
        messages = messages + userMsg
        draft = ""
        isSending = true

        scope.launch {
            val historyForServer = messages.dropLast(1)  // 不含剛才剛加進去的 user msg (已放在 message 欄位)
            val result = runCatching {
                withContext(Dispatchers.IO) {
                    callChat(backendHost, text, historyForServer)
                }
            }
            isSending = false
            result.onSuccess { reply ->
                messages = messages + reply
                // 自動廣播 AI 回覆給所有前線 / HQ 裝置
                if (autoBroadcast && !reply.isError && reply.content.isNotBlank()) {
                    runCatching {
                        viewModel.sendTextBroadcast("[AI] " + reply.content, "normal")
                    }
                }
            }.onFailure { e ->
                messages = messages + HQAIMessage(
                    role = "assistant",
                    content = "AI 通訊失敗:${e.message ?: "未知錯誤"}",
                    isError = true
                )
            }
        }
    }

    Column(modifier = Modifier.fillMaxSize().padding(12.dp)) {
        // === 頂部狀態列 ===
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(8.dp))
                .background(NV.card.copy(alpha = 0.6f))
                .border(
                    width = 1.dp,
                    color = NV.green.copy(alpha = 0.25f),
                    shape = RoundedCornerShape(8.dp)
                )
                .padding(horizontal = 12.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Box(
                Modifier
                    .size(8.dp)
                    .clip(CircleShape)
                    .background(if (backendConnected) NV.green else Color.Gray)
            )
            Spacer(Modifier.width(8.dp))
            Text(
                "AI COMMAND CHAT",
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold,
                color = NV.green,
                letterSpacing = 2.sp,
                fontFamily = FontFamily.Monospace
            )
            Spacer(Modifier.weight(1f))
            Text(
                if (backendHost.isBlank()) "未連線" else "BACKEND ▸ $backendHost",
                fontSize = 10.sp,
                color = NV.textSecondary,
                fontFamily = FontFamily.Monospace
            )
            Spacer(Modifier.width(8.dp))
            // 自動廣播切換 (AI 回覆自動推送至所有前線)
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .clip(RoundedCornerShape(4.dp))
                    .background(
                        if (autoBroadcast) NV.green.copy(alpha = 0.18f)
                        else Color.Transparent
                    )
                    .border(
                        1.dp,
                        if (autoBroadcast) NV.green.copy(alpha = 0.6f)
                        else NV.textSecondary.copy(alpha = 0.4f),
                        RoundedCornerShape(4.dp)
                    )
                    .clickable { autoBroadcast = !autoBroadcast }
                    .padding(horizontal = 6.dp, vertical = 3.dp)
            ) {
                Icon(
                    Icons.Default.Campaign,
                    contentDescription = null,
                    tint = if (autoBroadcast) NV.green else NV.textSecondary,
                    modifier = Modifier.size(12.dp)
                )
                Spacer(Modifier.width(3.dp))
                Text(
                    if (autoBroadcast) "AUTO BC" else "BC OFF",
                    fontSize = 9.sp,
                    fontWeight = FontWeight.Bold,
                    color = if (autoBroadcast) NV.green else NV.textSecondary,
                    fontFamily = FontFamily.Monospace
                )
            }
            Spacer(Modifier.width(6.dp))
            IconButton(
                onClick = { messages = emptyList() },
                enabled = messages.isNotEmpty() && !isSending,
                modifier = Modifier.size(28.dp)
            ) {
                Icon(
                    Icons.Default.DeleteSweep,
                    contentDescription = "清除對話",
                    tint = if (messages.isEmpty()) NV.textSecondary else NV.warning,
                    modifier = Modifier.size(18.dp)
                )
            }
        }

        Spacer(Modifier.height(10.dp))

        // === 訊息列表 ===
        Box(modifier = Modifier.weight(1f).fillMaxWidth()) {
            if (messages.isEmpty() && !isSending) {
                EmptyHint()
            } else {
                LazyColumn(
                    state = listState,
                    modifier = Modifier.fillMaxSize(),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                    contentPadding = PaddingValues(vertical = 4.dp)
                ) {
                    items(messages) { msg ->
                        AIBubble(msg)
                    }
                    if (isSending) {
                        item { TypingIndicator() }
                    }
                }
            }
        }

        Spacer(Modifier.height(8.dp))

        // === 輸入列 ===
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.Bottom
        ) {
            OutlinedTextField(
                value = draft,
                onValueChange = { draft = it },
                modifier = Modifier.weight(1f),
                placeholder = { Text("向 AI 提問或下達指揮指令…", fontSize = 13.sp) },
                maxLines = 4,
                enabled = !isSending,
                keyboardOptions = KeyboardOptions(
                    capitalization = KeyboardCapitalization.Sentences,
                    imeAction = ImeAction.Default
                ),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = NV.green,
                    unfocusedBorderColor = NV.green.copy(alpha = 0.3f),
                    focusedTextColor = NV.white,
                    unfocusedTextColor = NV.white,
                    cursorColor = NV.green
                )
            )
            Spacer(Modifier.width(8.dp))
            FilledIconButton(
                onClick = { sendMessage() },
                enabled = draft.isNotBlank() && !isSending && backendHost.isNotBlank(),
                modifier = Modifier.size(56.dp),
                colors = IconButtonDefaults.filledIconButtonColors(
                    containerColor = NV.green,
                    disabledContainerColor = NV.green.copy(alpha = 0.2f)
                )
            ) {
                Icon(Icons.Default.Send, contentDescription = "送出", tint = Color.Black)
            }
        }
    }
}

@Composable
private fun EmptyHint() {
    Column(
        modifier = Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.Center,
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Icon(
            Icons.Default.AutoAwesome,
            contentDescription = null,
            tint = NV.green.copy(alpha = 0.3f),
            modifier = Modifier.size(64.dp)
        )
        Spacer(Modifier.height(12.dp))
        Text(
            "AI 指揮對話",
            fontSize = 16.sp,
            fontWeight = FontWeight.Bold,
            color = NV.green.copy(alpha = 0.7f),
            letterSpacing = 4.sp,
            fontFamily = FontFamily.Monospace
        )
        Spacer(Modifier.height(8.dp))
        Text(
            "可詢問:處置建議 / 戰術規劃 / 資源評估 / 風險分析",
            fontSize = 12.sp,
            color = NV.textSecondary
        )
    }
}

@Composable
private fun AIBubble(msg: HQAIMessage) {
    val isUser = msg.role == "user"
    val bubbleColor = when {
        msg.isError -> NV.danger.copy(alpha = 0.18f)
        isUser -> NV.blue.copy(alpha = 0.18f)
        else -> NV.green.copy(alpha = 0.10f)
    }
    val borderColor = when {
        msg.isError -> NV.danger.copy(alpha = 0.5f)
        isUser -> NV.blue.copy(alpha = 0.4f)
        else -> NV.green.copy(alpha = 0.4f)
    }

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = if (isUser) Arrangement.End else Arrangement.Start
    ) {
        if (isUser) Spacer(Modifier.width(48.dp))
        Column(
            modifier = Modifier
                .clip(RoundedCornerShape(10.dp))
                .background(bubbleColor)
                .border(1.dp, borderColor, RoundedCornerShape(10.dp))
                .padding(horizontal = 12.dp, vertical = 8.dp)
        ) {
            // Header
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    if (isUser) Icons.Default.Person else Icons.Default.AutoAwesome,
                    contentDescription = null,
                    tint = if (msg.isError) NV.danger else if (isUser) NV.blue else NV.green,
                    modifier = Modifier.size(14.dp)
                )
                Spacer(Modifier.width(6.dp))
                Text(
                    text = if (isUser) "HQ 指揮官" else (msg.model ?: "GEMMA4 AI"),
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Bold,
                    color = if (msg.isError) NV.danger else if (isUser) NV.blue else NV.green,
                    fontFamily = FontFamily.Monospace,
                    letterSpacing = 1.sp
                )
                Spacer(Modifier.weight(1f))
                Text(
                    formatTs(msg.timestamp),
                    fontSize = 9.sp,
                    color = NV.textSecondary,
                    fontFamily = FontFamily.Monospace
                )
            }
            Spacer(Modifier.height(4.dp))
            Text(
                text = msg.content,
                fontSize = 13.sp,
                color = NV.white,
                lineHeight = 18.sp
            )
            if (!isUser && msg.elapsedMs != null) {
                Spacer(Modifier.height(4.dp))
                Text(
                    "響應 ${msg.elapsedMs} ms",
                    fontSize = 9.sp,
                    color = NV.textSecondary,
                    fontFamily = FontFamily.Monospace
                )
            }
        }
        if (!isUser) Spacer(Modifier.width(48.dp))
    }
}

@Composable
private fun TypingIndicator() {
    val infinite = rememberInfiniteTransition(label = "typing")
    val alpha by infinite.animateFloat(
        initialValue = 0.3f, targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(700, easing = EaseInOut), RepeatMode.Reverse),
        label = "alpha"
    )
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.Start
    ) {
        Row(
            modifier = Modifier
                .clip(RoundedCornerShape(10.dp))
                .background(NV.green.copy(alpha = 0.10f))
                .border(1.dp, NV.green.copy(alpha = 0.4f), RoundedCornerShape(10.dp))
                .padding(horizontal = 14.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                Icons.Default.AutoAwesome,
                contentDescription = null,
                tint = NV.green.copy(alpha = alpha),
                modifier = Modifier.size(14.dp)
            )
            Spacer(Modifier.width(6.dp))
            Text(
                "AI 思考中…",
                fontSize = 12.sp,
                color = NV.green.copy(alpha = alpha),
                fontFamily = FontFamily.Monospace,
                letterSpacing = 2.sp
            )
        }
    }
}

private val httpClient: OkHttpClient by lazy {
    OkHttpClient.Builder()
        .connectTimeout(8, TimeUnit.SECONDS)
        .readTimeout(120, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .build()
}

private val JSON_MEDIA = "application/json; charset=utf-8".toMediaType()

@Throws(Exception::class)
private fun callChat(backendHost: String, message: String, history: List<HQAIMessage>): HQAIMessage {
    val url = "http://$backendHost:8001/chat"
    val body = JSONObject().apply {
        put("message", message)
        put("history", JSONArray().apply {
            history.takeLast(12).forEach {
                put(JSONObject().apply {
                    put("role", it.role)
                    put("content", it.content)
                })
            }
        })
    }.toString().toRequestBody(JSON_MEDIA)

    val request = Request.Builder().url(url).post(body).build()
    httpClient.newCall(request).execute().use { resp ->
        val raw = resp.body?.string().orEmpty()
        if (!resp.isSuccessful) throw RuntimeException("HTTP ${resp.code}: ${raw.take(200)}")
        val json = JSONObject(raw)
        val data = json.optJSONObject("data") ?: json
        val reply = data.optString("reply").trim()
        val model = data.optString("model").ifBlank { null }
        val elapsed = if (data.has("elapsed_ms")) data.optInt("elapsed_ms") else null
        return HQAIMessage(
            role = "assistant",
            content = reply.ifBlank { "(AI 未回覆任何內容)" },
            model = model,
            elapsedMs = elapsed,
            isError = reply.isBlank()
        )
    }
}

private fun formatTs(ts: Long): String =
    SimpleDateFormat("HH:mm:ss", Locale.US).format(Date(ts))
