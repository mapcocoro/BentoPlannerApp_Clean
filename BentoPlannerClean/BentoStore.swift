import Foundation
import SwiftUI

class BentoStore: ObservableObject {
    @Published var recipes: [BentoRecipe] = []
    @Published var weeklyPlan: WeeklyPlan = WeeklyPlan(weekOf: Date())
    @Published var favoriteRecipes: [BentoRecipe] = []
    @Published var aiGeneratedRecipes: [BentoRecipe] = []
    @Published var dailyRecommendations: [BentoRecipe] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let recipesKey = "SavedBentoRecipes"
    private let weeklyPlanKey = "SavedWeeklyPlan"
    private let dailyRecommendationsKey = "DailyRecommendations"
    private let lastUpdateDateKey = "LastUpdateDate"
    private let aiService = BentoAIService()

    init() {
        loadRecipes()
        if recipes.isEmpty {
            loadSampleData()
        }
        loadWeeklyPlan()
        updateFavorites()
        loadDailyRecommendations()
        generateDailyRecommendations()
    }

    // MARK: - AI Recipe Generation
    func generateAIRecipes(for category: BentoCategory) async {
        print("🔄 Starting AI recipe generation for category: \(category.rawValue)")
        
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        do {
            let newRecipes = try await aiService.generateBentoRecipes(for: category)
            print("✅ Successfully generated \(newRecipes.count) recipes")

            await MainActor.run {
                self.aiGeneratedRecipes = newRecipes
                self.isLoading = false
                print("✅ UI updated with new recipes")
            }
        } catch {
            print("❌ AI recipe generation failed: \(error.localizedDescription)")
            
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
                // フォールバック: 既存のレシピから提案
                let fallbackRecipes = self.generateBentoSuggestions(for: category)
                self.aiGeneratedRecipes = fallbackRecipes
                print("🔄 Using fallback recipes: \(fallbackRecipes.count) recipes")
            }
        }
    }

    // MARK: - Favorite Management
    func toggleFavorite(_ recipe: BentoRecipe) {
        var updatedRecipe = recipe
        updatedRecipe.isFavorite.toggle()
        
        // Update in main recipes list
        if let index = recipes.firstIndex(where: { $0.id == recipe.id }) {
            recipes[index] = updatedRecipe
        } else {
            // Add to main list if not exists
            recipes.append(updatedRecipe)
        }
        
        // Update in AI generated recipes
        if let index = aiGeneratedRecipes.firstIndex(where: { $0.id == recipe.id }) {
            aiGeneratedRecipes[index] = updatedRecipe
        }
        
        saveRecipes()
        updateFavorites()
    }
    
    func isRecipeFavorite(_ recipe: BentoRecipe) -> Bool {
        if let foundRecipe = recipes.first(where: { $0.id == recipe.id }) {
            return foundRecipe.isFavorite
        }
        if let foundRecipe = aiGeneratedRecipes.first(where: { $0.id == recipe.id }) {
            return foundRecipe.isFavorite
        }
        return recipe.isFavorite
    }

    // MARK: - Weekly Plan Management
    func addRecipeToWeeklyPlan(_ recipe: BentoRecipe, day: String) {
        // Add to main recipes if not exists
        if !recipes.contains(where: { $0.id == recipe.id }) {
            recipes.append(recipe)
            saveRecipes()
        }

        switch day {
        case "月": weeklyPlan.monday = recipe
        case "火": weeklyPlan.tuesday = recipe
        case "水": weeklyPlan.wednesday = recipe
        case "木": weeklyPlan.thursday = recipe
        case "金": weeklyPlan.friday = recipe
        default: break
        }
        saveWeeklyPlan()
    }
    
    func removeRecipeFromWeeklyPlan(day: String) {
        switch day {
        case "月": weeklyPlan.monday = nil
        case "火": weeklyPlan.tuesday = nil
        case "水": weeklyPlan.wednesday = nil
        case "木": weeklyPlan.thursday = nil
        case "金": weeklyPlan.friday = nil
        case "土": weeklyPlan.saturday = nil
        case "日": weeklyPlan.sunday = nil
        default: break
        }
        saveWeeklyPlan()
    }

    // MARK: - Helper Methods
    private func generateBentoSuggestions(for category: BentoCategory) -> [BentoRecipe] {
        return recipes.filter { $0.category == category }.shuffled().prefix(3).map { $0 }
    }
    
    private func updateFavorites() {
        favoriteRecipes = recipes.filter { $0.isFavorite }
    }
    
    // MARK: - Daily Recommendations
    func generateDailyRecommendations() {
        let today = Date()
        let calendar = Calendar.current
        
        // 今日の日付を文字列で比較
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let todayString = dateFormatter.string(from: today)
        
        if let lastUpdateDate = UserDefaults.standard.object(forKey: lastUpdateDateKey) as? Date {
            let lastUpdateString = dateFormatter.string(from: lastUpdateDate)
            if todayString == lastUpdateString {
                // 今日既に更新済み
                return
            }
        }
        
        print("🔄 Generating daily recommendations...")
        print("📊 Total recipes available: \(recipes.count)")
        
        // 日付ベースのランダム推薦を生成
        let allCategories = BentoCategory.allCases
        let daysSinceEpoch = calendar.dateComponents([.day], from: Date(timeIntervalSince1970: 0), to: today).day!
        
        var recommendations: [BentoRecipe] = []
        
        for i in 0..<3 {
            let categoryIndex = (daysSinceEpoch + i) % allCategories.count
            let category = allCategories[categoryIndex]
            
            let categoryRecipes = recipes.filter { $0.category == category }
            if let randomRecipe = categoryRecipes.randomElement() {
                recommendations.append(randomRecipe)
                print("✅ Added recommendation from \(category.rawValue): \(randomRecipe.name)")
            }
        }
        
        // 足りない分はランダムに補填
        while recommendations.count < 3 && !recipes.isEmpty {
            if let randomRecipe = recipes.randomElement(),
               !recommendations.contains(where: { $0.id == randomRecipe.id }) {
                recommendations.append(randomRecipe)
                print("✅ Added fallback recommendation: \(randomRecipe.name)")
            }
        }
        
        // 推薦が0個の場合は最低でも1つ追加
        if recommendations.isEmpty && !recipes.isEmpty {
            if let firstRecipe = recipes.first {
                recommendations.append(firstRecipe)
                print("✅ Added first available recipe: \(firstRecipe.name)")
            }
        }
        
        dailyRecommendations = recommendations
        UserDefaults.standard.set(today, forKey: lastUpdateDateKey)
        saveDailyRecommendations()
        
        print("📱 Daily recommendations updated: \(recommendations.count) recipes")
        print("📝 Recipes: \(recommendations.map { $0.name })")
    }
    
    // 強制的に本日の推薦を再生成
    func forceUpdateDailyRecommendations() {
        UserDefaults.standard.removeObject(forKey: lastUpdateDateKey)
        generateDailyRecommendations()
    }
    
    private func saveDailyRecommendations() {
        if let encoded = try? JSONEncoder().encode(dailyRecommendations) {
            UserDefaults.standard.set(encoded, forKey: dailyRecommendationsKey)
        }
    }
    
    private func loadDailyRecommendations() {
        if let data = UserDefaults.standard.data(forKey: dailyRecommendationsKey),
           let decoded = try? JSONDecoder().decode([BentoRecipe].self, from: data) {
            dailyRecommendations = decoded
        }
    }

    // MARK: - Persistence
    private func saveRecipes() {
        if let encoded = try? JSONEncoder().encode(recipes) {
            UserDefaults.standard.set(encoded, forKey: recipesKey)
        }
    }

    private func loadRecipes() {
        if let data = UserDefaults.standard.data(forKey: recipesKey),
           let decoded = try? JSONDecoder().decode([BentoRecipe].self, from: data) {
            recipes = decoded
        }
    }

    private func saveWeeklyPlan() {
        if let encoded = try? JSONEncoder().encode(weeklyPlan) {
            UserDefaults.standard.set(encoded, forKey: weeklyPlanKey)
        }
    }

    private func loadWeeklyPlan() {
        if let data = UserDefaults.standard.data(forKey: weeklyPlanKey),
           let decoded = try? JSONDecoder().decode(WeeklyPlan.self, from: data) {
            weeklyPlan = decoded
        }
    }
    
    // MARK: - Sample Data
    private func loadSampleData() {
        let sampleRecipes = [
            BentoRecipe(
                name: "鮭の塩焼き弁当",
                description: "焼き鮭をメインにした和風お弁当",
                category: .fishMain,
                mainDish: DishItem(
                    name: "鮭の塩焼き",
                    ingredients: ["鮭切り身 1切れ", "塩 少々", "レモン 適量"],
                    instructions: ["鮭に塩をふって15分置く", "フライパンで両面を焼く", "レモンを添える"]
                ),
                sideDish1: DishItem(
                    name: "ブロッコリーのごま和え",
                    ingredients: ["ブロッコリー 1/2株", "白ごま 大さじ1", "醤油 小さじ2", "砂糖 小さじ1"],
                    instructions: ["ブロッコリーを茹でる", "ごまをすって調味料と混ぜる", "ブロッコリーと和える"]
                ),
                sideDish2: DishItem(
                    name: "だし巻き卵",
                    ingredients: ["卵 3個", "だし汁 大さじ2", "砂糖 小さじ1", "塩 少々"],
                    instructions: ["材料を全て混ぜる", "フライパンで巻きながら焼く"]
                ),
                prepTime: 25,
                calories: 450,
                difficulty: .easy,
                tips: ["鮭は焼きすぎに注意", "卵は弱火でゆっくり焼く"]
            ),
            BentoRecipe(
                name: "鶏の照り焼き弁当",
                description: "甘辛い照り焼きチキンの人気弁当",
                category: .hearty,
                mainDish: DishItem(
                    name: "鶏の照り焼き",
                    ingredients: ["鶏もも肉 200g", "醤油 大さじ3", "みりん 大さじ2", "砂糖 大さじ1", "酒 大さじ1"],
                    instructions: ["鶏肉を一口大に切る", "調味料を混ぜる", "鶏肉を焼いてタレを絡める"]
                ),
                sideDish1: DishItem(
                    name: "人参のグラッセ",
                    ingredients: ["人参 1本", "バター 大さじ1", "砂糖 小さじ2", "塩 少々"],
                    instructions: ["人参を輪切りにする", "バターで炒める", "調味料を加えて煮詰める"]
                ),
                sideDish2: DishItem(
                    name: "いんげんの胡麻和え",
                    ingredients: ["いんげん 100g", "白ごま 大さじ1", "醤油 小さじ2", "砂糖 小さじ1"],
                    instructions: ["いんげんを茹でる", "ごまをすって調味料と混ぜる", "いんげんと和える"]
                ),
                prepTime: 30,
                calories: 520,
                difficulty: .medium,
                tips: ["照り焼きは強火で仕上げる", "野菜の色を鮮やかに保つ"]
            )
        ]
        
        recipes = sampleRecipes
        saveRecipes()
    }
}