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
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash-latest:generateContent"
    
    func generateBentoRecipes(for category: BentoCategory, randomSeed: Int = 0, avoidRecipeNames: [String] = []) async throws -> [BentoRecipe] {
        print("🔄 Starting AI recipe generation for category: \(category.rawValue)")
        print("🔑 API Key status: \(apiKey.isEmpty ? "MISSING" : "AVAILABLE (length: \(apiKey.count))")")
        
        guard !apiKey.isEmpty else {
            print("❌ API Key is missing")
            throw BentoAIError.apiKeyMissing
        }
        
        let prompt = createPrompt(for: category, randomSeed: randomSeed, avoidRecipeNames: avoidRecipeNames)
        
        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        [
                            "text": """
                            あなたは創造的で知識豊富な料理家です。ユーザーが毎回新鮮な驚きを感じるような、ユニークで多様なお弁当レシピを必ず3つ提案してください。**毎回、全く異なる視点からレシピを考案し、ありふれた組み合わせや以前の提案に囚われないでください。**
                            
                            【🚨 絶対厳守: レシピ名と材料の完全一致ルール】
                            **料理名に含まれる食材・調味料は必ず材料リストに記載すること**
                            
                            【🔥 CRITICAL BUG FIX: 以下のミスは絶対に禁止】
                            ❌ 禁止例: 「鯖のトマトハーブ」→材料に「トマト」「ハーブ」がない
                            ❌ 禁止例: 「牛肉のわさび醤油」→材料にわさびなし
                            ❌ 禁止例: 「豚肉のりんごバルサミコ」→材料にりんごなし  
                            ❌ 禁止例: 「鶏肉のハーブ焼き」→材料にハーブなし
                            ❌ 禁止例: 「鮭のハーブクラスト」→材料にハーブなし
                            ❌ 禁止例: 「豚肉のスパイス炒め」→材料にスパイスなし
                            ❌ 禁止例: 「鯖もも肉」（鯖は魚！もも肉はない！）
                            
                            ✅ 正解例: 「鯖のトマトハーブ」→材料に「鯖切り身」「トマト」「ハーブ（バジル、オレガノなど）」を記載
                            ✅ 正解例: 「牛肉のわさび醤油」→材料に「牛肉」「わさび」「醤油」を記載
                            ✅ 正解例: 「豚肉のりんごバルサミコ」→材料に「豚肉」「りんご」「バルサミコ酢」を記載
                            ✅ 正解例: 「鮭のハーブクラスト」→材料に「鮭」「ハーブ（パセリ、ローズマリーなど）」「パン粉」を記載
                            
                            【⚠️ 魚の部位について】
                            魚には「もも肉」はありません！正しい表記：
                            ✅ 鯖切り身、鮭切り身、ブリ切り身、タラ切り身
                            ❌ 鯖もも肉、鮭もも肉（存在しない！）
                            
                            【🔥 CRITICAL: 必ず3つの異なるテーマのレシピを生成】
                            ✅ レシピ1: 和風テーマ（伝統的な日本の調理法と味付け）
                            ✅ レシピ2: 洋風テーマ（西洋の調理法とハーブ・スパイス）  
                            ✅ レシピ3: 中華・エスニックテーマ（アジアの調理法と香辛料）
                            
                            【🔥 CRITICAL: 絶対に守るルール】
                            1. **実在する食材と明確な料理名**:
                               - レシピ名や説明には、**実在する一般的な食材のみを使用してください。** 架空の食材や一般的でない部位（例：玉ねぎの葉）は絶対に使用しないでください。
                               - 料理名は日本語で分かりやすく、誤解を招かない表現を使用してください。
                               - ❌ 「ソイ焼き」（豆乳と誤解される）→ ✅ 「醤油焼き」「生姜醤油焼き」
                               - ❌ 「タプナード」（不明瞭）→ ✅ 「オリーブ炒め」「地中海風炒め」
                               - 弁当名に「鶏肉のオリーブ炒め」と記載したら、材料に「鶏もも肉」「オリーブ」を含める
                               - 弁当名に「豚肉のマスタード焼き」と記載したら、材料に「豚ロース」「粒マスタード」を含める
                               - 弁当名に「鮭の生姜醤油焼き」と記載したら、材料に「鮭」「生姜」「醤油」を含める
                               - 弁当名に「鮭のハーブクラスト」と記載したら、材料に「鮭」「ハーブ（パセリ、ローズマリーなど）」「パン粉」を含める
                               - 弁当名に「チキンのスパイス焼き」と記載したら、材料に「鶏肉」「スパイス（カレー粉、クミンなど）」を含める
                               - 特殊な調味料や特徴的な材料は必ず材料リストに記載する
                               - カタカナ表記の外来語調味料は避け、日本語で分かりやすい表現を使用する
                               
                            【🔥 CRITICAL: 料理名検証チェックリスト】
                            生成前に以下を必ずチェック：
                            ✅ 料理名に含まれるすべての食材が材料リストにあるか？
                            ✅ 料理名に含まれるすべての調味料が材料リストにあるか？
                            ✅ 料理名に含まれるすべての調理法に対応する材料があるか？
                            ✅ 「ハーブ」「スパイス」などの抽象的な表現を具体的な材料に変換したか？
                            ✅ 魚料理の場合、正しい部位名を使用しているか？（「切り身」であり「もも肉」ではない）
                            
                            【⚠️ 最終確認: 料理名の単語と材料の完全一致】
                            例：「鯖のトマトハーブ」の場合
                            - 「鯖」→ 材料に「鯖切り身」が必要
                            - 「トマト」→ 材料に「トマト」が必要
                            - 「ハーブ」→ 材料に「バジル」「オレガノ」などの具体的ハーブが必要
                            
                            2. **多様性**:
                               - 週の中で料理の種類、調理法（焼く、炒める、煮る、揚げるなど）、味付け（和風、洋風、中華、エスニックなど）に**最大限の変化**をつけ、毎回新鮮な気持ちで楽しめるようなレシピにしてください。同じような料理が続かないように注意してください。
                               - 前回と異なる肉/魚を使用（鶏肉→豚肉→魚→牛肉の順で変化）
                               - 前回と異なる調理法（焼く→炒める→揚げる→煮るの順で変化）
                               - 前回と異なる味付け（和風→洋風→中華→エスニックの順で変化）
                            
                            3. 【🔥 副菜の多様性を強制的に確保・ローテーション排除】：
                               - 同じ弁当内で副菜2品は絶対に重複禁止
                               - 3つのレシピ全体でも副菜の重複は最小限に抑制
                               - 毎回全く新しい副菜組み合わせを必ず生成（ローテーション禁止）
                               - 定番副菜（ひじきの煮物、いんげんの胡麻和え、ほうれん草のお浸し、きんぴらごぼう、だし巻き卵）の過度な使用を避ける
                               - 副菜は以下の豊富なカテゴリから予想外の組み合わせを選択：
                                 ★ 葉物野菜: ほうれん草のお浸し、小松菜の胡麻和え、白菜の浅漬け、水菜のサラダ、春菊の胡麻和え、菜の花の辛子和え、チンゲン菜の炒め物、レタスの炒め物
                                 ★ 根菜類: きんぴらごぼう、人参しりしり、大根の煮物、蓮根のきんぴら、さつまいもの甘煮、里芋の煮っころがし、牛蒡の照り焼き、人参グラッセ
                                 ★ こんにゃく系: こんにゃくの煮物、糸こんにゃくの炒め物、しらたきのピリ辛炒め、こんにゃくの味噌田楽、しらたきの明太子炒め
                                 ★ 卵・揚げ物系: だし巻き卵、卵の味噌漬け、厚揚げの煮物、がんもどきの煮物、スクランブルエッグ、厚揚げの甘辛炒め
                                 ★ 海藻・山菜: ひじきの煮物、わかめの酢の物、きくらげの中華炒め、昆布の佃煮、もずくの天ぷら、海苔の佃煮、わかめスープ
                                 ★ きのこ類: しいたけの甘辛煮、エリンギのバター炒め、えのきの和え物、まいたけの天ぷら、きくらげの卵炒め、しめじのソテー、なめこおろし
                                 ★ いも類: 里芋の煮っころがし、じゃがいもの金平、長芋の梅和え、さつまいもの甘辛炒め、じゃがいものガレット
                                 ★ 豆類: いんげんの胡麻和え、枝豆のペペロンチーノ、金時豆の甘煮、スナップエンドウの塩炒め、そら豆の塩茹で、絹さやの炒め物
                                 ★ その他創意工夫: オクラの梅和え、ズッキーニの炒め物、アスパラのベーコン巻き、ピーマンの塩昆布炒め、茄子の揚げ浸し、かぼちゃサラダ
                            
                            4. **安全性と適合性**:
                               - 献立は、お弁当に適しており、食中毒のリスクが低いものにしてください。
                               - 以下の種類の料理は**絶対に避けてください**:
                                 - 汁気が多いもの（例：もずく酢、スープ類）
                                 - 生ものや加熱が不十分なもの（例：生の豆腐（冷奴など）、刺身、半熟卵など）。お弁当として安全に持ち運べないものは厳禁です。
                                 - 傷みやすいもの（例：マヨネーズを多用したポテトサラダなど）
                                 - お弁当箱に詰めにくかったり、他の料理に影響を与えやすいもの。
                               - **必ず加熱調理**され、冷めても美味しく、お弁当箱に詰めやすいものを選んでください。
                            
                            5. **手順の記載ルール**:
                               - instructions配列には手順のテキストのみを記載
                               - ❌ 禁止例: ["1. 鮭に塩を振る", "2. フライパンで焼く"]
                               - ✅ 正解例: ["鮭に塩を振る", "フライパンで焼く"]
                               - 番号は表示時に自動で付与されるため、手順テキストには番号を含めない
                            
                            \(prompt)
                            
                            【必須JSON形式 - 必ず3つのレシピを含む】
                            {"recipes": [
                              {
                                "name": "具体的料理名弁当1", 
                                "description": "簡潔な説明", 
                                "mainDish": {
                                  "name": "料理名", 
                                  "ingredients": ["料理名に含まれるすべての食材・調味料を必ず含む完全リスト（例：料理名が「牛肉のわさび醤油」なら「牛肉」「わさび」「醤油」を必須記載）"], 
                                  "instructions": ["手順のテキストのみ（番号なし）", "手順のテキストのみ（番号なし）", "手順のテキストのみ（番号なし）", "よく冷ましてからお弁当箱に詰める"]
                                }, 
                                "sideDish1": {
                                  "name": "副菜名1", 
                                  "ingredients": ["材料リスト"], 
                                  "instructions": ["手順1", "手順2", "手順3", "冷ましてお弁当箱に詰める"]
                                }, 
                                "sideDish2": {
                                  "name": "副菜名2", 
                                  "ingredients": ["材料リスト"], 
                                  "instructions": ["手順1", "手順2", "手順3", "冷ましてお弁当箱に詰める"]
                                }, 
                                "prepTime": 数値, 
                                "calories": 数値, 
                                "difficulty": "easy/medium/hard", 
                                "tips": ["実用的なコツ"]
                              },
                              {
                                "name": "具体的料理名弁当2", 
                                "description": "簡潔な説明", 
                                "mainDish": {
                                  "name": "料理名", 
                                  "ingredients": ["詳細リスト"], 
                                  "instructions": ["手順1", "手順2", "手順3", "よく冷ましてからお弁当箱に詰める"]
                                }, 
                                "sideDish1": {
                                  "name": "副菜名1", 
                                  "ingredients": ["材料リスト"], 
                                  "instructions": ["手順1", "手順2", "手順3", "冷ましてお弁当箱に詰める"]
                                }, 
                                "sideDish2": {
                                  "name": "副菜名2", 
                                  "ingredients": ["材料リスト"], 
                                  "instructions": ["手順1", "手順2", "手順3", "冷ましてお弁当箱に詰める"]
                                }, 
                                "prepTime": 数値, 
                                "calories": 数値, 
                                "difficulty": "easy/medium/hard", 
                                "tips": ["実用的なコツ"]
                              },
                              {
                                "name": "具体的料理名弁当3", 
                                "description": "簡潔な説明", 
                                "mainDish": {
                                  "name": "料理名", 
                                  "ingredients": ["詳細リスト"], 
                                  "instructions": ["手順1", "手順2", "手順3", "よく冷ましてからお弁当箱に詰める"]
                                }, 
                                "sideDish1": {
                                  "name": "副菜名1", 
                                  "ingredients": ["材料リスト"], 
                                  "instructions": ["手順1", "手順2", "手順3", "冷ましてお弁当箱に詰める"]
                                }, 
                                "sideDish2": {
                                  "name": "副菜名2", 
                                  "ingredients": ["材料リスト"], 
                                  "instructions": ["手順1", "手順2", "手順3", "冷ましてお弁当箱に詰める"]
                                }, 
                                "prepTime": 数値, 
                                "calories": 数値, 
                                "difficulty": "easy/medium/hard", 
                                "tips": ["実用的なコツ"]
                              }
                            ]}
                            
                            🔥 CRITICAL: 必ず3つの異なるレシピを生成してください。1つや2つではなく、必ず3つです。
                            
                            【🔍 最終チェック必須】生成前に必ず確認：
                            ✅ 料理名「○○の××」→材料に「○○」「××」が記載されているか？
                            ✅ 例：「牛肉のわさび醤油」→材料に「牛肉」「わさび」「醤油」があるか？
                            ✅ 例：「豚肉のりんごバルサミコ」→材料に「豚肉」「りんご」「バルサミコ酢」があるか？
                            ✅ 例：「鯖のトマトハーブ」→材料に「鯖切り身」「トマト」「バジル（またはオレガノなど）」があるか？
                            ❌ 料理名に記載した食材が材料にない場合は、絶対に修正してから出力すること
                            ❌ 魚に「もも肉」という部位は存在しません！必ず「切り身」と記載すること
                            """
                        ]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 1.0,
                "topK": 30,
                "topP": 0.95,
                "maxOutputTokens": 2500
            ]
        ]
        
        guard let url = URL(string: "\(baseURL)?key=\(apiKey)") else {
            print("❌ Invalid URL construction")
            throw BentoAIError.invalidURL
        }
        
        print("🌐 Making request to: \(baseURL)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
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
                "temperature": 0.7,
                "topK": 40,
                "topP": 0.95,
                "maxOutputTokens": 2048
            ]
        ]
        
        guard let url = URL(string: "\(baseURL)?key=\(apiKey)") else {
            throw BentoAIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
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
    
    private func createPrompt(for category: BentoCategory, randomSeed: Int = 0, avoidRecipeNames: [String] = []) -> String {
        let categoryDescription = getCategoryDescription(category)
        let now = Date()
        let timestamp = Int(now.timeIntervalSince1970)
        let safeRandomSeed = randomSeed % 100000  // 値を制限
        let safeCategoryHash = abs(category.hashValue) % 100000  // 値を制限
        let uniqueId = (timestamp % 1000000) + safeRandomSeed + safeCategoryHash
        let categorySpecificInstructions = getCategorySpecificInstructions(category)
        let dailyRotation = (timestamp / 86400) % 7 // 曜日ローテーション
        
        return """
        \(categoryDescription)
        
        \(categorySpecificInstructions)
        
        【レシピ要件】
        ✅ 3つのレシピは異なる調理法・食材・味付けで多様性を確保
        ✅ 具体的主菜名入り弁当名（抽象名は禁止）
        ✅ 家庭で再現可能な実用的なレシピ
        ✅ お弁当に適した安全で美味しい料理
        ✅ 毎回新鮮な気持ちで楽しめる内容
        
        【避けるべき内容】
        ❌ 他カテゴリとの重複・類似
        ❌ 抽象的弁当名（「バランス弁当」「ヘルシー弁当」等）
        ❌ 同じような調理法の重複（照り焼き×3等）
        ❌ 副菜の重複（同じ弁当内で重複、3つのレシピ間での過度な重複）
        ❌ 生もの・汁物・傷みやすい食材
        ❌ 珍しすぎる食材や複雑すぎる調理法
        
        【必須JSON形式】
        {"recipes": [{"name": "具体的主菜名弁当", "description": "簡潔な説明", "mainDish": {"name": "料理名", "ingredients": ["材料リスト"], "instructions": ["4ステップ手順"]}, "sideDish1": {...}, "sideDish2": {...}, "prepTime": 数値, "calories": 数値, "difficulty": "easy/medium/hard", "tips": ["実用的なコツ"]}]}
        
        【🔥 副菜重複防止・強制多様化・ローテーション排除】
        - 同じ弁当内で副菜2品は絶対に重複禁止（例：「いんげんの胡麻和え」と「なすの味噌田楽」は必ず異なる副菜）
        - 3つのレシピ全体でも副菜の重複は最小限（できれば全て異なる副菜を使用）
        - 副菜は異なるカテゴリから選択（葉物・根菜・こんにゃく・卵揚げ物・海藻・きのこ・豆類など）
        - ⚠️ 定番副菜ローテーション禁止：「ひじきの煮物」「いんげんの胡麻和え」「ほうれん草のお浸し」「きんぴらごぼう」「だし巻き卵」「蓮根のきんぴら」の繰り返し使用を避ける
        - ✅ 創意工夫副菜推奨：「オクラの梅和え」「ズッキーニの炒め物」「チンゲン菜の炒め物」「なめこおろし」「しらたきの明太子炒め」「人参グラッセ」「茄子の揚げ浸し」など予想外の副菜を積極採用
        
        【重要】完全に新しいレシピを生成してください。前回と異なるメイン料理、副菜、調理法を使用してください。
        
        🎲 多様性強制パラメータ（このIDを使って必ず異なるレシピを生成）：
        - ランダム化ID: \(uniqueId)
        - 曜日ローテーション: \(dailyRotation)  
        - カテゴリシード: \(category.hashValue)
        - タイムスタンプ: \(timestamp)
        - 追加シード: \(randomSeed)
        
        【🎯 必須多様化ルール - 絶対遵守】
        1. **メイン食材の強制ローテーション**: 鶏肉→豚肉→魚→牛肉の順で変化
        2. **調理法の強制変更**: 焼く→炒める→揚げる→煮る→蒸す→グリルの順で変化
        3. **味付けの強制変更**: 醤油系→塩系→味噌系→洋風→中華→エスニックの順で変化
        4. **副菜系統の強制変更**: 和風→洋風→中華→エスニック→創作の順で変化
        
        【🔥 完全新規レシピ強制指令 - ウェブアプリ成功パターン適用】
        
        **各レシピに必ず異なるテーマを割り当て**：
        🎯 レシピ1: 和風テーマ（塩焼き、西京焼き、味噌煮、照り焼きなど）+ 和風副菜
        🎯 レシピ2: 洋風テーマ（ハーブ焼き、バター焼き、トマト煮込み、レモンソテーなど）+ 洋風副菜  
        🎯 レシピ3: 中華・エスニックテーマ（甘酢あん、甘辛ソース、カレー風味、ガーリック炒めなど）+ アジアン副菜
        
        **毎回強制的に変更する要素**：
        ✅ 3つのレシピは必ず異なるテーマ（和・洋・中華/エスニック）
        ✅ 調理法を必ず変える（焼く→蒸す→揚げる、煮る→炒める→グリル）
        ✅ 魚種を必ず変える（鮭→アジ→カジキ、鯖→タラ→ブリなど）
        ✅ 副菜カテゴリを必ず変える（根菜→葉物→海藻、卵→きのこ→豆類）
        ✅ 味付けベースを必ず変える（醤油ベース→塩ベース→味噌ベース→オイルベース）
        
        **創造性発揮例**：
        - 「鮭の西京焼き + ひじき煮物 + ほうれん草お浸し」（和風）
        - 「カジキのハーブグリル + 野菜グリル + マカロニサラダ」（洋風）  
        - 「ブリの甘辛照り焼き + ニラ玉 + もやし中華和え」（中華風）
        
        ⚠️ 毎回このような多様性のある3テーマ構成で生成してください。
        
        \(avoidRecipeNames.isEmpty ? "" : """
        
        【🚫 絶対に避けるべき前回のレシピ名】
        以下のレシピ名は前回生成されたものなので、**絶対に同じ名前や類似名を避けてください**：
        \(avoidRecipeNames.map { "❌ \($0)" }.joined(separator: "\n"))
        
        **重要**: 上記のレシピと同じまたは類似する名前は絶対に生成しないでください。全く新しい料理名を考案してください。
        """)
        """
    }
    
    private func getCategoryDescription(_ category: BentoCategory) -> String {
        switch category {
        case .omakase:
            return """
            【おまかせ】毎回全く異なる世界の料理テーマ：
            
            **3つのレシピは必ず異なる世界のテーマで構成**：
            🌏 レシピ1: エスニック・アジアンテーマ（鶏のココナッツカレー炒め + 春雨エスニックサラダ + フルーツ串）
            🇯🇵 レシピ2: 和食の基本テーマ（鮭の塩焼き + ひじき煮物 + ほうれん草お浸し）
            🇮🇹 レシピ3: 洋食・イタリアンテーマ（鶏のハーブグリル + ラタトゥイユ + チーズ&フルーツ）
            
            **または**：
            🇨🇳 中華テーマ（青椒肉絲 + 卵焼き + ザーサイ）
            🍳 揚げ物テーマ（鶏唐揚げ + だし巻き卵 + きんぴらごぼう）
            🥩 贅沢テーマ（牛肉串焼き + きのこソテー + ミニキッシュ）
            🌿 ヘルシーテーマ（鶏照り焼き + ブロッコリー胡麻和え + 焼きおにぎり）
            
            🔄 テーマ別メイン料理例：
            【エスニック】: 鶏ココナッツカレー炒め、豚肉のパクチー炒め、海老のスイートチリ炒め
            【和食基本】: 鮭の塩焼き、鯖の味噌煮、鶏の照り焼き、豚の生姜焼き
            【洋食】: 鶏のハーブグリル、ハンバーグ、豚のマスタード焼き、牛肉のガーリック炒め  
            【中華】: 青椒肉絲、酢豚、麻婆豆腐、回鍋肉
            【揚げ物】: 鶏の唐揚げ、豚カツ、アジフライ、エビフライ
            【贅沢】: 牛肉串焼き、ローストチキン、鯛の煮付け
            【ヘルシー】: 蒸し鶏、豆腐ハンバーグ、野菜炒め
            
            🔄 テーマ別副菜セット：
            【エスニック副菜】: 春雨エスニックサラダ + フルーツ串、パクチーサラダ + エスニック和え物
            【和食副菜】: ひじき煮物 + ほうれん草お浸し、きんぴらごぼう + だし巻き卵
            【洋食副菜】: ラタトゥイユ + チーズ&フルーツ、野菜グリル + マカロニサラダ
            【中華副菜】: 卵焼き + ザーサイ、もやしナムル + 中華風キュウリ
            【揚げ物副菜】: だし巻き卵 + きんぴらごぼう、ひじき煮物 + 野菜炒め
            【贅沢副菜】: きのこソテー + ミニキッシュ、アスパラ巻き + 彩り野菜
            【ヘルシー副菜】: ブロッコリー胡麻和え + 焼きおにぎり、蒸し野菜 + 豆サラダ
            
            ⚠️ 重要：毎回全く異なるテーマを必ず選択し、同じような組み合わせは絶対に避ける。
            """
        case .hearty:
            return """
            【がっつり】ボリューム満点・多様なテーマで満足感：
            
            **3つのレシピは必ず異なるテーマで構成（ボリューム感を維持）**：
            💪 スタミナ満点（豚肉の生姜焼き丼 + ニラ玉 + 鶏肉とカシューナッツ炒め）
            🌿 ヘルシーがっつり（鶏むね肉のハーブグリル + カラフルピクルス + ひじきの梅風味和え）
            🇯🇵 和風がっつり（鮭の塩焼き + きんぴらごぼう + ほうれん草のおひたし）
            
            **または**：
            🌍 エスニックがっつり（タンドリーチキン + レンズ豆のカレー風味 + 紫キャベツコールスロー）
            🇨🇳 中華がっつり（回鍋肉 + 卵焼き + 春雨サラダ）
            🇮🇹 洋食がっつり（鶏のトマト煮込み + ブロッコリーガーリック炒め + きのこソテー）
            🌱 シンプルがっつり（鶏の照り焼き + だし巻き卵 + 焼きピーマン甘辛和え）
            
            🔄 テーマ別がっつりメイン（高カロリー・満足感重視）：
            【スタミナ満点】: 豚の生姜焼き丼、牛焼肉丼、鶏の唐揚げ、豚カツ
            【ヘルシーがっつり】: 鶏むね肉のハーブグリル、鮭のガーリック焼き、豆腐ステーキ
            【和風がっつり】: 鮭の塩焼き、鶏の照り焼き、豚の角煮、牛肉のしぐれ煮
            【エスニックがっつり】: タンドリーチキン、ガパオライス、カレー炒め、スパイス焼き
            【中華がっつり】: 回鍋肉、青椒肉絲、麻婆豆腐、酢豚
            【洋食がっつり】: 鶏のトマト煮込み、ハンバーグ、ビーフステーキ、ポークソテー
            【シンプルがっつり】: 鶏の照り焼き、豚の塩焼き、牛肉の醤油炒め
            
            🔄 テーマ別がっつり副菜（ボリューム感とバランス重視）：
            【スタミナ副菜】: ニラ玉 + 鶏肉とカシューナッツ炒め、豚肉炒め + ボリューム卵料理
            【ヘルシー副菜】: カラフルピクルス + ひじきの梅風味和え、野菜グリル + 豆サラダ
            【和風副菜】: きんぴらごぼう + ほうれん草のおひたし、ひじき煮物 + だし巻き卵
            【エスニック副菜】: レンズ豆のカレー風味 + 紫キャベツコールスロー、スパイス野菜 + ナッツサラダ
            【中華副菜】: 卵焼き + 春雨サラダ、ニラ玉 + もやしナムル
            【洋食副菜】: ブロッコリーガーリック炒め + きのこソテー、野菜グリル + マカロニサラダ
            【シンプル副菜】: だし巻き卵 + 焼きピーマン甘辛和え、きんぴら + 野菜炒め
            
            - カロリー目安：650kcal以上でガッツリ満足
            - 調理法：揚げ物・炒め物・焼き物・煮込み・グリル
            - 特徴：ボリューム重視でも多様なテーマで飽きない
            - 副菜特徴：がっつりメインを支える多彩な副菜でバランス調整
            
            ⚠️ 重要：ボリューム感を維持しながら毎回異なるテーマを選択。同じパターンの連続は絶対禁止。
            """
        case .fishMain:
            return """
            【魚メイン】魚類専用・肉類絶対禁止：
            
            **3つのレシピは必ず異なるテーマで構成**：
            🎯 和風魚料理（1レシピ）: 鮭の西京焼き、鯖の味噌煮、アジの塩焼き、タラの煮付け
            🎯 洋風魚料理（1レシピ）: カジキのハーブグリル、鮭のムニエル、タラのトマト煮込み、ブリのレモンソテー
            🎯 中華・エスニック魚料理（1レシピ）: ブリの甘辛照り焼き、鯖の黒酢あん、アジの南蛮漬け、カジキのカレー風味焼き
            
            🔄 使用魚種（毎回変化・重複禁止）：
            White-fish: 鯛、たら、ひらめ、カレイ、白身魚、金目鯛
            Blue-fish: 鯖、さんま、いわし、あじ、ぶり 
            Salmon: 鮭、サーモン、鮭ハラス
            Special: かじき、まぐろ、うなぎ
            
            🔄 ローテーション必須調理法（毎回変化・分かりやすい日本語表記）：
            Japanese: 塩焼き、味噌煮、照り焼き、煮付け、西京焼き、生姜醤油焼き
            Western: バター焼き、ハーブ焼き、レモンソテー、トマト煮込み
            Asian: 南蛮漬け、甘酢あんかけ、中華蒸し、甘辛ソース焼き
            Fried: フライ、天ぷら、竜田揚げ、唐揚げ
            
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
            【簡単弁当】15分以内・時短調理で多様性：
            
            **3つのレシピは必ず異なるテーマで構成（時短調理を維持）**：
            🌿 ヘルシー時短（鶏むね肉のハーブグリル + カラフルピーマン甘酢炒め + ひじき梅風味煮）
            🇨🇳 中華時短（豚肉のオイスターソース炒め + ニラ玉 + ザーサイ風きゅうり）
            🇯🇵 和風時短（鮭の塩焼き + 鶏ごぼう甘辛煮 + ほうれん草のおかか和え）
            
            **または**：
            🌍 エスニック時短（ガパオ風鶏ひき肉炒め + トマトマリネ + 春雨サラダ）
            🍳 揚げ物時短（鶏の唐揚げ + だし巻き卵 + ブロッコリー塩昆布和え）
            🇮🇹 洋食時短（ハンバーグ + ミニマカロニグラタン + キャロットラペ）
            🌱 シンプル時短（豚の生姜焼き + きんぴらごぼう + 焼きナスおかか和え）
            
            🔄 テーマ別時短メイン（15分以内）：
            【ヘルシー時短】: 鶏むね肉ハーブグリル、鮭のレモンペッパー焼き、蒸し鶏サラダ
            【中華時短】: 豚肉オイスター炒め、鶏のガーリック炒め、海老の塩炒め
            【和風時短】: 鮭の塩焼き、豚の生姜焼き、鶏の照り焼き
            【エスニック時短】: ガパオ風炒め、鶏のスパイス焼き、カレー風味炒め
            【揚げ物時短】: 冷凍唐揚げ活用、冷凍コロッケ、冷凍エビフライ
            【洋食時短】: ハンバーグ、鶏のトマト炒め、ソーセージ炒め
            【シンプル時短】: 塩焼き、蒸し料理、シンプル炒め
            
            🔄 時短調理法（毎回変化）：
            【レンジ系】: レンジ蒸し鶏、レンジ豚バラ、レンジ魚、レンジ野菜
            【フライパン系】: 簡単炒め物、ソテー、焼き物
            【茹で系】: 茹で卵、茹で野菜、茹で麺
            【冷凍活用】: 冷凍唐揚げ、冷凍ハンバーグ、冷凍野菜
            【缶詰活用】: ツナ缶、鮭フレーク、缶詰サバ
            
            🔄 テーマ別簡単副菜（毎回変化・重複禁止）：
            【ヘルシー副菜】: カラフルピーマン甘酢炒め + ひじき梅風味煮、野菜マリネ + 蒸し野菜
            【中華副菜】: ニラ玉 + ザーサイ風きゅうり、もやしナムル + 中華風和え物
            【和風副菜】: 鶏ごぼう甘辛煮 + ほうれん草おかか和え、きんぴらごぼう + だし巻き卵
            【エスニック副菜】: トマトマリネ + 春雨サラダ、パクチーサラダ + スパイス野菜
            【揚げ物副菜】: だし巻き卵 + ブロッコリー塩昆布和え、簡単サラダ + 野菜炒め
            【洋食副菜】: ミニマカロニグラタン + キャロットラペ、野菜グリル + コールスロー
            【シンプル副菜】: きんぴらごぼう + 焼きナスおかか和え、蒸し野菜 + 塩昆布和え
            
            - 調理時間：合計15分以内厳守
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
                ["鮭", "鯖", "鯵"],
                ["鰤", "さんま", "たら"],
                ["いわし", "かじき", "ぶり"],
                ["めかじき", "鯛", "あじ"]
            ]
            let cookingVariations = [
                ["塩焼き", "味噌煮", "照り焼き"],
                ["南蛮漬け", "竜田揚げ", "蒸し焼き"],
                ["西京焼き", "煮付け", "フライ"],
                ["マリネ", "ムニエル", "ホイル焼き"]
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
                ["牛こま肉", "豚バラ肉", "鶏もも肉"],
                ["豚ロース", "牛バラ肉", "鶏手羽"],
                ["ひき肉", "豚こま肉", "牛ロース"],
                ["鶏むね肉", "豚肩ロース", "牛もも肉"]
            ]
            let heartyMethods = [
                ["揚げる", "こってり炒める", "ガーリック焼き"],
                ["スパイシー炒め", "チーズ焼き", "バター炒め"],
                ["濃厚煮込み", "照り焼き", "味噌炒め"],
                ["唐揚げ", "ステーキ", "生姜焼き"]
            ]
            let selectedMeats = meatVariations[dailyVariation % meatVariations.count]
            let selectedMethods = heartyMethods[dailyVariation % heartyMethods.count]
            
            return """
            【🍖 がっつり専用・超高カロリー】
            - 本日の肉種：\(selectedMeats.joined(separator: "・"))から選択
            - 調理法指定：\(selectedMethods.joined(separator: "・"))から選択
            - カロリー目標：700kcal以上必須
            - 必須条件：こってり・濃厚・ボリューム満点
            - 味付け：ガーリック・スパイス・濃い目の調味料
            - 禁止：ヘルシー・あっさり・野菜メイン
            - 特徴：スタミナ満点の肉料理専門弁当
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
        let cleanedJSON = extractJSON(from: jsonString)
        
        print("🧹 Cleaned JSON length: \(cleanedJSON.count) characters")
        if cleanedJSON.count < 500 {
            print("🧹 Cleaned JSON: \(cleanedJSON)")
        }
        
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
    
    private func createIngredientBasedPrompt(_ selectedIngredients: [Ingredient], additionalNotes: String) -> String {
        let mainProteins = selectedIngredients.filter { $0.category == .mainProtein }
        let vegetables = selectedIngredients.filter { $0.category == .vegetables }
        let seasonings = selectedIngredients.filter { $0.category == .seasonings }
        
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