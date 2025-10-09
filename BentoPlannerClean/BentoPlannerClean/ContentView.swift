//
//  ContentView.swift
//  BentoPlannerClean
//
//  Created by ru na on 2025/07/01.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var bentoStore: BentoStore
    
    var body: some View {
        TabView {
            NavigationView {
                HomeView()
            }
            .tabItem {
                Image(systemName: "house.fill")
                Text("ホーム")
            }
            
            NavigationView {
                IngredientSelectionView()
            }
            .tabItem {
                Image(systemName: "refrigerator")
                Text("食材から検索")
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
    }
}

struct HomeView: View {
    @EnvironmentObject var bentoStore: BentoStore
    @State private var selectedCategory: BentoCategory? = nil
    @State private var selectedRecommendation: BentoRecipe? = nil
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // ヘッダーセクション
                headerSection
                
                // カテゴリ選択
                categorySection
                
                // 本日のおすすめ
                recommendationsSection
                
                // お弁当を安全に楽しむために
                safetyGuidelinesSection
                
                Spacer(minLength: 80)
            }
            .padding(.horizontal)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack {
                    Image("bento_planner_logo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                    
                    Text("Bento Planner")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.orange, .pink],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
            }
        }
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $selectedCategory) { category in
            NavigationView {
                RecipeGenerationView(category: category)
            }
        }
        .sheet(item: $selectedRecommendation) { recipe in
            NavigationView {
                RecipeDetailView(recipe: recipe)
            }
        }
        .onAppear {
            bentoStore.forceUpdateDailyRecommendations()
        }
    }
    
    var headerSection: some View {
        VStack(spacing: 6) {
            Text("毎日のお弁当作りをサポート")
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .foregroundColor(.primary)
            
            Text("カテゴリを選んでレシピを提案してもらいましょう")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 8)
    }
    
    var categorySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("カテゴリから選ぶ")
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
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
            Text("本日のおすすめ")
                .font(.system(size: 18, weight: .medium, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)
            
            if dailyRecommendedRecipes.isEmpty {
                // 空の場合の表示
                VStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 30))
                        .foregroundColor(.gray.opacity(0.5))
                    
                    Text("本日のおすすめを生成中...")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.gray)
                    
                    Button("更新") {
                        bentoStore.forceUpdateDailyRecommendations()
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.1))
                )
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(dailyRecommendedRecipes) { recipe in
                            RecommendationCard(recipe: recipe) {
                                selectedRecommendation = recipe
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
    
    private var dailyRecommendedRecipes: [BentoRecipe] {
        return bentoStore.dailyRecommendations
    }
    
    var safetyGuidelinesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 18))
                    .foregroundColor(.blue)
                
                Text("お弁当を安全に楽しむために")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 12) {
                SafetyTipView(icon: "hands.and.sparkles", text: "調理前、盛り付け前には必ず石鹸で手を洗いましょう。", color: .blue)
                
                SafetyTipView(icon: "flame.fill", text: "肉・魚・卵などの食材は、中心部まで十分に加熱しましょう。", color: .orange)
                
                SafetyTipView(icon: "wind", text: "ご飯やおかずは、お弁当箱に詰める前によく冷ましましょう。温かいままフタをすると蒸気で傷みやすくなります。", color: .mint)
                
                SafetyTipView(icon: "drop.fill", text: "汁気の多いおかずは避け、水気をよく切ってから詰めましょう。", color: .cyan)
                
                SafetyTipView(icon: "leaf.fill", text: "生の野菜や果物はよく洗い、水気をしっかり切りましょう。特に夏場は注意が必要です。", color: .green)
                
                SafetyTipView(icon: "square.grid.2x2.fill", text: "まな板や包丁などの調理器具は、使用するたびにきれいに洗い、乾燥させましょう。", color: .indigo)
                
                SafetyTipView(icon: "sun.max.fill", text: "作ったお弁当は、直射日光を避け、なるべく涼しい場所に保管し、できるだけ早く（目安として4時間以内）食べましょう。", color: .yellow)
                
                SafetyTipView(icon: "snowflake", text: "持ち運びには保冷剤や保冷バッグを活用し、温度管理に気を配りましょう。", color: .blue)
                
                SafetyTipView(icon: "microwave", text: "食べる前にもう一度加熱できる環境であれば、再加熱するとより安全です。", color: .red)
                
                SafetyTipView(icon: "clock.fill", text: "前日の残り物や作り置きのおかずを詰める場合は、必ず再加熱してから冷まして詰めましょう。", color: .purple)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.blue.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .padding(.top, 8)
    }
}

struct SafetyTipView: View {
    let icon: String
    let text: String
    let color: Color
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(color)
                .frame(width: 24, height: 24)
            
            Text(text)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundColor(.primary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer(minLength: 0)
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
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(.primary)
                    
                    Text(category.description)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 125)
            .padding(.vertical, 12)
            .padding(.horizontal, 6)
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
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                Text(recipe.category.emoji)
                    .font(.title2)
                
                Text(recipe.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(2)
                    .foregroundColor(.primary)
                
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
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Helper for sheet presentation
struct DaySelection: Identifiable {
    let id = UUID()
    let day: String
}

// MARK: - Other Views (Placeholder)
struct WeeklyPlanView: View {
    @EnvironmentObject var bentoStore: BentoStore
    @State private var selectedWeek = Date()
    @State private var selectedDayForRecipe: DaySelection?
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // ヘッダーセクション
                headerSection
                
                // 週間カレンダー
                weeklyCalendarSection
                
                Spacer(minLength: 50)
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack {
                    Image(systemName: "calendar")
                        .font(.system(size: 18, weight: .medium))
                    Text("週間プラン")
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                }
            }
        }
        .sheet(item: $selectedDayForRecipe) { daySelection in
            RecipeSelectionView(selectedDay: daySelection.day)
        }
    }
    
    var headerSection: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Text("今週のお弁当プラン")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .foregroundColor(.primary)
                
                Text("一週間のお弁当を計画しましょう")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.top)
    }
    
    var weeklyCalendarSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("今週のプラン")
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                
                Spacer()
                
                Text(weekDateString)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            VStack(spacing: 12) {
                ForEach(weekDays, id: \.key) { day in
                    WeeklyPlanDayCard(
                        dayName: day.key,
                        recipe: day.value,
                        onAddRecipe: {
                            selectedDayForRecipe = DaySelection(day: day.key)
                        },
                        onRemoveRecipe: {
                            if let recipe = day.value {
                                bentoStore.removeRecipeFromWeeklyPlan(day: day.key)
                            }
                        }
                    )
                }
            }
        }
    }
    
    private var weekDays: [(key: String, value: BentoRecipe?)] {
        return [
            ("月", bentoStore.weeklyPlan.monday),
            ("火", bentoStore.weeklyPlan.tuesday),
            ("水", bentoStore.weeklyPlan.wednesday),
            ("木", bentoStore.weeklyPlan.thursday),
            ("金", bentoStore.weeklyPlan.friday),
            ("土", bentoStore.weeklyPlan.saturday),
            ("日", bentoStore.weeklyPlan.sunday)
        ]
    }
    
    private var weekDateString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M月d日"
        
        let startOfWeek = Calendar.current.dateInterval(of: .weekOfYear, for: selectedWeek)?.start ?? selectedWeek
        let endOfWeek = Calendar.current.date(byAdding: .day, value: 6, to: startOfWeek) ?? selectedWeek
        
        return "\(formatter.string(from: startOfWeek)) 〜 \(formatter.string(from: endOfWeek))"
    }
}

struct FavoritesView: View {
    @EnvironmentObject var bentoStore: BentoStore
    @State private var selectedRecipe: BentoRecipe?
    
    var body: some View {
        VStack {
            if bentoStore.favoriteRecipes.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "heart")
                        .font(.system(size: 60))
                        .foregroundColor(.gray.opacity(0.5))
                    
                    Text("お気に入りがありません")
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundColor(.gray)
                    
                    Text("気に入ったレシピをハートマークでお気に入りに追加しましょう")
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else {
                List(bentoStore.favoriteRecipes) { recipe in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(recipe.category.emoji)
                            
                            Button(action: {
                                selectedRecipe = recipe
                            }) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(recipe.name)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    
                                    Text(recipe.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            Spacer()
                            
                            Button(action: {
                                bentoStore.toggleFavorite(recipe)
                            }) {
                                Image(systemName: "heart.fill")
                                    .foregroundColor(.red)
                                    .font(.title2)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.red)
                    Text("お気に入り")
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                }
            }
        }
        .sheet(item: $selectedRecipe) { recipe in
            NavigationView {
                RecipeDetailView(recipe: recipe)
            }
        }
    }
}

struct WeeklyPlanDayCard: View {
    let dayName: String
    let recipe: BentoRecipe?
    let onAddRecipe: () -> Void
    let onRemoveRecipe: () -> Void
    @State private var showingRecipeDetail = false
    
    var body: some View {
        HStack(spacing: 16) {
            // 曜日表示
            VStack {
                Text(dayName)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text("曜日")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(width: 50)
            
            if let recipe = recipe {
                // レシピが設定されている場合
                Button(action: {
                    showingRecipeDetail = true
                }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(recipe.name)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                            
                            Text(recipe.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            
                            HStack(spacing: 12) {
                                Label("\(recipe.prepTime)分", systemImage: "clock")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                
                                Label("\(recipe.calories)kcal", systemImage: "flame")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        // 削除ボタン
                        Button(action: onRemoveRecipe) {
                            Image(systemName: "trash")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        .onTapGesture {
                            // イベントの伝播を停止
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(recipe.category.color.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(recipe.category.color.opacity(0.3), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(PlainButtonStyle())
                .sheet(isPresented: $showingRecipeDetail) {
                    RecipeDetailView(recipe: recipe)
                }
            } else {
                // レシピが未設定の場合
                Button(action: onAddRecipe) {
                    HStack {
                        Image(systemName: "plus.circle.dashed")
                            .font(.title2)
                            .foregroundColor(.gray)
                        
                        Text("レシピを追加")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        
                        Spacer()
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.3), style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [5]))
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
}

struct WeeklyPlanFavoritesView: View {
    @EnvironmentObject var bentoStore: BentoStore
    @Environment(\.dismiss) var dismiss
    let selectedDay: String

    var body: some View {
        VStack {
            if bentoStore.favoriteRecipes.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "heart")
                        .font(.system(size: 60))
                        .foregroundColor(.gray.opacity(0.5))
                    
                    Text("お気に入りがありません")
                        .font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundColor(.gray)
                    
                    Text("気に入ったレシピをハートマークでお気に入りに追加しましょう")
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else {
                List(bentoStore.favoriteRecipes) { recipe in
                    Button(action: {
                        bentoStore.addRecipeToWeeklyPlan(recipe, day: selectedDay)
                        dismiss()
                    }) {
                        HStack(spacing: 16) {
                            Text(recipe.category.emoji)
                                .font(.title2)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(recipe.name)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                Text(recipe.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                HStack(spacing: 12) {
                                    Label("\(recipe.prepTime)分", systemImage: "clock")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    
                                    Label("\(recipe.calories)kcal", systemImage: "flame")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .navigationTitle("\(selectedDay)曜日のレシピ選択")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("キャンセル") {
                    dismiss()
                }
            }
        }
        .onAppear {
            print("🔄 WeeklyPlanFavoritesView: onAppear - selectedDay = '\(selectedDay)'")
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(BentoStore())
}