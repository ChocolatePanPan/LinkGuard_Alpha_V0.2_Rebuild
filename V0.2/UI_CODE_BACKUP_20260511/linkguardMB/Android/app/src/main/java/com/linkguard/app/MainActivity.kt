package com.linkguard.app

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
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
import com.linkguard.app.ui.screens.MainScreen
import com.linkguard.app.ui.screens.OnboardingScreen
import com.linkguard.app.ui.screens.SplashScreen
import com.linkguard.app.ui.theme.LinkGuardTheme
import com.linkguard.app.ui.theme.NV
import com.linkguard.app.util.LocaleHelper
import com.linkguard.app.viewmodel.LinkGuardViewModel

class MainActivity : ComponentActivity() {

    private val viewModel: LinkGuardViewModel by viewModels()

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
