import Foundation

class BentoAIService: ObservableObject {
    // Gemini APIキー（環境変数から取得）
    private let apiKey: String
    
    init() {
        // 設定ファイルからAPIキーを読み込み
        if let path = Bundle.main.path(forResource: "Config", ofType: "plist"),
           let config = NSDictionary(contentsOfFile: path),
           let key = config["GEMINI_API_KEY"] as? String {
            self.apiKey = key
        } else {
            // フォールバック: Info.plistから取得
            if let key = Bundle.main.object(forInfoDictionaryKey: "GEMINI_API_KEY") as? String {
                self.apiKey = key
            } else {
                // 緊急時のフォールバック（リリース前に削除）
                self.apiKey = ""
                NSLog("⚠️ APIキーが見つかりません。Config.plistを確認してください。")
            }
        }
    }
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"
    
    func generateBentoRecipes(for category: BentoCategory, randomSeed: Int = 0, avoidRecipeNames: [String] = [], previousMainDishes: [String] = [], previousSideDishes: [String] = [], previousCookingMethods: [String] = []) async throws -> [BentoRecipe] {
        NSLog("🔄 Starting AI recipe generation for category: \(category.rawValue)")
        NSLog("🔑 API Key status: \(apiKey.isEmpty ? "MISSING" : "AVAILABLE (length: \(apiKey.count))")")

        guard !apiKey.isEmpty else {
            NSLog("❌ API Key is missing")
            throw BentoAIError.apiKeyMissing
        }
        
        let prompt = createPrompt(for: category, randomSeed: randomSeed, avoidRecipeNames: avoidRecipeNames, previousMainDishes: previousMainDishes, previousSideDishes: previousSideDishes, previousCookingMethods: previousCookingMethods)
        
        let requestBody: [String: Any] = [
            "system_instruction": [
                "parts": [
                    [
                        "text": "あなたは日本のお弁当レシピ専門AIです。ユーザーの指示に従って、必ずJSON形式でレシピを出力してください。料理名に含まれる食材は必ず材料リストに記載してください。内部思考は一切出力せず、JSONのみを返してください。"
                    ]
                ]
            ],
            "contents": [
                [
                    "parts": [
                        [
                            "text": "\(prompt)"
                        ]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 1.2,
                "topK": 120,
                "topP": 0.95,
                "maxOutputTokens": 8000,
                "candidateCount": 1,
                "responseMimeType": "application/json",
                "responseSchema": [
                    "type": "object",
                    "properties": [
                        "recipes": [
                            "type": "array",
                            "items": [
                                "type": "object",
                                "properties": [
                                    "name": ["type": "string"],
                                    "description": ["type": "string"],
                                    "mainDish": [
                                        "type": "object",
                                        "properties": [
                                            "name": ["type": "string"],
                                            "ingredients": ["type": "array", "items": ["type": "string"]],
                                            "instructions": ["type": "array", "items": ["type": "string"]]
                                        ],
                                        "required": ["name", "ingredients", "instructions"]
                                    ],
                                    "sideDish1": [
                                        "type": "object",
                                        "properties": [
                                            "name": ["type": "string"],
                                            "ingredients": ["type": "array", "items": ["type": "string"]],
                                            "instructions": ["type": "array", "items": ["type": "string"]]
                                        ],
                                        "required": ["name", "ingredients", "instructions"]
                                    ],
                                    "sideDish2": [
                                        "type": "object",
                                        "properties": [
                                            "name": ["type": "string"],
                                            "ingredients": ["type": "array", "items": ["type": "string"]],
                                            "instructions": ["type": "array", "items": ["type": "string"]]
                                        ],
                                        "required": ["name", "ingredients", "instructions"]
                                    ],
                                    "prepTime": ["type": "integer"],
                                    "calories": ["type": "integer"],
                                    "difficulty": ["type": "string"],
                                    "tips": ["type": "array", "items": ["type": "string"]]
                                ],
                                "required": ["name", "description", "mainDish", "sideDish1", "sideDish2", "prepTime", "calories", "difficulty", "tips"]
                            ],
                            "minItems": 3,
                            "maxItems": 3
                        ]
                    ],
                    "required": ["recipes"]
                ]
            ]
        ]
        
        guard let url = URL(string: "\(baseURL)?key=\(apiKey)") else {
            NSLog("❌ Invalid URL construction")
            throw BentoAIError.invalidURL
        }
        
        NSLog("🌐 Making request to: \(baseURL)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60  // Extended from 15 to 60 seconds
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            throw BentoAIError.invalidRequest
        }
        
        // タイムアウト設定付きでAPI呼び出し
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            NSLog("❌ Network error: \(error)")
            throw BentoAIError.serverError
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BentoAIError.serverError
        }

        NSLog("HTTP Status Code: \(httpResponse.statusCode)")

        guard httpResponse.statusCode == 200 else {
            NSLog("❌ API Error - Status: \(httpResponse.statusCode)")
            if let errorData = String(data: data, encoding: .utf8) {
                NSLog("❌ Error Response: \(errorData)")
            }
            throw BentoAIError.serverError
        }

        // Print complete raw response for debugging
        if let responseString = String(data: data, encoding: .utf8) {
            NSLog("📦 COMPLETE RAW RESPONSE (first 1000 chars):")
            NSLog(String(responseString.prefix(1000)))
        }

        // Try to parse as generic JSON first to see the structure
        do {
            if let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                NSLog("🔍 Response has keys: \(jsonObject.keys)")

                // Navigate through the structure manually
                if let candidates = jsonObject["candidates"] as? [[String: Any]],
                   let firstCandidate = candidates.first,
                   let content = firstCandidate["content"] as? [String: Any] {
                    NSLog("🔍 Content has keys: \(Array(content.keys))")

                    if let parts = content["parts"] as? [[String: Any]],
                       let firstPart = parts.first,
                       let text = firstPart["text"] as? String {
                        NSLog("✅ Successfully extracted text from response")
                        NSLog("📝 Content length: \(text.count) characters")

                        // レシピ解析を試行
                        do {
                            let recipes = try parseRecipesFromJSON(text, category: category)
                            NSLog("✅ Successfully parsed \(recipes.count) recipes")
                            return recipes
                        } catch {
                            NSLog("❌ Recipe parsing failed: \(error)")
                            throw BentoAIError.invalidJSON
                        }
                    } else {
                        NSLog("❌ No 'text' field in parts or parts is not an array")
                        if let parts = content["parts"] {
                            NSLog("Parts type: \(type(of: parts))")
                            NSLog("Parts value: \(parts)")
                        }
                        throw BentoAIError.noContent
                    }
                } else {
                    NSLog("❌ Could not extract content from candidates")
                    if let candidates = jsonObject["candidates"] as? [[String: Any]],
                       let firstCandidate = candidates.first {
                        NSLog("First candidate keys: \(firstCandidate.keys)")
                        NSLog("First candidate: \(firstCandidate)")
                    }
                    throw BentoAIError.noContent
                }
            }
        } catch {
            NSLog("❌ Failed to parse response: \(error)")
            throw BentoAIError.invalidJSON
        }

        // This should never be reached, but Swift requires a return
        throw BentoAIError.noContent
    }
    
    func generateRecipesFromIngredients(_ selectedIngredients: [Ingredient], additionalNotes: String = "") async throws -> [BentoRecipe] {
        guard !apiKey.isEmpty else {
            throw BentoAIError.apiKeyMissing
        }

        let prompt = createIngredientBasedPrompt(selectedIngredients, additionalNotes: additionalNotes)

        let requestBody: [String: Any] = [
            "system_instruction": [
                "parts": [
                    [
                        "text": "あなたは日本のお弁当レシピ専門AIです。ユーザーの指示に従って、必ずJSON形式でレシピを出力してください。料理名に含まれる食材は必ず材料リストに記載してください。内部思考は一切出力せず、JSONのみを返してください。"
                    ]
                ]
            ],
            "contents": [
                [
                    "parts": [
                        [
                            "text": "\(prompt)"
                        ]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 1.2,
                "topK": 120,
                "topP": 0.95,
                "maxOutputTokens": 8000,
                "candidateCount": 1,
                "responseMimeType": "application/json",
                "responseSchema": [
                    "type": "object",
                    "properties": [
                        "recipes": [
                            "type": "array",
                            "items": [
                                "type": "object",
                                "properties": [
                                    "name": ["type": "string"],
                                    "description": ["type": "string"],
                                    "mainDish": [
                                        "type": "object",
                                        "properties": [
                                            "name": ["type": "string"],
                                            "ingredients": ["type": "array", "items": ["type": "string"]],
                                            "instructions": ["type": "array", "items": ["type": "string"]]
                                        ],
                                        "required": ["name", "ingredients", "instructions"]
                                    ],
                                    "sideDish1": [
                                        "type": "object",
                                        "properties": [
                                            "name": ["type": "string"],
                                            "ingredients": ["type": "array", "items": ["type": "string"]],
                                            "instructions": ["type": "array", "items": ["type": "string"]]
                                        ],
                                        "required": ["name", "ingredients", "instructions"]
                                    ],
                                    "sideDish2": [
                                        "type": "object",
                                        "properties": [
                                            "name": ["type": "string"],
                                            "ingredients": ["type": "array", "items": ["type": "string"]],
                                            "instructions": ["type": "array", "items": ["type": "string"]]
                                        ],
                                        "required": ["name", "ingredients", "instructions"]
                                    ],
                                    "prepTime": ["type": "integer"],
                                    "calories": ["type": "integer"],
                                    "difficulty": ["type": "string"],
                                    "tips": ["type": "array", "items": ["type": "string"]]
                                ],
                                "required": ["name", "description", "mainDish", "sideDish1", "sideDish2", "prepTime", "calories", "difficulty", "tips"]
                            ],
                            "minItems": 3,
                            "maxItems": 3
                        ]
                    ],
                    "required": ["recipes"]
                ]
            ]
        ]
        
        guard let url = URL(string: "\(baseURL)?key=\(apiKey)") else {
            throw BentoAIError.invalidURL
        }

        NSLog("🌐 Making ingredient-based request to: \(baseURL)")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 120  // Extended to 120 seconds for ingredient-based generation
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            NSLog("📤 Request body size: \(request.httpBody?.count ?? 0) bytes")
        } catch {
            NSLog("❌ Failed to serialize request body")
            throw BentoAIError.invalidRequest
        }

        // タイムアウト設定付きでAPI呼び出し
        NSLog("⏱️ Starting API call with 120s timeout...")
        let startTime = Date()
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
            let duration = Date().timeIntervalSince(startTime)
            NSLog("✅ API call completed in \(String(format: "%.1f", duration))s")
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            NSLog("❌ Network error after \(String(format: "%.1f", duration))s: \(error)")
            throw BentoAIError.serverError
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BentoAIError.serverError
        }
        
        NSLog("HTTP Status Code: \(httpResponse.statusCode)")
        if let responseString = String(data: data, encoding: .utf8) {
            NSLog("Response: \(responseString)")
        }
        
        guard httpResponse.statusCode == 200 else {
            NSLog("❌ API Error - Status: \(httpResponse.statusCode)")
            if let errorData = String(data: data, encoding: .utf8) {
                NSLog("❌ Error Response: \(errorData)")
            }
            throw BentoAIError.serverError
        }

        // Print complete raw response for debugging
        if let responseString = String(data: data, encoding: .utf8) {
            NSLog("📦 INGREDIENT-BASED RESPONSE (first 1000 chars):")
            NSLog(String(responseString.prefix(1000)))
        }

        // Try to parse as generic JSON first to see the structure
        do {
            if let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                NSLog("🔍 Response has keys: \(jsonObject.keys)")

                // Navigate through the structure manually
                if let candidates = jsonObject["candidates"] as? [[String: Any]],
                   let firstCandidate = candidates.first,
                   let content = firstCandidate["content"] as? [String: Any] {
                    NSLog("🔍 Content has keys: \(Array(content.keys))")

                    if let parts = content["parts"] as? [[String: Any]],
                       let firstPart = parts.first,
                       let text = firstPart["text"] as? String {
                        NSLog("✅ Successfully extracted text from response")
                        NSLog("📝 Content length: \(text.count) characters")

                        // レシピ解析を試行
                        do {
                            let recipes = try parseRecipesFromJSON(text, category: .omakase) // 食材ベースはおまかせカテゴリとして扱う
                            NSLog("✅ Successfully parsed \(recipes.count) recipes")
                            return recipes
                        } catch {
                            NSLog("❌ Recipe parsing failed: \(error)")
                            throw BentoAIError.invalidJSON
                        }
                    } else {
                        NSLog("❌ No 'text' field in parts or parts is not an array")
                        if let parts = content["parts"] {
                            NSLog("Parts type: \(type(of: parts))")
                            NSLog("Parts value: \(parts)")
                        }
                        throw BentoAIError.noContent
                    }
                } else {
                    NSLog("❌ Could not extract content from candidates")
                    if let candidates = jsonObject["candidates"] as? [[String: Any]],
                       let firstCandidate = candidates.first {
                        NSLog("First candidate keys: \(firstCandidate.keys)")
                        NSLog("First candidate: \(firstCandidate)")
                    }
                    throw BentoAIError.noContent
                }
            }
        } catch {
            NSLog("❌ Failed to parse response: \(error)")
            throw BentoAIError.invalidJSON
        }

        // This should never be reached, but Swift requires a return
        throw BentoAIError.noContent
    }
    
    private func createPrompt(for category: BentoCategory, randomSeed: Int = 0, avoidRecipeNames: [String] = [], previousMainDishes: [String] = [], previousSideDishes: [String] = [], previousCookingMethods: [String] = []) -> String {
        let now = Date()
        let timestamp = Int(now.timeIntervalSince1970)
        let uniqueId = timestamp + randomSeed + abs(category.hashValue)

        // カテゴリごとの簡潔な指示
        let categoryHint: String
        switch category {
        case .omakase:
            categoryHint = "バランス。弁当名:シンプルに「鶏の照り焼き弁当」等"
        case .hearty:
            categoryHint = "がっつり700kcal。肉メイン(魚は使わない)。弁当名:「豚の生姜焼き弁当」等"
        case .simple:
            categoryHint = "10分以内。弁当名:シンプルに"
        case .fishMain:
            categoryHint = "魚メイン。弁当名:「鯖の味噌煮弁当」等"
        }

        return """
        \(categoryHint) ID:\(uniqueId)

        必ず3レシピ生成。料理名の食材は材料に必須記載。副菜:「〜の煮浸し」「〜の煮物」「〜のきんぴら」等(煮浸しとお浸しは同一献立に入れない)。全6副菜は異なる調理法必須。
        \(avoidRecipeNames.isEmpty ? "" : "避:\(avoidRecipeNames.prefix(3).joined(separator: ","))")
        """
    }

    
    private func parseRecipesFromJSON(_ jsonString: String, category: BentoCategory) throws -> [BentoRecipe] {
        // 🔍 ENHANCED LOGGING: Complete raw API response
        NSLog(String(repeating: "=", count: 80))
        NSLog("🔍 RAW API RESPONSE - START")
        NSLog(String(repeating: "=", count: 80))
        NSLog(jsonString)
        NSLog(String(repeating: "=", count: 80))
        NSLog("🔍 RAW API RESPONSE - END")
        NSLog(String(repeating: "=", count: 80))

        let cleanedJSON = extractJSON(from: jsonString)

        NSLog("🧹 Cleaned JSON length: \(cleanedJSON.count) characters")
        NSLog("🧹 CLEANED JSON - START")
        NSLog(cleanedJSON)
        NSLog("🧹 CLEANED JSON - END")

        guard let data = cleanedJSON.data(using: .utf8) else {
            throw BentoAIError.invalidJSON
        }

        let aiRecipesResponse: AIRecipeResponse
        do {
            aiRecipesResponse = try JSONDecoder().decode(AIRecipeResponse.self, from: data)
            NSLog("✅ JSON decoded successfully")
        } catch {
            NSLog("❌ JSON decode error: \(error)")
            NSLog("❌ Failed JSON: \(cleanedJSON)")
            throw BentoAIError.invalidJSON
        }

        guard !aiRecipesResponse.recipes.isEmpty else {
            NSLog("❌ No recipes found in response")
            throw BentoAIError.noContent
        }

        NSLog("🍱 Converting \(aiRecipesResponse.recipes.count) AI recipes to BentoRecipe format")

        // 🚨 VALIDATION: Collect all side dishes to check for duplicates
        var allSideDishes: [String] = []
        var validationErrors: [String] = []

        for (index, aiRecipe) in aiRecipesResponse.recipes.enumerated() {
            NSLog("\n🔍 Validating Recipe \(index + 1): \(aiRecipe.name)")

            // Validate main dish
            let mainDishErrors = validateDishNameMatchesIngredients(
                dishName: aiRecipe.mainDish.name,
                ingredients: aiRecipe.mainDish.ingredients,
                dishType: "主菜"
            )
            if !mainDishErrors.isEmpty {
                validationErrors.append("Recipe \(index + 1) - 主菜: \(mainDishErrors.joined(separator: ", "))")
            }

            // Validate side dishes
            let side1Errors = validateDishNameMatchesIngredients(
                dishName: aiRecipe.sideDish1.name,
                ingredients: aiRecipe.sideDish1.ingredients,
                dishType: "副菜1"
            )
            if !side1Errors.isEmpty {
                validationErrors.append("Recipe \(index + 1) - 副菜1: \(side1Errors.joined(separator: ", "))")
            }

            let side2Errors = validateDishNameMatchesIngredients(
                dishName: aiRecipe.sideDish2.name,
                ingredients: aiRecipe.sideDish2.ingredients,
                dishType: "副菜2"
            )
            if !side2Errors.isEmpty {
                validationErrors.append("Recipe \(index + 1) - 副菜2: \(side2Errors.joined(separator: ", "))")
            }

            // Check for duplicate cooking methods within same bento
            let cookingMethod1 = extractCookingMethod(aiRecipe.sideDish1.name)
            let cookingMethod2 = extractCookingMethod(aiRecipe.sideDish2.name)

            if !cookingMethod1.isEmpty && !cookingMethod2.isEmpty && cookingMethod1 == cookingMethod2 {
                let error = "⚠️ 同じ弁当内で調理法が重複: 副菜1「\(aiRecipe.sideDish1.name)」と副菜2「\(aiRecipe.sideDish2.name)」がどちらも「\(cookingMethod1)」"
                validationErrors.append(error)
                NSLog(error)
            }

            // Collect all side dishes
            allSideDishes.append(aiRecipe.sideDish1.name)
            allSideDishes.append(aiRecipe.sideDish2.name)
        }

        // 🚨 CRITICAL VALIDATION: Check for duplicate side dishes across all recipes
        NSLog("\n🔍 Checking for duplicate side dishes across all \(aiRecipesResponse.recipes.count) recipes:")
        NSLog("All side dishes: \(allSideDishes)")

        let sideDishCounts = Dictionary(grouping: allSideDishes, by: { $0 }).mapValues { $0.count }
        for (dish, count) in sideDishCounts where count > 1 {
            let error = "⚠️ 副菜が重複: 「\(dish)」が\(count)回出現"
            validationErrors.append(error)
            NSLog(error)
        }

        // 🚨 CRITICAL VALIDATION: Check for similar cooking methods across all side dishes
        let cookingMethods = allSideDishes.map { extractCookingMethod($0) }.filter { !$0.isEmpty }
        let methodCounts = Dictionary(grouping: cookingMethods, by: { $0 }).mapValues { $0.count }
        for (method, count) in methodCounts where count > 1 {
            let warning = "⚠️ 調理法が重複: 「\(method)」が\(count)回出現"
            validationErrors.append(warning)
            NSLog(warning)
        }

        // Print validation summary (but continue anyway - just log warnings)
        if !validationErrors.isEmpty {
            NSLog("\n⚠️ VALIDATION WARNINGS (\(validationErrors.count) issues - proceeding anyway):")
            for error in validationErrors {
                NSLog("  - \(error)")
            }
            NSLog("\n⚠️ Note: Recipes will be shown despite minor validation issues")
        } else {
            NSLog("\n✅ All validation checks passed!")
        }

        let bentoRecipes = aiRecipesResponse.recipes.map { aiRecipe in
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

        NSLog("✅ Successfully converted to \(bentoRecipes.count) BentoRecipe objects")
        return bentoRecipes
    }

    // Helper function to validate dish name matches ingredients
    private func validateDishNameMatchesIngredients(dishName: String, ingredients: [String], dishType: String) -> [String] {
        var errors: [String] = []

        // Extract ingredient keywords from dish name
        let keywords = extractIngredientsFromName(dishName)

        NSLog("  \(dishType) '\(dishName)' - キーワード: \(keywords)")

        for keyword in keywords {
            let found = ingredients.contains { ingredient in
                ingredient.contains(keyword) || keyword.contains(ingredient)
            }

            if !found {
                errors.append("「\(dishName)」に「\(keyword)」が含まれているが、材料リストに見つかりません")
                NSLog("    ❌ Missing: \(keyword)")
            } else {
                NSLog("    ✅ Found: \(keyword)")
            }
        }

        return errors
    }

    // Extract ingredient keywords from dish name
    private func extractIngredientsFromName(_ name: String) -> [String] {
        var keywords: [String] = []

        // Common ingredients and flavors to check
        let ingredientPatterns = [
            "レモン", "ライム", "ゆず", "柚子",
            "タイム", "ローズマリー", "ロゼマリー", "バジル", "パセリ", "オレガノ", "セージ",
            "にんにく", "ガーリック", "生姜", "しょうが",
            "トマト", "きのこ", "しいたけ", "えのき",
            "わさび", "からし", "マスタード",
            "りんご", "バルサミコ", "ハーブ", "スパイス",
            "チーズ", "バター", "マヨネーズ"
        ]

        for pattern in ingredientPatterns {
            if name.contains(pattern) {
                keywords.append(pattern)
            }
        }

        return keywords
    }

    // Extract cooking method from dish name
    private func extractCookingMethod(_ dishName: String) -> String {
        let cookingMethods = [
            "煮物", "煮付け", "含め煮", "甘露煮", "佃煮", "角煮", "煮込み", "煉物",  // 煉物も煮物として扱う
            "焼き", "塩焼き", "味噌焼き", "照り焼き", "蒲焼き", "西京焼き",
            "揚げ", "唐揚げ", "竜田揚げ", "天ぷら", "フライ", "カツ",
            "炒め", "炒め物", "きんぴら",
            "和え", "和え物", "胡麻和え", "ごま和え", "お浸し", "おひたし",
            "蒸し", "酒蒸し", "ホイル蒸し",
            "漬け", "南蛮漬け", "マリネ"
        ]

        for method in cookingMethods {
            if dishName.contains(method) {
                // 煉物は煮物として統一
                return method == "煉物" ? "煮物" : method
            }
        }

        return ""
    }
    
    private func extractJSON(from text: String) -> String {
        // マークダウンコードブロック (```json または ```) を削除
        var cleanedText = text.replacingOccurrences(of: "```json", with: "")
        cleanedText = cleanedText.replacingOccurrences(of: "```", with: "")
        cleanedText = cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)

        // JSONの開始と終了を探す
        if let startIndex = cleanedText.range(of: "{")?.lowerBound,
           let endIndex = cleanedText.range(of: "}", options: .backwards)?.upperBound {
            return String(cleanedText[startIndex..<endIndex])
        }
        return cleanedText
    }
    
    private func mapDifficulty(_ difficulty: String) -> String {
        switch difficulty.lowercased() {
        case "easy": return "簡単"
        case "medium": return "普通"
        case "hard": return "上級"
        default: return "簡単"
        }
    }
    
    private func getCurrentSeason() -> String {
        let calendar = Calendar.current
        let month = calendar.component(.month, from: Date())

        switch month {
        case 3, 4, 5:
            return "春（桜、菜の花、たけのこ、新玉ねぎ、春キャベツなどの旬食材）"
        case 6, 7, 8:
            return "夏（トマト、きゅうり、ナス、とうもろこし、オクラ、枝豆などの旬食材）"
        case 9, 10, 11:
            return "秋（さつまいも、かぼちゃ、きのこ類、鮭、さんまなどの旬食材）"
        case 12, 1, 2:
            return "冬（大根、白菜、ほうれん草、ブリ、牡蠣などの旬食材）"
        default:
            return "春（旬の食材を活用）"
        }
    }

    private func getWeeklyTheme() -> String {
        let calendar = Calendar.current
        let weekOfYear = calendar.component(.weekOfYear, from: Date())

        let themes = [
            "地中海リゾート（イタリア・スペイン・ギリシャの太陽の味）",
            "アメリカンダイナー（ステーキ・BBQ・ハンバーガーの豪快さ）",
            "フランス田舎料理（素朴で温かいビストロの味）",
            "メキシカンフィエスタ（スパイシーで陽気なメキシコ料理）",
            "インド香辛料紀行（カレー・タンドール・多彩なスパイス）",
            "タイ屋台グルメ（パクチー・ココナッツ・エスニック）",
            "ドイツビアホール（ソーセージ・ザワークラウト・豪快料理）",
            "モロッコ異国情緒（タジン・クスクス・エキゾチック）",
            "日本の郷土料理（各地の伝統的な家庭の味）",
            "北欧シンプル（サーモン・ディル・さっぱり爽やか）"
        ]

        return themes[weekOfYear % themes.count]
    }

    private func createIngredientBasedPrompt(_ selectedIngredients: [Ingredient], additionalNotes: String) -> String {
        let mainProteins = selectedIngredients.filter { $0.category == .mainProtein }
        let vegetables = selectedIngredients.filter { $0.category == .vegetables }

        let timestamp = Int(Date().timeIntervalSince1970)
        let randomSeed = Int.random(in: 100000...999999)
        let uniqueId = timestamp + randomSeed

        let ingredientList = (mainProteins + vegetables).map { $0.name }.joined(separator: "・")

        return """
        \(ingredientList)\(additionalNotes.isEmpty ? "" : "。\(additionalNotes)") ID:\(uniqueId)

        3レシピ。副菜異なる調理法。
        """
    }
}

// MARK: - AI Response Models
struct GeminiResponse: Codable {
    let candidates: [Candidate]
    
    struct Candidate: Codable {
        let content: Content
        
        struct Content: Codable {
            let parts: [Part]
            
            struct Part: Codable {
                let text: String
            }
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
    case invalidRecipeContent

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "無効なURLです"
        case .invalidRequest: return "リクエストが無効です"
        case .serverError: return "サーバーエラーが発生しました"
        case .noContent: return "コンテンツが見つかりません"
        case .invalidJSON: return "JSONの解析に失敗しました"
        case .apiKeyMissing: return "APIキーが設定されていません"
        case .invalidRecipeContent: return "レシピの内容に問題があります（材料不一致・重複など）"
        }
    }
}
