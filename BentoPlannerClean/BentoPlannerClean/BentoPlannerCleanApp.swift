//
//  BentoPlannerCleanApp.swift
//  BentoPlannerClean
//
//  Created by ru na on 2025/07/01.
//

import SwiftUI
import GoogleMobileAds

@main
struct BentoPlannerCleanApp: App {
    @StateObject private var bentoStore = BentoStore()

    init() {
        print("🚀 アプリ起動: AdMob SDK初期化開始")
        // AdMob SDKを初期化
        GADMobileAds.sharedInstance().start { status in
            print("✅ AdMob SDK初期化完了")
            print("📊 AdMob Adapter Status:")
            for (adapterName, adapterStatus) in status.adapterStatusesByClassName {
                print("  - \(adapterName): \(adapterStatus.state.rawValue) - \(adapterStatus.description)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bentoStore)
                .font(.system(size: 16, weight: .regular, design: .rounded))
        }
    }
}
