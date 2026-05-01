//
//  linkguardApp.swift
//  linkguard
//
//  Created by YL on 2026/3/21.
//

import SwiftUI

@main
struct linkguardApp: App {
    @State private var showSplash = true
    @AppStorage("appColorScheme") private var appColorScheme: String = "dark"
    @StateObject private var l10n = L10n.shared

    init() {
        // Plan v2 Phase B：啟動全域電台監聽（背景/鎖屏可繼續播放 HQ 廣播）
        GlobalRadioListener.shared.activate()
    }

    private var colorScheme: ColorScheme? {
        switch appColorScheme {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .opacity(showSplash ? 0 : 1)

                if showSplash {
                    SplashView {
                        showSplash = false
                    }
                    .transition(.opacity)
                    .zIndex(999)
                }
            }
            .animation(.easeInOut(duration: 0.5), value: showSplash)
            .preferredColorScheme(colorScheme)
            .environment(\.locale, Locale(identifier: l10n.language))
            .environmentObject(l10n)
            .tint(NV.green)
        }
    }
}
