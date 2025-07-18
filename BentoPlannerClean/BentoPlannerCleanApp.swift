import SwiftUI

@main
struct BentoPlannerCleanApp: App {
    @StateObject private var bentoStore = BentoStore()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(bentoStore)
        }
    }
}