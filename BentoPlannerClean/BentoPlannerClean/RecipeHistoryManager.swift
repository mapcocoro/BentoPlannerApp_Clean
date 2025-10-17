import Foundation

class RecipeHistoryManager {
    private let userDefaults = UserDefaults.standard
    private let historyKeyPrefix = "RecipeHistory_"
    private let maxHistoryPerCategory = 30  // 履歴を30個に制限（プリセットJSONは50個なので30個で十分）

    struct HistoryItem: Codable {
        let recipe: BentoRecipe
        let timestamp: Date
        let mainDishName: String
        let sideDish1Name: String
        let sideDish2Name: String
        let cookingMethod: String
        let mainIngredient: String
    }

    func addToHistory(_ recipe: BentoRecipe, category: BentoCategory) {
        let key = historyKeyPrefix + category.rawValue
        var history = getHistory(for: category)

        let historyItem = HistoryItem(
            recipe: recipe,
            timestamp: Date(),
            mainDishName: recipe.mainDish.name,
            sideDish1Name: recipe.sideDish1.name,
            sideDish2Name: recipe.sideDish2.name,
            cookingMethod: extractCookingMethod(from: recipe.mainDish.name),
            mainIngredient: extractMainIngredient(from: recipe.mainDish)
        )

        history.insert(historyItem, at: 0)

        if history.count > maxHistoryPerCategory {
            history = Array(history.prefix(maxHistoryPerCategory))
        }

        if let encoded = try? JSONEncoder().encode(history) {
            userDefaults.set(encoded, forKey: key)
        }
    }

    func getRecentRecipes(for category: BentoCategory, limit: Int = 30) -> [BentoRecipe] {
        let history = getHistory(for: category)
        let result = Array(history.prefix(limit)).map { $0.recipe }
        NSLog("📊 [RecipeHistory] Returning \(result.count) recipes for category \(category.rawValue) (requested limit: \(limit), total history: \(history.count))")
        return result
    }

    func getRecentMainDishes(for category: BentoCategory, limit: Int = 50) -> [String] {
        let history = getHistory(for: category)
        return Array(history.prefix(limit)).map { $0.mainDishName }
    }

    func getRecentSideDishes(for category: BentoCategory, limit: Int = 50) -> [String] {
        let history = getHistory(for: category)
        var sideDishes: [String] = []
        for item in history.prefix(limit) {
            sideDishes.append(item.sideDish1Name)
            sideDishes.append(item.sideDish2Name)
        }
        return Array(Set(sideDishes))
    }

    func getRecentCookingMethods(for category: BentoCategory, limit: Int = 20) -> [String] {
        let history = getHistory(for: category)
        let methods = Array(history.prefix(limit)).map { $0.cookingMethod }
        return Array(Set(methods))
    }

    func getRecentMainIngredients(for category: BentoCategory, limit: Int = 20) -> [String] {
        let history = getHistory(for: category)
        let ingredients = Array(history.prefix(limit)).map { $0.mainIngredient }
        return Array(Set(ingredients))
    }

    func clearHistory(for category: BentoCategory) {
        let key = historyKeyPrefix + category.rawValue
        userDefaults.removeObject(forKey: key)
    }

    func clearAllHistory() {
        for category in BentoCategory.allCases {
            clearHistory(for: category)
        }
    }

    private func getHistory(for category: BentoCategory) -> [HistoryItem] {
        let key = historyKeyPrefix + category.rawValue
        guard let data = userDefaults.data(forKey: key),
              let history = try? JSONDecoder().decode([HistoryItem].self, from: data) else {
            return []
        }
        return history
    }

    private func extractCookingMethod(from dishName: String) -> String {
        let methods = ["焼き", "炒め", "煮", "揚げ", "蒸し", "グリル", "ソテー", "フライ", "天ぷら", "唐揚げ", "照り焼き", "塩焼き", "味噌煮", "甘辛", "マリネ", "ムニエル"]

        for method in methods {
            if dishName.contains(method) {
                return method
            }
        }
        return "その他"
    }

    private func extractMainIngredient(from dish: DishItem) -> String {
        let proteins = ["鶏", "豚", "牛", "鮭", "鯖", "鱈", "鰤", "ぶり", "ブリ", "鯵", "あじ", "アジ", "いわし", "さんま", "かじき", "鯛", "たら", "タラ"]

        for protein in proteins {
            if dish.name.contains(protein) || dish.ingredients.joined(separator: " ").contains(protein) {
                return protein
            }
        }
        return "その他"
    }
}