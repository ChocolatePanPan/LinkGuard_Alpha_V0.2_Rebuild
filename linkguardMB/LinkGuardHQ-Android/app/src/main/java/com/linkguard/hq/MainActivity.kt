package com.linkguard.hq

import android.content.Context
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.material3.windowsizeclass.ExperimentalMaterial3WindowSizeClassApi
import androidx.compose.material3.windowsizeclass.calculateWindowSizeClass
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.lifecycle.viewmodel.compose.viewModel
import com.linkguard.hq.ui.HQDashboardScreen
import com.linkguard.hq.ui.HQSplashScreen
import com.linkguard.hq.util.LocaleHelper
import com.linkguard.hq.viewmodel.HQViewModel

class MainActivity : ComponentActivity() {

    override fun attachBaseContext(newBase: Context) {
        super.attachBaseContext(LocaleHelper.wrap(newBase))
    }

    @OptIn(ExperimentalMaterial3WindowSizeClassApi::class)
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT)
        )
        setContent {
            val viewModel: HQViewModel = viewModel()
            val windowSizeClass = calculateWindowSizeClass(this)
            var showSplash by remember { mutableStateOf(true) }
            if (showSplash) {
                HQSplashScreen(onComplete = { showSplash = false })
            } else {
                HQDashboardScreen(viewModel, windowSizeClass)
            }
        }
    }
}
