package com.linkguard.app

import android.Manifest
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.nfc.NdefMessage
import android.nfc.NfcAdapter
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.material3.windowsizeclass.ExperimentalMaterial3WindowSizeClassApi
import androidx.compose.material3.windowsizeclass.calculateWindowSizeClass
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.core.content.ContextCompat
import com.linkguard.app.engine.LinkGuardForegroundService
import com.linkguard.app.model.NfcScanResult
import com.linkguard.app.ui.screens.MainScreen
import com.linkguard.app.ui.screens.OnboardingScreen
import com.linkguard.app.ui.screens.SplashScreen
import com.linkguard.app.ui.theme.LinkGuardTheme
import com.linkguard.app.ui.theme.NV
import com.linkguard.app.util.LocaleHelper
import com.linkguard.app.viewmodel.LinkGuardViewModel

class MainActivity : ComponentActivity() {

    private val viewModel: LinkGuardViewModel by viewModels()
    private var nfcAdapter: NfcAdapter? = null
    private var nfcPendingIntent: PendingIntent? = null

    private val permissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { /* 權限結果，BLE 操作時會再檢查 */ }

    override fun attachBaseContext(newBase: Context) {
        super.attachBaseContext(LocaleHelper.wrap(newBase))
    }

    @OptIn(ExperimentalMaterial3WindowSizeClassApi::class)
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestBLEPermissions()

        // NFC 初始化
        nfcAdapter = NfcAdapter.getDefaultAdapter(this)
        viewModel.setNfcAvailable(nfcAdapter != null)
        nfcPendingIntent = PendingIntent.getActivity(
            this, 0,
            Intent(this, javaClass).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
        )

        // 啟動前景保活服務
        LinkGuardForegroundService.start(this)

        setContent {
            val windowSizeClass = calculateWindowSizeClass(this)
            var showSplash by remember { mutableStateOf(true) }
            val isOnboardingComplete by viewModel.isOnboardingComplete.collectAsState()
            val themeMode by viewModel.themeMode.collectAsState()
            LinkGuardTheme(mode = themeMode) {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = NV.bg
                ) {
                    if (showSplash) {
                        SplashScreen(onComplete = { showSplash = false })
                    } else if (!isOnboardingComplete) {
                        OnboardingScreen(onComplete = { role, deptCode ->
                            viewModel.completeOnboarding(role, deptCode)
                        })
                    } else {
                        MainScreen(viewModel, windowSizeClass)
                    }
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        nfcAdapter?.enableForegroundDispatch(this, nfcPendingIntent, null, null)
    }

    override fun onPause() {
        super.onPause()
        nfcAdapter?.disableForegroundDispatch(this)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.action == NfcAdapter.ACTION_NDEF_DISCOVERED ||
            intent.action == NfcAdapter.ACTION_TAG_DISCOVERED ||
            intent.action == NfcAdapter.ACTION_TECH_DISCOVERED) {
            parseNfcIntent(intent)
        }
    }

    private fun parseNfcIntent(intent: Intent) {
        val rawMessages = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableArrayExtra(NfcAdapter.EXTRA_NDEF_MESSAGES, NdefMessage::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableArrayExtra(NfcAdapter.EXTRA_NDEF_MESSAGES)
        } ?: return

        val sb = StringBuilder()
        rawMessages.forEach { raw ->
            val msg = raw as? NdefMessage ?: return@forEach
            msg.records.forEach { record ->
                val payload = record.payload
                if (payload.isNotEmpty()) {
                    // NDEF Text record: byte[0] = status, rest = lang+text
                    val textEncoding = if ((payload[0].toInt() and 0x80) == 0) "UTF-8" else "UTF-16"
                    val langLen = payload[0].toInt() and 0x3F
                    val text = String(payload, langLen + 1, payload.size - langLen - 1, charset(textEncoding))
                    sb.appendLine(text)
                }
            }
        }

        val rawText = sb.toString().trim()
        if (rawText.isNotEmpty()) {
            viewModel.onNfcScanned(NfcScanResult(rawText = rawText))
        }
    }

    private fun requestBLEPermissions() {
        val permissions = mutableListOf<String>()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            permissions.add(Manifest.permission.BLUETOOTH_SCAN)
            permissions.add(Manifest.permission.BLUETOOTH_CONNECT)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            permissions.add(Manifest.permission.POST_NOTIFICATIONS)
        }
        permissions.add(Manifest.permission.ACCESS_FINE_LOCATION)

        val needed = permissions.filter {
            ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
        }
        if (needed.isNotEmpty()) {
            permissionLauncher.launch(needed.toTypedArray())
        }
    }
}
