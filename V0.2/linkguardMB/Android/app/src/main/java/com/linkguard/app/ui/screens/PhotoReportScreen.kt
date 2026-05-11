package com.linkguard.app.ui.screens

import android.Manifest
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Environment
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import coil.compose.AsyncImage
import com.linkguard.app.ui.theme.NV
import com.linkguard.app.ui.theme.NVShape
import com.linkguard.app.viewmodel.LinkGuardViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.MultipartBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.File
import java.text.SimpleDateFormat
import java.util.*
import java.util.concurrent.TimeUnit

// =====================================================
//  照片回報頁面 — 對應 iOS PhotoReportView
// =====================================================

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PhotoReportScreen(viewModel: LinkGuardViewModel) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val photoReports by viewModel.photoReports.collectAsState()
    val isConnected by viewModel.commandClient.isConnected.collectAsState()

    var selectedImageUri by remember { mutableStateOf<Uri?>(null) }
    var locationDesc by remember { mutableStateOf("") }
    var caption by remember { mutableStateOf("") }
    var isUploading by remember { mutableStateOf(false) }
    var statusMessage by remember { mutableStateOf<String?>(null) }
    var cameraImageUri by remember { mutableStateOf<Uri?>(null) }

    // 相簿選擇器
    val galleryLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.GetContent()
    ) { uri -> uri?.let { selectedImageUri = it } }

    // 相機拍照
    val cameraLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.TakePicture()
    ) { success ->
        if (success) selectedImageUri = cameraImageUri
    }

    // 相機權限
    val cameraPermissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) {
            val photoFile = File.createTempFile(
                "LG_${SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())}_",
                ".jpg",
                context.getExternalFilesDir(Environment.DIRECTORY_PICTURES)
            )
            val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", photoFile)
            cameraImageUri = uri
            cameraLauncher.launch(uri)
        }
    }

    fun launchCamera() {
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA)
            == PackageManager.PERMISSION_GRANTED
        ) {
            val photoFile = File.createTempFile(
                "LG_${SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())}_",
                ".jpg",
                context.getExternalFilesDir(Environment.DIRECTORY_PICTURES)
            )
            val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", photoFile)
            cameraImageUri = uri
            cameraLauncher.launch(uri)
        } else {
            cameraPermissionLauncher.launch(Manifest.permission.CAMERA)
        }
    }

    fun uploadPhoto() {
        val uri = selectedImageUri ?: return
        val host = viewModel.commandClient.serverHost
        if (host.isEmpty()) {
            statusMessage = "未連線指揮中心，無法上傳"
            return
        }
        isUploading = true
        statusMessage = null
        scope.launch {
            try {
                val result = withContext(Dispatchers.IO) {
                    val inputStream = context.contentResolver.openInputStream(uri)
                        ?: throw Exception("無法讀取照片")
                    val bytes = inputStream.readBytes()
                    inputStream.close()

                    val isoFmt = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ssXXX", Locale.US)
                    val requestBody = MultipartBody.Builder()
                        .setType(MultipartBody.FORM)
                        .addFormDataPart("device_id", "android-${android.os.Build.MODEL}")
                        .addFormDataPart("sender_name", "android-${android.os.Build.MODEL}")
                        .addFormDataPart("lat", "0")
                        .addFormDataPart("lon", "0")
                        .addFormDataPart("location_desc", locationDesc)
                        .addFormDataPart("caption", caption)
                        .addFormDataPart("timestamp", isoFmt.format(Date()))
                        .addFormDataPart(
                            "photo", "photo.jpg",
                            bytes.toRequestBody("image/jpeg".toMediaType())
                        )
                        .build()

                    val request = Request.Builder()
                        .url("http://$host:8014/photo")
                        .post(requestBody)
                        .build()

                    val client = OkHttpClient.Builder()
                        .connectTimeout(15, TimeUnit.SECONDS)
                        .writeTimeout(60, TimeUnit.SECONDS)
                        .readTimeout(15, TimeUnit.SECONDS)
                        .build()

                    val response = client.newCall(request).execute()
                    if (response.isSuccessful) "上傳成功"
                    else "上傳失敗：${response.code}"
                }
                statusMessage = result
                if (result == "上傳成功") {
                    selectedImageUri = null
                    caption = ""
                    locationDesc = ""
                }
            } catch (e: Exception) {
                statusMessage = "上傳失敗：${e.message}"
            } finally {
                isUploading = false
            }
        }
    }

    Column(modifier = Modifier.fillMaxSize()) {
        Text(
            "照片回報",
            fontSize = 22.sp,
            fontWeight = FontWeight.Bold,
            color = NV.white,
            modifier = Modifier.padding(start = 16.dp, top = 12.dp, end = 16.dp)
        )

        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 16.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            // 照片預覽
            item {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(containerColor = NV.card),
                    shape = NVShape.card,
                    elevation = CardDefaults.cardElevation(defaultElevation = 4.dp)
                ) {
                    if (selectedImageUri != null) {
                        AsyncImage(
                            model = selectedImageUri,
                            contentDescription = "選擇的照片",
                            modifier = Modifier
                                .fillMaxWidth()
                                .heightIn(max = 280.dp)
                                .clip(NVShape.card),
                            contentScale = ContentScale.Fit
                        )
                    } else {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(200.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                                Icon(
                                    Icons.Default.CameraAlt, null,
                                    modifier = Modifier.size(64.dp),
                                    tint = NV.textSecondary.copy(alpha = 0.5f)
                                )
                                Spacer(modifier = Modifier.height(8.dp))
                                Text("選擇或拍攝照片", color = NV.textSecondary, fontSize = 16.sp)
                            }
                        }
                    }
                }
            }

            // 照片來源按鈕
            item {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Button(
                        onClick = { launchCamera() },
                        colors = ButtonDefaults.buttonColors(containerColor = NV.command),
                        modifier = Modifier.weight(1f).defaultMinSize(minHeight = 56.dp)
                    ) {
                        Icon(Icons.Default.CameraAlt, null, modifier = Modifier.size(22.dp))
                        Spacer(modifier = Modifier.width(6.dp))
                        Text("拍照", fontSize = 16.sp)
                    }
                    Button(
                        onClick = { galleryLauncher.launch("image/*") },
                        colors = ButtonDefaults.buttonColors(containerColor = NV.team),
                        modifier = Modifier.weight(1f).defaultMinSize(minHeight = 56.dp)
                    ) {
                        Icon(Icons.Default.PhotoLibrary, null, modifier = Modifier.size(22.dp))
                        Spacer(modifier = Modifier.width(6.dp))
                        Text("相簿", fontSize = 16.sp)
                    }
                }
            }

            // 說明欄位
            item {
                Card(
                    modifier = Modifier.fillMaxWidth(),
                    colors = CardDefaults.cardColors(containerColor = NV.card),
                    shape = NVShape.card,
                    elevation = CardDefaults.cardElevation(defaultElevation = 4.dp)
                ) {
                    Column(
                        modifier = Modifier.padding(16.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        OutlinedTextField(
                            value = locationDesc,
                            onValueChange = { locationDesc = it },
                            label = { Text("位置描述（如：B區3F走廊）") },
                            modifier = Modifier.fillMaxWidth(),
                            singleLine = true,
                            colors = OutlinedTextFieldDefaults.colors(
                                focusedTextColor = NV.white,
                                unfocusedTextColor = NV.white,
                                focusedBorderColor = NV.command,
                                unfocusedBorderColor = NV.cardBorder,
                                focusedLabelColor = NV.command,
                                unfocusedLabelColor = NV.textSecondary
                            )
                        )
                        OutlinedTextField(
                            value = caption,
                            onValueChange = { caption = it },
                            label = { Text("照片說明") },
                            modifier = Modifier.fillMaxWidth(),
                            singleLine = true,
                            colors = OutlinedTextFieldDefaults.colors(
                                focusedTextColor = NV.white,
                                unfocusedTextColor = NV.white,
                                focusedBorderColor = NV.command,
                                unfocusedBorderColor = NV.cardBorder,
                                focusedLabelColor = NV.command,
                                unfocusedLabelColor = NV.textSecondary
                            )
                        )
                    }
                }
            }

            // 上傳按鈕
            item {
                Button(
                    onClick = { uploadPhoto() },
                    enabled = selectedImageUri != null && !isUploading && isConnected,
                    colors = ButtonDefaults.buttonColors(
                        containerColor = NV.green,
                        disabledContainerColor = NV.cardBorder
                    ),
                    modifier = Modifier.fillMaxWidth().defaultMinSize(minHeight = 56.dp)
                ) {
                    if (isUploading) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(18.dp),
                            color = NV.white,
                            strokeWidth = 2.dp
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("上傳中…", color = NV.white)
                    } else {
                        Icon(Icons.Default.CloudUpload, null, tint = NV.white)
                        Spacer(modifier = Modifier.width(8.dp))
                        Text("上傳照片回報", color = NV.white, fontWeight = FontWeight.Bold)
                    }
                }
            }

            // 狀態訊息
            statusMessage?.let { msg ->
                item {
                    Text(
                        msg,
                        color = if (msg.contains("成功")) NV.green else NV.danger,
                        fontSize = 13.sp
                    )
                }
            }

            // 已回報照片列表
            if (photoReports.isNotEmpty()) {
                item {
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        "已回報照片（${photoReports.size}）",
                        color = NV.textSecondary,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Bold
                    )
                }
                items(photoReports, key = { it.id }) { photo ->
                    Card(
                        modifier = Modifier.fillMaxWidth(),
                        colors = CardDefaults.cardColors(containerColor = NV.card),
                        shape = RoundedCornerShape(8.dp),
                        elevation = CardDefaults.cardElevation(defaultElevation = 3.dp)
                    ) {
                        Row(
                            modifier = Modifier.padding(12.dp),
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            AsyncImage(
                                model = photo.thumbnailURL,
                                contentDescription = null,
                                modifier = Modifier
                                    .size(56.dp)
                                    .clip(RoundedCornerShape(8.dp)),
                                contentScale = ContentScale.Crop
                            )
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    photo.caption.ifEmpty { photo.id },
                                    color = NV.white,
                                    fontSize = 13.sp,
                                    fontWeight = FontWeight.Bold,
                                    maxLines = 1
                                )
                                Text(
                                    "${photo.senderName} · ${photo.locationDesc}",
                                    color = NV.textSecondary,
                                    fontSize = 11.sp
                                )
                            }
                        }
                    }
                }
            }

            item { Spacer(modifier = Modifier.height(16.dp)) }
        }
    }
}
