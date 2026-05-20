package com.linkguard.app.ui.screens

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.speech.tts.TextToSpeech
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.res.stringResource
import com.linkguard.app.R
import com.linkguard.app.model.TranslationResult
import com.linkguard.app.ui.theme.NV
import com.linkguard.app.ui.theme.NVShape
import com.linkguard.app.viewmodel.LinkGuardViewModel
import java.util.*

private val languages = listOf(
    "auto" to "自動偵測",
    "zh-TW" to "繁體中文",
    "en" to "English",
    "ja" to "日本語",
    "ko" to "한국어",
    "vi" to "Tiếng Việt",
    "th" to "ภาษาไทย",
    "id" to "Bahasa Indonesia",
    "ms" to "Bahasa Melayu",
)

private val quickPhrases = listOf(
    "你有哪裡不舒服？" to "哪裡不舒服",
    "你能呼吸嗎？" to "能呼吸嗎",
    "我要幫助你" to "我要幫你",
    "請不要移動" to "不要移動",
    "救護車來了" to "救護車來了",
    "你叫什麼名字？" to "你的名字",
    "你有沒有過敏？" to "過敏史",
    "請張開嘴巴" to "張開嘴巴",
)

private val langToLocale = mapOf(
    "zh-TW" to Locale.TRADITIONAL_CHINESE,
    "en" to Locale.US,
    "ja" to Locale.JAPAN,
    "ko" to Locale.KOREA,
    "vi" to Locale("vi"),
    "th" to Locale("th"),
    "id" to Locale("in"),
    "ms" to Locale("ms"),
)

@Composable
fun TranslatorScreen(viewModel: LinkGuardViewModel) {
    val context = LocalContext.current
    var inputText by remember { mutableStateOf("") }
    var sourceLang by remember { mutableStateOf("auto") }
    var targetLang by remember { mutableStateOf("en") }
    var sourceExpanded by remember { mutableStateOf(false) }
    var targetExpanded by remember { mutableStateOf(false) }
    val result by viewModel.latestTranslation.collectAsState()
    val isTranslating by viewModel.isTranslating.collectAsState()
    val translationError by viewModel.translationError.collectAsState()

    var tts by remember { mutableStateOf<TextToSpeech?>(null) }
    DisposableEffect(Unit) {
        val t = TextToSpeech(context) {}
        tts = t
        onDispose { t.shutdown() }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        // 語言選擇器
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.fillMaxWidth()
        ) {
            // 來源語言
            Box(modifier = Modifier.weight(1f)) {
                OutlinedButton(onClick = { sourceExpanded = true }, modifier = Modifier.fillMaxWidth().defaultMinSize(minHeight = 56.dp)) {
                    Text(languages.firstOrNull { it.first == sourceLang }?.second ?: sourceLang, fontSize = 14.sp, color = NV.white)
                }
                DropdownMenu(expanded = sourceExpanded, onDismissRequest = { sourceExpanded = false }) {
                    languages.forEach { (code, name) ->
                        DropdownMenuItem(text = { Text(name, color = NV.white) }, onClick = {
                            sourceLang = code
                            sourceExpanded = false
                        })
                    }
                }
            }

            // 交換按鈕
            IconButton(
                onClick = {
                    if (sourceLang != "auto") {
                        val tmp = sourceLang
                        sourceLang = targetLang
                        targetLang = tmp
                    }
                },
                enabled = sourceLang != "auto",
                modifier = Modifier.defaultMinSize(minWidth = 56.dp, minHeight = 56.dp)
            ) {
                Icon(Icons.Default.SwapHoriz, contentDescription = stringResource(R.string.translator_swap), tint = NV.command)
            }

            // 目標語言
            Box(modifier = Modifier.weight(1f)) {
                OutlinedButton(onClick = { targetExpanded = true }, modifier = Modifier.fillMaxWidth().defaultMinSize(minHeight = 56.dp)) {
                    Text(languages.firstOrNull { it.first == targetLang }?.second ?: targetLang, fontSize = 14.sp, color = NV.white)
                }
                DropdownMenu(expanded = targetExpanded, onDismissRequest = { targetExpanded = false }) {
                    languages.filter { it.first != "auto" }.forEach { (code, name) ->
                        DropdownMenuItem(text = { Text(name, color = NV.white) }, onClick = {
                            targetLang = code
                            targetExpanded = false
                        })
                    }
                }
            }
        }

        // 輸入區
        OutlinedTextField(
            value = inputText,
            onValueChange = { inputText = it },
            modifier = Modifier.fillMaxWidth().heightIn(min = 100.dp),
            placeholder = { Text(stringResource(R.string.translator_placeholder), color = NV.textSecondary.copy(alpha = 0.6f)) },
            maxLines = 5,
            colors = OutlinedTextFieldDefaults.colors(
                focusedTextColor = NV.white,
                unfocusedTextColor = NV.white,
                focusedBorderColor = NV.command,
                unfocusedBorderColor = NV.cardBorder
            )
        )

        Button(
            onClick = {
                val text = inputText.trim()
                if (text.isNotEmpty()) {
                    viewModel.requestTranslation(text, sourceLang, targetLang)
                }
            },
            modifier = Modifier.fillMaxWidth().defaultMinSize(minHeight = 56.dp),
            enabled = inputText.trim().isNotEmpty() && !isTranslating,
            colors = ButtonDefaults.buttonColors(containerColor = NV.command)
        ) {
            if (isTranslating) {
                CircularProgressIndicator(
                    modifier = Modifier.size(20.dp),
                    color = NV.white,
                    strokeWidth = 2.dp
                )
                Spacer(Modifier.width(8.dp))
                Text(stringResource(R.string.translator_translate) + "...", fontSize = 16.sp)
            } else {
                Icon(Icons.Default.Translate, contentDescription = null, modifier = Modifier.size(22.dp))
                Spacer(Modifier.width(8.dp))
                Text(stringResource(R.string.translator_translate), fontSize = 16.sp)
            }
        }

        // 錯誤訊息
        translationError?.let { err ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(Color(0xFF4A1F1F), RoundedCornerShape(8.dp))
                    .padding(12.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(Icons.Default.Warning, contentDescription = null, tint = Color(0xFFFF6B6B), modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(8.dp))
                Text(err, fontSize = 13.sp, color = Color(0xFFFFB3B3), modifier = Modifier.weight(1f))
                TextButton(onClick = { viewModel.clearTranslationError() }) {
                    Text("✕", color = NV.textSecondary)
                }
            }
        }

        // 快速醫療用語
        Text(stringResource(R.string.translator_quick), fontSize = 14.sp, color = NV.textSecondary, fontWeight = FontWeight.SemiBold)
        LazyVerticalGrid(
            columns = GridCells.Fixed(2),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier.heightIn(max = 200.dp)
        ) {
            items(quickPhrases) { (text, label) ->
                OutlinedButton(
                    onClick = {
                        inputText = text
                        viewModel.requestTranslation(text, sourceLang, targetLang)
                    },
                    contentPadding = PaddingValues(horizontal = 12.dp, vertical = 10.dp),
                    modifier = Modifier.fillMaxWidth().defaultMinSize(minHeight = 48.dp)
                ) {
                    Text(label, fontSize = 14.sp, maxLines = 1, color = NV.command)
                }
            }
        }

        // 翻譯結果
        result?.let { r ->
            @Suppress("DEPRECATION")
            androidx.compose.material3.Divider()

            // 原文
            Column {
                Row {
                    Text(stringResource(R.string.translator_original), fontSize = 12.sp, color = NV.textSecondary)
                    if (r.detectedLang.isNotEmpty()) {
                        Text(" (${r.detectedLang})", fontSize = 10.sp, color = NV.textSecondary)
                    }
                }
                Text(r.original, fontSize = 14.sp, color = NV.white)
            }

            // 譯文
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(NV.command.copy(alpha = 0.08f), NVShape.card)
                    .padding(16.dp)
            ) {
                Text("${stringResource(R.string.translator_result)} (${r.targetLang})", fontSize = 12.sp, color = NV.textSecondary)
                Spacer(Modifier.height(4.dp))
                Text(r.translated, fontSize = 20.sp, fontWeight = FontWeight.Medium, color = NV.white)
            }

            // 操作按鈕
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedButton(onClick = {
                    val clipboard = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    clipboard.setPrimaryClip(ClipData.newPlainText("translation", r.translated))
                }) {
                    Icon(Icons.Default.ContentCopy, contentDescription = null, modifier = Modifier.size(16.dp))
                    Spacer(Modifier.width(4.dp))
                    Text(stringResource(R.string.translator_copy), fontSize = 13.sp, color = NV.command)
                }

                OutlinedButton(onClick = {
                    val locale = langToLocale[r.targetLang] ?: Locale.US
                    tts?.language = locale
                    tts?.speak(r.translated, TextToSpeech.QUEUE_FLUSH, null, null)
                }) {
                    Icon(Icons.Default.VolumeUp, contentDescription = null, modifier = Modifier.size(16.dp), tint = NV.command)
                    Spacer(Modifier.width(4.dp))
                    Text(stringResource(R.string.translator_speak), fontSize = 13.sp, color = NV.command)
                }
            }
        }
    }
}
