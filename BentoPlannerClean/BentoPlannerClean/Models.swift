import Foundation
import SwiftUI

// MARK: - Bento Category Enum
enum BentoCategory: String, CaseIterable, Identifiable, Codable {
    case omakase = "おまかせ"
    case hearty = "がっつり"
    case fishMain = "お魚弁当"
    case simple = "簡単弁当"
    
    var id: String { rawValue }
    
    var emoji: String {
        switch self {
        case .omakase: return "🍴"
        case .hearty: return "🍖"
        case .fishMain: return "🐟"
        case .simple: return "⚡"
        }
    }
    
    var color: Color {
        switch self {
        case .omakase: return .green
        case .hearty: return .red
        case .fishMain: return .blue
        case .simple: return .purple
        }
    }
    
    var description: String {
        switch self {
        case .omakase: return "バランス重視の万能お弁当"
        case .hearty: return "ボリューム満点・満足感たっぷり"
        case .fishMain: return "魚をメインにした和風弁当"
        case .simple: return "時短・簡単に作れるお弁当"
        }
    }
}

// MARK: - Dish Item
struct DishItem: Identifiable, Codable {
    let id = UUID()
    let name: String
    let ingredients: [String]
    let instructions: [String]

    enum CodingKeys: String, CodingKey {
        case name, ingredients, instructions
    }
}

// MARK: - Bento Recipe
struct BentoRecipe: Identifiable, Codable {
    let id = UUID()
    let name: String
    let description: String
    let category: BentoCategory
    let mainDish: DishItem
    let sideDish1: DishItem
    let sideDish2: DishItem
    let prepTime: Int // minutes
    let calories: Int
    let difficulty: Difficulty
    let tips: [String]
    var isFavorite: Bool = false
    
    enum Difficulty: String, CaseIterable, Codable {
        case easy = "簡単"
        case medium = "普通"
        case hard = "上級"
    }
    
    // 全ての材料を統合
    var allIngredients: [String] {
        return mainDish.ingredients + sideDish1.ingredients + sideDish2.ingredients
    }
    
    // 全ての手順を統合
    var allInstructions: [String] {
        var instructions: [String] = []
        instructions.append("【\(mainDish.name)】")
        instructions.append(contentsOf: mainDish.instructions)
        instructions.append("【\(sideDish1.name)】")
        instructions.append(contentsOf: sideDish1.instructions)
        instructions.append("【\(sideDish2.name)】")
        instructions.append(contentsOf: sideDish2.instructions)
        return instructions
    }
}

// MARK: - Weekly Plan
struct WeeklyPlan: Codable {
    var weekOf: Date
    var monday: BentoRecipe?
    var tuesday: BentoRecipe?
    var wednesday: BentoRecipe?
    var thursday: BentoRecipe?
    var friday: BentoRecipe?
    var saturday: BentoRecipe?
    var sunday: BentoRecipe?
    
    init(weekOf: Date) {
        self.weekOf = weekOf
    }
    
    var dayRecipes: [String: BentoRecipe?] {
        return [
            "月": monday,
            "火": tuesday,
            "水": wednesday,
            "木": thursday,
            "金": friday,
            "土": saturday,
            "日": sunday
        ]
    }
}

// MARK: - Ingredient Models
enum IngredientCategory: String, CaseIterable, Identifiable {
    case mainProtein = "主材料"
    case vegetables = "野菜"
    case seasonings = "その他の材料・調味料"
    
    var id: String { rawValue }
}

struct Ingredient: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let category: IngredientCategory
    let emoji: String
}

// MARK: - Preset Main Dish (for combination system)
struct PresetMainDish: Identifiable, Codable {
    let id = UUID()
    let name: String
    let description: String
    let dish: DishItem
    let prepTime: Int // minutes
    let calories: Int // approximate calories for main dish only
    let difficulty: BentoRecipe.Difficulty
    let season: String? // "春", "夏", "秋", "冬", or nil for all seasons

    enum CodingKeys: String, CodingKey {
        case name, description, dish, prepTime, calories, difficulty, season
    }
}

// MARK: - Preset Side Dish (for combination system)
struct PresetSideDish: Identifiable, Codable {
    let id = UUID()
    let name: String
    let dish: DishItem
    let prepTime: Int // minutes
    let calories: Int // approximate calories
    let cookingMethod: String // "きんぴら", "煮物", "和え物", etc.
    let season: String? // "春", "夏", "秋", "冬", or nil for all seasons
}

// MARK: - Predefined Ingredients
extension Ingredient {
    static let allIngredients: [Ingredient] = [
        // 主材料
        Ingredient(name: "豚肉", category: .mainProtein, emoji: "🐷"),
        Ingredient(name: "鶏肉", category: .mainProtein, emoji: "🐔"),
        Ingredient(name: "牛肉", category: .mainProtein, emoji: "🐄"),
        Ingredient(name: "鮭", category: .mainProtein, emoji: "🐟"),
        Ingredient(name: "卵", category: .mainProtein, emoji: "🥚"),
        Ingredient(name: "鯖", category: .mainProtein, emoji: "🐟"),

        // 野菜
        Ingredient(name: "キャベツ", category: .vegetables, emoji: "🥬"),
        Ingredient(name: "玉ねぎ", category: .vegetables, emoji: "🧅"),
        Ingredient(name: "人参", category: .vegetables, emoji: "🥕"),
        Ingredient(name: "ピーマン", category: .vegetables, emoji: "🫑"),
        Ingredient(name: "じゃがいも", category: .vegetables, emoji: "🥔"),
        Ingredient(name: "ブロッコリー", category: .vegetables, emoji: "🥦"),
        Ingredient(name: "きのこ類", category: .vegetables, emoji: "🍄"),
        Ingredient(name: "なす", category: .vegetables, emoji: "🍆"),
        Ingredient(name: "かぼちゃ", category: .vegetables, emoji: "🎃"),

        // その他の材料・調味料
        Ingredient(name: "ごま油", category: .seasonings, emoji: "🫒"),
        Ingredient(name: "醤油", category: .seasonings, emoji: "🥢"),
        Ingredient(name: "みりん", category: .seasonings, emoji: "🍶"),
        Ingredient(name: "だしの素", category: .seasonings, emoji: "🥢"),
        Ingredient(name: "味噌", category: .seasonings, emoji: "🥢"),
        Ingredient(name: "オリーブオイル", category: .seasonings, emoji: "🫒"),
        Ingredient(name: "バター", category: .seasonings, emoji: "🧈"),
        Ingredient(name: "冷凍食品", category: .seasonings, emoji: "🧊"),
        Ingredient(name: "缶詰", category: .seasonings, emoji: "🥫")
    ]

    static func ingredientsByCategory(_ category: IngredientCategory) -> [Ingredient] {
        return allIngredients.filter { $0.category == category }
    }
}