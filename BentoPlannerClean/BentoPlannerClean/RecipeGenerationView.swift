import SwiftUI

struct RecipeGenerationView: View {
    let category: BentoCategory
    @EnvironmentObject var bentoStore: BentoStore
    @Environment(\.dismiss) var dismiss
    @State private var selectedRecipe: BentoRecipe?
    @State private var currentTip: String = CookingTips.randomTip()
    @State private var timer: Timer?

    // 献立名の表示ロジック
    var navigationTitle: String {
        // おまかせカテゴリーはそのまま表示
        if category == .omakase {
            return category.rawValue
        }

        // レシピが生成されている場合は最初のレシピ名を表示
        if let recipes = bentoStore.aiGeneratedRecipes[category],
           let firstRecipe = recipes.first,
           !bentoStore.isLoading {
            return firstRecipe.name
        }

        // それ以外はカテゴリー名を表示
        return category.rawValue
    }

    var body: some View {
        VStack(spacing: 20) {
            // ヘッダー
            VStack(spacing: 12) {
                Text("\(category.emoji)")
                    .font(.system(size: 60))
                
                Text(category.rawValue)
                    .font(.title)
                    .fontWeight(.bold)
                
                Text(category.description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding()
            
            // コンテンツ
            if bentoStore.isLoading {
                loadingView
            } else if bentoStore.aiGeneratedRecipes[category]?.isEmpty ?? true {
                emptyStateView
            } else {
                recipesListView
            }
            
            Spacer()
            
            // 生成ボタン
            generateButton
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("閉じる") {
                    dismiss()
                }
            }
        }
        .onAppear {
            // 初回表示時に自動生成
            if bentoStore.aiGeneratedRecipes[category]?.isEmpty ?? true {
                Task {
                    await bentoStore.generateAIRecipes(for: category)
                }
            }
        }
        .sheet(item: $selectedRecipe) { recipe in
            NavigationView {
                RecipeDetailView(recipe: recipe)
            }
        }
    }
    
    var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)

            Text("レシピを生成中...")
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)

            // 豆知識表示
            VStack(spacing: 12) {
                Text("💡 お料理豆知識")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(.orange)

                Text(currentTip)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .lineLimit(3)
                    .transition(.opacity)
                    .id(currentTip) // アニメーション用
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.orange.opacity(0.1))
            )
            .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            startTipRotation()
        }
        .onDisappear {
            stopTipRotation()
        }
    }
    
    var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            
            Text("レシピを生成しましょう")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("下のボタンをタップして\nAIにレシピを提案してもらいましょう")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    var recipesListView: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(bentoStore.aiGeneratedRecipes[category] ?? []) { recipe in
                    RecipeCard(recipe: recipe) {
                        selectedRecipe = recipe
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    
    var generateButton: some View {
        Button(action: {
            // アクション内で直接チェック
            guard !bentoStore.isLoading else {
                NSLog("⚠️ [Button Action] Button disabled, isLoading is true")
                return
            }

            NSLog("🔘 [Button Action] Generate button tapped for category: \(category.rawValue)")

            // Taskを作成（メインアクターで実行）
            Task { @MainActor in
                await bentoStore.generateAIRecipes(for: category)
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

                Text(bentoStore.isLoading ? "生成中..." : "新しいレシピを生成")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(bentoStore.isLoading ? Color.orange.opacity(0.8) : Color.orange)
            )
            .foregroundColor(.white)
        }
        .disabled(bentoStore.isLoading)
        .padding(.horizontal)
    }

    // 豆知識ローテーション
    func startTipRotation() {
        currentTip = CookingTips.randomTip()
        timer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.5)) {
                currentTip = CookingTips.randomTip()
            }
        }
    }

    func stopTipRotation() {
        timer?.invalidate()
        timer = nil
    }
}

struct RecipeCard: View {
    let recipe: BentoRecipe
    @EnvironmentObject var bentoStore: BentoStore
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                // ヘッダー
                HStack {
                    Text(recipe.category.emoji)
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
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    NavigationView {
        RecipeGenerationView(category: .fishMain)
            .environmentObject(BentoStore())
    }
}