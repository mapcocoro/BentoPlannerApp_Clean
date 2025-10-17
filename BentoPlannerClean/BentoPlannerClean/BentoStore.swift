import Foundation
import SwiftUI

// 日付ベースの固定ランダム生成器
struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64
    
    init(seed: UInt64) {
        self.state = seed
    }
    
    mutating func next() -> UInt64 {
        state = state &* 1103515245 &+ 12345
        return state
    }
}

@MainActor
class BentoStore: ObservableObject {
    @Published var recipes: [BentoRecipe] = []
    @Published var weeklyPlan: WeeklyPlan = WeeklyPlan(weekOf: Date())
    @Published var favoriteRecipes: [BentoRecipe] = []
    @Published var aiGeneratedRecipes: [BentoCategory: [BentoRecipe]] = [:]
    @Published var ingredientBasedRecipes: [BentoRecipe] = []
    @Published var dailyRecommendations: [BentoRecipe] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // レシピ生成履歴を記録（重複回避用）
    private var recipeHistoryManager = RecipeHistoryManager()
    private var lastGeneratedRecipeNames: [BentoCategory: [String]] = [:]

    // バックグラウンドで生成したAPIレシピキャッシュ（即座に表示用）
    private var cachedApiRecipes: [BentoCategory: [BentoRecipe]] = [:]
    
    private let dailyRecommendationsKey = "DailyRecommendations"
    private let lastUpdateDateKey = "LastUpdateDate"
    
    private let recipesKey = "SavedBentoRecipes"
    private let weeklyPlanKey = "SavedWeeklyPlan"
    private let aiService = BentoAIService()

    init() {
        loadRecipes()
        if recipes.isEmpty {
            loadSampleData()
        }
        loadWeeklyPlan()
        updateFavorites()
        // アプリを開くたびに必ず新しいメニューを生成
        forceUpdateDailyRecommendations()
    }

    // MARK: - Recipe Generation
    func generateAIRecipes(for category: BentoCategory) async {
        NSLog("🔄 [ENTRY] generateAIRecipes called for category: \(category.rawValue)")
        NSLog("🔄 [ENTRY] Current isLoading: \(isLoading)")

        let now = Date()
        let timestamp = Int(now.timeIntervalSince1970)
        let safeTimestamp = timestamp % 1000000
        let randomId = Int.random(in: 1000...9999)
        let safeCategoryHash = abs(category.rawValue.hashValue) % 10000

        let complexRandomId = safeTimestamp + randomId + safeCategoryHash

        NSLog("🔄 Starting recipe generation for category: \(category.rawValue) - ID: \(complexRandomId)")

        // 既にローディング中の場合は処理をスキップ
        if isLoading {
            NSLog("⚠️ Already generating recipes, skipping duplicate request")
            return
        }

        isLoading = true
        errorMessage = nil

        // 既存のレシピを即座にクリア（必ず新しいメニューを表示するため）
        self.aiGeneratedRecipes[category] = []

        let historyRecipes = recipeHistoryManager.getRecentRecipes(for: category, limit: 5)  // 最近5個のみ除外

        // 1. まずキャッシュされたAPIレシピをチェック（最優先）
        if let cachedRecipes = cachedApiRecipes[category], cachedRecipes.count >= 3 {
            let recipesToShow = Array(cachedRecipes.prefix(3))
            NSLog("⚡️ Using \(recipesToShow.count) cached API recipes (generated in background)")
            NSLog("⚡️ Recipe names: \(recipesToShow.map { $0.name }.joined(separator: ", "))")

            // UX向上：3-5秒の演出的な遅延を追加
            Task { @MainActor in
                NSLog("⏱️ [Cache Display Task] Started on main actor")
                let delay = Double.random(in: 3.0...5.0)
                NSLog("⏱️ Adding \(String(format: "%.1f", delay))s delay for better UX...")

                do {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    NSLog("⏱️ [Cache Display Task] Delay completed")
                } catch {
                    NSLog("❌ [Cache Display Task] Sleep error: \(error)")
                }

                NSLog("📝 [Cache Display Task] Setting aiGeneratedRecipes[\(category.rawValue)] to \(recipesToShow.count) recipes")
                self.aiGeneratedRecipes[category] = recipesToShow
                NSLog("📝 [Cache Display Task] aiGeneratedRecipes[\(category.rawValue)] now has \(self.aiGeneratedRecipes[category]?.count ?? 0) recipes")

                NSLog("📝 [Cache Display Task] Adding to history...")
                for recipe in recipesToShow {
                    recipeHistoryManager.addToHistory(recipe, category: category)
                }

                NSLog("📝 [Cache Display Task] Updating lastGeneratedRecipeNames...")
                self.lastGeneratedRecipeNames[category] = recipesToShow.map { $0.name }

                NSLog("📝 [Cache Display Task] About to set isLoading to false...")
                // 既に@MainActorなので直接実行
                self.isLoading = false
                NSLog("✅ \(recipesToShow.count) cached recipes loaded - isLoading is now: \(self.isLoading)")

                // objectWillChangeを明示的に送信
                self.objectWillChange.send()
                NSLog("📝 [Cache Display Task] Sent objectWillChange - completed successfully")

                // キャッシュから削除
                NSLog("📝 [Cache Display Task] Removing used recipes from cache...")
                self.cachedApiRecipes[category] = Array(cachedRecipes.dropFirst(3))
                NSLog("✅ \(recipesToShow.count) cached API recipes displayed after delay, \(self.cachedApiRecipes[category]?.count ?? 0) recipes remaining in cache")

                // バックグラウンドで次のレシピを生成してキャッシュ補充
                NSLog("📝 [Cache Display Task] Starting background API generation...")
                Task {
                    await self.generateAndAddToPresetPool(for: category)
                }
                NSLog("📝 [Cache Display Task] Task completed successfully")
            }
            return
        }

        // 2. 次にプリセット献立を即座に表示（ユーザーを待たせない）
        var presetRecipes: [BentoRecipe] = []
        var excludedRecipes = historyRecipes

        // 3つのユニークなレシピを取得
        for _ in 0..<3 {
            if let recipe = PresetRecipeManager.shared.getRandomRecipe(for: category, excluding: excludedRecipes) {
                presetRecipes.append(recipe)
                excludedRecipes.append(recipe)
            }
        }

        if !presetRecipes.isEmpty {
            NSLog("📦 Using \(presetRecipes.count) preset recipes")
            NSLog("🚫 Excluded \(historyRecipes.count) previous recipes to ensure uniqueness")

            // UX向上：3-5秒の演出的な遅延を追加
            Task { @MainActor in
                let delay = Double.random(in: 3.0...5.0)
                NSLog("⏱️ Adding \(String(format: "%.1f", delay))s delay for better UX...")
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

                self.aiGeneratedRecipes[category] = presetRecipes

                // 履歴に追加
                for recipe in presetRecipes {
                    recipeHistoryManager.addToHistory(recipe, category: category)
                }

                self.lastGeneratedRecipeNames[category] = presetRecipes.map { $0.name }

                NSLog("📝 [Preset Display Task] About to set isLoading to false...")
                // 既に@MainActorなので直接実行
                self.isLoading = false
                NSLog("✅ \(presetRecipes.count) preset recipes loaded - isLoading is now: \(self.isLoading)")

                // objectWillChangeを明示的に送信
                self.objectWillChange.send()
                NSLog("📝 [Preset Display Task] Sent objectWillChange - completed successfully")

                // バックグラウンドでAPIを呼んで新しいレシピも生成（キャッシュに追加）
                Task {
                    await generateAndAddToPresetPool(for: category)
                }
            }
            return
        }

        // プリセットがない場合のみAPI生成を待つ
        NSLog("⚠️ No unique preset recipes available, generating via API...")

        do {
            NSLog("📡 Making API request...")
            // すべての履歴を取得して絶対に重複しないようにする
            let previousRecipeNames = historyRecipes.map { $0.name }
            let previousMainDishes = recipeHistoryManager.getRecentMainDishes(for: category, limit: 100)
            let previousSideDishes = recipeHistoryManager.getRecentSideDishes(for: category, limit: 100)
            let previousCookingMethods = recipeHistoryManager.getRecentCookingMethods(for: category, limit: 50)

            NSLog("🚫 Avoiding \(previousRecipeNames.count) previous recipes")
            NSLog("🍳 Avoiding \(previousMainDishes.count) main dishes")
            NSLog("🥗 Avoiding \(previousSideDishes.count) side dishes")
            NSLog("🔥 Avoiding \(previousCookingMethods.count) cooking methods")

            let newRecipes = try await aiService.generateBentoRecipes(
                for: category,
                randomSeed: complexRandomId,
                avoidRecipeNames: previousRecipeNames,
                previousMainDishes: previousMainDishes,
                previousSideDishes: previousSideDishes,
                previousCookingMethods: previousCookingMethods
            )
            NSLog("✅ Successfully generated \(newRecipes.count) unique recipes")

            self.aiGeneratedRecipes[category] = newRecipes

            for recipe in newRecipes {
                recipeHistoryManager.addToHistory(recipe, category: category)
            }
            self.lastGeneratedRecipeNames[category] = newRecipes.map { $0.name }

            self.isLoading = false
            NSLog("✅ UI updated with new recipes for category: \(category.rawValue)")
        } catch {
            NSLog("❌ Recipe generation failed: \(error.localizedDescription)")

            self.errorMessage = "AIサーバーエラーが発生しました。フォールバックレシピを表示しています。"
            self.isLoading = false
            let fallbackRecipes = self.generateCategorySpecificFallback(for: category)
            self.aiGeneratedRecipes[category] = fallbackRecipes
            NSLog("🔄 Using fallback recipes for \(category.rawValue): \(fallbackRecipes.count) recipes")
        }
    }

    // MARK: - Background API Generation (キャッシュに追加用)
    private func generateAndAddToPresetPool(for category: BentoCategory) async {
        NSLog("🔄 [Background] Starting API generation to add to cache for \(category.rawValue)")

        do {
            // 履歴を取得して重複を避ける
            let historyRecipes = recipeHistoryManager.getRecentRecipes(for: category, limit: 5)  // 最近5個のみ除外
            let previousRecipeNames = historyRecipes.map { $0.name }
            let previousMainDishes = recipeHistoryManager.getRecentMainDishes(for: category, limit: 100)
            let previousSideDishes = recipeHistoryManager.getRecentSideDishes(for: category, limit: 100)
            let previousCookingMethods = recipeHistoryManager.getRecentCookingMethods(for: category, limit: 50)

            NSLog("🔄 [Background] Generating new recipe avoiding \(previousRecipeNames.count) previous recipes")

            let newRecipes = try await aiService.generateBentoRecipes(
                for: category,
                randomSeed: Int.random(in: 0...999999),
                avoidRecipeNames: previousRecipeNames,
                previousMainDishes: previousMainDishes,
                previousSideDishes: previousSideDishes,
                previousCookingMethods: previousCookingMethods
            )

            NSLog("✅ [Background] Successfully generated \(newRecipes.count) new recipes")

            // キャッシュに追加（次回「新しいレシピを生成」を押したときに即座に表示）
            if cachedApiRecipes[category] == nil {
                cachedApiRecipes[category] = []
            }
            cachedApiRecipes[category]?.append(contentsOf: newRecipes)

            // キャッシュサイズ制限（最大5レシピまで保持）
            if let cacheCount = cachedApiRecipes[category]?.count, cacheCount > 5 {
                cachedApiRecipes[category] = Array(cachedApiRecipes[category]!.prefix(5))
            }

            NSLog("✅ [Background] Added to cache. Cache now has \(cachedApiRecipes[category]?.count ?? 0) recipes for \(category.rawValue)")

        } catch {
            NSLog("⚠️ [Background] API generation failed (non-critical): \(error.localizedDescription)")
            // バックグラウンド処理なので、エラーでもユーザーには影響なし
        }
    }

    // MARK: - Ingredient-Based Recipe Generation
    func generateRecipesFromIngredients(_ selectedIngredients: [Ingredient], additionalNotes: String = "") async {
        NSLog("🔄 Starting ingredient-based recipe generation")
        
        // 既にローディング中の場合はスキップ
        if isLoading {
            NSLog("⚠️ Already generating recipes, skipping duplicate request")
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            NSLog("📡 Making ingredient-based API request...")
            let newRecipes = try await aiService.generateRecipesFromIngredients(selectedIngredients, additionalNotes: additionalNotes)
            NSLog("✅ Successfully generated \(newRecipes.count) ingredient-based recipes")

            self.ingredientBasedRecipes = newRecipes
            self.isLoading = false
            NSLog("✅ UI updated with new ingredient-based recipes")
        } catch {
            NSLog("❌ Ingredient-based recipe generation failed: \(error.localizedDescription)")

            self.errorMessage = error.localizedDescription
            self.isLoading = false
            // フォールバック: 選択された食材に基づいたサンプルレシピを生成
            let fallbackRecipes = self.generateIngredientBasedFallback(selectedIngredients)
            self.ingredientBasedRecipes = fallbackRecipes
            NSLog("🔄 Using ingredient-based fallback recipes: \(fallbackRecipes.count) recipes")
            NSLog("📋 Recipe names: \(fallbackRecipes.map { $0.name })")
            NSLog("🔍 Final ingredientBasedRecipes count: \(self.ingredientBasedRecipes.count)")
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
        for category in BentoCategory.allCases {
            if let recipes = aiGeneratedRecipes[category],
               let index = recipes.firstIndex(where: { $0.id == recipe.id }) {
                aiGeneratedRecipes[category]?[index] = updatedRecipe
            }
        }
        
        // Update in ingredient-based recipes
        if let index = ingredientBasedRecipes.firstIndex(where: { $0.id == recipe.id }) {
            ingredientBasedRecipes[index] = updatedRecipe
        }
        
        saveRecipes()
        updateFavorites()
    }
    
    func isRecipeFavorite(_ recipe: BentoRecipe) -> Bool {
        if let foundRecipe = recipes.first(where: { $0.id == recipe.id }) {
            return foundRecipe.isFavorite
        }
        for category in BentoCategory.allCases {
            if let recipes = aiGeneratedRecipes[category],
               let foundRecipe = recipes.first(where: { $0.id == recipe.id }) {
                return foundRecipe.isFavorite
            }
        }
        if let foundRecipe = ingredientBasedRecipes.first(where: { $0.id == recipe.id }) {
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
        case "月":
            weeklyPlan.monday = recipe
        case "火":
            weeklyPlan.tuesday = recipe
        case "水":
            weeklyPlan.wednesday = recipe
        case "木":
            weeklyPlan.thursday = recipe
        case "金":
            weeklyPlan.friday = recipe
        case "土":
            weeklyPlan.saturday = recipe
        case "日":
            weeklyPlan.sunday = recipe
        default:
            return
        }

        saveWeeklyPlan()

        // UIを強制更新
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
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
        print("✅ Removed recipe from \(day)曜日")
    }

    // MARK: - Helper Methods
    private func generateBentoSuggestions(for category: BentoCategory) -> [BentoRecipe] {
        return recipes.filter { $0.category == category }.shuffled().prefix(3).map { $0 }
    }
    
    private func generateCategorySpecificFallback(for category: BentoCategory) -> [BentoRecipe] {
        // 毎回異なるレシピを生成するための強化されたランダム要素
        let timestamp = Int(Date().timeIntervalSince1970)
        let microseconds = Int(Date().timeIntervalSince1970 * 1000000) % 1000000
        let randomSeed = Int.random(in: 0...999999)
        let uniqueVariation = (timestamp + microseconds + randomSeed + category.hashValue) % 1000 // 0-999の1000パターン
        
        print("🎲 Generating fallback with timestamp: \(timestamp), microseconds: \(microseconds), seed: \(randomSeed), variation: \(uniqueVariation)")
        
        // カテゴリに合わせた3つのフォールバックレシピを生成
        switch category {
        case .omakase:
            return generateRandomOmakaseRecipes(variation: uniqueVariation)
        case .hearty:
            return generateRandomHeartyRecipes(variation: uniqueVariation)
        case .fishMain:
            return generateRandomFishRecipes(variation: uniqueVariation)
        case .simple:
            return generateRandomSimpleRecipes(variation: uniqueVariation)
        }
    }
    
    // MARK: - Random Recipe Generation Functions
    
    // 安全な配列アクセス関数
    private func safeArrayAccess<T>(_ array: [T], index: Int) -> T {
        guard !array.isEmpty else { 
            fatalError("配列が空です") 
        }
        let safeIndex = abs(index) % array.count
        return array[safeIndex]
    }
    
    // 副菜を動的に生成する関数
    private func generateSideDishes(mainDishName: String, category: BentoCategory, variation: Int) -> (DishItem, DishItem) {
        // カテゴリ別の副菜候補
        let healthySides = [
            ("アボカドとトマトのサラダ", ["アボカド 1個", "ミニトマト 6個", "レモン汁 大さじ1", "オリーブオイル 小さじ1", "塩胡椒 少々"], ["アボカドを一口大に切る", "ミニトマトを半分に切る", "レモン汁とオリーブオイルで和える", "塩胡椒で味を整える", "よく冷ましてからお弁当箱に詰める"]),
            ("カリフラワーのカレー炒め", ["カリフラワー 1/2株", "カレー粉 小さじ1", "オリーブオイル 大さじ1", "塩 少々"], ["カリフラワーを小房に分ける", "フライパンでオリーブオイルを熱する", "カリフラワーを炒める", "カレー粉と塩で味付け", "よく冷ましてからお弁当箱に詰める"]),
            ("ズッキーニのマリネ", ["ズッキーニ 1本", "酢 大さじ2", "オリーブオイル 大さじ1", "ハーブ 適量", "塩胡椒 少々"], ["ズッキーニを薄切りにする", "塩を振って10分置く", "水気を絞る", "調味料とハーブで和える", "よく冷ましてからお弁当箱に詰める"]),
            ("きのこのバルサミコソテー", ["エリンギ 2本", "しめじ 1/2パック", "バルサミコ酢 大さじ1", "オリーブオイル 大さじ1", "塩胡椒 少々"], ["きのこを食べやすい大きさに切る", "フライパンでオリーブオイルを熱する", "きのこを炒める", "バルサミコ酢を加えて炒め合わせる", "塩胡椒で味を整える"]),
            ("パプリカのハニーマスタード和え", ["赤パプリカ 1/2個", "黄パプリカ 1/2個", "はちみつ 小さじ1", "粒マスタード 小さじ1", "オリーブオイル 小さじ1"], ["パプリカを細切りにする", "フライパンで軽く炒める", "はちみつとマスタードを混ぜる", "パプリカと和える", "よく冷ましてからお弁当箱に詰める"]),
            ("オクラの胡麻和え", ["オクラ 10本", "白すりごま 大さじ2", "醤油 小さじ2", "砂糖 小さじ1"], ["オクラの産毛を取り塩で板ずりする", "沸騰したお湯で1分半茹でる", "冷水に取って水気を切る", "すりごまと調味料を混ぜて和える", "よく冷ましてからお弁当箱に詰める"])
        ]
        
        let heartySides = [
            ("厚焼き卵", ["卵 4個", "だし汁 大さじ3", "砂糖 大さじ2", "塩 少々"], ["材料をよく混ぜる", "卵焼き器で厚く焼く", "巻きながら層を作る", "粗熱を取る", "よく冷ましてからお弁当箱に詰める"]),
            ("なすの味噌田楽", ["なす 1本", "味噌 大さじ2", "砂糖 大さじ1", "みりん 大さじ1", "白ごま 小さじ1"], ["なすを縦半分に切り格子状に切れ目を入れる", "フライパンに油を熱しなすを両面焼く", "味噌、砂糖、みりんを混ぜたタレを塗る", "さらに両面を焼いて照りをつける", "白ごまを振りかける"]),
            ("れんこんのきんぴら", ["れんこん 1節", "ごま油 大さじ1", "醤油 大さじ1", "砂糖 小さじ1", "唐辛子 少々"], ["れんこんを薄切りにして水にさらす", "フライパンでごま油を熱する", "れんこんを炒める", "調味料を加えて炒め合わせる", "よく冷ましてからお弁当箱に詰める"]),
            ("豚バラ大根", ["豚バラ肉 100g", "大根 1/3本", "醤油 大さじ2", "砂糖 大さじ1", "みりん 大さじ1"], ["大根を厚めの半月切りにする", "豚バラ肉を一口大に切る", "フライパンで豚バラを炒める", "大根を加えて調味料で煮る", "よく冷ましてからお弁当箱に詰める"]),
            ("肉じゃが風煮物", ["牛肉 100g", "じゃがいも 2個", "玉ねぎ 1/2個", "だし汁 200ml", "醤油 大さじ2"], ["じゃがいもと玉ねぎを切る", "牛肉を炒める", "野菜を加えて炒める", "だし汁と調味料で煮る", "よく冷ましてからお弁当箱に詰める"]),
            ("鶏つくねの照り焼き", ["鶏ひき肉 150g", "玉ねぎ 1/4個", "醤油 大さじ2", "みりん 大さじ2", "砂糖 大さじ1"], ["玉ねぎをみじん切りにする", "鶏ひき肉と混ぜて丸める", "フライパンで焼く", "調味料を加えて照りをつける", "よく冷ましてからお弁当箱に詰める"]),
            ("きのこのバター醤油炒め", ["しめじ 1パック", "エリンギ 2本", "バター 15g", "醤油 大さじ1", "にんにく 1片"], ["きのこを食べやすく切る", "にんにくをみじん切りにする", "フライパンでバターを溶かす", "きのことにんにくを炒める", "醤油で味付けして冷ます"]),
            ("インゲンの胡麻和え", ["いんげん 150g", "白すりごま 大さじ2", "醤油 小さじ2", "砂糖 小さじ1"], ["いんげんの筋を取り3cm幅に切る", "沸騰したお湯で2分茹でる", "冷水に取って水気を切る", "すりごまと調味料を混ぜて和える", "よく冷ましてからお弁当箱に詰める"]),
            ("かぼちゃの煮物", ["かぼちゃ 1/4個", "だし汁 150ml", "醤油 大さじ1", "砂糖 大さじ1", "みりん 大さじ1"], ["かぼちゃを一口大に切る", "鍋にだし汁と調味料を入れる", "かぼちゃを加えて煮る", "柔らかくなるまで煮込む", "よく冷ましてからお弁当箱に詰める"]),
            ("牛ごぼう", ["牛肉 100g", "ごぼう 1本", "醤油 大さじ2", "砂糖 大さじ1", "ごま油 大さじ1"], ["ごぼうを斜め切りにして水にさらす", "牛肉を一口大に切る", "フライパンでごま油を熱する", "牛肉とごぼうを炒める", "調味料を加えて炒め煮にする"])
        ]
        
        let vegetableSides = [
            ("人参のグラッセ", ["人参 2本", "バター 15g", "砂糖 大さじ1", "塩 少々", "パセリ 少々"], ["人参を乱切りに切る", "フライパンでバターを温める", "人参を加えて炒める", "砂糖と塩で味付けして照りを出す", "パセリを散らして仕上げる"]),
            ("ブロッコリーのアーモンド和え", ["ブロッコリー 1/2株", "スライスアーモンド 大さじ2", "オリーブオイル 大さじ1", "レモン汁 小さじ1", "塩胡椒 少々"], ["ブロッコリーを小房に分けて30秒茹でる", "アーモンドを乾熙りで炒る", "ブロッコリーとアーモンドを混ぜる", "オリーブオイルとレモン汁で和える", "塩胡椒で味を整える"]),
            ("かぼちゃのロースト", ["かぼちゃ 1/4個", "オリーブオイル 大さじ1", "シナモン 少々", "塩 少々", "はちみつ 小さじ1"], ["かぼちゃを一口大に切る", "オリーブオイルと調味料を絡める", "オーブン200度で20分焼く", "柔らかくなったら取り出す", "よく冷ましてからお弁当箱に詰める"]),
            ("アスパラのベーコン巻き", ["アスパラ 8本", "ベーコン 4枚", "オリーブオイル 小さじ1", "黒胡椒 少々"], ["アスパラの根元を切り落とす", "ベーコンで2本ずつ巻く", "フライパンでオイルを熱す", "ベーコンのところを下にして焼く", "黒胡椒を振って仕上げる"]),
            ("ズッキーニのチーズ焼き", ["ズッキーニ 1本", "ピザチーズ 30g", "パン粉 大さじ2", "オリーブオイル 大さじ1", "バジル 少々"], ["ズッキーニを縦半分に切り中身をくり抜く", "チーズとパン粉を詰める", "オーブントースターで5分焼く", "チーズが溶けたら取り出す", "バジルを散らして仕上げる"]),
            ("パプリカのマリネ", ["赤パプリカ 1個", "黄パプリカ 1個", "オリーブオイル 大さじ2", "バルサミコ酢 大さじ1", "ハーブソルト 少々"], ["パプリカを縦に8等分して種を取る", "グリルで表面が焼けるまで焼く", "熱いうちにマリネ液をかける", "10分置いて味を馴染ませる", "よく冷ましてからお弁当箱に詰める"])
        ]
        
        let simpleSides = [
            ("ブロッコリー茹で", ["ブロッコリー 1/2株", "塩 少々"], ["ブロッコリーを小房に分ける", "沸騰したお湯で2分茹でる", "水気を切る", "よく冷ましてからお弁当箱に詰める"]),
            ("コーンバター炒め", ["コーン缶詰 100g", "バター 10g", "塩胡椒 少々"], ["フライパンでバターを温める", "コーンを加えて炒める", "塩胡椒で味付け", "よく冷ましてからお弁当箱に詰める"]),
            ("さつまいものレンジ煮", ["さつまいも 1/2本", "バター 10g", "砂糖 大さじ1"], ["さつまいもを輪切りにしてラップする", "レンジ600Wで3分加熱", "バターと砂糖を混ぜる", "よく冷ましてからお弁当箱に詰める"]),
            ("ミニトマト", ["ミニトマト 6個"], ["ミニトマトを洗う", "ヘタを取る", "半分に切る", "よく冷ましてからお弁当箱に詰める"]),
            ("ほうれん草のバター炒め", ["ほうれん草 1束", "バター 10g", "塩 少々"], ["ほうれん草を洗って3cm幅に切る", "フライパンでバターを溶かす", "ほうれん草を炒める", "塩で味付けして冷ます"]),
            ("きゅうりの酢の物", ["きゅうり 1本", "塩 小さじ1", "酢 小さじ1"], ["きゅうりを薄切りにする", "塩でもみ10分置く", "水気を絞って酢を加える", "よく冷ましてからお弁当箱に詰める"]),
            ("ピーマンのおかか炒め", ["ピーマン 2個", "かつお節 1パック", "醤油 小さじ1", "ごま油 小さじ1"], ["ピーマンを細切りにする", "ごま油で炒める", "かつお節と醤油を加えて混ぜる", "よく冷ましてからお弁当箱に詰める"]),
            ("もやしのナムル", ["もやし 1袋", "ごま油 大さじ1", "塩 小さじ1", "白ごま 小さじ1"], ["もやしを洗って水気を切る", "レンジで2分加熱", "ごま油と塩で和える", "白ごまを振りかける"]),
            ("キャベツの塩昆布和え", ["キャベツ 3枚", "塩昆布 小さじ2", "ごま油 小さじ1"], ["キャベツを千切りにする", "塩昆布とごま油で和える", "10分置いて味を馴染ませる", "よく冷ましてからお弁当箱に詰める"]),
            ("しめじのバター醤油炒め", ["しめじ 1パック", "バター 10g", "醤油 小さじ1"], ["しめじを小房に分ける", "フライパンでバターを溶かす", "しめじを炒めて醤油で味付け", "よく冷ましてからお弁当箱に詰める"])
        ]
        
        let omakaseSides = [
            ("ブロッコリーのおかか和え", ["ブロッコリー 1/2株", "かつお節 1パック", "醤油 小さじ1"], ["ブロッコリーを茹でる", "水気を切る", "かつお節と醤油で和える", "よく冷ましてからお弁当箱に詰める"]),
            ("ナスの煤び浸し", ["ナス 2本", "めんつゆ 大さじ3", "しょうが 片", "だし汁 大さじ3", "サラダ油 適量"], ["ナスを乱切りにし水にさらす", "しょうがをすりおろしにする", "ナスを素揚げして煩く", "つけだれとしょうがをかける", "よく冷ましてからお弁当箱に詰める"]),
            ("しいたけの煤物", ["乾燥しいたけ 20g", "人参 1/3本", "油揚げ 1枚", "だし汁 150ml", "醤油 大さじ2", "みりん 大さじ1"], ["しいたけを水で30分浸して戻す", "人参と油揚げを細切りにする", "鍋にだし汁と調味料を入れて煩立てる", "具材を入れて落し蓋をして煮る", "汁気が少なくなったら完成"]),
            ("人参のきんぴら", ["人参 1本", "ごま油 大さじ1", "醤油 大さじ1", "砂糖 小さじ1"], ["人参を千切りにする", "ごま油で炒める", "調味料を加えて味付け", "よく冷ましてからお弁当箱に詰める"]),
            ("いんげんの胡麻和え", ["いんげん 100g", "白すりごま 大さじ2", "醤油 小さじ2", "砂糖 小さじ1"], ["いんげんの筋を取り3cm幅に切る", "沸騰したお湯で2分茹でる", "冷水に取って水気を切る", "すりごまと調味料を混ぜて和える", "よく冷ましてからお弁当箱に詰める"]),
            ("ひじきの煤物", ["乾燥ひじき 20g", "人参 1/3本", "油揚げ 1枚", "だし汁 150ml", "醤油 大さじ2", "みりん 大さじ1"], ["ひじきを水で30分浸して戻す", "人参と油揚げを細切りにする", "鍋にだし汁と調味料を入れて煩立てる", "具材を入れて落し蓋をして煮る", "汁気が少なくなったら完成"]),
            ("きんぴらごぼう", ["ごぼう 1本", "人参 1/3本", "ごま油 大さじ1", "醤油 大さじ1", "砂糖 小さじ1"], ["ごぼうと人参を千切り", "ごま油で炒める", "調味料で味付け", "よく冷ましてからお弁当箱に詰める"]),
            ("小松菜の胡麻和え", ["小松菜 1束", "白ごま 大さじ1", "醤油 小さじ2", "砂糖 小さじ1"], ["小松菜を茹でて切る", "胡麻をすって調味料と混ぜる", "小松菜と和える", "よく冷ましてからお弁当箱に詰める"])
        ]
        
        // カテゴリに応じて副菜候補を選択
        let sideCandidates: [(String, [String], [String])]
        switch category {
        case .hearty:
            sideCandidates = heartySides
        case .simple:
            sideCandidates = simpleSides
        case .omakase, .fishMain:
            sideCandidates = omakaseSides
        }
        
        // メインに基づいて副菜をスマートに選択（確実に異なる副菜を選ぶ）
        let side1Index = (variation + mainDishName.hashValue) % sideCandidates.count
        var side2Index = (variation + mainDishName.hashValue + 3) % sideCandidates.count
        
        // 同じ副菜を避ける
        if side2Index == side1Index {
            side2Index = (side1Index + (sideCandidates.count / 2)) % sideCandidates.count
        }
        
        let side1 = safeArrayAccess(sideCandidates, index: side1Index)
        let side2 = safeArrayAccess(sideCandidates, index: side2Index)
        
        return (
            DishItem(name: side1.0, ingredients: side1.1, instructions: side1.2),
            DishItem(name: side2.0, ingredients: side2.1, instructions: side2.2)
        )
    }
    
    private func generateRandomFishRecipes(variation: Int) -> [BentoRecipe] {
        let recipes = [
            // 和風魚料理
            ("鮭の塩焼き", "鮭", "塩焼き"),
            ("鯖の味噌煮", "鯖", "味噌煮"),
            ("ぶりの照り焼き", "ぶり", "照り焼き"),
            ("鯵の南蛮漬け", "鯵", "南蛮漬け"),
            ("さんまの塩焼き", "さんま", "塩焼き"),
            ("鮭のちゃんちゃん焼き", "鮭", "ちゃんちゃん焼き"),
            ("鯖の竜田揚げ", "鯖", "竜田揚げ"),
            ("鯛の煮付け", "鯛", "煮付け"),
            ("金目鯛の姿煮", "金目鯛", "姿煮"),
            ("鰤の西京焼き", "ぶり", "西京焼き"),
            ("鯖の塩焼き", "鯖", "塩焼き"),
            ("鮭の粕漬け焼き", "鮭", "粕漬け焼き"),
            
            // 洋風魚料理
            ("鮭のムニエル", "鮭", "ムニエル"),
            ("白身魚のクリーム煮", "白身魚", "クリーム煮"),
            ("鯛のアクアパッツァ", "鯛", "アクアパッツァ"),
            ("鮭のハーブグリル", "鮭", "ハーブグリル"),
            ("タラのトマト煮", "タラ", "トマト煮"),
            ("ヒラメのポワレ", "ヒラメ", "ポワレ"),
            ("カジキのガーリックソテー", "カジキ", "ガーリックソテー"),
            ("鮭のレモンバター焼き", "鮭", "レモンバター焼き"),
            
            // 中華・アジア風魚料理
            ("鯖の甘酢あんかけ", "鯖", "甘酢あんかけ"),
            ("白身魚の中華蒸し", "白身魚", "中華蒸し"),
            ("鮭のチリソース", "鮭", "チリソース"),
            ("鯵の唐揚げ甘酢だれ", "鯵", "唐揚げ甘酢だれ"),
            ("鯛の蒸し物中華風", "鯛", "蒸し物中華風"),
            
            // フライ・揚げ物
            ("鯵フライ", "鯵", "フライ"),
            ("白身魚フライ", "白身魚", "フライ"),
            ("鮭の天ぷら", "鮭", "天ぷら"),
            ("鯖の唐揚げ", "鯖", "唐揚げ"),
            ("アジのなめろう風", "鯵", "なめろう風")
        ]
        
        // 正しい材料を調理法に応じて設定
        func getIngredientsAndInstructions(name: String, fish: String, method: String) -> ([String], [String]) {
            switch method {
            case "南蛮漬け":
                return (
                    ["\(fish) 1切れ", "玉ねぎ 1/2個", "人参 1/3本", "片栗粉 大さじ2", "酢 大さじ3", "砂糖 大さじ2", "醤油 大さじ1", "だし汁 大さじ2"],
                    ["\(fish)に片栗粉をまぶして揚げる", "野菜を薄切りにする", "調味料を混ぜて南蛮酢を作る", "揚げた魚と野菜を南蛮酢に漬ける", "よく冷ましてからお弁当箱に詰める"]
                )
            case "照り焼き":
                return (
                    ["\(fish) 1切れ", "醤油 大さじ2", "みりん 大さじ2", "砂糖 大さじ1", "酒 大さじ1", "サラダ油 小さじ1"],
                    ["\(fish)に軽く塩をふって下味をつける", "フライパンに油を熱し、\(fish)を焼く", "調味料を混ぜ合わせる", "魚に照り焼きソースを絡める", "よく冷ましてからお弁当箱に詰める"]
                )
            case "味噌煮":
                return (
                    ["\(fish) 1切れ", "味噌 大さじ2", "砂糖 大さじ1", "みりん 大さじ1", "酒 大さじ2", "水 100ml", "生姜 1片"],
                    ["\(fish)は切り身にして臭みを取る", "生姜を薄切りにする", "鍋に調味料と水、生姜を入れて煮立てる", "\(fish)を加えて煮る", "よく冷ましてからお弁当箱に詰める"]
                )
            case "塩焼き":
                return (
                    ["\(fish) 1切れ", "塩 小さじ1/2", "レモン 1/4個"],
                    ["\(fish)に塩をふって15分置く", "グリルまたはフライパンで両面を焼く", "レモンを添える", "よく冷ましてからお弁当箱に詰める"]
                )
            case "ちゃんちゃん焼き":
                return (
                    ["\(fish) 1切れ", "キャベツ 2枚", "玉ねぎ 1/2個", "人参 1/3本", "味噌 大さじ2", "砂糖 大さじ1", "みりん 大さじ1", "バター 10g"],
                    ["野菜を食べやすい大きさに切る", "\(fish)を一口大に切る", "味噌、砂糖、みりんを混ぜ合わせる", "フライパンでバターを溶かし、魚と野菜を炒める", "味噌ダレを加えて炒め合わせる", "よく冷ましてからお弁当箱に詰める"]
                )
            case "竜田揚げ":
                return (
                    ["\(fish) 1切れ", "醤油 大さじ1", "酒 大さじ1", "生姜汁 小さじ1", "片栗粉 大さじ3", "揚げ油 適量"],
                    ["\(fish)を一口大に切る", "醤油、酒、生姜汁で下味をつける", "片栗粉をまぶす", "170℃の油で揚げる", "よく冷ましてからお弁当箱に詰める"]
                )
            case "ムニエル":
                return (
                    ["\(fish) 1切れ", "塩 少々", "胡椒 少々", "小麦粉 大さじ2", "バター 20g", "レモン 1/4個"],
                    ["\(fish)に塩胡椒で下味をつける", "小麦粉をまぶす", "フライパンでバターを溶かし、\(fish)を焼く", "両面きれいに焼く", "レモンを添える", "よく冷ましてからお弁当箱に詰める"]
                )
            case "煮付け":
                return (
                    ["\(fish) 1切れ", "醤油 大さじ3", "みりん 大さじ2", "砂糖 大さじ2", "酒 大さじ2", "水 100ml", "生姜 1片"],
                    ["\(fish)は切り身にして湯通しする", "生姜を薄切りにする", "鍋に調味料と水、生姜を入れて煮立てる", "\(fish)を加えて煮る", "よく冷ましてからお弁当箱に詰める"]
                )
            case "姿煮":
                return (
                    ["\(fish) 1尾", "醤油 大さじ4", "みりん 大さじ3", "砂糖 大さじ2", "酒 大さじ3", "水 200ml", "生姜 2片"],
                    ["\(fish)に切り込みを入れる", "生姜をスライスする", "鍋に調味料を煮立てる", "\(fish)を入れて煮る", "よく冷ましてからお弁当箱に詰める"]
                )
            case "西京焼き":
                return (
                    ["\(fish) 1切れ", "西京味噌 大さじ3", "みりん 大さじ1", "酒 大さじ1"],
                    ["\(fish)の水気を拭き取る", "西京味噌と調味料を混ぜる", "\(fish)に塗って一晩漬ける", "味噌を軽く拭き取って焼く", "よく冷ましてからお弁当箱に詰める"]
                )
            case "粕漬け焼き":
                return (
                    ["\(fish) 1切れ", "酒粕 50g", "みりん 大さじ1", "砂糖 大さじ1", "塩 少々"],
                    ["\(fish)に塩をふって30分置く", "酒粕と調味料を混ぜる", "\(fish)に塗って一晩漬ける", "粕を軽く拭き取って焼く", "よく冷ましてからお弁当箱に詰める"]
                )
            case "クリーム煮":
                return (
                    ["\(fish) 1切れ", "玉ねぎ 1/2個", "しめじ 50g", "生クリーム 100ml", "白ワイン 大さじ2", "バター 20g", "塩胡椒 少々"],
                    ["\(fish)を一口大に切る", "野菜を切る", "フライパンでバターを溶かし、\(fish)を焼く", "野菜を加えて炒める", "白ワインと生クリームを加えて煮る", "よく冷ましてからお弁当箱に詰める"]
                )
            case "アクアパッツァ":
                return (
                    ["\(fish) 1切れ", "ミニトマト 6個", "オリーブ 6個", "ニンニク 2片", "白ワイン 大さじ3", "オリーブオイル 大さじ2", "塩胡椒 少々"],
                    ["\(fish)に塩胡椒で下味をつける", "ニンニクをスライスする", "フライパンでオリーブオイルを熱し、\(fish)を焼く", "野菜を加えて炒める", "白ワインを加えて蒸し煮にする", "よく冷ましてからお弁当箱に詰める"]
                )
            case "ハーブグリル":
                return (
                    ["\(fish) 1切れ", "ローズマリー 2本", "タイム 2本", "レモン汁 大さじ1", "オリーブオイル 大さじ2", "塩胡椒 少々"],
                    ["\(fish)に塩胡椒で下味をつける", "ハーブを刻む", "オリーブオイルとレモン汁と合わせる", "\(fish)にまぶしてグリルで焼く", "よく冷ましてからお弁当箱に詰める"]
                )
            case "トマト煮":
                return (
                    ["\(fish) 1切れ", "トマト缶 1/2缶", "玉ねぎ 1/2個", "ニンニク 1片", "オリーブオイル 大さじ2", "塩胡椒 少々", "バジル 適量"],
                    ["\(fish)を一口大に切る", "野菜をみじん切りにする", "フライパンでオリーブオイルを熱し、\(fish)を焼く", "野菜を加えて炒める", "トマト缶を加えて煮込む", "よく冷ましてからお弁当箱に詰める"]
                )
            case "ポワレ":
                return (
                    ["\(fish) 1切れ", "塩 少々", "胡椒 少々", "小麦粉 大さじ1", "オリーブオイル 大さじ2", "バター 10g", "レモン 1/4個"],
                    ["\(fish)に塩胡椒で下味をつける", "薄く小麦粉をまぶす", "フライパンでオリーブオイルを熱し、\(fish)を焼く", "バターを加えて香りをつける", "レモンを添える", "よく冷ましてからお弁当箱に詰める"]
                )
            case "ガーリックソテー":
                return (
                    ["\(fish) 1切れ", "ニンニク 3片", "オリーブオイル 大さじ2", "塩胡椒 少々", "パセリ 適量", "白ワイン 大さじ2"],
                    ["\(fish)を一口大に切る", "ニンニクをスライスする", "フライパンでオリーブオイルを熱し、ニンニクを炒める", "\(fish)を加えて焼く", "白ワインを加えて仕上げる", "よく冷ましてからお弁当箱に詰める"]
                )
            case "レモンバター焼き":
                return (
                    ["\(fish) 1切れ", "バター 20g", "レモン汁 大さじ2", "レモンの皮 適量", "塩胡椒 少々", "パセリ 適量"],
                    ["\(fish)に塩胡椒で下味をつける", "フライパンでバターを溶かし、\(fish)を焼く", "レモン汁とレモンの皮を加える", "パセリを散らす", "よく冷ましてからお弁当箱に詰める"]
                )
            case "甘酢あんかけ":
                return (
                    ["\(fish) 1切れ", "片栗粉 大さじ3", "酢 大さじ3", "砂糖 大さじ3", "醤油 大さじ2", "ケチャップ 大さじ1", "水 大さじ3", "揚げ油 適量"],
                    ["\(fish)に片栗粉をまぶして揚げる", "甘酢の調味料を混ぜる", "フライパンで甘酢を煮立てる", "揚げた\(fish)に絡める", "よく冷ましてからお弁当箱に詰める"]
                )
            case "中華蒸し":
                return (
                    ["\(fish) 1切れ", "生姜 2片", "長ねぎ 1/2本", "醤油 大さじ2", "紹興酒 大さじ1", "ごま油 大さじ1", "砂糖 小さじ1"],
                    ["\(fish)に塩をふって15分置く", "生姜と長ねぎを千切りにする", "\(fish)に野菜をのせて蒸す", "調味料を混ぜて熱し、\(fish)にかける", "よく冷ましてからお弁当箱に詰める"]
                )
            case "チリソース":
                return (
                    ["\(fish) 1切れ", "片栗粉 大さじ2", "ケチャップ 大さじ3", "砂糖 大さじ2", "酢 大さじ1", "豆板醤 小さじ1", "ニンニク 1片", "生姜 1片"],
                    ["\(fish)を一口大に切り、片栗粉をまぶす", "油で揚げる", "調味料を混ぜ合わせる", "フライパンでソースを煮立て、\(fish)を絡める", "よく冷ましてからお弁当箱に詰める"]
                )
            case "唐揚げ甘酢だれ":
                return (
                    ["\(fish) 1切れ", "醤油 大さじ1", "酒 大さじ1", "片栗粉 大さじ3", "酢 大さじ2", "砂糖 大さじ2", "醤油 大さじ1", "揚げ油 適量"],
                    ["\(fish)を一口大に切り、下味をつける", "片栗粉をまぶして揚げる", "甘酢だれを作る", "揚げた\(fish)に甘酢だれを絡める", "よく冷ましてからお弁当箱に詰める"]
                )
            case "蒸し物中華風":
                return (
                    ["\(fish) 1切れ", "生姜 2片", "長ねぎ 1/2本", "醤油 大さじ2", "オイスターソース 大さじ1", "ごま油 大さじ1"],
                    ["\(fish)に下味をつける", "生姜と長ねぎを千切りにする", "\(fish)と野菜を蒸し器で蒸す", "調味料を混ぜて熱し、\(fish)にかける", "よく冷ましてからお弁当箱に詰める"]
                )
            case "フライ":
                return (
                    ["\(fish) 1切れ", "小麦粉 大さじ2", "卵 1個", "パン粉 適量", "揚げ油 適量", "塩胡椒 少々"],
                    ["\(fish)に塩胡椒で下味をつける", "小麦粉、卵、パン粉の順につける", "170℃の油で揚げる", "きつね色になったら取り出す", "よく油を切って冷まし、お弁当箱に詰める"]
                )
            case "天ぷら":
                return (
                    ["\(fish) 1切れ", "天ぷら粉 大さじ3", "冷水 大さじ3", "揚げ油 適量"],
                    ["\(fish)を一口大に切る", "天ぷら粉と冷水を軽く混ぜる", "\(fish)に衣をつける", "170℃の油で揚げる", "よく油を切って冷まし、お弁当箱に詰める"]
                )
            case "唐揚げ":
                return (
                    ["\(fish) 1切れ", "醤油 大さじ1", "酒 大さじ1", "生姜汁 小さじ1", "片栗粉 大さじ3", "揚げ油 適量"],
                    ["\(fish)を一口大に切り、調味料で下味をつける", "片栗粉をまぶす", "170℃の油で揚げる", "カリッと揚がったら取り出す", "よく油を切って冷まし、お弁当箱に詰める"]
                )
            case "なめろう風":
                return (
                    ["\(fish) 1切れ", "味噌 大さじ1", "生姜 1片", "長ねぎ 1/4本", "青じそ 3枚"],
                    ["\(fish)を細かく刻む", "生姜、長ねぎ、青じそもみじん切りにする", "味噌と一緒に叩いて混ぜる", "一口大にまとめてフライパンで焼く", "よく冷ましてからお弁当箱に詰める"]
                )
            default:
                return (
                    ["\(fish) 1切れ", "塩 適量"],
                    ["\(fish)に塩をふる", "グリルで焼く", "よく冷ましてからお弁当箱に詰める"]
                )
            }
        }
        
        // より強力なランダム選択のためにレシピをシャッフル
        let shuffledRecipes = recipes.shuffled()
        let selectedRecipes = [
            safeArrayAccess(shuffledRecipes, index: variation % shuffledRecipes.count),
            safeArrayAccess(shuffledRecipes, index: (variation + 1) % shuffledRecipes.count),
            safeArrayAccess(shuffledRecipes, index: (variation + 2) % shuffledRecipes.count)
        ]
        
        return selectedRecipes.enumerated().map { index, recipe in
            let (name, fish, method) = recipe
            let (ingredients, instructions) = getIngredientsAndInstructions(name: name, fish: fish, method: method)
            
            return BentoRecipe(
                name: "\(name)弁当",
                description: "\(fish)を\(method)で美味しく調理したお弁当",
                category: .fishMain,
                mainDish: DishItem(
                    name: name,
                    ingredients: ingredients,
                    instructions: instructions
                ),
                sideDish1: {
                    let sides = generateSideDishes(mainDishName: name, category: .fishMain, variation: variation + index)
                    return sides.0
                }(),
                sideDish2: {
                    let sides = generateSideDishes(mainDishName: name, category: .fishMain, variation: variation + index)
                    return sides.1
                }(),
                prepTime: 25 + index * 2,
                calories: 350 + index * 20,
                difficulty: .easy,
                tips: ["\(method)は火加減が重要", "魚の臭みを取ること"]
            )
        }
    }
    
    
    private func generateRandomHeartyRecipes(variation: Int) -> [BentoRecipe] {
        let recipes = [
            // 和風料理
            ("豚の生姜焼き", "豚ロース薄切り", "生姜焼き"),
            ("鶏の照り焼き", "鶏もも肉", "照り焼き"),
            ("鶏の唐揚げ", "鶏もも肉", "唐揚げ"),
            ("鶏胸肉のゴマ照り", "鶏胸肉", "ゴマ照り"),
            ("豚の角煮", "豚バラ肉", "角煮"),
            ("鶏の竜田揚げ", "鶏もも肉", "竜田揚げ"),
            ("豚の味噌漬け焼き", "豚ロース", "味噌漬け焼き"),
            ("牛肉のしぐれ煮", "牛肉", "しぐれ煮"),
            
            // 洋風料理
            ("牛肉ステーキ", "牛ステーキ肉", "ステーキ"),
            ("ハンバーグ", "合いびき肉", "ハンバーグ"),
            ("ポークチャップ", "豚ロース", "ポークチャップ"),
            ("チキンソテー", "鶏むね肉", "チキンソテー"),
            ("ミートボール", "合いびき肉", "ミートボール"),
            ("鶏肉のマスタード焼き", "鶏もも肉", "マスタード焼き"),
            ("豚肉のハーブ焼き", "豚ロース", "ハーブ焼き"),
            ("ビーフシチュー風煮込み", "牛肉", "ビーフシチュー風"),
            
            // 中華風料理
            ("豚バラの甘辣炒め", "豚バラ肉", "甘辣炒め"),
            ("鶏肉の黒酢あん", "鶏もも肉", "黒酢あん"),
            ("豚肉の四川風炒め", "豚バラ肉", "四川風炒め"),
            ("牛肉のオイスター炒め", "牛肉", "オイスター炒め"),
            ("鶏肉の麻婆風", "鶏ひき肉", "麻婆風"),
            ("豚肉の回鍋肉風", "豚バラ肉", "回鍋肉風"),
            
            // イタリアン風料理
            ("鶏肉のトマト煮込み", "鶏もも肉", "トマト煮込み"),
            ("豚肉のバルサミコ焼き", "豚ロース", "バルサミコ焼き"),
            ("牛肉のガーリック炒め", "牛肉", "ガーリック炒め"),
            ("鶏肉のハーブグリル", "鶏むね肉", "ハーブグリル"),
            
            // その他多国籍料理
            ("鶏肉のタンドリー風", "鶏もも肉", "タンドリー風"),
            ("豚肉のBBQソース焼き", "豚ロース", "BBQソース焼き"),
            ("牛肉のペッパーステーキ", "牛肉", "ペッパーステーキ"),
            ("鶏肉のカレー風味焼き", "鶏もも肉", "カレー風味焼き")
        ]
        
        func getIngredientsAndInstructions(name: String, meat: String, method: String) -> ([String], [String]) {
            switch method {
            case "生姜焼き":
                return (
                    ["豚ロース薄切り 200g", "玉ねぎ 1/2個", "生姜 1片", "醤油 大さじ3", "みりん 大さじ2", "砂糖 大さじ1", "酒 大さじ2", "サラダ油 大さじ1"],
                    ["豚肉を常温に戻し、一口大に切る", "玉ねぎをスライス、生姜をすりおろしにする", "調味料を混ぜ合わせておく", "フライパンに油を熱し、豚肉を炒める", "玉ねぎを加えて炒め、調味料を絡める", "よく冷ましてからお弁当箱に詰める"]
                )
            case "照り焼き":
                return (
                    ["鶏もも肉 200g", "醤油 大さじ3", "みりん 大さじ3", "砂糖 大さじ2", "酒 大さじ2", "サラダ油 大さじ1"],
                    ["鶏肉を一口大に切り、塩胡椒で下味をつける", "調味料を混ぜ合わせておく", "フライパンに油を熱し、鶏肉を焼く", "調味料を加えて照りをつける", "よく冷ましてからお弁当箱に詰める"]
                )
            case "ステーキ":
                return (
                    ["牛ステーキ肉 180g", "塩 適量", "黒胡椒 適量", "ニンニク 2片", "バター 20g", "オリーブオイル 大さじ1"],
                    ["牛肉を常温に戻し、塩胡椒で下味をつける", "ニンニクをつぶす", "フライパンを強火で熱し、オイルを入れる", "牛肉を焼き、ニンニクとバターを加える", "休ませてから切り、よく冷ましてからお弁当箱に詰める"]
                )
            case "唐揚げ":
                return (
                    ["鶏もも肉 250g", "醤油 大さじ2", "酒 大さじ1", "生姜汁 小さじ1", "ニンニク 1片", "片栗粉 大さじ4", "揚げ油 適量"],
                    ["鶏肉を一口大に切り、下味の材料に30分漬ける", "水気を拭き取り、片栗粉をまぶす", "170℃の油で一度揚げ、一度取り出す", "180℃で二度揚げしてカリッと仕上げる", "よく油を切って冷まし、お弁当箱に詰める"]
                )
            case "甘辣炒め":
                return (
                    ["豚バラ肉 200g", "玉ねぎ 1/2個", "醤油 大さじ2", "砂糖 大さじ2", "コチュジャン 大さじ1", "ごま油 大さじ1", "にんにく 1片"],
                    ["豚バラ肉を一口大に切る", "玉ねぎをスライスし、にんにくをみじん切りにする", "フライパンでごま油を熱し、豚肉を炒める", "玉ねぎとにんにくを加えて炒める", "調味料を加えて甘辛く炒め合わせる", "よく冷ましてからお弁当箱に詰める"]
                )
            case "ゴマ照り":
                return (
                    ["鶏胸肉 200g", "醤油 大さじ2", "みりん 大さじ2", "砂糖 大さじ1", "白ごま 大さじ2", "ごま油 大さじ1"],
                    ["鶏胸肉を削ぎ切りにして一口大に切る", "調味料を混ぜ合わせてタレを作る", "フライパンでごま油を熱し、鶏肉を焼く", "タレを加えて照りをつける", "白ごまを振りかけて混ぜる", "よく冷ましてからお弁当箱に詰める"]
                )
            case "角煮":
                return (
                    ["豚バラ肉 300g", "醤油 大さじ4", "みりん 大さじ3", "砂糖 大さじ2", "酒 大さじ3", "生姜 1片", "長ねぎ 1本"],
                    ["豚バラ肉を5cm角に切る", "フライパンで表面を焼く", "煮込み鍋に移し、調味料と水を加える", "1時間煮込む", "よく冷ましてからお弁当箱に詰める"]
                )
            case "竜田揚げ":
                return (
                    ["鶏もも肉 250g", "醤油 大さじ2", "酒 大さじ1", "みりん 大さじ1", "生姜汁 小さじ1", "片栗粉 大さじ5", "揚げ油 適量"],
                    ["鶏肉を一口大に切り、下味に30分漬ける", "片栗粉をまぶす", "170℃の油で揚げる", "表面がカリッとしたら取り出す", "よく油を切って冷まし、お弁当箱に詰める"]
                )
            case "味噌漬け焼き":
                return (
                    ["豚ロース 200g", "味噌 大さじ3", "みりん 大さじ2", "砂糖 大さじ1", "酒 大さじ1", "ごま油 大さじ1"],
                    ["豚肉を一口大に切る", "味噌ダレを作り、豚肉に30分漬ける", "フライパンでごま油を熱し、豚肉を焼く", "味噌ダレを絡めながら焼く", "よく冷ましてからお弁当箱に詰める"]
                )
            case "しぐれ煮":
                return (
                    ["牛肉 200g", "生姜 2片", "醤油 大さじ3", "みりん 大さじ2", "砂糖 大さじ1", "酒 大さじ2"],
                    ["牛肉を細切りにする", "生姜を千切りにする", "フライパンで牛肉を炒める", "調味料を加えて汁気がなくなるまで煮る", "よく冷ましてからお弁当箱に詰める"]
                )
            case "ハンバーグ":
                return (
                    ["合いびき肉 250g", "玉ねぎ 1/2個", "パン粉 大さじ3", "牛乳 大さじ2", "卵 1個", "塩胡椒 少々", "サラダ油 大さじ1"],
                    ["玉ねぎをみじん切りにして炒める", "パン粉を牛乳に浸す", "全ての材料を混ぜ合わせる", "楕円形に成形する", "フライパンで両面を焼く", "よく冷ましてからお弁当箱に詰める"]
                )
            case "ポークチャップ":
                return (
                    ["豚ロース 200g", "玉ねぎ 1/2個", "ケチャップ 大さじ3", "ウスターソース 大さじ2", "砂糖 大さじ1", "塩胡椒 少々", "サラダ油 大さじ1"],
                    ["豚肉に塩胡椒で下味をつける", "玉ねぎをスライスする", "フライパンで豚肉を焼く", "玉ねぎを加えて炒める", "調味料を加えて絡める", "よく冷ましてからお弁当箱に詰める"]
                )
            case "チキンソテー":
                return (
                    ["鶏むね肉 200g", "塩 少々", "胡椒 少々", "小麦粉 大さじ2", "バター 20g", "レモン汁 大さじ1", "白ワイン 大さじ2"],
                    ["鶏肉を削ぎ切りにし、塩胡椒で下味をつける", "小麦粉をまぶす", "フライパンでバターを溶かし、鶏肉を焼く", "白ワインとレモン汁を加える", "よく冷ましてからお弁当箱に詰める"]
                )
            case "ミートボール":
                return (
                    ["合いびき肉 200g", "玉ねぎ 1/4個", "パン粉 大さじ2", "牛乳 大さじ1", "卵 1/2個", "トマトソース 大さじ4", "塩胡椒 少々"],
                    ["玉ねぎをみじん切りにする", "肉だねを作り、丸める", "フライパンで転がしながら焼く", "トマトソースを加えて煮込む", "よく冷ましてからお弁当箱に詰める"]
                )
            case "マスタード焼き":
                return (
                    ["鶏もも肉 200g", "粒マスタード 大さじ2", "はちみつ 大さじ1", "醤油 大さじ1", "オリーブオイル 大さじ1"],
                    ["鶏肉を一口大に切る", "調味料を混ぜ合わせる", "鶏肉に調味料を絡める", "フライパンで焼く", "よく冷ましてからお弁当箱に詰める"]
                )
            case "ハーブ焼き":
                return (
                    ["豚ロース 200g", "ローズマリー 2本", "タイム 2本", "ニンニク 2片", "オリーブオイル 大さじ2", "塩胡椒 少々"],
                    ["豚肉に塩胡椒で下味をつける", "ハーブとニンニクを刻む", "オリーブオイルと合わせる", "豚肉にまぶしてフライパンで焼く", "よく冷ましてからお弁当箱に詰める"]
                )
            case "ビーフシチュー風":
                return (
                    ["牛肉 200g", "玉ねぎ 1/2個", "人参 1/2本", "デミグラスソース 大さじ4", "赤ワイン 大さじ2", "バター 20g"],
                    ["牛肉を一口大に切る", "野菜を切る", "フライパンで牛肉を焼く", "野菜を加えて炒める", "デミグラスソースと赤ワインを加えて煮込む", "よく冷ましてからお弁当箱に詰める"]
                )
            case "黒酢あん":
                return (
                    ["鶏もも肉 200g", "黒酢 大さじ3", "砂糖 大さじ2", "醤油 大さじ2", "片栗粉 大さじ1", "サラダ油 大さじ1"],
                    ["鶏肉を一口大に切る", "調味料を混ぜ合わせる", "鶏肉に片栗粉をまぶす", "フライパンで焼く", "黒酢あんを絡める", "よく冷ましてからお弁当箱に詰める"]
                )
            case "四川風炒め":
                return (
                    ["豚バラ肉 200g", "豆板醤 大さじ1", "醤油 大さじ2", "砂糖 大さじ1", "花椒 少々", "ごま油 大さじ1", "長ねぎ 1本"],
                    ["豚肉を一口大に切る", "長ねぎを切る", "フライパンでごま油を熱し、豚肉を炒める", "豆板醤を加えて炒める", "調味料を加えて仕上げる", "よく冷ましてからお弁当箱に詰める"]
                )
            case "オイスター炒め":
                return (
                    ["牛肉 200g", "オイスターソース 大さじ2", "醤油 大さじ1", "砂糖 小さじ1", "ごま油 大さじ1", "ニンニク 1片"],
                    ["牛肉を薄切りにする", "ニンニクをみじん切りにする", "フライパンでごま油を熱し、牛肉を炒める", "調味料を加えて炒め合わせる", "よく冷ましてからお弁当箱に詰める"]
                )
            case "麻婆風":
                return (
                    ["鶏ひき肉 200g", "豆腐 1/2丁", "豆板醤 大さじ1", "醤油 大さじ2", "砂糖 大さじ1", "ごま油 大さじ1", "長ねぎ 1/2本"],
                    ["豆腐を1cm角に切る", "長ねぎをみじん切りにする", "フライパンでひき肉を炒める", "豆板醤を加えて炒める", "豆腐と調味料を加えて煮込む", "よく冷ましてからお弁当箱に詰める"]
                )
            case "回鍋肉風":
                return (
                    ["豚バラ肉 200g", "キャベツ 3枚", "甜麺醤 大さじ2", "醤油 大さじ1", "砂糖 小さじ1", "ごま油 大さじ1", "ニンニク 1片"],
                    ["豚肉を薄切りにする", "キャベツを一口大に切る", "フライパンでごま油を熱し、豚肉を炒める", "キャベツを加えて炒める", "調味料を加えて炒め合わせる", "よく冷ましてからお弁当箱に詰める"]
                )
            case "トマト煮込み":
                return (
                    ["鶏もも肉 200g", "トマト缶 1/2缶", "玉ねぎ 1/2個", "ニンニク 1片", "オリーブオイル 大さじ2", "塩胡椒 少々", "バジル 適量"],
                    ["鶏肉を一口大に切る", "玉ねぎとニンニクをみじん切りにする", "フライパンでオリーブオイルを熱し、鶏肉を焼く", "野菜を加えて炒める", "トマト缶を加えて煮込む", "よく冷ましてからお弁当箱に詰める"]
                )
            case "バルサミコ焼き":
                return (
                    ["豚ロース 200g", "バルサミコ酢 大さじ2", "はちみつ 大さじ1", "醤油 大さじ1", "オリーブオイル 大さじ1"],
                    ["豚肉を一口大に切る", "調味料を混ぜ合わせる", "豚肉に調味料を絡める", "フライパンで焼く", "よく冷ましてからお弁当箱に詰める"]
                )
            case "ガーリック炒め":
                return (
                    ["牛肉 200g", "ニンニク 3片", "オリーブオイル 大さじ2", "塩胡椒 少々", "パセリ 適量", "白ワイン 大さじ2"],
                    ["牛肉を薄切りにする", "ニンニクをスライスする", "フライパンでオリーブオイルを熱し、ニンニクを炒める", "牛肉を加えて炒める", "白ワインを加えて仕上げる", "よく冷ましてからお弁当箱に詰める"]
                )
            case "ハーブグリル":
                return (
                    ["鶏むね肉 200g", "ローズマリー 2本", "タイム 2本", "レモン汁 大さじ1", "オリーブオイル 大さじ2", "塩胡椒 少々"],
                    ["鶏肉を削ぎ切りにする", "ハーブを刻む", "調味料と合わせる", "鶏肉にまぶしてグリルで焼く", "よく冷ましてからお弁当箱に詰める"]
                )
            case "タンドリー風":
                return (
                    ["鶏もも肉 200g", "ヨーグルト 大さじ3", "カレー粉 大さじ1", "ニンニク 1片", "生姜 1片", "塩 少々", "オリーブオイル 大さじ1"],
                    ["鶏肉を一口大に切る", "ヨーグルトと香辛料を混ぜる", "鶏肉に30分漬ける", "フライパンで焼く", "よく冷ましてからお弁当箱に詰める"]
                )
            case "BBQソース焼き":
                return (
                    ["豚ロース 200g", "BBQソース 大さじ3", "はちみつ 大さじ1", "醤油 大さじ1", "ニンニク 1片", "玉ねぎ 1/4個"],
                    ["豚肉を一口大に切る", "調味料を混ぜ合わせる", "豚肉に調味料を絡める", "フライパンで焼く", "よく冷ましてからお弁当箱に詰める"]
                )
            case "ペッパーステーキ":
                return (
                    ["牛肉 200g", "黒胡椒 小さじ2", "塩 少々", "バター 20g", "醤油 大さじ1", "ニンニク 1片"],
                    ["牛肉に塩と黒胡椒を押し付ける", "フライパンを熱し、牛肉を焼く", "バターとニンニクを加える", "醤油で香り付け", "よく冷ましてからお弁当箱に詰める"]
                )
            case "カレー風味焼き":
                return (
                    ["鶏もも肉 200g", "カレー粉 大さじ1", "醤油 大さじ2", "みりん 大さじ1", "砂糖 小さじ1", "サラダ油 大さじ1"],
                    ["鶏肉を一口大に切る", "調味料を混ぜ合わせる", "鶏肉に調味料を絡める", "フライパンで焼く", "よく冷ましてからお弁当箱に詰める"]
                )
            default:
                return (
                    ["豚肉 200g", "醤油 大さじ2", "塩胡椒 少々"],
                    ["豚肉を炒める", "調味料で味付け", "よく冷ましてからお弁当箱に詰める"]
                )
            }
        }
        
        // より強力なランダム選択のためにレシピをシャッフル
        let shuffledRecipes = recipes.shuffled()
        let selectedRecipes = [
            safeArrayAccess(shuffledRecipes, index: variation % shuffledRecipes.count),
            safeArrayAccess(shuffledRecipes, index: (variation + 1) % shuffledRecipes.count),
            safeArrayAccess(shuffledRecipes, index: (variation + 2) % shuffledRecipes.count)
        ]
        
        return selectedRecipes.enumerated().map { index, recipe in
            let (name, meat, method) = recipe
            let (ingredients, instructions) = getIngredientsAndInstructions(name: name, meat: meat, method: method)
            
            return BentoRecipe(
                name: "\(name)弁当",
                description: "ボリューム満点の\(name)",
                category: .hearty,
                mainDish: DishItem(
                    name: name,
                    ingredients: ingredients,
                    instructions: instructions
                ),
                sideDish1: {
                    let sides = generateSideDishes(mainDishName: name, category: .hearty, variation: variation + index)
                    return sides.0
                }(),
                sideDish2: {
                    let sides = generateSideDishes(mainDishName: name, category: .hearty, variation: variation + index)
                    return sides.1
                }(),
                prepTime: 25,
                calories: 550,
                difficulty: .medium,
                tips: ["\(method)のコツを掌握", "ガッツり系で満足感アップ"]
            )
        }
    }
    
    private func generateRandomVegetableRecipes(variation: Int) -> [BentoRecipe] {
        // 完全な多様性のために拡張されたリスト
        let mainVeggies = ["なす", "かぼちゃ", "ズッキーニ", "パプリカ", "トマト", "アスパラ", "オクラ", "いんげん", "ブロッコリー", "カリフラワー"]
        let cookingMethods = ["グリル", "蒸し焼き", "炒め物", "煮物", "マリネ", "ロースト", "蒸し物", "ソテー", "炒め煮", "焼き浸し"]
        let uniqueStyles = ["カレー風味", "中華風", "イタリアン風", "和風", "エスニック風", "ハーブ風味", "スパイス炒め", "バルサミコ風味", "ガーリック風味", "レモン風味"]
        
        let veggie = safeArrayAccess(mainVeggies, index: variation)
        let method = safeArrayAccess(cookingMethods, index: variation)
        let style = safeArrayAccess(uniqueStyles, index: variation + 2)
        
        return [
            BentoRecipe(
                name: "\(veggie)の\(method)弁当",
                description: "\(veggie)が主役の野菜たっぷり弁当",
                category: .omakase,
                mainDish: DishItem(
                    name: "\(veggie)の\(method)",
                    ingredients: ["\(veggie) 2個", "オリーブオイル 大さじ1", "塩 少々"],
                    instructions: ["\(veggie)を切る", "\(method)で調理", "よく冷ましてからお弁当箱に詰める"]
                ),
                sideDish1: {
                    let sides = generateSideDishes(mainDishName: "\(veggie)の\(method)", category: .omakase, variation: variation)
                    return sides.0
                }(),
                sideDish2: {
                    let sides = generateSideDishes(mainDishName: "\(veggie)の\(method)", category: .omakase, variation: variation)
                    return sides.1
                }(),
                prepTime: 25,
                calories: 300,
                difficulty: .easy,
                tips: ["野菜の食感を活かす", "彩りよく"]
            ),
            BentoRecipe(
                name: "\(veggie)の\(style)\(method)弁当",
                description: "\(veggie)を\(style)に\(method)した個性的な弁当",
                category: .omakase,
                mainDish: DishItem(
                    name: "\(veggie)の\(style)\(method)",
                    ingredients: ["\(veggie) 2個", "特製スパイス 適量", "オリーブオイル 大さじ1"],
                    instructions: ["\(veggie)を準備", "\(style)の技法で\(method)", "よく冷ましてからお弁当箱に詰める"]
                ),
                sideDish1: {
                    let sides = generateSideDishes(mainDishName: "\(veggie)の\(style)\(method)", category: .omakase, variation: variation + 1)
                    return sides.0
                }(),
                sideDish2: {
                    let sides = generateSideDishes(mainDishName: "\(veggie)の\(style)\(method)", category: .omakase, variation: variation + 1)
                    return sides.1
                }(),
                prepTime: 25,
                calories: 290,
                difficulty: .medium,
                tips: ["\(style)の風味を活かす", "新しい野菜の楽しみ方"]
            ),
            BentoRecipe(
                name: "キノアと野菜のパワーサラダ弁当",
                description: "キノア入りの栄養満点野菜サラダ弁当",
                category: .omakase,
                mainDish: DishItem(
                    name: "キノアベジタブルサラダ",
                    ingredients: ["キノア 50g", "紫キャベツ 2枚", "黄パプリカ 1個", "枝豆 50g", "フェタチーズ 30g"],
                    instructions: ["キノアを茹でる", "野菜を細切り", "全て混ぜ合わせる", "よく冷ましてからお弁当箱に詰める"]
                ),
                sideDish1: {
                    let sides = generateSideDishes(mainDishName: "キノアベジタブルサラダ", category: .omakase, variation: variation + 2)
                    return sides.0
                }(),
                sideDish2: {
                    let sides = generateSideDishes(mainDishName: "キノアベジタブルサラダ", category: .omakase, variation: variation + 2)
                    return sides.1
                }(),
                prepTime: 30,
                calories: 340,
                difficulty: .medium,
                tips: ["スーパーフード活用", "栄養密度最大化"]
            )
        ]
    }
    
    private func generateRandomSimpleRecipes(variation: Int) -> [BentoRecipe] {
        let easyMains = ["卵焼き", "ウインナー", "ハンバーグ", "冷凍から揚げ", "ツナ炒め", "チーズオムレツ", "ソーセージ炒め", "ミートボール", "鮭フレーク", "缶詰サバ"]
        let quickSides = ["ブロッコリー茹で", "人参炒め", "コーン炒め", "もやし炒め", "キャベツ炒め", "きのこソテー", "スナップエンドウ", "ミニトマト", "枝豆", "アスパラ炒め"]
        let timeVariations = ["3分", "5分", "8分", "10分", "12分", "15分"]
        
        let main = safeArrayAccess(easyMains, index: variation)
        let side1 = safeArrayAccess(quickSides, index: variation)
        let side2 = safeArrayAccess(quickSides, index: variation + 1)
        let timeLimit = safeArrayAccess(timeVariations, index: variation)
        
        return [
            BentoRecipe(
                name: "簡単卵焼き弁当",
                description: "10分で作れる卵焼きメイン弁当",
                category: .simple,
                mainDish: DishItem(
                    name: "卵焼き",
                    ingredients: ["卵 3個", "だし汁 大さじ2", "砂糖 大さじ1", "塩 少々"],
                    instructions: ["材料をボウルで混ぜる", "卵焼き器で巻きながら焼く", "粗熱を取る", "よく冷ましてからお弁当箱に詰める"]
                ),
                sideDish1: {
                    let sides = generateSideDishes(mainDishName: "卵焼き", category: .simple, variation: 0)
                    return sides.0
                }(),
                sideDish2: {
                    let sides = generateSideDishes(mainDishName: "卵焼き", category: .simple, variation: 0)
                    return sides.1
                }(),
                prepTime: 10,
                calories: 350,
                difficulty: .easy,
                tips: ["卵焼きは弱火でゆっくり", "彩りを大切に"]
            ),
            BentoRecipe(
                name: "レンジ蒸し鶏弁当",
                description: "電子レンジで作る蒸し鶏メイン弁当",
                category: .simple,
                mainDish: DishItem(
                    name: "レンジ蒸し鶏",
                    ingredients: ["鶏むね肉 150g", "塩 少々", "酒 大さじ1", "生姜 1片"],
                    instructions: ["鶏肉に塩と酒をふりかける", "生姜をのせてラップし600Wで3分加熱", "そのまま2分蒸らす", "よく冷ましてからお弁当箱に詰める"]
                ),
                sideDish1: {
                    let sides = generateSideDishes(mainDishName: "レンジ蒸し鶏", category: .simple, variation: 1)
                    return sides.0
                }(),
                sideDish2: {
                    let sides = generateSideDishes(mainDishName: "レンジ蒸し鶏", category: .simple, variation: 1)
                    return sides.1
                }(),
                prepTime: 8,
                calories: 320,
                difficulty: .easy,
                tips: ["レンジは短時間ずつ加熱", "加熱後はよく混ぜる"]
            ),
            BentoRecipe(
                name: "冷凍唐揚げ弁当",
                description: "冷凍唐揚げをメインにした簡単弁当",
                category: .simple,
                mainDish: DishItem(
                    name: "冷凍唐揚げ",
                    ingredients: ["冷凍唐揚げ 6個", "レモン 1/4個"],
                    instructions: ["冷凍唐揚げを表示通りに加熱", "レモンを絞って風味付け", "粗熱を取る", "よく冷ましてからお弁当箱に詰める"]
                ),
                sideDish1: {
                    let sides = generateSideDishes(mainDishName: "冷凍唐揚げ", category: .simple, variation: 2)
                    return sides.0
                }(),
                sideDish2: {
                    let sides = generateSideDishes(mainDishName: "冷凍唐揚げ", category: .simple, variation: 2)
                    return sides.1
                }(),
                prepTime: 12,
                calories: 420,
                difficulty: .easy,
                tips: ["冷凍食品は完全に加熱", "彩りよく詰める"]
            )
        ]
    }
    
    private func generateRandomOmakaseRecipes(variation: Int) -> [BentoRecipe] {
        // 完全にユニークな創造的レシピのための拡張リスト
        let creativeMains = [
            "鶏肉のスパイス味噌焼き", "豚肉のりんごバルサミコ", "鮭のハーブクラスト", "牛肉の柚子胡椒ステーキ", "鶏肉のココナッツカレー焼き",
            "豚肉のマスタードハニー", "鯖のオリーブタプナード", "鶏肉のレモンタイム", "牛肉のロゼマリーガーリック", "鮭のジンジャーソイ",
            "豚肉のパイナップル焼き", "鶏肉のバジルペスト", "鯖のトマトハーブ", "牛肉のわさび醤油", "鮭のディル風味"
        ]
        let creativeSides = [
            "紫キャベツのアップル和え", "ビーツのバルサミコロースト", "芽キャベツのベーコン巻き", "カリフラワーのスパイス焼き", "ズッキーニのリボンサラダ",
            "人参のハニーグレーズ", "アスパラのパルメザン焼き", "茄子のミントマリネ", "パプリカのチーズ詰め", "ブロッコリーのアーモンド和え",
            "大根のレモンピクルス", "きのこのハーブバター", "オクラのガーリック炒め", "いんげんのセサミ和え", "かぼちゃのシナモンロースト"
        ]
        let uniqueConcepts = [
            "地中海風", "北欧風", "南米風", "中東風", "カリブ風", "アジアンフュージョン", "モダン和食", "クリエイティブ洋食", "エキゾチック", "アーバンスタイル"
        ]
        
        let main = safeArrayAccess(creativeMains, index: variation)
        let side1 = safeArrayAccess(creativeSides, index: variation)
        let side2 = safeArrayAccess(creativeSides, index: variation + 1)
        let concept = safeArrayAccess(uniqueConcepts, index: variation)
        
        // 料理名に応じた適切な材料を設定する関数
        func getIngredientsForDish(_ dishName: String) -> ([String], [String]) {
            if dishName.contains("鶏肉") {
                return (["鶏もも肉 200g", "醤油 大さじ2", "みりん 大さじ1", "生姜 1片"], 
                       ["鶏肉を一口大に切る", "調味料で下味をつける", "フライパンで焼く", "よく冷ましてからお弁当箱に詰める"])
            } else if dishName.contains("豚肉") {
                if dishName.contains("パイナップル") {
                    return (["豚ロース 200g", "パイナップル 1/4個", "醤油 大さじ1", "砂糖 大さじ1", "酢 大さじ1"], 
                           ["豚肉とパイナップルを切る", "フライパンで豚肉を焼く", "パイナップルと調味料を加える", "よく冷ましてからお弁当箱に詰める"])
                } else {
                    return (["豚ロース 200g", "玉ねぎ 1/2個", "醤油 大さじ2", "みりん 大さじ1"], 
                           ["豚肉と玉ねぎを切る", "フライパンで炒める", "調味料で味付け", "よく冷ましてからお弁当箱に詰める"])
                }
            } else if dishName.contains("牛肉") {
                return (["牛肉 200g", "醤油 大さじ2", "みりん 大さじ1", "にんにく 1片"], 
                       ["牛肉を切る", "にんにくをみじん切り", "フライパンで焼いて調味料で味付け", "よく冷ましてからお弁当箱に詰める"])
            } else if dishName.contains("鮭") {
                return (["鮭切り身 1切れ", "塩 少々", "レモン 1/4個"], 
                       ["鮭に塩をふる", "グリルで焼く", "レモンを添える", "よく冷ましてからお弁当箱に詰める"])
            } else {
                // デフォルト
                return (["鶏もも肉 200g", "醤油 大さじ2", "塩 少々"], 
                       ["食材を切る", "調味料で味付け", "加熱調理", "よく冷ましてからお弁当箱に詰める"])
            }
        }
        
        let (ingredients, instructions) = getIngredientsForDish(main)
        
        return [
            BentoRecipe(
                name: "\(main)弁当",
                description: "\(main)がメインの家庭的なお弁当",
                category: .omakase,
                mainDish: DishItem(
                    name: "\(main)",
                    ingredients: ingredients,
                    instructions: instructions
                ),
                sideDish1: {
                    let sides = generateSideDishes(mainDishName: main, category: .omakase, variation: variation)
                    return sides.0
                }(),
                sideDish2: {
                    let sides = generateSideDishes(mainDishName: main, category: .omakase, variation: variation)
                    return sides.1
                }(),
                prepTime: 25,
                calories: 450,
                difficulty: .easy,
                tips: ["鶏肉は皮目から焼く", "野菜は彩りよく"]
            ),
            BentoRecipe(
                name: "豚の生姜焼き弁当",
                description: "定番の豚の生姜焼きがメインの家庭的弁当",
                category: .omakase,
                mainDish: DishItem(
                    name: "豚の生姜焼き",
                    ingredients: ["豚ロース薄切り 200g", "玉ねぎ 1/2個", "生姜 1片", "醤油 大さじ2", "みりん 大さじ1"],
                    instructions: ["豚肉と玉ねぎを切る", "生姜をすりおろす", "フライパンで炒めて調味料で味付け", "よく冷ましてからお弁当箱に詰める"]
                ),
                sideDish1: {
                    let sides = generateSideDishes(mainDishName: "豚の生姜焼き", category: .omakase, variation: variation + 1)
                    return sides.0
                }(),
                sideDish2: {
                    let sides = generateSideDishes(mainDishName: "豚の生姜焼き", category: .omakase, variation: variation + 1)
                    return sides.1
                }(),
                prepTime: 20,
                calories: 480,
                difficulty: .easy,
                tips: ["豚肉は強火で炒める", "卵焼きは弱火でゆっくり"]
            ),
            BentoRecipe(
                name: "鮭の塩焼き弁当",
                description: "焼き鮭をメインにした和風お弁当",
                category: .omakase,
                mainDish: DishItem(
                    name: "鮭の塩焼き",
                    ingredients: ["鮭切り身 1切れ", "塩 少々", "レモン 1/4個"],
                    instructions: ["鮭に塩をふって15分置く", "グリルで両面を焼く", "レモンを添える", "よく冷ましてからお弁当箱に詰める"]
                ),
                sideDish1: {
                    let sides = generateSideDishes(mainDishName: "鮭の塩焼き", category: .omakase, variation: variation + 2)
                    return sides.0
                }(),
                sideDish2: {
                    let sides = generateSideDishes(mainDishName: "鮭の塩焼き", category: .omakase, variation: variation + 2)
                    return sides.1
                }(),
                prepTime: 25,
                calories: 380,
                difficulty: .easy,
                tips: ["鮭は焼きすぎに注意", "ごぼうはアク抜きを忘れずに"]
            )
        ]
    }
    
    private func generateIngredientBasedFallback(_ selectedIngredients: [Ingredient]) -> [BentoRecipe] {
        // 選択された主材料を取得
        let mainProteins = selectedIngredients.filter { $0.category == .mainProtein }
        let vegetables = selectedIngredients.filter { $0.category == .vegetables }
        let seasonings = selectedIngredients.filter { $0.category == .seasonings }
        
        var fallbackRecipes: [BentoRecipe] = []
        
        print("🔄 生成フォールバックレシピ - 主材料: \(mainProteins.count), 野菜: \(vegetables.count)")
        
        // 主材料がある場合の処理
        if let mainProtein = mainProteins.first {
            // 主材料に基づくメインレシピ
            fallbackRecipes.append(createMainProteinRecipe(mainProtein, vegetables: vegetables))
            print("✅ 主材料レシピ追加: \(fallbackRecipes.count)")
            
            // 追加の主材料レシピまたはバリエーション
            if mainProteins.count > 1 {
                fallbackRecipes.append(createMainProteinRecipe(safeArrayAccess(mainProteins, index: 1), vegetables: vegetables))
            } else {
                fallbackRecipes.append(createVariationRecipe(mainProtein, vegetables: vegetables))
            }
            print("✅ バリエーションレシピ追加: \(fallbackRecipes.count)")
        }
        
        // 野菜中心のレシピ
        if vegetables.count >= 2 && fallbackRecipes.count < 3 {
            fallbackRecipes.append(createVegetableRecipe(vegetables, hasProtein: !mainProteins.isEmpty))
            print("✅ 野菜レシピ追加: \(fallbackRecipes.count)")
        }
        
        // 3つ未満の場合は基本レシピで補完
        while fallbackRecipes.count < 3 {
            let basicRecipe = createBasicRecipe(index: fallbackRecipes.count)
            fallbackRecipes.append(basicRecipe)
            print("✅ 基本レシピ追加 (\(fallbackRecipes.count)): \(basicRecipe.name)")
        }
        
        print("🎯 最終的に生成されたレシピ数: \(fallbackRecipes.count)")
        return Array(fallbackRecipes.prefix(3)) // 必ず3つまで
    }
    
    private func createMainProteinRecipe(_ protein: Ingredient, vegetables: [Ingredient]) -> BentoRecipe {
        let vegNames = vegetables.prefix(2).map { "\($0.name) 適量" }
        let mainVeg = vegetables.first?.name ?? "人参"
        
        switch protein.name {
        case "鶏肉":
            return BentoRecipe(
                name: "鶏肉と\(mainVeg)の炒め弁当",
                description: "選択した食材で作る鶏肉メイン弁当",
                category: .omakase,
                mainDish: DishItem(
                    name: "鶏肉の醤油炒め",
                    ingredients: ["鶏もも肉 200g", "醤油 大さじ2", "みりん 大さじ1"] + vegNames,
                    instructions: ["鶏肉を一口大に切る", "野菜と一緒に炒める", "よく冷ましてからお弁当箱に詰める"]
                ),
                sideDish1: DishItem(
                    name: "\(mainVeg)の炒め物",
                    ingredients: ["\(mainVeg) 適量", "ごま油 大さじ1", "塩 少々"],
                    instructions: ["食材を切る", "炒めて調味する", "よく冷ましてからお弁当箱に詰める"]
                ),
                sideDish2: DishItem(
                    name: "卵焼き",
                    ingredients: ["卵 2個", "だし汁 大さじ1", "砂糖 小さじ1"],
                    instructions: ["材料を混ぜる", "卵焼き器で焼く", "よく冷ましてからお弁当箱に詰める"]
                ),
                prepTime: 25,
                calories: 480,
                difficulty: .easy,
                tips: ["選択した食材を活用", "味付けは調整可能"]
            )
        case "豚肉":
            return BentoRecipe(
                name: "豚肉の生姜焼き弁当",
                description: "選択した食材で作る豚肉メイン弁当",
                category: .omakase,
                mainDish: DishItem(
                    name: "豚肉の生姜炒め",
                    ingredients: ["豚バラ肉 200g", "生姜 1片", "醤油 大さじ2"] + vegNames,
                    instructions: ["豚肉を炒める", "野菜を加えて炒める", "よく冷ましてからお弁当箱に詰める"]
                ),
                sideDish1: DishItem(
                    name: "\(mainVeg)のきんぴら",
                    ingredients: ["\(mainVeg) 適量", "ごま油 大さじ1", "醤油 大さじ1"],
                    instructions: ["細切りにする", "炒めて調味", "よく冷ましてからお弁当箱に詰める"]
                ),
                sideDish2: DishItem(
                    name: "厚焼き卵",
                    ingredients: ["卵 3個", "だし汁 大さじ2", "砂糖 大さじ1"],
                    instructions: ["材料を混ぜる", "厚焼きに仕上げる", "よく冷ましてからお弁当箱に詰める"]
                ),
                prepTime: 30,
                calories: 520,
                difficulty: .medium,
                tips: ["豚肉は強火で炒める", "野菜は食感を残す"]
            )
        case "鮭", "鯖", "鯵", "鰤":
            return BentoRecipe(
                name: "\(protein.name)の塩焼き弁当",
                description: "選択した魚をメインにしたお弁当",
                category: .fishMain,
                mainDish: DishItem(
                    name: "\(protein.name)の塩焼き",
                    ingredients: ["\(protein.name) 1切れ", "塩 適量", "レモン 1/4個"],
                    instructions: ["魚に塩をふる", "グリルで焼く", "よく冷ましてからお弁当箱に詰める"]
                ),
                sideDish1: DishItem(
                    name: "\(mainVeg)の蒸し物",
                    ingredients: ["\(mainVeg) 適量", "塩 少々"],
                    instructions: ["食材を切る", "蒸す", "よく冷ましてからお弁当箱に詰める"]
                ),
                sideDish2: DishItem(
                    name: "ひじきの煮物",
                    ingredients: ["乾燥ひじき 20g", "人参 1/3本", "だし汁 150ml"],
                    instructions: ["ひじきを戻す", "煮る", "よく冷ましてからお弁当箱に詰める"]
                ),
                prepTime: 25,
                calories: 350,
                difficulty: .easy,
                tips: ["魚は焼きすぎに注意", "野菜で彩りを"]
            )
        default:
            return createBasicRecipe(index: 0)
        }
    }
    
    private func createVariationRecipe(_ protein: Ingredient, vegetables: [Ingredient]) -> BentoRecipe {
        let mainVeg = vegetables.first?.name ?? "キャベツ"
        
        switch protein.name {
        case "鶏肉":
            return BentoRecipe(
                name: "鶏肉の照り焼き弁当",
                description: "照り焼き風味の鶏肉弁当",
                category: .omakase,
                mainDish: DishItem(
                    name: "鶏肉の照り焼き",
                    ingredients: ["鶏もも肉 200g", "醤油 大さじ3", "みりん 大さじ2", "砂糖 大さじ1"],
                    instructions: ["鶏肉を焼く", "調味料で照り焼きに", "よく冷ましてからお弁当箱に詰める"]
                ),
                sideDish1: DishItem(
                    name: "\(mainVeg)の塩炒め",
                    ingredients: ["\(mainVeg) 適量", "塩 少々", "ごま油 小さじ1"],
                    instructions: ["食材を切る", "塩炒めにする", "よく冷ましてからお弁当箱に詰める"]
                ),
                sideDish2: DishItem(
                    name: "いんげんの胡麻和え",
                    ingredients: ["いんげん 100g", "白ごま 大さじ1", "醤油 小さじ2"],
                    instructions: ["いんげんを茹でる", "胡麻で和える", "よく冷ましてからお弁当箱に詰める"]
                ),
                prepTime: 30,
                calories: 450,
                difficulty: .medium,
                tips: ["照り焼きは強火で仕上げる", "野菜は彩りよく"]
            )
        default:
            return createBasicRecipe(index: 1)
        }
    }
    
    private func createVegetableRecipe(_ vegetables: [Ingredient], hasProtein: Bool) -> BentoRecipe {
        let vegNames = vegetables.prefix(4).map { "\($0.name) 適量" }
        let mainVeg = vegetables.first?.name ?? "キャベツ"
        
        return BentoRecipe(
            name: "選択野菜のヘルシー弁当",
            description: "選択した野菜をたっぷり使ったヘルシー弁当",
            category: .omakase,
            mainDish: DishItem(
                name: "野菜炒め",
                ingredients: vegNames + ["ごま油 大さじ1", "醤油 大さじ1"],
                instructions: ["野菜を切る", "順番に炒める", "よく冷ましてからお弁当箱に詰める"]
            ),
            sideDish1: DishItem(
                name: "\(mainVeg)の煮物",
                ingredients: ["\(mainVeg) 適量", "だし汁 100ml", "醤油 大さじ1"],
                instructions: ["食材を切る", "だしで煮る", "よく冷ましてからお弁当箱に詰める"]
            ),
            sideDish2: DishItem(
                name: "きのこのソテー",
                ingredients: ["しめじ 1パック", "オリーブオイル 大さじ1", "塩 少々"],
                instructions: ["きのこを切る", "炒める", "よく冷ましてからお弁当箱に詰める"]
            ),
            prepTime: 20,
            calories: 280,
            difficulty: .easy,
            tips: ["野菜の食感を活かす", "彩りよく"]
        )
    }
    
    private func createBasicRecipe(index: Int) -> BentoRecipe {
        switch index {
        case 0:
            return BentoRecipe(
                name: "基本の照り焼きチキン弁当",
                description: "定番の照り焼きチキン弁当",
                category: .omakase,
                mainDish: DishItem(
                    name: "鶏の照り焼き",
                    ingredients: ["鶏もも肉 200g", "醤油 大さじ2", "みりん 大さじ2"],
                    instructions: ["鶏肉を焼く", "調味料で照り焼きに", "よく冷ましてからお弁当箱に詰める"]
                ),
                sideDish1: DishItem(
                    name: "野菜炒め",
                    ingredients: ["人参 1/2本", "ピーマン 2個", "ごま油 大さじ1"],
                    instructions: ["野菜を切る", "炒める", "よく冷ましてからお弁当箱に詰める"]
                ),
                sideDish2: DishItem(
                    name: "卵焼き",
                    ingredients: ["卵 2個", "砂糖 小さじ1", "だし汁 大さじ1"],
                    instructions: ["材料を混ぜる", "焼く", "よく冷ましてからお弁当箱に詰める"]
                ),
                prepTime: 25,
                calories: 450,
                difficulty: .easy,
                tips: ["基本の調理法", "バランスよく"]
            )
        case 1:
            return BentoRecipe(
                name: "豚の生姜焼き弁当",
                description: "ご飯がすすむ生姜焼き弁当",
                category: .omakase,
                mainDish: DishItem(
                    name: "豚の生姜焼き",
                    ingredients: ["豚ロース 200g", "生姜 2片", "醤油 大さじ2", "みりん 大さじ1"],
                    instructions: ["豚肉を焼く", "生姜だれで味付け", "よく冷ましてからお弁当箱に詰める"]
                ),
                sideDish1: DishItem(
                    name: "キャベツ炒め",
                    ingredients: ["キャベツ 3枚", "塩 少々", "ごま油 小さじ1"],
                    instructions: ["キャベツを切る", "炒める", "よく冷ましてからお弁当箱に詰める"]
                ),
                sideDish2: DishItem(
                    name: "人参のグラッセ",
                    ingredients: ["人参 1本", "バター 大さじ1", "砂糖 小さじ1"],
                    instructions: ["人参を切る", "バターで炒める", "よく冷ましてからお弁当箱に詰める"]
                ),
                prepTime: 30,
                calories: 480,
                difficulty: .medium,
                tips: ["生姜は多めに", "豚肉は火を通しすぎない"]
            )
        default:
            return BentoRecipe(
                name: "鮭の塩焼き弁当",
                description: "シンプルで美味しい鮭弁当",
                category: .fishMain,
                mainDish: DishItem(
                    name: "鮭の塩焼き",
                    ingredients: ["鮭 1切れ", "塩 適量"],
                    instructions: ["鮭に塩をふる", "グリルで焼く", "よく冷ましてからお弁当箱に詰める"]
                ),
                sideDish1: DishItem(
                    name: "ブロッコリーの蒸し物",
                    ingredients: ["ブロッコリー 1/2株", "塩 少々"],
                    instructions: ["ブロッコリーを切る", "蒸す", "よく冷ましてからお弁当箱に詰める"]
                ),
                sideDish2: DishItem(
                    name: "きんぴらごぼう",
                    ingredients: ["ごぼう 1本", "人参 1/2本", "ごま油 大さじ1"],
                    instructions: ["細切りにする", "炒める", "よく冷ましてからお弁当箱に詰める"]
                ),
                prepTime: 25,
                calories: 380,
                difficulty: .easy,
                tips: ["鮭は焼きすぎない", "野菜で彩りを"]
            )
        }
    }
    
    private func updateFavorites() {
        favoriteRecipes = recipes.filter { $0.isFavorite }
    }
    
    // MARK: - Daily Recommendations
    func generateDailyRecommendations() {
        let today = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let todayString = dateFormatter.string(from: today)
        
        // 日付チェックを一時的に無効化（デバッグ用）
        // if let lastUpdateDate = UserDefaults.standard.object(forKey: lastUpdateDateKey) as? Date {
        //     let lastUpdateString = dateFormatter.string(from: lastUpdateDate)
        //     if todayString == lastUpdateString {
        //         return
        //     }
        // }
        
        print("🔄 Generating daily recommendations...")
        print("📊 Total recipes available: \(recipes.count)")
        
        // レシピが空の場合はサンプルデータをロード
        if recipes.isEmpty {
            print("⚠️ No recipes found, loading sample data...")
            loadSampleData()
        }
        
        var recommendations: [BentoRecipe] = []
        
        // サンプルレシピから推薦を生成
        let shuffledRecipes = recipes.shuffled()
        for i in 0..<min(3, shuffledRecipes.count) {
            recommendations.append(shuffledRecipes[i])
            print("✅ Added recommendation: \(shuffledRecipes[i].name)")
        }
        
        // 推薦が0個の場合は最低でも1つ追加
        if recommendations.isEmpty {
            print("⚠️ No recommendations generated, creating fallback...")
            // 緊急時のサンプルレシピを作成
            let fallbackRecipe = BentoRecipe(
                name: "鮭の塩焼き弁当",
                description: "焼き鮭をメインにした和風お弁当",
                category: .fishMain,
                mainDish: DishItem(
                    name: "鮭の塩焼き",
                    ingredients: ["鮭切り身 1切れ", "塩 少々", "レモン 適量"],
                    instructions: ["鮭に塩をふって15分置く", "フライパンで両面を焼く", "レモンを添える", "よく冷ましてからお弁当箱に詰める"]
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
            )
            recommendations.append(fallbackRecipe)
            print("✅ Added fallback recipe: \(fallbackRecipe.name)")
        }
        
        dailyRecommendations = recommendations
        UserDefaults.standard.set(today, forKey: lastUpdateDateKey)
        saveDailyRecommendations()
        
        // UIを強制更新
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
        
        print("📱 Daily recommendations updated: \(recommendations.count) recipes")
    }
    
    func forceUpdateDailyRecommendations() {
        print("🔄 Force updating daily recommendations...")
        UserDefaults.standard.removeObject(forKey: lastUpdateDateKey)
        UserDefaults.standard.removeObject(forKey: dailyRecommendationsKey)
        generateDailyRecommendations()
        print("✅ Force update completed with \(dailyRecommendations.count) recommendations")
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
            print("💾 Weekly plan saved successfully")
        } else {
            print("❌ Failed to encode weekly plan")
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