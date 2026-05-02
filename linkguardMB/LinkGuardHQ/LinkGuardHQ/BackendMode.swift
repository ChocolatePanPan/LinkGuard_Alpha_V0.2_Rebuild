//
//  BackendMode.swift
//  LinkGuardHQ
//
//  Lets the user pick where the Python backend (Gemma4 / Whisper / DB / etc.)
//  runs:
//    - .embedded — managed in-process by BackendSupervisor (this Mac)
//    - .remote   — fixed host:port on another machine
//    - .bonjour  — original behaviour: NWBrowser auto-discovers `_linkguardpy._tcp`
//
//  Persisted via @AppStorage("hq.backendMode") on HQSettingsView.
//

import Foundation
import SwiftUI

enum BackendMode: String, CaseIterable, Identifiable {
    case embedded   = "embedded"
    case remote     = "remote"
    case bonjour    = "bonjour"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .embedded: return L("內建後端 (此 Mac)")
        case .remote:   return L("遠端後端")
        case .bonjour:  return L("Bonjour 自動探索")
        }
    }

    var systemImage: String {
        switch self {
        case .embedded: return "cpu"
        case .remote:   return "network"
        case .bonjour:  return "antenna.radiowaves.left.and.right"
        }
    }

    var helpText: String {
        switch self {
        case .embedded:
            return L("在此 Mac 啟動核心後端服務；Gemma4 / Python Whisper 需要時再啟動。")
        case .remote:
            return L("連接另一台主機上已執行的 Python 後端 (例如效能更強的工作站)。")
        case .bonjour:
            return L("透過 Bonjour 自動尋找區網內的 _linkguardpy._tcp 服務。")
        }
    }
}
