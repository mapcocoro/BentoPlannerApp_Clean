import Foundation

class PresetRecipeManager {
    static let shared = PresetRecipeManager()

    private var presetMainDishes: [BentoCategory: [PresetMainDish]] = [:]
    private var presetSideDishes: [PresetSideDish] = []

    private init() {
        loadPresetData()
    }

    func loadPresetData() {
        NSLog("🔍 [PresetRecipeManager] Starting to load preset data...")

        // Load main dishes
        guard let mainDishURL = Bundle.main.url(forResource: "PresetMainDishes", withExtension: "json") else {
            NSLog("❌ [PresetRecipeManager] PresetMainDishes.json not found in bundle")
            return
        }

        // Load side dishes
        guard let sideDishURL = Bundle.main.url(forResource: "PresetSideDishes", withExtension: "json") else {
            NSLog("❌ [PresetRecipeManager] PresetSideDishes.json not found in bundle")
            return
        }

        do {
            // Load main dishes
            let mainDishData = try Data(contentsOf: mainDishURL)
            let mainDishDecoder = JSONDecoder()
            let mainDishCategoryData = try mainDishDecoder.decode([String: [PresetMainDish]].self, from: mainDishData)

            presetMainDishes = [
                .omakase: mainDishCategoryData["omakase"] ?? [],
                .hearty: mainDishCategoryData["hearty"] ?? [],
                .fishMain: mainDishCategoryData["fishMain"] ?? [],
                .simple: mainDishCategoryData["simple"] ?? []
            ]

            NSLog("✅ [PresetRecipeManager] Loaded main dishes:")
            for (category, dishes) in presetMainDishes {
                NSLog("   - \(category.rawValue): \(dishes.count) dishes")
            }

            // Load side dishes
            let sideDishData = try Data(contentsOf: sideDishURL)
            let sideDishDecoder = JSONDecoder()
            let sideDishContainer = try sideDishDecoder.decode([String: [PresetSideDish]].self, from: sideDishData)
            presetSideDishes = sideDishContainer["sideDishes"] ?? []

            NSLog("✅ [PresetRecipeManager] Loaded \(presetSideDishes.count) side dishes")

        } catch {
            NSLog("❌ [PresetRecipeManager] Failed to decode preset data: \(error)")
        }
    }

    // 現在の季節を取得
    private func getCurrentSeason() -> String {
        let month = Calendar.current.component(.month, from: Date())
        switch month {
        case 3...5:
            return "春"
        case 6...8:
            return "夏"
        case 9...11:
            return "秋"
        default: // 12, 1, 2
            return "冬"
        }
    }

    // 季節プレフィックスを削除
    private func removeSeasonPrefix(from name: String) -> String {
        let seasonPrefixes = ["春の", "夏の", "秋の", "冬の", "春風香る", "初夏の", "真夏の", "盛夏の", "初秋の", "晩秋の", "初冬の", "真冬の"]
        var cleanedName = name
        for prefix in seasonPrefixes {
            if cleanedName.hasPrefix(prefix) {
                cleanedName = String(cleanedName.dropFirst(prefix.count))
                break
            }
        }
        return cleanedName
    }

    // メインディッシュが現在の季節に適しているかチェック
    private func isMainDishSuitableForCurrentSeason(_ mainDish: PresetMainDish) -> Bool {
        let currentSeason = getCurrentSeason()

        // seasonがnilの場合は常にOK
        guard let season = mainDish.season else {
            return true
        }

        // 現在の季節と一致する場合のみOK
        return season == currentSeason
    }

    // 副菜が現在の季節に適しているかチェック
    private func isSideDishSuitableForCurrentSeason(_ sideDish: PresetSideDish) -> Bool {
        let currentSeason = getCurrentSeason()

        // seasonがnilの場合は常にOK
        guard let season = sideDish.season else {
            return true
        }

        // 現在の季節と一致する場合のみOK
        return season == currentSeason
    }

    // 調理方法が似ているかチェック
    private func areCookingMethodsSimilar(_ method1: String, _ method2: String) -> Bool {
        // 完全一致
        if method1 == method2 {
            return true
        }

        // きんぴらグループ
        let kinpiraGroup = ["きんぴら", "金平"]
        if kinpiraGroup.contains(method1) && kinpiraGroup.contains(method2) {
            return true
        }

        // 煮物グループ
        let nimononGroup = ["煮物", "煮", "煮浸し", "揚げ浸し"]
        if nimononGroup.contains(method1) && nimononGroup.contains(method2) {
            return true
        }

        // 和え物グループ
        let aemonoGroup = ["和え物", "胡麻和え", "おひたし"]
        if aemonoGroup.contains(method1) && aemonoGroup.contains(method2) {
            return true
        }

        // 炒め物グループ
        let itamemonoGroup = ["炒め物", "炒め"]
        if itamemonoGroup.contains(method1) && itamemonoGroup.contains(method2) {
            return true
        }

        return false
    }

    // ランダムなレシピを生成（メイン + 副菜2つの組み合わせ）
    func getRandomRecipe(for category: BentoCategory, excluding: [BentoRecipe] = []) -> BentoRecipe? {
        NSLog("🔍 [PresetRecipeManager] getRandomRecipe called for category: \(category.rawValue)")

        guard let mainDishes = presetMainDishes[category], !mainDishes.isEmpty else {
            NSLog("❌ [PresetRecipeManager] No main dishes available for category: \(category.rawValue)")
            return nil
        }

        guard !presetSideDishes.isEmpty else {
            NSLog("❌ [PresetRecipeManager] No side dishes available")
            return nil
        }

        // 除外するメインディッシュ名を抽出（最近5個のみ）
        let recentExcluding = Array(excluding.suffix(5))
        let excludedMainDishNames = Set(recentExcluding.map { $0.mainDish.name })
        NSLog("🔍 [PresetRecipeManager] Excluding \(excludedMainDishNames.count) main dishes (from last 5 recipes)")

        // 季節フィルタリング + 除外フィルタリング
        let currentSeason = getCurrentSeason()
        let availableMainDishes = mainDishes.filter { mainDish in
            !excludedMainDishNames.contains(mainDish.dish.name) && isMainDishSuitableForCurrentSeason(mainDish)
        }

        NSLog("🔍 [PresetRecipeManager] Current season: \(currentSeason)")
        NSLog("🔍 [PresetRecipeManager] Available main dishes after filtering: \(availableMainDishes.count)")

        guard let selectedMainDish = availableMainDishes.randomElement() else {
            NSLog("⚠️ [PresetRecipeManager] No main dishes available after filtering")
            return nil
        }

        // 季節に合った副菜を選択
        let availableSideDishes = presetSideDishes.filter { isSideDishSuitableForCurrentSeason($0) }
        NSLog("🔍 [PresetRecipeManager] Available side dishes for season: \(availableSideDishes.count)")

        // 副菜1を選択
        guard let sideDish1 = availableSideDishes.randomElement() else {
            NSLog("⚠️ [PresetRecipeManager] No side dishes available")
            return nil
        }

        // 副菜2を選択（副菜1と調理方法が異ならないようにする）
        let availableSideDishes2 = availableSideDishes.filter { sideDish in
            !areCookingMethodsSimilar(sideDish.cookingMethod, sideDish1.cookingMethod)
        }

        NSLog("🔍 [PresetRecipeManager] Available side dishes 2 (different cooking method): \(availableSideDishes2.count)")

        guard let sideDish2 = availableSideDishes2.randomElement() else {
            NSLog("⚠️ [PresetRecipeManager] No second side dish with different cooking method available, using any")
            // フォールバック: 同じ調理方法でも許可
            guard let fallbackSideDish = availableSideDishes.filter({ $0.name != sideDish1.name }).randomElement() else {
                NSLog("❌ [PresetRecipeManager] Failed to find any second side dish")
                return nil
            }
            return combineIntoRecipe(mainDish: selectedMainDish, sideDish1: sideDish1, sideDish2: fallbackSideDish, category: category)
        }

        // レシピを組み合わせる
        let recipe = combineIntoRecipe(mainDish: selectedMainDish, sideDish1: sideDish1, sideDish2: sideDish2, category: category)

        NSLog("✅ [PresetRecipeManager] Selected recipe: \(recipe.name)")
        NSLog("   - Main: \(selectedMainDish.name)")
        NSLog("   - Side 1: \(sideDish1.name) (\(sideDish1.cookingMethod))")
        NSLog("   - Side 2: \(sideDish2.name) (\(sideDish2.cookingMethod))")

        return recipe
    }

    // メインディッシュと副菜を組み合わせてBentoRecipeを作成
    private func combineIntoRecipe(mainDish: PresetMainDish, sideDish1: PresetSideDish, sideDish2: PresetSideDish, category: BentoCategory) -> BentoRecipe {
        // レシピ名は基本的にメインディッシュ名
        let recipeName = mainDish.name

        // 合計調理時間と カロリーを計算
        let totalPrepTime = mainDish.prepTime + sideDish1.prepTime + sideDish2.prepTime
        let totalCalories = mainDish.calories + sideDish1.calories + sideDish2.calories

        // BentoRecipeを作成
        return BentoRecipe(
            name: recipeName,
            description: mainDish.description,
            category: category,
            mainDish: mainDish.dish,
            sideDish1: sideDish1.dish,
            sideDish2: sideDish2.dish,
            prepTime: totalPrepTime,
            calories: totalCalories,
            difficulty: mainDish.difficulty,
            tips: []  // 組み合わせレシピにはtipsは不要
        )
    }

    func getAllMainDishes(for category: BentoCategory) -> [PresetMainDish] {
        return presetMainDishes[category] ?? []
    }

    func getAllSideDishes() -> [PresetSideDish] {
        return presetSideDishes
    }
}
