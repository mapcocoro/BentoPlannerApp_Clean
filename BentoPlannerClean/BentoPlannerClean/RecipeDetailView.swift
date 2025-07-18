import SwiftUI

struct RecipeDetailView: View {
    let recipe: BentoRecipe
    @EnvironmentObject var bentoStore: BentoStore
    @Environment(\.dismiss) var dismiss
    @State private var showingWeeklyPlanSheet = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // レシピ名とカテゴリ
                VStack(spacing: 12) {
                    Text(recipe.category.emoji)
                        .font(.system(size: 60))
                    
                    Text(recipe.name)
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                }
                .padding()
                
                // 基本情報カード
                HStack(spacing: 20) {
                    InfoCard(title: "準備時間", value: "\(recipe.prepTime)", unit: "分", color: .blue)
                    InfoCard(title: "カロリー", value: "\(recipe.calories)", unit: "kcal", color: .orange)
                    InfoCard(title: "難易度", value: recipe.difficulty.rawValue, unit: "", color: .green)
                }
                .padding(.horizontal)
                
                // レシピ説明
                VStack(alignment: .leading, spacing: 8) {
                    Text("レシピについて")
                        .font(.headline)
                        .fontWeight(.bold)
                    
                    Text(recipe.description)
                        .font(.body)
                        .lineSpacing(4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)
                
                // 料理詳細
                VStack(spacing: 16) {
                    DishDetailView(title: "🍖 メイン料理", dish: recipe.mainDish, color: .orange)
                    DishDetailView(title: "🥗 サイド料理 1", dish: recipe.sideDish1, color: .green)
                    DishDetailView(title: "🥕 サイド料理 2", dish: recipe.sideDish2, color: .blue)
                }
                .padding(.horizontal)
                
                // コツ・ポイント
                if !recipe.tips.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("🔥 コツ・ポイント")
                            .font(.headline)
                            .fontWeight(.bold)
                        
                        ForEach(recipe.tips, id: \.self) { tip in
                            HStack(alignment: .top) {
                                Text("•")
                                    .foregroundColor(.orange)
                                Text(tip)
                                    .font(.body)
                                Spacer()
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.systemYellow).opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                }
                
                // お気に入りボタン
                Button(action: {
                    bentoStore.toggleFavorite(recipe)
                }) {
                    let isFavorite = bentoStore.isRecipeFavorite(recipe)
                    HStack {
                        Image(systemName: isFavorite ? "heart.fill" : "heart")
                            .foregroundColor(isFavorite ? .red : .pink)
                        Text(isFavorite ? "お気に入り登録済み" : "お気に入りに追加")
                            .foregroundColor(isFavorite ? .red : .pink)
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isFavorite ? Color.red : Color.pink, lineWidth: 2)
                    )
                }
                .padding(.horizontal)
                .padding(.bottom, 30)
            }
        }
        .navigationTitle("レシピ詳細")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    Button(action: {
                        showingWeeklyPlanSheet = true
                    }) {
                        Image(systemName: "calendar.badge.plus")
                            .foregroundColor(.blue)
                    }
                    
                    Button("閉じる") {
                        dismiss()
                    }
                }
            }
        }
        .actionSheet(isPresented: $showingWeeklyPlanSheet) {
            ActionSheet(
                title: Text("週間プランに追加"),
                message: Text("このレシピをどの曜日に追加しますか？"),
                buttons: [
                    .default(Text("月曜日")) {
                        bentoStore.addRecipeToWeeklyPlan(recipe, day: "月")
                    },
                    .default(Text("火曜日")) {
                        bentoStore.addRecipeToWeeklyPlan(recipe, day: "火")
                    },
                    .default(Text("水曜日")) {
                        bentoStore.addRecipeToWeeklyPlan(recipe, day: "水")
                    },
                    .default(Text("木曜日")) {
                        bentoStore.addRecipeToWeeklyPlan(recipe, day: "木")
                    },
                    .default(Text("金曜日")) {
                        bentoStore.addRecipeToWeeklyPlan(recipe, day: "金")
                    },
                    .default(Text("土曜日")) {
                        bentoStore.addRecipeToWeeklyPlan(recipe, day: "土")
                    },
                    .default(Text("日曜日")) {
                        bentoStore.addRecipeToWeeklyPlan(recipe, day: "日")
                    },
                    .cancel(Text("キャンセル"))
                ]
            )
        }
    }
}

struct InfoCard: View {
    let title: String
    let value: String
    let unit: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack(alignment: .bottom, spacing: 2) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(color)
                
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.1))
        )
    }
}

struct DishDetailView: View {
    let title: String
    let dish: DishItem
    let color: Color
    
    // 手順から番号プレフィックスを削除する関数
    private func removeNumberPrefix(from instruction: String) -> String {
        let pattern = "^\\d+\\.\\s*"
        return instruction.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(color)
            
            Text(dish.name)
                .font(.title3)
                .fontWeight(.semibold)
            
            // 材料
            VStack(alignment: .leading, spacing: 8) {
                Text("材料:")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                ForEach(dish.ingredients, id: \.self) { ingredient in
                    HStack {
                        Text("•")
                            .foregroundColor(color)
                        Text(ingredient)
                            .font(.body)
                        Spacer()
                    }
                }
            }
            
            // 作り方
            VStack(alignment: .leading, spacing: 8) {
                Text("作り方:")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                ForEach(Array(dish.instructions.enumerated()), id: \.offset) { index, instruction in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1).")
                            .foregroundColor(color)
                            .fontWeight(.semibold)
                            .font(.body)
                            .frame(minWidth: 20, alignment: .leading)
                        // 既存の番号を除去する処理
                        Text(removeNumberPrefix(from: instruction))
                            .font(.body)
                            .lineLimit(nil)
                            .multilineTextAlignment(.leading)
                        Spacer()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.3), lineWidth: 1)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(color.opacity(0.05))
                )
        )
    }
}

#Preview {
    NavigationView {
        RecipeDetailView(recipe: BentoRecipe(
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
                ingredients: ["ブロッコリー 1/2株", "白ごま 大さじ1", "醤油 小さじ2"],
                instructions: ["ブロッコリーを茹でる", "ごまをすって調味料と混ぜる"]
            ),
            sideDish2: DishItem(
                name: "だし巻き卵",
                ingredients: ["卵 3個", "だし汁 大さじ2", "砂糖 小さじ1"],
                instructions: ["材料を全て混ぜる", "フライパンで巻きながら焼く"]
            ),
            prepTime: 25,
            calories: 450,
            difficulty: .easy,
            tips: ["鮭は焼きすぎに注意", "卵は弱火でゆっくり焼く"]
        ))
        .environmentObject(BentoStore())
    }
}