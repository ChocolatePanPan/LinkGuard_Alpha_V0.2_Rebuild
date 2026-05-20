package com.linkguard.app.ui.theme

import androidx.compose.foundation.shape.CornerSize
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Shapes
import androidx.compose.ui.unit.dp

// =====================================================
//  NVShapes — 全圓角設計系統 (Material 3 Expressive)
// =====================================================
//
// 將以下值傳入 MaterialTheme(shapes = NVShapes) 後，
// 所有 M3 元件 (Card, Button, TextField, AlertDialog,
// ModalBottomSheet, TopAppBar...) 會自動採用對應圓角：
//
//   extraSmall  →  Chip / Badge
//   small       →  TextField / 小型輸入
//   medium      →  Button / 次要動作
//   large       →  Card / 主容器
//   extraLarge  →  Dialog / BottomSheet / 大型容器
//
val NVShapes = Shapes(
    extraSmall = RoundedCornerShape(8.dp),
    small      = RoundedCornerShape(16.dp),
    medium     = RoundedCornerShape(20.dp),
    large      = RoundedCornerShape(24.dp),
    extraLarge = RoundedCornerShape(28.dp),
)

/**
 * 專案專用圓角 token。給非 Material 元件
 * (Box / Modifier.clip / .background / .border / .shadow) 使用，
 * 取代散落各處的 RoundedCornerShape(14.dp) 字面值。
 */
object NVShape {
    /** 50% 圓角，膠囊狀 — 主要按鈕 / FAB-like 元件 */
    val pill   = RoundedCornerShape(percent = 50)

    /** 卡片標準圓角 (24dp) */
    val card   = RoundedCornerShape(24.dp)

    /** 表單輸入框 (16dp) */
    val field  = RoundedCornerShape(16.dp)

    /** 對話框 (28dp) */
    val dialog = RoundedCornerShape(28.dp)

    /** 底部抽屜（僅頂部圓角） */
    val sheet  = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp)

    /** 圖片 / 縮圖 (20dp) */
    val image  = RoundedCornerShape(20.dp)

    /** 小型徽章 / 標籤 (8dp) — 取代 4-8dp 散值 */
    val badge  = RoundedCornerShape(8.dp)

    /** 次要按鈕 / 內嵌動作 (20dp) */
    val button = RoundedCornerShape(20.dp)
}
