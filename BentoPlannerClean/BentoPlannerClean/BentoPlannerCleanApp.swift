//
//  BentoPlannerCleanApp.swift
//  BentoPlannerClean
//
//  Created by ru na on 2025/07/01.
//

import SwiftUI

@main
struct BentoPlannerCleanApp: App {
    @StateObject private var bentoStore = BentoStore()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bentoStore)
                .font(.system(size: 16, weight: .regular, design: .rounded))
        }
    }
}
