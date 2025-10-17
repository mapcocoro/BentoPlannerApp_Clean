import SwiftUI

struct ContentView: View {
    @EnvironmentObject var bentoStore: BentoStore

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView {
                NavigationView {
                    HomeView()
                }
                .tabItem {
                    Image(systemName: "house.fill")
                    Text("ホーム")
                }

                NavigationView {
                    WeeklyPlanView()
                }
                .tabItem {
                    Image(systemName: "calendar")
                    Text("週間プラン")
                }

                NavigationView {
                    FavoritesView()
                }
                .tabItem {
                    Image(systemName: "heart.fill")
                    Text("お気に入り")
                }
            }
            .accentColor(.orange)

            // AdMob Banner Ad (テスト用ID)
            VStack(spacing: 0) {
                Spacer()
                AdMobBannerView(adUnitID: "ca-app-pub-3940256099942544/2934735716")
                    .frame(width: UIScreen.main.bounds.width, height: 50)
                    .background(Color.gray.opacity(0.3))
                    .overlay(
                        Rectangle()
                            .stroke(Color.red, lineWidth: 2)
                    )
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .onAppear {
            print("📱 ContentView appeared - バナー広告の初期化")
        }
    }
}

struct HomeView: View {
    @EnvironmentObject var bentoStore: BentoStore
    @State private var selectedCategory: BentoCategory? = nil
    
    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // ヘッダーセクション
                headerSection
                
                // カテゴリ選択
                categorySection
                
                // 本日のおすすめ
                if !bentoStore.recipes.isEmpty {
                    recommendationsSection
                }
            }
            .padding()
        }
        .navigationTitle("🍱 Bento Planner")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $selectedCategory) { category in
            NavigationView {
                RecipeGenerationView(category: category)
            }
        }
    }
    
    var headerSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "takeoutbag.and.cup.and.straw.fill")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            
            VStack(spacing: 8) {
                Text("毎日のお弁当作りをサポート")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text("カテゴリを選んでAIにレシピを提案してもらいましょう")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top)
    }
    
    var categorySection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("カテゴリから選ぶ")
                .font(.title2)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                ForEach(BentoCategory.allCases) { category in
                    CategoryCard(category: category) {
                        selectedCategory = category
                    }
                }
            }
        }
    }
    
    var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("サンプルレシピ")
                .font(.title2)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(bentoStore.recipes.prefix(5)) { recipe in
                        RecommendationCard(recipe: recipe)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct CategoryCard: View {
    let category: BentoCategory
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Text(category.emoji)
                    .font(.system(size: 40))
                    .frame(width: 60, height: 60)
                    .background(
                        Circle()
                            .fill(category.color.opacity(0.15))
                    )
                
                VStack(spacing: 4) {
                    Text(category.rawValue)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text(category.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 140)
            .padding(.vertical, 16)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white)
                    .shadow(color: category.color.opacity(0.15), radius: 6, x: 0, y: 3)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct RecommendationCard: View {
    let recipe: BentoRecipe
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(recipe.category.emoji)
                .font(.title2)
            
            Text(recipe.name)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(2)
            
            Text(recipe.description)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
            
            HStack {
                Label("\(recipe.prepTime)分", systemImage: "clock")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Label("\(recipe.calories)kcal", systemImage: "flame")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 150, height: 120)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
                .shadow(color: .gray.opacity(0.2), radius: 4, x: 0, y: 2)
        )
    }
}

// MARK: - Other Views (Placeholder)
struct WeeklyPlanView: View {
    var body: some View {
        VStack {
            Text("週間プラン")
                .font(.title)
                .padding()
            
            Text("週間のお弁当プランを管理します")
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .navigationTitle("📅 週間プラン")
    }
}

struct FavoritesView: View {
    @EnvironmentObject var bentoStore: BentoStore
    
    var body: some View {
        VStack {
            if bentoStore.favoriteRecipes.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "heart")
                        .font(.system(size: 60))
                        .foregroundColor(.gray.opacity(0.5))
                    
                    Text("お気に入りがありません")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.gray)
                    
                    Text("気に入ったレシピをハートマークでお気に入りに追加しましょう")
                        .font(.body)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else {
                List(bentoStore.favoriteRecipes) { recipe in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(recipe.category.emoji)
                            Text(recipe.name)
                                .font(.headline)
                            Spacer()
                            Image(systemName: "heart.fill")
                                .foregroundColor(.red)
                        }
                        
                        Text(recipe.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("⭐ お気に入り")
    }
}

#Preview {
    ContentView()
        .environmentObject(BentoStore())
}