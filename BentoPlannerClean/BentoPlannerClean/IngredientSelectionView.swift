import SwiftUI

struct IngredientSelectionView: View {
    @EnvironmentObject var bentoStore: BentoStore
    @State private var selectedIngredients: Set<Ingredient> = []
    @State private var additionalNotes: String = ""
    @State private var showingResults = false
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 24) {
                    // ヘッダーセクション
                    headerSection
                    
                    // 食材選択セクション（その他の調味料は除外）
                    ForEach(IngredientCategory.allCases.filter { $0 != .seasonings }) { category in
                        ingredientCategorySection(category)
                    }
                    
                    // 追加メモセクション
                    additionalNotesSection
                    
                    // 生成ボタン
                    generateButton
                    
                    // 結果表示セクション
                    if !bentoStore.ingredientBasedRecipes.isEmpty {
                        resultsSection
                            .id("resultsSection")
                    }
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack {
                        Image(systemName: "refrigerator")
                            .font(.system(size: 18, weight: .medium))
                        Text("食材から検索")
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                    }
                }
            }
            .onChange(of: bentoStore.ingredientBasedRecipes.count) { newCount in
                if newCount > 0 && !bentoStore.isLoading {
                    withAnimation(.easeInOut(duration: 0.8)) {
                        proxy.scrollTo("resultsSection", anchor: .top)
                    }
                }
            }
        }
    }
    
    var headerSection: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text("冷蔵庫の食材でお弁当レシピ！")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundColor(.primary)
                
                Text("お持ちの食材を選ぶと、お弁当にぴったりのレシピを3つの献立で提案します。\n主材料は1つ以上選んでください。")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top)
    }
    
    func ingredientCategorySection(_ category: IngredientCategory) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(category.rawValue)
                    .font(.headline)
                    .fontWeight(.bold)
                
                if category == .mainProtein {
                    Text("(1つ以上選択)")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                
                Spacer()
            }
            
            let ingredients = Ingredient.ingredientsByCategory(category)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(ingredients, id: \.id) { ingredient in
                    IngredientButton(
                        ingredient: ingredient,
                        isSelected: selectedIngredients.contains(ingredient)
                    ) {
                        toggleIngredient(ingredient)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }
    
    var additionalNotesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("その他の材料・調味料 (任意)")
                .font(.headline)
                .fontWeight(.bold)
            
            Text("例: ごま油、醤油、みりん、だしの素、冷蔵庫に残っている半端な野菜など")
                .font(.caption)
                .foregroundColor(.secondary)
            
            TextEditor(text: $additionalNotes)
                .frame(height: 80)
                .padding(8)
                .background(Color(.systemGray6))
                .cornerRadius(8)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }
    
    var generateButton: some View {
        Button(action: {
            Task {
                await bentoStore.generateRecipesFromIngredients(Array(selectedIngredients), additionalNotes: additionalNotes)
            }
        }) {
            HStack {
                if bentoStore.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "sparkles")
                }
                
                Text(bentoStore.isLoading ? "レシピ生成中..." : "お弁当レシピを提案してもらう")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(canGenerate ? Color.pink : Color.gray)
            )
            .foregroundColor(.white)
        }
        .disabled(!canGenerate || bentoStore.isLoading)
    }
    
    var resultsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("提案されたレシピ")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                // レシピ数を表示（デバッグ用）
                Text("\(bentoStore.ingredientBasedRecipes.count)品")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(6)
            }
            
            if bentoStore.ingredientBasedRecipes.isEmpty {
                Text("レシピが生成されていません")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(bentoStore.ingredientBasedRecipes) { recipe in
                        NavigationLink(destination: RecipeDetailView(recipe: recipe)) {
                            IngredientRecipeCard(recipe: recipe)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            
            // エラーメッセージがある場合表示
            if let errorMessage = bentoStore.errorMessage {
                Text("エラー: \(errorMessage)")
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
            }
        }
        .padding(.top)
    }
    
    private var canGenerate: Bool {
        let hasMainProtein = selectedIngredients.contains { $0.category == .mainProtein }
        return hasMainProtein
    }
    
    private func toggleIngredient(_ ingredient: Ingredient) {
        if selectedIngredients.contains(ingredient) {
            selectedIngredients.remove(ingredient)
        } else {
            selectedIngredients.insert(ingredient)
        }
    }
}

struct IngredientButton: View {
    let ingredient: Ingredient
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(ingredient.emoji)
                    .font(.title2)
                
                Text(ingredient.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 70)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.pink.opacity(0.2) : Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSelected ? Color.pink : Color.gray.opacity(0.3), lineWidth: isSelected ? 2 : 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct IngredientRecipeCard: View {
    let recipe: BentoRecipe
    @EnvironmentObject var bentoStore: BentoStore
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // ヘッダー
            HStack {
                Text("🍱")
                    .font(.title)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(recipe.name)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    
                    Text(recipe.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                // お気に入りボタン
                Button(action: {
                    bentoStore.toggleFavorite(recipe)
                }) {
                    let isFavorite = bentoStore.isRecipeFavorite(recipe)
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.title2)
                        .foregroundColor(isFavorite ? .red : .gray)
                }
            }
            
            // メタ情報
            HStack(spacing: 16) {
                Label("\(recipe.prepTime)分", systemImage: "clock")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Label("\(recipe.calories)kcal", systemImage: "flame")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Label(recipe.difficulty.rawValue, systemImage: "star")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
                .shadow(color: .gray.opacity(0.2), radius: 4, x: 0, y: 2)
        )
    }
}

#Preview {
    NavigationView {
        IngredientSelectionView()
            .environmentObject(BentoStore())
    }
}