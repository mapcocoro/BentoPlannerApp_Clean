import Foundation
import SwiftUI

// MARK: - Bento Category Enum
enum BentoCategory: String, CaseIterable, Identifiable, Codable {
    case omakase = "おまかせ"
    case healthy = "ヘルシー"
    case hearty = "がっつり"
    case vegetableRich = "野菜多め"
    case fishMain = "お魚弁当"
    case simple = "簡単弁当"
    
    var id: String { rawValue }
    
    var emoji: String {
        switch self {
        case .omakase: return "🍴"
        case .healthy: return "🥗"
        case .hearty: return "🍖"
        case .vegetableRich: return "🥕"
        case .fishMain: return "🐟"
        case .simple: return "⚡"
        }
    }
    
    var color: Color {
        switch self {
        case .omakase: return .green
        case .healthy: return .mint
        case .hearty: return .red
        case .vegetableRich: return .orange
        case .fishMain: return .blue
        case .simple: return .purple
        }
    }
    
    var description: String {
        switch self {
        case .omakase: return "バランス重視の万能お弁当"
        case .healthy: return "カロリー控えめ・栄養満点"
        case .hearty: return "ボリューム満点・満足感たっぷり"
        case .vegetableRich: return "野菜中心のヘルシー弁当"
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
    
    init(weekOf: Date) {
        self.weekOf = weekOf
    }
    
    var dayRecipes: [String: BentoRecipe?] {
        return [
            "月": monday,
            "火": tuesday,
            "水": wednesday,
            "木": thursday,
            "金": friday
        ]
    }
}