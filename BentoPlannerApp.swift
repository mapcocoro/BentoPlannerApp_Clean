import SwiftUI

@main
struct BentoPlannerApp: App {
    @StateObject private var bentoStore = BentoStore()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bentoStore)
        }
    }
}