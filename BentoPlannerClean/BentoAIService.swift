import Foundation

class BentoAIService: ObservableObject {
    // APIキーはInfo.plistから安全に読み込みます
    private var apiKey: String {
        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String,
              !apiKey.isEmpty,
              apiKey != "YOUR_NEW_OPENAI_API_KEY_HERE" else {
            fatalError("OpenAI API Key not found in Info.plist. Please add your API key to Config.xcconfig file.")
        }
        return apiKey
    }
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    
    func generateBentoRecipes(for category: BentoCategory) async throws -> [BentoRecipe] {
        guard !apiKey.contains("YOUR_OPENAI_API_KEY") else {
            throw BentoAIError.apiKeyMissing
        }
        
        let prompt = createPrompt(for: category)
        
        let requestBody: [String: Any] = [
            "model": "gpt-3.5-turbo",
            "messages": [
                [
                    "role": "system",
                    "content": """
                    お弁当レシピを3つ、JSON形式で生成してください。
                    
                    【絶対禁止】白米・ご飯・パン・生野菜サラダ・刺身・生卵・汁物・マヨネーズ和え
                    【必須】全料理加熱済み・冷めても美味しい・分量記載・お弁当適正・調味料詳細記載
                    
                    JSONフォーマットで返してください。
                    """
                ],
                [
                    "role": "user",
                    "content": prompt
                ]
            ],
            "max_tokens": 800,
            "temperature": 0.5
        ]
        
        guard let url = URL(string: baseURL) else {
            throw BentoAIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            throw BentoAIError.invalidRequest
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BentoAIError.serverError
        }
        
        print("HTTP Status Code: \(httpResponse.statusCode)")
        if let responseString = String(data: data, encoding: .utf8) {
            print("Response: \(responseString)")
        }
        
        guard httpResponse.statusCode == 200 else {
            print("❌ API Error - Status: \(httpResponse.statusCode)")
            if let errorData = String(data: data, encoding: .utf8) {
                print("❌ Error Response: \(errorData)")
            }
            throw BentoAIError.serverError
        }
        
        do {
            let aiResponse = try JSONDecoder().decode(OpenAIResponse.self, from: data)
            
            guard let content = aiResponse.choices.first?.message.content else {
                print("❌ No content in AI response")
                throw BentoAIError.noContent
            }
            
            print("✅ AI Response received successfully")
            
            return try parseRecipesFromJSON(content, category: category)
            
        } catch {
            print("❌ JSON Decode Error: \(error)")
            throw BentoAIError.invalidJSON
        }
    }
    
    private func createPrompt(for category: BentoCategory) -> String {
        let categoryDescription = getCategoryDescription(category)
        let randomSeed = Int.random(in: 1000...9999)
        let categorySpecificInstructions = getCategorySpecificInstructions(category)
        
        return """
        \(categoryDescription)
        
        \(categorySpecificInstructions)
        
        お弁当レシピを3つ生成してください。各レシピは「メイン1品 + サイド2品」の3品構成にしてください。
        
        【重要：カテゴリ違反は絶対に禁止】
        - 魚メインカテゴリでは肉類を一切使用しない
        - 肉メインカテゴリでは魚類を一切使用しない
        - 各カテゴリで全く異なるレシピを作る
        
        【調味料・味付け必須】
        - 各料理に具体的な調味料と分量を明記
        - 味付けの詳細を必ず含める（塩コショウ、醤油、みりん、砂糖、酒、味噌、ソースなど）
        
        【共通の禁止事項】
        - 生もの、汁物、水分多い料理、マヨネーズ和え完全禁止
        - 白米・ご飯・おにぎり・パン等の主食類は完全禁止
        - 生野菜サラダ・刺身・生卵等の非加熱料理は完全禁止
        - ただ洗っただけの野菜・切っただけの野菜は完全禁止
        
        【共通の必須事項】
        - 全ての料理は必ず加熱調理する（焼く・炒める・煮る・蒸す・揚げる）
        - サイド料理も必ず加熱した料理のみ（和え物・炒め物・煮物・焼き物）
        - 分量記載、「メイン料理名+弁当」形式
        - カテゴリの条件を厳格に守る
        - 調味料を詳細に記載する
        - お弁当に適した冷めても美味しい料理のみ
        
        JSONフォーマット例：
        {
          "recipes": [
            {
              "name": "鶏の照り焼き弁当",
              "description": "甘辛い照り焼きチキンがメインの栄養バランス弁当",
              "mainDish": {
                "name": "鶏の照り焼き",
                "ingredients": ["鶏もも肉 200g", "醤油 大さじ3", "みりん 大さじ2", "砂糖 大さじ1", "酒 大さじ1", "サラダ油 小さじ1"],
                "instructions": ["鶏肉に塩コショウで下味をつける", "フライパンで皮目から焼く", "醤油・みりん・砂糖・酒を混ぜたタレを加えて照り焼きにする"]
              },
              "sideDish1": {
                "name": "ブロッコリーのごま和え",
                "ingredients": ["ブロッコリー 1/2株", "白ごま 大さじ1", "醤油 小さじ2", "砂糖 小さじ1", "塩 少々"],
                "instructions": ["ブロッコリーを塩茹でする", "白ごまをすり、醤油と砂糖を混ぜる", "茹でたブロッコリーと和える"]
              },
              "sideDish2": {
                "name": "人参のきんぴら",
                "ingredients": ["人参 1本", "ごま油 大さじ1", "醤油 大さじ1", "みりん 大さじ1", "砂糖 小さじ1", "白ごま 適量"],
                "instructions": ["人参を千切りにする", "ごま油で炒める", "調味料を加えて炒め煮にする", "白ごまをふる"]
              },
              "prepTime": 25,
              "calories": 480,
              "difficulty": "easy",
              "tips": ["水分をしっかり切る", "照り焼きは強火で仕上げる"]
            }
          ]
        }
        
        ランダムシード: \(randomSeed)
        """
    }
    
    private func getCategoryDescription(_ category: BentoCategory) -> String {
        switch category {
        case .omakase:
            return """
            おまかせ【バランス重視・自由度高】：
            - 主材料：鶏肉・豚肉・牛肉・魚類のいずれか1つをメイン
            - 調理法例：照り焼き・竜田揚げ・生姜焼き・味噌煮・塩焼きなど多様
            - 必須：栄養バランス重視、季節感、万人受けする味付け
            - 特徴：制約が少なく創作性を重視したバラエティ豊かなお弁当
            """
        case .healthy:
            return """
            ヘルシー【低カロリー・栄養重視】：
            - カロリー制限：400kcal以下必須
            - 主材料：鶏むね肉・魚・豆腐・野菜中心
            - 調理法：蒸し・茹で・グリル中心（揚げ物禁止）
            - 特徴：栄養バランス重視の健康志向弁当
            """
        case .hearty:
            return """
            がっつり【高カロリー・満足感重視】：
            - カロリー目安：600kcal以上
            - 主材料：牛肉・豚肉・鶏もも肉などボリューム重視
            - 調理法：揚げ物・炒め物・焼き物でガッツリ系
            - 特徴：満足感とボリューム重視の食べ応え弁当
            """
        case .vegetableRich:
            return """
            野菜多め【野菜中心・肉魚少量】：
            - メイン料理：野菜炒め・野菜グラタン・野菜カレー・野菜ハンバーグ等
            - 必須野菜：かぼちゃ・なす・ピーマン・ブロッコリー・人参・キャベツ・きのこ類から最低5種
            - 肉魚：風味付け程度（50g以下）のみ許可
            - 調理法：蒸し・焼き・炒め中心、揚げ物禁止
            - 特徴：野菜が主役の健康志向弁当
            """
        case .fishMain:
            return """
            魚メイン【魚類専用・肉類絶対禁止】：
            - 必須魚種：鮭・鯖・鯵・鰤・さんま・たら・いわし・かじき・ぶりから選択
            - 調理法：塩焼き・味噌煮・照り焼き・南蛮漬け・竜田揚げ等
            - 絶対禁止：鶏肉・豚肉・牛肉・ひき肉・ハム・ソーセージ等すべての肉類
            - サイド：海藻・野菜・卵・豆腐のみ
            - 弁当名：必ず魚名を含める（例：鯖の味噌煮弁当）
            """
        case .simple:
            return """
            簡単弁当【15分以内・簡単調理】：
            - 調理時間：合計15分以内厳守
            - 許可調理法：電子レンジ・フライパン炒め・茹でるのみ
            - 禁止調理法：揚げ物・煮込み・オーブン・蒸し器使用
            - 活用推奨：冷凍食品・レトルト・缶詰・即席調味料
            - 特徴：忙しい朝でも作れる超時短弁当
            """
        }
    }
    
    private func getCategorySpecificInstructions(_ category: BentoCategory) -> String {
        let timestamp = Int(Date().timeIntervalSince1970)
        let categorySeed = category.rawValue.hashValue
        let uniqueSeed = timestamp + categorySeed
        
        switch category {
        case .fishMain:
            let fishTypes = ["鮭", "鯖", "鯵", "鰤", "さんま", "たら", "いわし", "かじき", "ぶり"]
            let cookingMethods = ["塩焼き", "味噌煮", "照り焼き", "南蛮漬け", "竜田揚げ", "蒸し焼き"]
            let selectedFish = fishTypes.randomElement() ?? "鮭"
            let selectedMethod = cookingMethods.randomElement() ?? "塩焼き"
            
            return """
            【魚メイン専用・絶対遵守】
            - メイン魚種指定：\(selectedFish)を使用（他の魚も可）
            - 推奨調理法：\(selectedMethod)系統
            - 絶対禁止：鶏肉・豚肉・牛肉・ひき肉・ハム・ソーセージ
            - 弁当名：魚名必須（例：\(selectedFish)の\(selectedMethod)弁当）
            - 特徴：魚の旨味を活かした和風弁当
            - ユニークシード：\(uniqueSeed)
            """
        case .hearty:
            let meatTypes = ["鶏もも肉", "豚こま肉", "豚ロース", "牛こま肉", "ひき肉"]
            let cookingMethods = ["唐揚げ", "生姜焼き", "照り焼き", "ハンバーグ", "炒め物", "竜田揚げ"]
            let selectedMeat = meatTypes.randomElement() ?? "鶏もも肉"
            let selectedMethod = cookingMethods.randomElement() ?? "照り焼き"
            
            return """
            【がっつり専用・絶対遵守】
            - メイン肉種指定：\(selectedMeat)を使用
            - 推奨調理法：\(selectedMethod)系統
            - カロリー目標：600kcal以上
            - 特徴：ガッツリ満足感重視弁当
            - ユニークシード：\(uniqueSeed)
            """
        case .healthy:
            let healthyMains = ["鶏むね肉", "白身魚", "豆腐", "卵"]
            let healthyMethods = ["蒸し焼き", "茹で", "グリル", "ソテー"]
            let selectedMain = healthyMains.randomElement() ?? "鶏むね肉"
            let selectedMethod = healthyMethods.randomElement() ?? "蒸し焼き"
            
            return """
            【ヘルシー専用・絶対遵守】
            - メイン食材：\(selectedMain)を使用
            - 推奨調理法：\(selectedMethod)系統
            - カロリー制限：400kcal以下
            - 禁止：揚げ物・炒め物
            - 特徴：低カロリー健康志向弁当
            - ユニークシード：\(uniqueSeed)
            """
        case .vegetableRich:
            let vegetables = ["かぼちゃ", "なす", "ピーマン", "ブロッコリー", "人参", "キャベツ"]
            let selectedVeggies = vegetables.shuffled().prefix(3).joined(separator: "・")
            
            return """
            【野菜多め専用・絶対遵守】
            - 重点野菜：\(selectedVeggies)を含む5種以上
            - メイン料理：野菜が主役（肉魚は少量）
            - 禁止：生野菜サラダ・白米・ただ切っただけの野菜
            - 特徴：野菜が主役のヘルシー弁当
            - ユニークシード：\(uniqueSeed)
            """
        case .simple:
            let quickMethods = ["電子レンジ調理", "フライパン炒め", "茹でる調理"]
            let selectedMethod = quickMethods.randomElement() ?? "電子レンジ調理"
            
            return """
            【簡単弁当専用・絶対遵守】
            - 重点調理法：\(selectedMethod)中心
            - 時間制限：合計15分以内厳守
            - 禁止：揚げ物・煮込み・オーブン使用・生野菜・白米
            - 必須：全て加熱調理したお弁当適正料理
            - 特徴：忙しい朝の救世主弁当
            - ユニークシード：\(uniqueSeed)
            """
        case .omakase:
            let themes = ["和風", "洋風", "中華風", "家庭料理"]
            let selectedTheme = themes.randomElement() ?? "和風"
            
            return """
            【おまかせ専用・自由度高】
            - テーマ：\(selectedTheme)ベース
            - 特徴：バランス重視の万能弁当
            - 自由度：制約少なく創作性重視
            - ユニークシード：\(uniqueSeed)
            """
        }
    }
    
    private func parseRecipesFromJSON(_ jsonString: String, category: BentoCategory) throws -> [BentoRecipe] {
        let cleanedJSON = extractJSON(from: jsonString)
        
        print("Cleaned JSON: \(cleanedJSON)")
        
        guard let data = cleanedJSON.data(using: .utf8) else {
            throw BentoAIError.invalidJSON
        }
        
        let aiRecipesResponse: AIRecipeResponse
        do {
            aiRecipesResponse = try JSONDecoder().decode(AIRecipeResponse.self, from: data)
        } catch {
            print("JSON decode error: \(error)")
            throw BentoAIError.invalidJSON
        }
        
        return aiRecipesResponse.recipes.map { aiRecipe in
            let mainDish = DishItem(name: aiRecipe.mainDish.name, ingredients: aiRecipe.mainDish.ingredients, instructions: aiRecipe.mainDish.instructions)
            let sideDish1 = DishItem(name: aiRecipe.sideDish1.name, ingredients: aiRecipe.sideDish1.ingredients, instructions: aiRecipe.sideDish1.instructions)
            let sideDish2 = DishItem(name: aiRecipe.sideDish2.name, ingredients: aiRecipe.sideDish2.ingredients, instructions: aiRecipe.sideDish2.instructions)

            return BentoRecipe(
                name: aiRecipe.name,
                description: aiRecipe.description,
                category: category,
                mainDish: mainDish,
                sideDish1: sideDish1,
                sideDish2: sideDish2,
                prepTime: aiRecipe.prepTime,
                calories: aiRecipe.calories,
                difficulty: BentoRecipe.Difficulty(rawValue: mapDifficulty(aiRecipe.difficulty)) ?? .easy,
                tips: aiRecipe.tips
            )
        }
    }
    
    private func extractJSON(from text: String) -> String {
        if let startIndex = text.range(of: "{")?.lowerBound,
           let endIndex = text.range(of: "}", options: .backwards)?.upperBound {
            return String(text[startIndex..<endIndex])
        }
        return text
    }
    
    private func mapDifficulty(_ difficulty: String) -> String {
        switch difficulty.lowercased() {
        case "easy": return "簡単"
        case "medium": return "普通"
        case "hard": return "上級"
        default: return "簡単"
        }
    }
}

// MARK: - AI Response Models
struct OpenAIResponse: Codable {
    let choices: [Choice]
    
    struct Choice: Codable {
        let message: Message
        
        struct Message: Codable {
            let content: String
        }
    }
}

struct AIDishItem: Codable {
    let name: String
    let ingredients: [String]
    let instructions: [String]
}

struct AIRecipeResponse: Codable {
    let recipes: [AIRecipe]
    
    struct AIRecipe: Codable {
        let name: String
        let description: String
        let mainDish: AIDishItem
        let sideDish1: AIDishItem
        let sideDish2: AIDishItem
        let prepTime: Int
        let calories: Int
        let difficulty: String
        let tips: [String]
    }
}

// MARK: - Error Types
enum BentoAIError: Error, LocalizedError {
    case invalidURL
    case invalidRequest
    case serverError
    case noContent
    case invalidJSON
    case apiKeyMissing
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "無効なURLです"
        case .invalidRequest: return "リクエストが無効です"
        case .serverError: return "サーバーエラーが発生しました"
        case .noContent: return "コンテンツが見つかりません"
        case .invalidJSON: return "JSONの解析に失敗しました"
        case .apiKeyMissing: return "APIキーが設定されていません"
        }
    }
}