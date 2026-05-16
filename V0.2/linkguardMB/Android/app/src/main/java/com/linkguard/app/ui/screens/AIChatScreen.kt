package com.linkguard.app.ui.screens

import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.linkguard.app.model.FieldAIMessage
import com.linkguard.app.ui.theme.NV
import com.linkguard.app.ui.theme.NVShape
import com.linkguard.app.viewmodel.LinkGuardViewModel
import kotlinx.coroutines.launch

// =====================================================
//  AI 助理畫面 — 對齊 iOS FieldAIChatView
//  前線搜救人員與 Gemma4 AI 自由對話
//  呼叫 HQ gemma4_server :8001/chat
// =====================================================

@Composable
fun AIChatScreen(viewModel: LinkGuardViewModel) {
    val messages by viewModel.aiChatMessages.collectAsState()
    val isSending by viewModel.isAISending.collectAsState()
    val isAIPaused by viewModel.isAIServicePaused.collectAsState()
    val isConnected by viewModel.commandClient.isConnected.collectAsState()

    var draft by remember { mutableStateOf("") }
    var includeContext by remember { mutableStateOf(true) }

    val listState = rememberLazyListState()
    val scope = rememberCoroutineScope()
    val focusManager = LocalFocusManager.current
    val focusRequester = remember { FocusRequester() }

    // 有新訊息時捲到底部
    LaunchedEffect(messages.size, isSending) {
        if (messages.isNotEmpty() || isSending) {
            listState.animateScrollToItem(maxOf(0, listState.layoutInfo.totalItemsCount - 1))
        }
    }

    Column(modifier = Modifier.fillMaxSize().background(NV.bg)) {
        // 頂部狀態列
        AIChatStatusBar(
            isConnected = isConnected,
            isAIPaused = isAIPaused,
            includeContext = includeContext,
            onContextToggle = { includeContext = it },
            onClear = { viewModel.clearAIChat() },
            canClear = messages.isNotEmpty() && !isSending
        )

        Divider(color = NV.command.copy(alpha = 0.2f), thickness = 0.5.dp)

        if (isAIPaused) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(NV.warning.copy(alpha = 0.08f))
                    .padding(horizontal = 12.dp, vertical = 8.dp)
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Default.PauseCircle, contentDescription = null, tint = NV.warning, modifier = Modifier.size(16.dp))
                    Spacer(Modifier.width(6.dp))
                    Text("AI 服務暫停中（由 HQ 控制）", color = NV.warning, fontSize = 12.sp)
                }
            }
        }

        // 訊息列表
        LazyColumn(
            state = listState,
            modifier = Modifier.weight(1f),
            contentPadding = PaddingValues(horizontal = 12.dp, vertical = 10.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            if (messages.isEmpty() && !isSending) {
                item { AIChatEmptyHint(onPickPrompt = { draft = it }) }
            }

            items(messages, key = { it.id }) { msg ->
                AIChatBubble(msg)
            }

            if (isSending) {
                item { TypingIndicator() }
            }
        }

        Divider(color = NV.command.copy(alpha = 0.2f), thickness = 0.5.dp)

        // 輸入列
        AIChatInputBar(
            draft = draft,
            onDraftChange = { draft = it },
            canSend = draft.isNotBlank() && !isSending && !isAIPaused,
            focusRequester = focusRequester,
            onSend = {
                val text = draft.trim()
                if (text.isNotBlank()) {
                    viewModel.sendAIMessage(text, includeContext)
                    draft = ""
                    focusManager.clearFocus()
                    scope.launch {
                        listState.animateScrollToItem(maxOf(0, listState.layoutInfo.totalItemsCount - 1))
                    }
                }
            }
        )
    }
}

// ===== Status Bar =====

@Composable
private fun AIChatStatusBar(
    isConnected: Boolean,
    isAIPaused: Boolean,
    includeContext: Boolean,
    onContextToggle: (Boolean) -> Unit,
    onClear: () -> Unit,
    canClear: Boolean
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(NV.surface.copy(alpha = 0.6f))
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(8.dp)
                .clip(CircleShape)
                .background(when {
                    isAIPaused   -> Color.Gray
                    isConnected  -> NV.green
                    else         -> Color.Gray
                })
        )
        Spacer(Modifier.width(8.dp))
        Text(
            if (isAIPaused) "AI 服務暫停" else "FIELD AI ASSISTANT",
            color = if (isAIPaused) NV.textSecondary else NV.command,
            fontSize = 12.sp,
            fontWeight = FontWeight.Bold,
            fontFamily = FontFamily.Monospace,
            letterSpacing = 1.5.sp
        )
        Spacer(Modifier.weight(1f))

        // 附帶現場資訊 toggle
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("附帶現場資訊", color = NV.textSecondary, fontSize = 11.sp)
            Spacer(Modifier.width(4.dp))
            Switch(
                checked = includeContext,
                onCheckedChange = onContextToggle,
                colors = SwitchDefaults.colors(
                    checkedThumbColor = Color.White,
                    checkedTrackColor = NV.info,
                    uncheckedThumbColor = NV.textSecondary,
                    uncheckedTrackColor = NV.surface
                ),
                modifier = Modifier.height(24.dp)
            )
        }

        Spacer(Modifier.width(8.dp))
        IconButton(
            onClick = onClear,
            enabled = canClear,
            modifier = Modifier.size(32.dp)
        ) {
            Icon(
                Icons.Default.DeleteOutline,
                contentDescription = "清除對話",
                tint = if (canClear) NV.warning else NV.textSecondary.copy(alpha = 0.4f),
                modifier = Modifier.size(18.dp)
            )
        }
    }
}

// ===== Chat Bubble =====

@Composable
private fun AIChatBubble(msg: FieldAIMessage) {
    val isUser = msg.role == "user"
    val bgColor = when {
        msg.isError -> NV.danger.copy(alpha = 0.15f)
        isUser      -> NV.command.copy(alpha = 0.18f)
        else        -> NV.green.copy(alpha = 0.10f)
    }
    val borderColor = when {
        msg.isError -> NV.danger.copy(alpha = 0.45f)
        isUser      -> NV.command.copy(alpha = 0.45f)
        else        -> NV.green.copy(alpha = 0.45f)
    }
    val accent = when {
        msg.isError -> NV.danger
        isUser      -> NV.command
        else        -> NV.green
    }

    Row(modifier = Modifier.fillMaxWidth()) {
        if (isUser) Spacer(Modifier.width(40.dp))
        Column(
            modifier = Modifier
                .weight(1f)
                .clip(NVShape.card)
                .background(bgColor)
                .border(1.dp, borderColor, NVShape.card)
                .padding(horizontal = 12.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp)
        ) {
            // 頭部：角色 + 時間
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    if (isUser) Icons.Default.Person else Icons.Default.AutoAwesome,
                    contentDescription = null,
                    tint = accent,
                    modifier = Modifier.size(12.dp)
                )
                Spacer(Modifier.width(4.dp))
                Text(
                    if (isUser) "搜救人員" else (msg.model?.uppercase() ?: "GEMMA4 AI"),
                    color = accent,
                    fontSize = 10.sp,
                    fontWeight = FontWeight.Bold,
                    fontFamily = FontFamily.Monospace,
                    letterSpacing = 0.8.sp
                )
                Spacer(Modifier.weight(1f))
                Text(msg.timeText, color = NV.textSecondary, fontSize = 10.sp, fontFamily = FontFamily.Monospace)
            }

            // 訊息內容
            Text(
                msg.content,
                color = NV.textPrimary,
                fontSize = 14.sp,
                lineHeight = 20.sp
            )

            // AI 響應時間
            if (!isUser && msg.elapsedMs != null) {
                Text(
                    "耗時 ${msg.elapsedMs} ms",
                    color = NV.textSecondary.copy(alpha = 0.6f),
                    fontSize = 10.sp,
                    fontFamily = FontFamily.Monospace
                )
            }
        }
        if (!isUser) Spacer(Modifier.width(40.dp))
    }
}

// ===== Typing Indicator =====

@Composable
private fun TypingIndicator() {
    val infiniteTransition = rememberInfiniteTransition(label = "typing")
    val alpha by infiniteTransition.animateFloat(
        initialValue = 0.3f,
        targetValue  = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(700, easing = EaseInOut),
            repeatMode = RepeatMode.Reverse
        ),
        label = "pulse"
    )
    Row(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .alpha(alpha)
                .clip(NVShape.card)
                .background(NV.green.copy(alpha = 0.10f))
                .border(1.dp, NV.green.copy(alpha = 0.4f), NVShape.card)
                .padding(horizontal = 14.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(Icons.Default.AutoAwesome, contentDescription = null, tint = NV.green, modifier = Modifier.size(12.dp))
            Spacer(Modifier.width(6.dp))
            Text(
                "AI 思考中…",
                color = NV.green,
                fontSize = 12.sp,
                fontFamily = FontFamily.Monospace,
                letterSpacing = 1.5.sp
            )
        }
        Spacer(Modifier.weight(1f))
    }
}

// ===== Empty Hint =====

@Composable
private fun AIChatEmptyHint(onPickPrompt: (String) -> Unit) {
    val prompts = listOf(
        "呼吸 36 次/分鐘且意識模糊，要怎麼處置？",
        "這個傷患需要立刻後送嗎？",
        "瓦斯外洩疑慮，撤離半徑多少？",
        "CPR 按壓深度與頻率？"
    )
    Column(
        modifier = Modifier.fillMaxWidth().padding(top = 48.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        Icon(Icons.Default.AutoAwesome, contentDescription = null, tint = NV.command.copy(alpha = 0.3f), modifier = Modifier.size(56.dp))
        Text(
            "AI 助理",
            color = NV.command.copy(alpha = 0.6f),
            fontSize = 16.sp,
            fontWeight = FontWeight.Bold,
            fontFamily = FontFamily.Monospace,
            letterSpacing = 3.sp
        )
        Text(
            "詢問處置建議 / 醫療判斷 / SOP / 翻譯 / 災情評估",
            color = NV.textSecondary,
            fontSize = 12.sp
        )
        Spacer(Modifier.height(8.dp))
        Text("試試問：", color = NV.textSecondary, fontSize = 11.sp)
        prompts.forEach { prompt ->
            TextButton(
                onClick = { onPickPrompt(prompt) },
                colors = ButtonDefaults.textButtonColors(contentColor = NV.info)
            ) {
                Text("• $prompt", fontSize = 12.sp)
            }
        }
    }
}

// ===== Input Bar =====

@Composable
private fun AIChatInputBar(
    draft: String,
    onDraftChange: (String) -> Unit,
    canSend: Boolean,
    focusRequester: FocusRequester,
    onSend: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(NV.surface)
            .padding(horizontal = 12.dp, vertical = 10.dp),
        verticalAlignment = Alignment.Bottom
    ) {
        OutlinedTextField(
            value = draft,
            onValueChange = onDraftChange,
            placeholder = { Text("向 AI 提問現場狀況或醫療建議", fontSize = 13.sp, color = NV.textSecondary) },
            modifier = Modifier
                .weight(1f)
                .focusRequester(focusRequester),
            colors = OutlinedTextFieldDefaults.colors(
                focusedBorderColor = NV.command,
                unfocusedBorderColor = NV.cardBorder,
                focusedTextColor = NV.textPrimary,
                unfocusedTextColor = NV.textPrimary,
                cursorColor = NV.command
            ),
            shape = RoundedCornerShape(20.dp),
            maxLines = 4,
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Send),
            keyboardActions = KeyboardActions(onSend = { if (canSend) onSend() })
        )
        Spacer(Modifier.width(8.dp))
        Box(
            modifier = Modifier
                .size(48.dp)
                .clip(CircleShape)
                .background(if (canSend) NV.green else NV.green.copy(alpha = 0.3f)),
            contentAlignment = Alignment.Center
        ) {
            IconButton(
                onClick = { if (canSend) onSend() },
                enabled = canSend,
                modifier = Modifier.size(48.dp)
            ) {
                Icon(
                    Icons.Default.Send,
                    contentDescription = "發送",
                    tint = if (canSend) Color.Black else Color.Black.copy(alpha = 0.4f),
                    modifier = Modifier.size(20.dp)
                )
            }
        }
    }
}
