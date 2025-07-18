import SwiftUI

struct RecipeSelectionView: View {
    @EnvironmentObject var bentoStore: BentoStore
    @Environment(\.dismiss) var dismiss
    let selectedDay: String
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // ヘッダーセクション
                    headerSection
                    
                    // お気に入りレシピセクション（優先表示）
                    if !bentoStore.favoriteRecipes.isEmpty {
                        favoriteRecipesSection
                    }
                    
                    // カテゴリ別レシピ
                    ForEach(BentoCategory.allCases) { category in
                        categorySection(category)
                    }
                    
                    // 食材ベースレシピ
                    if !bentoStore.ingredientBasedRecipes.isEmpty {
                        ingredientBasedSection
                    }
                    
                    Spacer(minLength: 50)
                }
                .padding()
            }
            .navigationTitle("\(selectedDay)曜日のレシピ選択")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("キャンセル") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    var headerSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            
            VStack(spacing: 8) {
                Text("\(selectedDay)曜日のレシピを選択")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text("お気に入りのレシピを週間プランに追加しましょう")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top)
    }
    
    func categorySection(_ category: BentoCategory) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(category.emoji)
                    .font(.title2)
                
                Text(category.rawValue)
                    .font(.headline)
                    .fontWeight(.bold)
                
                Spacer()
            }
            
            let categoryRecipes = getAllRecipesForCategory(category)
            
            if categoryRecipes.isEmpty {
                EmptyRecipeCard(category: category)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(categoryRecipes) { recipe in
                        SelectableRecipeCard(recipe: recipe) {
                            bentoStore.addRecipeToWeeklyPlan(recipe, day: selectedDay)
                            dismiss()
                        }
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(category.color.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(category.color.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    var favoriteRecipesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("❤️")
                    .font(.title2)
                
                Text("お気に入りレシピ")
                    .font(.headline)
                    .fontWeight(.bold)
                
                Spacer()
            }
            
            LazyVStack(spacing: 12) {
                ForEach(bentoStore.favoriteRecipes) { recipe in
                    SelectableRecipeCard(recipe: recipe) {
                        bentoStore.addRecipeToWeeklyPlan(recipe, day: selectedDay)
                        dismiss()
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.red.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.red.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    var ingredientBasedSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("🍱")
                    .font(.title2)
                
                Text("食材から作ったレシピ")
                    .font(.headline)
                    .fontWeight(.bold)
                
                Spacer()
            }
            
            LazyVStack(spacing: 12) {
                ForEach(bentoStore.ingredientBasedRecipes) { recipe in
                    SelectableRecipeCard(recipe: recipe) {
                        bentoStore.addRecipeToWeeklyPlan(recipe, day: selectedDay)
                        dismiss()
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.pink.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.pink.opacity(0.2), lineWidth: 1)
                )
        )
    }
    
    private func getAllRecipesForCategory(_ category: BentoCategory) -> [BentoRecipe] {
        var allRecipes: [BentoRecipe] = []
        
        // メインレシピから該当カテゴリを取得
        allRecipes.append(contentsOf: bentoStore.recipes.filter { $0.category == category })
        
        // AI生成レシピから該当カテゴリを取得
        if let aiRecipes = bentoStore.aiGeneratedRecipes[category] {
            allRecipes.append(contentsOf: aiRecipes)
        }
        
        // お気に入りレシピから該当カテゴリを取得
        allRecipes.append(contentsOf: bentoStore.favoriteRecipes.filter { $0.category == category })
        
        // 重複を除去
        return Array(Set(allRecipes.map { $0.id })).compactMap { id in
            allRecipes.first { $0.id == id }
        }
    }
}

struct SelectableRecipeCard: View {
    let recipe: BentoRecipe
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                // レシピ情報
                VStack(alignment: .leading, spacing: 4) {
                    Text(recipe.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    
                    Text(recipe.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                    
                    HStack(spacing: 12) {
                        Label("\(recipe.prepTime)分", systemImage: "clock")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Label("\(recipe.calories)kcal", systemImage: "flame")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Label(recipe.difficulty.rawValue, systemImage: "star")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // 選択ボタン
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                    .shadow(color: .gray.opacity(0.2), radius: 4, x: 0, y: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct EmptyRecipeCard: View {
    let category: BentoCategory
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.dashed")
                .font(.title2)
                .foregroundColor(.gray)
            
            Text("まだレシピがありません")
                .font(.subheadline)
                .foregroundColor(.gray)
            
            Text("「\(category.rawValue)」カテゴリでレシピを生成してから追加してください")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [5]))
        )
    }
}

#Preview {
    RecipeSelectionView(selectedDay: "月")
        .environmentObject(BentoStore())
}