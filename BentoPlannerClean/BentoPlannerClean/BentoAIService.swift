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
                print("⚠️ APIキーが見つかりません。Config.plistを確認してください。")
            }
        }
    }
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"
    
    func generateBentoRecipes(for category: BentoCategory, randomSeed: Int = 0, avoidRecipeNames: [String] = [], previousMainDishes: [String] = [], previousSideDishes: [String] = [], previousCookingMethods: [String] = []) async throws -> [BentoRecipe] {
        print("🔄 Starting AI recipe generation for category: \(category.rawValue)")
        print("🔑 API Key status: \(apiKey.isEmpty ? "MISSING" : "AVAILABLE (length: \(apiKey.count))")")
        
        guard !apiKey.isEmpty else {
            print("❌ API Key is missing")
            throw BentoAIError.apiKeyMissing
        }
        
        let prompt = createPrompt(for: category, randomSeed: randomSeed, avoidRecipeNames: avoidRecipeNames, previousMainDishes: previousMainDishes, previousSideDishes: previousSideDishes, previousCookingMethods: previousCookingMethods)
        
        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        [
                            "text": """
                            あなたは優秀なお弁当レシピクリエーターです。以下の最重要ルールを絶対に守ってレシピを生成してください。

                            🚨 絶対厳守ルール:
                            1. 料理名の食材は必ず材料リストに記載（例：「バジルペスト」→材料に「バジル」必須）
                            2. 6つの副菜（3レシピ×2副菜）は全て異なる調理法（煮物・炒め・和え物が重複禁止）
                            3. 毎回異なるメイン料理（「鮭の塩焼き」の繰り返し禁止）
                            4. 漢字は「煮物」を使う（「煉物」は間違い）
                            5. 魚は「切り身」と書く（「もも肉」は存在しない）

                            \(prompt)

                            副菜の調理法例: 胡麻和え、ナムル、おかか和え、ガーリック炒め、グラッセ、マリネ、サラダ（6つ全て異なる調理法）
                            
                            JSON形式（必ず3つのレシピ）：
                            {"recipes": [
                              {"name": "弁当名1", "description": "説明", "mainDish": {"name": "料理名", "ingredients": ["材料"], "instructions": ["手順"]}, "sideDish1": {...}, "sideDish2": {...}, "prepTime": 数値, "calories": 数値, "difficulty": "easy/medium/hard", "tips": ["コツ"]},
                              {"name": "弁当名2", ...},
                              {"name": "弁当名3", ...}
                            ]}
                            """
                        ]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 1.5,
                "topK": 200,
                "topP": 0.98,
                "maxOutputTokens": 3000,
                "candidateCount": 1
            ]
        ]
        
        guard let url = URL(string: "\(baseURL)?key=\(apiKey)") else {
            print("❌ Invalid URL construction")
            throw BentoAIError.invalidURL
        }
        
        print("🌐 Making request to: \(baseURL)")
        
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
            print("❌ Network error: \(error)")
            throw BentoAIError.serverError
        }
        
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
            let aiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)
            
            guard let content = aiResponse.candidates.first?.content.parts.first?.text else {
                print("❌ No content in AI response")
                throw BentoAIError.noContent
            }
            
            print("✅ AI Response received successfully")
            print("📝 Content length: \(content.count) characters")
            
            // レスポンス内容の詳細ログ
            if content.count < 100 {
                print("📝 Full content: \(content)")
            } else {
                print("📝 Content preview: \(String(content.prefix(200)))...")
            }
            
            // レシピ解析を試行
            do {
                let recipes = try parseRecipesFromJSON(content, category: category)
                print("✅ Successfully parsed \(recipes.count) recipes")
                return recipes
            } catch {
                print("❌ Recipe parsing failed: \(error)")
                // パース失敗時はエラーをスロー
                throw BentoAIError.invalidJSON
            }
            
        } catch let decodingError {
            print("❌ JSON Decode Error: \(decodingError)")
            print("❌ Raw response data: \(String(data: data, encoding: .utf8) ?? "Unable to decode data")")
            throw BentoAIError.invalidJSON
        }
    }
    
    func generateRecipesFromIngredients(_ selectedIngredients: [Ingredient], additionalNotes: String = "") async throws -> [BentoRecipe] {
        guard !apiKey.isEmpty else {
            throw BentoAIError.apiKeyMissing
        }
        
        let prompt = createIngredientBasedPrompt(selectedIngredients, additionalNotes: additionalNotes)
        
        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        [
                            "text": """
                            あなたは優秀なお弁当レシピクリエーターです。ユーザーが提供した材料に基づいて、美味しくて実用的なお弁当の献立をデザインしてください。
                            
                            【🚨 絶対厳守: レシピ名と材料の完全一致ルール】
                            **料理名に含まれる食材・調味料は必ず材料リストに記載すること**
                            ❌ 禁止例: 「鯖のトマトハーブ」→材料に「トマト」「ハーブ」がない
                            ✅ 正解例: 「鯖のトマトハーブ」→材料に「鯖切り身」「トマト」「バジル」を記載
                            
                            【⚠️ 魚の部位について】
                            魚には「もも肉」はありません！正しい表記：
                            ✅ 鯖切り身、鮭切り身、ブリ切り身
                            ❌ 鯖もも肉、鮭もも肉（存在しない！）
                            
                            【重要】必ず3つの異なるお弁当レシピを生成してください。
                            
                            【レシピ要件】
                            1. 主菜: 正確に1つの主菜を作成（主材料の少なくとも1つを際立たせる）
                            2. 副菜: 必ず「sideDish1」と「sideDish2」という名前で2つの副菜を作成
                            3. お弁当への適合性: 全ての料理はお弁当箱に詰めやすく、常温で安全に食べられること
                            4. レシピ形式: 各料理について材料リストと簡単で実行可能な調理手順を提供
                            5. 説明: お弁当箱全体の短く魅力的な説明を提供
                            6. 言語: 全ての出力は日本語で行う
                            7. 多様性: 3つのレシピは異なる調理法・味付けで作成
                            
                            \(prompt)
                            
                            提案はJSON形式で、以下のスキーマに厳密に従ってください（必ず3つのレシピを含めてください）:
                            {"recipes": [{"name": "選択食材を使った具体的弁当名", "description": "お弁当の簡潔な説明", "mainDish": {"name": "主菜名", "ingredients": ["材料"], "instructions": ["手順"]}, "sideDish1": {...}, "sideDish2": {...}, "prepTime": 数値, "calories": 数値, "difficulty": "easy/medium/hard", "tips": ["実用的なコツ"]}, {"name": "選択食材を使った具体的弁当名2", "description": "お弁当の簡潔な説明", "mainDish": {"name": "主菜名", "ingredients": ["材料"], "instructions": ["手順"]}, "sideDish1": {...}, "sideDish2": {...}, "prepTime": 数値, "calories": 数値, "difficulty": "easy/medium/hard", "tips": ["実用的なコツ"]}, {"name": "選択食材を使った具体的弁当名3", "description": "お弁当の簡潔な説明", "mainDish": {"name": "主菜名", "ingredients": ["材料"], "instructions": ["手順"]}, "sideDish1": {...}, "sideDish2": {...}, "prepTime": 数値, "calories": 数値, "difficulty": "easy/medium/hard", "tips": ["実用的なコツ"]}]}
                            """
                        ]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 1.3,
                "topK": 100,
                "topP": 0.99,
                "maxOutputTokens": 2048
            ]
        ]
        
        guard let url = URL(string: "\(baseURL)?key=\(apiKey)") else {
            throw BentoAIError.invalidURL
        }
        
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
            print("❌ Network error: \(error)")
            throw BentoAIError.serverError
        }
        
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
            let aiResponse = try JSONDecoder().decode(GeminiResponse.self, from: data)
            
            guard let content = aiResponse.candidates.first?.content.parts.first?.text else {
                print("❌ No content in AI response")
                throw BentoAIError.noContent
            }
            
            print("✅ AI Response received successfully")
            print("📝 Content length: \(content.count) characters")
            
            // レスポンス内容の詳細ログ
            if content.count < 200 {
                print("📝 Full content: \(content)")
            } else {
                print("📝 Content preview: \(String(content.prefix(300)))...")
            }
            
            // レシピ解析を試行
            do {
                let recipes = try parseRecipesFromJSON(content, category: .omakase) // 食材ベースはおまかせカテゴリとして扱う
                print("✅ Successfully parsed \(recipes.count) recipes")
                return recipes
            } catch {
                print("❌ Recipe parsing failed: \(error)")
                // パース失敗時はエラーをスロー
                throw BentoAIError.invalidJSON
            }
            
        } catch let decodingError {
            print("❌ JSON Decode Error: \(decodingError)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("❌ Raw response data: \(responseString)")
            }
            throw BentoAIError.invalidJSON
        }
    }
    
    private func createPrompt(for category: BentoCategory, randomSeed: Int = 0, avoidRecipeNames: [String] = [], previousMainDishes: [String] = [], previousSideDishes: [String] = [], previousCookingMethods: [String] = []) -> String {
        let categoryDescription = getCategoryDescription(category)
        let currentSeason = getCurrentSeason()
        let weeklyTheme = getWeeklyTheme()
        let now = Date()
        let timestamp = Int(now.timeIntervalSince1970)
        let uniqueId = timestamp + randomSeed + abs(category.hashValue)
        
        return """
        🎲 **GENERATION_ID: \(uniqueId)** - このIDを使って完全にユニークなレシピを生成してください
        📅 タイムスタンプ: \(timestamp) | シード値: \(randomSeed)

        <thinking_process>
          1.  まず、ユーザーから与えられた<user_context>（カテゴリ、季節、テーマ）を深く理解します。
          2.  次に、提案する3つの弁当それぞれに、全く異なるユニークなコンセプトを設定します。コンセプトは<user_context>から着想を得ます。（例: 「がっつり」カテゴリなら、「韓国屋台のチーズタッカルビ風」「洋食屋さんのデミグラスハンバーグ」「中華街の黒酢豚」など）
          3.  コンセプトに基づき、主菜と副菜を具体化します。<avoid_these_recipes>にある過去のレシピとは全く異なる食材、調理法、味付けを選びます。
          4.  🚨🚨🚨 CRITICAL 🚨🚨🚨: **副菜6つ全てが完全に異なること**を確認します。同じ調理法（例：胡麻和え）や同じ食材カテゴリ（例：葉物野菜3つ）の重複は絶対に避けます。副菜は定番を避け、主菜との相性や彩り、食感の面白さを重視します。
          5.  🚨重要🚨：すべての料理名から「なし」「抜き」等の否定表現を完全に除去します。「鶏ひき肉なし」→「野菜のみ」、「ごぼうなし」→「根菜」等に置き換えます。
          6.  料理名に含まれる全ての食材・調味料が材料リストに含まれていることを確認します（例：「ロゼマリーガーリック」なら必ず「ローズマリー」「にんにく」を材料に記載）。
          7.  最後に、<absolute_rules>と<output_format>の全項目を遵守しているか、厳しく自己評価してから出力します。
        </thinking_process>

        <user_context>
          - **お弁当カテゴリ**: \(category.rawValue)
          - **カテゴリの詳細指示**: \(categoryDescription)
          - **多様性を高めるヒント**:
            - **季節**: \(currentSeason) (旬の食材を意識してください)
            - **今週の隠しテーマ**: \(weeklyTheme) (このテーマからインスピレーションを得てください)
        </user_context>

        <avoid_these_recipes>
          - **過去のレシピ名**: \(avoidRecipeNames.prefix(30).joined(separator: "、"))
          - **過去の主菜**: \(previousMainDishes.prefix(30).joined(separator: "、"))
          - **過去の副菜**: \(previousSideDishes.prefix(50).joined(separator: "、"))
        </avoid_these_recipes>

        <absolute_rules>
          1.  **多様性の最大化**: 3つのレシピの【コンセプト・主材料・調理法・味付け】は完全に異なるものにすること。
          2.  **🚨🚨🚨 CRITICAL: 副菜は9つ全て完全に異なること 🚨🚨🚨**:
              - レシピ1の副菜1、副菜2
              - レシピ2の副菜1、副菜2
              - レシピ3の副菜1、副菜2
              - **これら6つの副菜は全て異なる料理名・食材・調理法でなければなりません**
              - **例**: 「いんげんの胡麻和え」を1つ使ったら、他の副菜で「小松菜の胡麻和え」「ほうれん草の胡麻和え」など胡麻和えは一切使用禁止
              - **過去の副菜リスト**: \(previousSideDishes.prefix(50).joined(separator: "、")) ← これらは絶対に使わないこと
          3.  **レシピ名と材料の完全一致**: レシピ名に「ロゼマリーガーリック」とあれば、材料に必ず「ローズマリー」「にんにく」を記載すること。曖昧な表現（例：「特製ソース」）は避け、具体的な材料を書くこと。
          4.  **お弁当の安全性**: 生もの、汁気の多いもの、傷みやすいもの（マヨネーズを多用したサラダ等）は厳禁。すべて完全に加熱調理されたレシピのみ提案すること。
          5.  **副菜の独創性**:
              - **絶対禁止の定番副菜**: だし巻き卵、きんぴらごぼう、ほうれん草のおひたし、もやしナムル、胡麻和え全般（特に多用されやすい）
              - **推奨する副菜**: 主菜の味を引き立てる、彩りや食感が楽しいクリエイティブな副菜を提案すること。（例: パプリカのハーブマリネ、長芋のバター醤油ソテー、きのこのアヒージョ風、アボカドのチーズ焼き、ズッキーニのレモンソテー、アスパラのベーコン巻き）
          6.  **調理法の多様性**: 3つのレシピで「焼く」「炒める」「煮る」「揚げる」「蒸す」などの調理法が重複しないように工夫すること。
          7.  **魚の部位**: 魚に「もも肉」は存在しません。必ず「切り身」「フィレ」など正しい部位名を使用すること。
        </absolute_rules>

        <output_format>
          {"recipes": [
            {
              "name": "（具体的で魅力的な弁当名1）",
              "description": "（弁当全体のコンセプトが伝わる簡潔な説明）",
              "mainDish": {
                "name": "（主菜の料理名）",
                "ingredients": ["（レシピ名と完全一致する材料リスト）"],
                "instructions": ["（番号を含まない手順のテキスト配列）", "...", "よく冷ましてからお弁当箱に詰める"]
              },
              "sideDish1": {
                "name": "（独創的な副菜名1）",
                "ingredients": ["..."],
                "instructions": ["...", "よく冷ましてから詰める"]
              },
              "sideDish2": {
                "name": "（全く異なるカテゴリの独創的な副菜名2）",
                "ingredients": ["..."],
                "instructions": ["...", "よく冷ましてから詰める"]
              },
              "prepTime": "(調理時間（分）を数値で)",
              "calories": "(カロリーを数値で)",
              "difficulty": "easy/medium/hard",
              "tips": ["（調理や詰め方の実用的なコツ）"]
            },
            {
              // ... レシピ2 (レシピ1とは全く異なる内容で) ...
            },
            {
              // ... レシピ3 (レシピ1、2とは全く異なる内容で) ...
            }
          ]}
        </output_format>

        🎯 **多様性強制パラメータ（このIDを使って必ず異なるレシピを生成）**：
        - 🔑 CRITICAL: GENERATION_ID \(uniqueId) を使用して、これまでとは完全に異なる新しいレシピを生成してください
        - 📊 このリクエストは一意です - 過去の応答をキャッシュせず、新鮮なアイデアを提供してください
        - 🌸 季節のヒント: \(currentSeason)
        - 🎨 今週のテーマ: \(weeklyTheme)

        **⚠️ IMPORTANT: 必ず3つの完全に異なるコンセプトのお弁当を提案してください。JSON形式で出力し、thinking_processの内容は出力に含めないでください。**
        
        \(avoidRecipeNames.isEmpty ? "" : """

        【🚫 絶対に避けるべき過去30回分の生成履歴】
        以下は最近生成されたレシピなので、**完全に異なる組み合わせを生成してください**：

        ❌ レシピ名: \(avoidRecipeNames.prefix(30).joined(separator: "、"))
        \(previousMainDishes.isEmpty ? "" : "❌ メイン料理: \(previousMainDishes.prefix(30).joined(separator: "、"))")
        \(previousSideDishes.isEmpty ? "" : "❌ 副菜: \(previousSideDishes.prefix(50).joined(separator: "、"))")
        \(previousCookingMethods.isEmpty ? "" : "❌ 調理法: \(previousCookingMethods.joined(separator: "、"))")

        **最重要**: 上記の履歴と重複しないよう、完全に新しい組み合わせを考案してください。
        世界中には無数の料理があるので、創造性を発揮して全く異なる料理を提案してください。
        """)
        """
    }
    
    private func getSpecialInstructions(for category: BentoCategory) -> String {
        switch category {
        case .hearty:
            return """
            【🔥🔥🔥 がっつりカテゴリ特別指示 - 最優先で守ること 🔥🔥🔥】
            1. 揚げ物多様化：
               - とんかつ、メンチカツ、チキンカツ、ビーフカツ
               - 唐揚げ、竜田揚げ、ザンギ、油淋鶏
               - チーズインカツ、カレーカツ、串カツ
            2. 肉の部位超多様化：
               - 牛：カルビ、ハラミ、サーロイン、リブロース、タン
               - 豚：バラ、ロース、肩ロース、ヒレ、スペアリブ
               - 鶏：もも、むね、手羽先、手羽元、せせり
            3. 味付けの多様化（同じ味付けを連続使用しない）：
               - スタミナ系：にんにく醤油、スタミナダレ、焼肉のタレ
               - 洋風：デミグラス、バーベキューソース、ハニーマスタード
               - 中華風：油淋ソース、黒酢ソース、XO醤
               - 激辛系：韓国風ヤンニョム、四川風麻辣、ハバネロソース
            4. 高カロリー：700kcal以上
            5. 魚料理禁止
            """
            
        case .omakase:
            return """
            【🌈🌈🌈 おまかせカテゴリ特別指示 - 最優先で守ること 🌈🌈🌈】
            1. 世界の料理から自由に選択：
               - 和食：親子丼、かつ丼、天丼、そぼろ弁当
               - 洋食：オムライス、ドリア風、グラタン風
               - 中華：チンジャオロース、ホイコーロー、エビチリ
               - 韓国：プルコギ、チャプチェ、ビビンバ風
               - 東南アジア：ガパオ、ナシゴレン風、サテ
               - 中東：ケバブ風、ファラフェル風
            2. 調理法の超多様化（照り焼き・甘辛・ハーブ焼き禁止！）
            3. 食材の多様化：
               - 肉：牛・豚・鶏・ひき肉・ラム
               - 魚：白身魚・青魚・エビ・イカ・タコ
               - 野菜：季節の野菜を豊富に
            4. 3つのレシピは必ず異なる国・地域の料理
            5. カロリー：500-600kcal
            """
            
        case .simple:
            return """
            【⚡⚡⚡ 簡単弁当カテゴリ特別指示 - 最優先で守ること ⚡⚡⚡】
            1. 冷凍・缶詰・レトルト活用の多様化：
               - 冷凍：シュウマイ、春巻き、肉団子、ハンバーグ、コロッケ
               - 缶詰：ツナ、サバ、焼き鳥、コンビーフ、スパム
               - レトルト：カレー、ミートソース、中華丼の具、麻婆豆腐
            2. アレンジの多様化：
               - チーズ焼き、マヨ焼き、ケチャップ焼き
               - カレー粉まぶし、青のりまぶし、ごま油和え
               - 卵とじ、とろろかけ、おろしポン酢
            3. 市販品の活用：
               - サラダチキン、焼き豚、チャーシュー
               - 温泉卵、味付け卵、チーズかまぼこ
            4. 調理時間：5分以内
            5. 電子レンジ・トースター活用
            """
            
        case .fishMain:
            return """
            【🐟🐟🐟 魚メインカテゴリ特別指示 - 最優先で守ること 🐟🐟🐟】
            1. 魚種の超多様化：
               今回必須：かれい、ひらめ、あんこう、きんめだい、めばる、はまち、さわら、たちうお、にしん
               通常：鮭、鯖、鱈、ぶり、かじき、いわし、あじ、さんま
            2. 調理法の多様化（同じ調理法を連続で使わない）：
               - 煮物：煮付け、味噌煮、梅煮、甘露煮、佃煮
               - 焼物：幽庵焼き、粕漬け焼き、山椒焼き、塩麹焼き
               - 揚物：竜田揚げ、天ぷら、フライ、唐揚げ
               - 蒸物：酒蒸し、野菜巻き蒸し、ホイル蒸し
               - その他：南蛮漬け、エスカベッシュ、ムニエル、アクアパッツァ風
            3. 3つのレシピで絶対に異なる調理法を使用
            4. 肉類完全禁止
            5. カロリー：550-650kcalの範囲
            """
        }
    }
    
    private func getCategoryDescription(_ category: BentoCategory) -> String {
        switch category {
        case .omakase:
            return """
            【おまかせ】世界各国の多様な料理テーマ・「○○風！」パターン禁止：

            **3つのレシピは必ず異なる世界のテーマで構成**：
            🇮🇹 地中海リゾート（トマトとバジルの鶏胸肉 + 野菜のバルサミコマリネ + モッツァレラのハーブサラダ）
            🇺🇸 アメリカンダイナー（ガーリックステーキ + コールスロー + ハニーマスタードポテト）
            🇫🇷 フランス田舎料理（豚肉のマスタード煮 + 人参グラッセ + ハーブバター野菜）
            🇲🇽 メキシカンフィエスタ（スパイシーチキン + アボカドサルサ + コーンとパプリカ炒め）
            🇮🇳 インド香辛料紀行（カレースパイス鶏 + ヨーグルトキュウリ + スパイス人参）
            🇹🇭 タイ屋台グルメ（ココナッツチキン + パクチーサラダ + タイ風春雨）
            🇩🇪 ドイツビアホール（ハーブソーセージ + ザワークラウト + ジャガイモのクミン炒め）
            🇲🇦 モロッコ異国情緒（クスクス風鶏肉 + ナッツとドライフルーツ和え + モロッコ風野菜）
            🇯🇵 日本郷土料理（地鶏の山椒焼き + 季節野菜の白和え + 地元風味付け）
            🇸🇪 北欧シンプル（サーモンのディル焼き + 根菜のシンプル煮 + さっぱりピクルス）

            🔄 世界料理メイン例：
            【地中海】: オリーブオイル鶏、トマト煮込み、ハーブグリル
            【アメリカン】: BBQポーク、ガーリックステーキ、ハニーマスタードチキン
            【フランス】: 白ワイン煮、マスタード焼き、ハーブバター炒め
            【メキシカン】: チリパウダー炒め、ライム風味、スパイシーグリル
            【インド】: カレースパイス、ガラムマサラ、タンドール風
            【タイ】: ココナッツ炒め、レモングラス風味、バジル炒め
            【ドイツ】: ハーブソーセージ、ビール煮込み、マスタード風味
            【モロッコ】: クスクス風、ナッツとスパイス、ドライフルーツ煮込み
            【日本郷土】: 山椒焼き、味噌漬け、地酒蒸し
            【北欧】: ディル風味、シンプル塩焼き、スモーク風

            ⚠️ 重要：毎回全く異なる国・地域のテーマを選択。「○○風！」は使わず自然な料理名にする。
            """
        case .hearty:
            return """
            【がっつり】ボリューム満点・多様な肉料理と揚げ物で大満足：
            
            **3つのレシピは必ず異なる肉種・部位・調理法で構成**：
            🥩 牛肉がっつり（牛カルビ焼肉丼、牛バラ肉の甘辛炒め、ビーフカツレツ、牛ロースステーキ）
            🐷 豚肉がっつり（豚バラ肉の角煮、豚ロースとんかつ、豚肩ロースの生姜焼き、豚ヒレカツ）
            🍗 鶏肉がっつり（鶏もも肉の唐揚げ、手羽先の甘辛揚げ、チキン南蛮、鶏むね肉のチーズカツ）
            
            **毎回変わる肉の部位使用**：
            🥩 牛肉部位: カルビ、バラ肉、ロース、肩ロース、もも肉、すね肉、タン
            🐷 豚肉部位: バラ肉、ロース、肩ロース、ヒレ、もも肉、スペアリブ
            🍗 鶏肉部位: もも肉、むね肉、手羽先、手羽元、ささみ、レバー、軟骨
            
            🔄 必須揚げ物バリエーション（最低1品は揚げ物を含む）：
            【定番揚げ物】: とんかつ、鶏の唐揚げ、メンチカツ、チキンカツ、串カツ
            【創作揚げ物】: チーズインハンバーグカツ、肉巻きフライ、スパイシーチキン、韓国風唐揚げ
            【和風揚げ物】: 竜田揚げ、天ぷら（肉・野菜）、かき揚げ、角煮コロッケ
            【洋風揚げ物】: ビーフカツレツ、ミラノ風カツレツ、フライドチキン、クリスピーチキン
            
            🔄 がっつり調理法ローテーション：
            【揚げる】: 唐揚げ、とんかつ、天ぷら、フライ、竜田揚げ、素揚げ
            【焼く】: ステーキ、焼肉、照り焼き、塩焼き、味噌焼き、バター焼き
            【炒める】: 回鍋肉、青椒肉絲、生姜焼き、ガーリック炒め、甘辛炒め
            【煮込む】: 角煮、煮込みハンバーグ、ビーフシチュー風、すき焼き風
            
            🔄 ガッツリ味付けバリエーション：
            【濃厚系】: デミグラスソース、濃厚味噌、とんかつソース、焼肉のタレ
            【スパイシー系】: ガーリックペッパー、スパイス揚げ、韓国風甘辛、カレー風味
            【和風濃い味】: 照り焼き、甘辛煮、味噌漬け、醤油ダレ
            【洋風こってり】: チーズ焼き、バター醤油、クリーム煮、トマト煮込み
            
            🔄 ガッツリ副菜（ボリューム重視・揚げ物禁止）：
            ❌ 副菜禁止：春巻き、コロッケ、揚げ餃子、チーズ揚げ、ミートボール、つくね（これらはメイン料理）
            ✅ 適切な副菜：
            【卵系副菜】: 厚焼き玉子、スクランブルエッグ、韓国風卵焼き、チーズオムレツ
            【野菜ボリューム副菜】: じゃがいものチーズ焼き、マカロニサラダ、野菜のバター炒め、チーズ焼き野菜
            【豆・穀物副菜】: ひよこ豆のサラダ、レンズ豆の煮込み、大豆の甘煮、玄米の炊き込み
            【根菜副菜】: さつまいものバターソテー、人参のグラッセ、里芋の煮っころがし、大根ステーキ
            
            - カロリー目安：700kcal以上で超満足
            - 必須要素：様々な部位の肉 + 揚げ物 + 濃い味付け
            - 特徴：肉の部位を変えて飽きない、揚げ物でボリューム満点
            
            ⚠️ 重要：毎回異なる肉の部位と調理法を使用。揚げ物は必ず1品以上含める。
            """
        case .fishMain:
            return """
            【魚メイン】魚類専用・肉類絶対禁止：

            **3つのレシピは必ず全く異なる魚種・調理法で構成**：

            【🚨 連続使用を避けるパターン】
            ⚠️ 前回使った調理法（西京焼き、ハーブ焼き、照り焼きなど）は今回は避ける
            ⚠️ 前回使った魚種（鮭、鯖、タラなど）は今回は避ける

            【✅ 必須：多様な魚種を使用】
            🎯 レシピ1: かれい、ひらめ、あんこう、きんめだい、めばる、はまち
            🎯 レシピ2: さわら、たちうお、にしん、ほっけ、あまだい、すずき
            🎯 レシピ3: いさき、あいなめ、むつ、かさご、めじな、ふぐ
            
            🔄 使用魚種（毎回変化・重複禁止）：
            White-fish: 鯛、たら、ひらめ、カレイ、白身魚、金目鯛
            Blue-fish: 鯖、さんま、いわし、あじ、ぶり 
            Salmon: 鮭、サーモン、鮭ハラス
            Special: かじき、まぐろ、うなぎ
            
            🔄 多様な調理法（甘辛・照り焼き・ハーブを連続使用しない）：
            和風: 塩焼き、味噌煮、煮付け、粕漬け焼き、幽庵焼き、山椒焼き
            洋風: ムニエル、アクアパッツァ風、グラタン風、パン粉焼き
            中華: 黒酢あん、豆鼓蒸し、葱油がけ、四川風
            揚げ物: フライ、天ぷら、竜田揚げ、唐揚げ、チーズフライ
            
            ⚠️ 外来語注意：「ムニエル」「ポワレ」「アクアパッツァ」「チリソース」など分かりにくい表現は避け、「バター焼き」「ハーブ焼き」「トマト煮込み」「甘辛ソース」など日本語で分かりやすく表現する
            
            🔄 テーマ別副菜（毎回変化・重複禁止）：
            【和風副菜セット】: ひじきの煮物 + ほうれん草のお浸し、きんぴらごぼう + だし巻き卵、切り干し大根 + 小松菜の胡麻和え
            【洋風副菜セット】: 彩り野菜グリル + マカロニサラダ、ブロッコリーガーリックソテー + グリーンサラダ、人参グラッセ + ポテトサラダ（少量マヨ）
            【中華・エスニック副菜セット】: ニラ玉 + もやし中華和え、きくらげ卵炒め + 青菜炒め、レンズ豆サラダ + キャロットラペ
            
            **重要**: 各レシピのテーマに合わせて副菜も統一する（和風なら和風副菜、洋風なら洋風副菜）
            
            - 絶対禁止：鶏肉・豚肉・牛肉・ひき肉・ハム・ソーセージ等すべての肉類
            - 弁当名：必ず魚名+調理法を含める（例：鯖の味噌煮弁当、鮭のムニエル弁当）
            
            ⚠️ 重要：毎回異なる魚種と調理法を使用。同じ魚料理の連続禁止。副菜は絶対に重複させない。
            """
        case .simple:
            return """
            【簡単弁当】10分以内・冷凍&缶詰&レトルト必須で超時短：

            🚨 重要：必ず冷凍食品・缶詰・レトルトを使用すること
            ❌ 普通の焼き物・炒め物は禁止（「鶏の唐揚げ」「豚の生姜焼き」などは時短ではない）

            **3つのレシピは必ず冷凍食品・缶詰・レトルトを活用**：
            ✅ 冷凍活用例：
            - 冷凍餃子のチーズ焼き
            - 冷凍シュウマイの甘酢あんかけ
            - 冷凍唐揚げのマヨソース
            - 冷凍春巻きのケチャップソース

            ✅ 缶詰活用例：
            - ツナ缶のチーズマヨ焼き
            - サバ缶の味噌チーズ
            - 焼き鳥缶の照り焼き風
            - コンビーフのハッシュ風

            ✅ レトルト活用例：
            - レトルトハンバーグのチーズ焼き
            - レトルトカレーコロッケ風
            - レトルト麻婆豆腐アレンジ
            
            🔄 超簡単メイン（5分以内・包丁不要）：
            【冷凍活用】: 冷凍餃子チーズ焼き、冷凍唐揚げマヨ、冷凍チャーハン
            【缶詰活用】: ツナ缶チーズ焼き、サバ缶味噌マヨ、焼き鳥缶照り焼き
            【レトルト活用】: レトルトカレー、ミートボール、ハンバーグ
            【レンジ活用】: ベーコンエッグ、ウインナー温め、冷凍ピラフ
            【市販品活用】: 市販唐揚げアレンジ、コンビニサラダチキン、惣菜コロッケ
            
            🔄 超簡単調理法（包丁・まな板不要）：
            【レンジだけ】: 冷凍食品温め、レトルト温め、缶詰温め
            【トースターだけ】: チーズ焼き、マヨ焼き、冷凍ピザ
            【混ぜるだけ】: 缶詰+マヨ、ふりかけご飯、混ぜ込みわかめ
            【のせるだけ】: レトルト+ご飯、缶詰+パン、冷凍食品+チーズ
            
            🔄 超簡単副菜（包丁不要・5分以内）：
            【冷凍副菜】: 冷凍枝豆、冷凍ブロッコリー、冷凍コーン
            【缶詰副菜】: コーン缶バター、ひじき缶、きんぴら缶
            【レトルト副菜】: パックサラダ、カット野菜、もずく
            【混ぜるだけ副菜】: ふりかけ和え、塩昆布和え、ごま油和え
            【市販品副菜】: カップスープ、インスタント味噌汁、パック納豆
            
            - 調理時間：合計10分以内厳守（できれば5分）
            - 許可調理法：電子レンジ・フライパン・茹でる・冷凍活用・缶詰活用
            - 禁止調理法：時間のかかる煮込み・オーブン・蒸し器使用
            
            ⚠️ 重要：時短調理を維持しながら毎回異なるテーマを選択。同じパターンの連続は絶対禁止。
            """
        }
    }
    
    private func getCategorySpecificInstructions(_ category: BentoCategory) -> String {
        let timestamp = Int(Date().timeIntervalSince1970)
        let categorySeed = category.rawValue.hashValue
        let uniqueSeed = timestamp + categorySeed
        let dailyVariation = (timestamp / 86400) % 10 // 日替わりパターン

        switch category {
        case .fishMain:
            let fishVariations = [
                ["かれい", "ひらめ", "あんこう"],
                ["きんめだい", "めばる", "はまち"],
                ["さわら", "たちうお", "にしん"],
                ["ほっけ", "あまだい", "すずき"],
                ["いさき", "あいなめ", "むつ"],
                ["かさご", "めじな", "ふぐ"],
                ["はたはた", "このしろ", "さより"]
            ]
            let cookingVariations = [
                ["煮付け", "粕漬け焼き", "竜田揚げ"],
                ["南蛮漬け", "酒蒸し", "塩焼き"],
                ["幽庵焼き", "山椒焼き", "フライ"],
                ["ムニエル", "梅煮", "天ぷら"],
                ["味噌煮", "唐揚げ", "ピカタ"],
                ["塩麹焼き", "ホイル蒸し", "チーズ焼き"],
                ["黒酢あん", "豆豉蒸し", "葱油がけ"],
                ["含め煮", "佃煮", "胡麻まぶし"],
                ["パン粉焼き", "マリネ", "甘酢漬け"]
            ]
            let selectedFishes = fishVariations[dailyVariation % fishVariations.count]
            let selectedMethods = cookingVariations[dailyVariation % cookingVariations.count]
            
            return """
            【🐟 魚メイン専用・肉類完全排除】
            - 本日の魚種：\(selectedFishes.joined(separator: "・"))から選択
            - 推奨調理：\(selectedMethods.joined(separator: "・"))から選択
            - 絶対禁止：鶏肉・豚肉・牛肉・ひき肉・ハム・ソーセージ・ベーコン
            - 必須条件：魚名を弁当名に含める、海の風味重視
            - サイド指定：海藻・貝・野菜・卵・豆腐のみ使用
            - 特徴：本格的な魚料理専門弁当
            - 変化ID：\(uniqueSeed)-\(dailyVariation)
            """
            
        case .hearty:
            let meatVariations = [
                ["牛カルビ", "豚バラ肉", "鶏もも肉"],
                ["牛ロース", "豚ロース", "手羽先"],
                ["牛バラ肉", "豚肩ロース", "鶏むね肉"],
                ["牛肩ロース", "豚ヒレ", "手羽元"],
                ["牛もも肉", "スペアリブ", "鶏レバー"],
                ["牛すね肉", "豚もも肉", "ささみ"],
                ["牛タン", "豚こま肉", "鶏軟骨"]
            ]
            let heartyMethods = [
                ["唐揚げ", "とんかつ", "ステーキ"],
                ["メンチカツ", "焼肉", "竜田揚げ"],
                ["チキンカツ", "角煮", "ビーフカツレツ"],
                ["フライドチキン", "生姜焼き", "串カツ"],
                ["天ぷら", "照り焼き", "チキン南蛮"],
                ["素揚げ", "ガーリック焼き", "味噌カツ"],
                ["かき揚げ", "バター焼き", "韓国風唐揚げ"]
            ]
            let selectedMeats = meatVariations[dailyVariation % meatVariations.count]
            let selectedMethods = heartyMethods[dailyVariation % heartyMethods.count]
            
            return """
            【🍖 がっつり専用・揚げ物＆肉づくし】
            - 本日の肉部位：\(selectedMeats.joined(separator: "・"))から選択
            - 推奨調理法：\(selectedMethods.joined(separator: "・"))から選択
            - カロリー目標：700kcal以上必須
            - 必須条件：揚げ物最低1品・こってり濃厚・ボリューム満点
            - 肉の部位：毎回異なる部位を使用（カルビ、ロース、バラ、肩ロース、ヒレ、もも、手羽など）
            - 味付け：デミグラス・とんかつソース・焼肉タレ・ガーリック・スパイス・濃厚味噌
            - 副菜も肉系：ミートボール・つくね・ソーセージ・厚焼き玉子・ポテトフライ
            - 禁止：ヘルシー・あっさり・野菜メイン・魚料理
            - 特徴：男性も大満足！揚げ物と肉の部位にこだわったスタミナ弁当
            - 変化ID：\(uniqueSeed)-\(dailyVariation)
            """
            
        case .simple:
            let quickVariations = [
                ["電子レンジ", "冷凍食品活用", "缶詰活用"],
                ["フライパン1つ", "茹でるだけ", "レトルト活用"],
                ["即席調味料", "市販ソース", "めんつゆ活用"],
                ["混ぜるだけ", "温めるだけ", "のせるだけ"]
            ]
            let quickMethods = [
                ["5分", "3ステップ", "1工程"],
                ["10分", "2ステップ", "同時調理"],
                ["8分", "ワンボウル", "レンジのみ"],
                ["6分", "切るだけ", "和えるだけ"]
            ]
            let selectedQuick = quickVariations[dailyVariation % quickVariations.count]
            let selectedMethods = quickMethods[dailyVariation % quickMethods.count]
            
            return """
            【⚡ 簡単弁当専用・超時短】
            - 本日のスタイル：\(selectedQuick.joined(separator: "・"))
            - 時短ポイント：\(selectedMethods.joined(separator: "・"))
            - 制限時間：調理開始から8分以内完成
            - 使用器具：電子レンジまたはフライパン1つのみ
            - 必須活用：冷凍食品・缶詰・レトルト・市販調味料
            - 禁止：複雑工程・長時間調理・複数器具・手作り調味料
            - 特徴：超忙しい朝でも絶対作れる弁当
            - 変化ID：\(uniqueSeed)-\(dailyVariation)
            """
            
        case .omakase:
            let omakaseVariations = [
                ["鶏の照り焼き", "豚の生姜焼き", "鮭の塩焼き"],
                ["ハンバーグ", "鶏の唐揚げ", "鯖の味噌煮"],
                ["豚カツ", "鶏の竜田揚げ", "つくね"],
                ["牛肉の甘辛炒め", "鯵の南蛮漬け", "卵焼き"]
            ]
            let classicSides = [
                ["きんぴらごぼう", "ひじきの煮物", "ほうれん草のごま和え"],
                ["人参しりしり", "ブロッコリーの胡麻和え", "もやしのナムル"],
                ["玉子焼き", "厚揚げの煮物", "小松菜のおひたし"],
                ["だし巻き卵", "人参のきんぴら", "ブロッコリーの塩茹で"]
            ]
            let selectedMains = omakaseVariations[dailyVariation % omakaseVariations.count]
            let selectedSides = classicSides[dailyVariation % classicSides.count]
            
            return """
            【🍱 おまかせ専用・定番家庭料理】
            - 本日のメイン：\(selectedMains.joined(separator: "・"))から選択
            - 推奨サイド：\(selectedSides.joined(separator: "・"))から選択
            - 調理法：家庭的で馴染みのある基本的な調理法のみ
            - 必須条件：誰でも作れる・馴染みの味・温かみのある仕上がり
            - 特徴：昔ながらの日本の家庭の味、お母さんの手作り弁当
            - 禁止：珍しい食材・複雑な調理法・創作料理・フュージョン料理
            - 目標：「いつものお弁当」の安心感と美味しさ
            - 変化ID：\(uniqueSeed)-\(dailyVariation)
            """
        }
    }
    
    private func parseRecipesFromJSON(_ jsonString: String, category: BentoCategory) throws -> [BentoRecipe] {
        // 🔍 ENHANCED LOGGING: Complete raw API response
        print(String(repeating: "=", count: 80))
        print("🔍 RAW API RESPONSE - START")
        print(String(repeating: "=", count: 80))
        print(jsonString)
        print(String(repeating: "=", count: 80))
        print("🔍 RAW API RESPONSE - END")
        print(String(repeating: "=", count: 80))

        let cleanedJSON = extractJSON(from: jsonString)

        print("🧹 Cleaned JSON length: \(cleanedJSON.count) characters")
        print("🧹 CLEANED JSON - START")
        print(cleanedJSON)
        print("🧹 CLEANED JSON - END")

        guard let data = cleanedJSON.data(using: .utf8) else {
            throw BentoAIError.invalidJSON
        }

        let aiRecipesResponse: AIRecipeResponse
        do {
            aiRecipesResponse = try JSONDecoder().decode(AIRecipeResponse.self, from: data)
            print("✅ JSON decoded successfully")
        } catch {
            print("❌ JSON decode error: \(error)")
            print("❌ Failed JSON: \(cleanedJSON)")
            throw BentoAIError.invalidJSON
        }

        guard !aiRecipesResponse.recipes.isEmpty else {
            print("❌ No recipes found in response")
            throw BentoAIError.noContent
        }

        print("🍱 Converting \(aiRecipesResponse.recipes.count) AI recipes to BentoRecipe format")

        // 🚨 VALIDATION: Collect all side dishes to check for duplicates
        var allSideDishes: [String] = []
        var validationErrors: [String] = []

        for (index, aiRecipe) in aiRecipesResponse.recipes.enumerated() {
            print("\n🔍 Validating Recipe \(index + 1): \(aiRecipe.name)")

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
                print(error)
            }

            // Collect all side dishes
            allSideDishes.append(aiRecipe.sideDish1.name)
            allSideDishes.append(aiRecipe.sideDish2.name)
        }

        // 🚨 CRITICAL VALIDATION: Check for duplicate side dishes across all recipes
        print("\n🔍 Checking for duplicate side dishes across all \(aiRecipesResponse.recipes.count) recipes:")
        print("All side dishes: \(allSideDishes)")

        let sideDishCounts = Dictionary(grouping: allSideDishes, by: { $0 }).mapValues { $0.count }
        for (dish, count) in sideDishCounts where count > 1 {
            let error = "⚠️ 副菜が重複: 「\(dish)」が\(count)回出現"
            validationErrors.append(error)
            print(error)
        }

        // 🚨 CRITICAL VALIDATION: Check for similar cooking methods across all side dishes
        let cookingMethods = allSideDishes.map { extractCookingMethod($0) }.filter { !$0.isEmpty }
        let methodCounts = Dictionary(grouping: cookingMethods, by: { $0 }).mapValues { $0.count }
        for (method, count) in methodCounts where count > 1 {
            let warning = "⚠️ 調理法が重複: 「\(method)」が\(count)回出現"
            validationErrors.append(warning)
            print(warning)
        }

        // Print validation summary
        if !validationErrors.isEmpty {
            print("\n❌ VALIDATION ERRORS DETECTED (\(validationErrors.count) issues):")
            for error in validationErrors {
                print("  - \(error)")
            }
            print("\n🚨 CRITICAL: Rejecting invalid recipes - API must regenerate")

            // バリデーションエラーがある場合はエラーを投げる
            throw BentoAIError.invalidRecipeContent
        } else {
            print("\n✅ All validation checks passed!")
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

        print("✅ Successfully converted to \(bentoRecipes.count) BentoRecipe objects")
        return bentoRecipes
    }

    // Helper function to validate dish name matches ingredients
    private func validateDishNameMatchesIngredients(dishName: String, ingredients: [String], dishType: String) -> [String] {
        var errors: [String] = []

        // Extract ingredient keywords from dish name
        let keywords = extractIngredientsFromName(dishName)

        print("  \(dishType) '\(dishName)' - キーワード: \(keywords)")

        for keyword in keywords {
            let found = ingredients.contains { ingredient in
                ingredient.contains(keyword) || keyword.contains(ingredient)
            }

            if !found {
                errors.append("「\(dishName)」に「\(keyword)」が含まれているが、材料リストに見つかりません")
                print("    ❌ Missing: \(keyword)")
            } else {
                print("    ✅ Found: \(keyword)")
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
        let _ = selectedIngredients.filter { $0.category == .seasonings }
        
        let timestamp = Int(Date().timeIntervalSince1970)
        let randomSeed = Int.random(in: 100000...999999)
        let uniqueId = timestamp + randomSeed
        
        return """
        提供された材料:
        - 主材料: \(mainProteins.map { $0.name }.joined(separator: "・"))
        - 野菜材料: \(vegetables.map { $0.name }.joined(separator: "・"))
        - 追加要望: \(additionalNotes.isEmpty ? "なし" : additionalNotes)
        
        【レシピ要件】
        1. 主菜: 正確に1つの主菜を作成（主材料の少なくとも1つを際立たせる）
        2. 副菜: 必ず「sideDish1」と「sideDish2」という名前で2つの副菜を作成
        3. お弁当への適合性: 全ての料理はお弁当箱に詰めやすく、常温で安全に食べられること
        4. レシピ形式: 各料理について材料リストと簡単で実行可能な4ステップの調理手順を提供
        5. 説明: お弁当箱全体の短く魅力的な説明を提供
        6. 言語: 全ての出力は日本語で行う
        
        【4番目のステップの例】「よく冷ましてからお弁当箱に彩りよく詰めます。」
        
        【必須JSON形式】
        {"recipes": [{"name": "選択食材を使った具体的弁当名", "description": "お弁当の簡潔な説明", "mainDish": {"name": "主菜名", "ingredients": ["材料"], "instructions": ["4ステップ"]}, "sideDish1": {...}, "sideDish2": {...}, "prepTime": 数値, "calories": 数値, "difficulty": "easy/medium/hard", "tips": ["実用的なコツ"]}]}
        
        選択食材を活用したお弁当プランを生成してください。
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