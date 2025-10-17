#!/usr/bin/env python3
"""
事前生成された献立データを作成するスクリプト
各カテゴリ50パターンずつ、合計200パターンの献立を生成します
"""

import json
import os
import time
from typing import List, Dict
from openai import OpenAI

# OpenAI APIの設定
import os
OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY")
if not OPENAI_API_KEY:
    print("❌ Error: OPENAI_API_KEY environment variable not set")
    exit(1)

client = OpenAI(api_key=OPENAI_API_KEY)

CATEGORIES = {
    "omakase": {
        "name": "おまかせ",
        "description": "バランス重視の万能お弁当"
    },
    "hearty": {
        "name": "がっつり",
        "description": "ボリューム満点・満足感たっぷり"
    },
    "fishMain": {
        "name": "お魚弁当",
        "description": "魚をメインにした和風弁当"
    },
    "simple": {
        "name": "簡単弁当",
        "description": "時短・簡単に作れるお弁当"
    }
}

RECIPES_PER_CATEGORY = 50  # 本番：各カテゴリ50個
BATCH_SIZE = 5  # 一度に生成するレシピ数

def generate_recipes_batch(category_key: str, category_info: Dict, count: int, existing_names: List[str]) -> List[Dict]:
    """指定されたカテゴリの献立をバッチ生成"""

    existing_names_text = ""
    if existing_names:
        existing_names_text = f"\n重要: 以下のレシピ名とは異なるものにしてください:\n" + "\n".join([f"- {name}" for name in existing_names])

    prompt = f"""
あなたはお弁当レシピの専門家です。以下の条件で{count}個の異なるお弁当レシピを生成してください。
{existing_names_text}

カテゴリ: {category_info['name']}
説明: {category_info['description']}

各レシピには以下を含めてください:
- お弁当の名前（魅力的で具体的なもの）
- 簡潔な説明（1文）
- メインディッシュ（名前、材料リスト、調理手順）
- 副菜1（名前、材料リスト、調理手順）
- 副菜2（名前、材料リスト、調理手順）
- 調理時間（分）
- カロリー（kcal）
- 難易度（簡単/普通/上級）
- 調理のコツ（2-3個）

重要な要件:
1. {count}個すべて異なる献立にすること
2. 季節の食材を取り入れること
3. 栄養バランスを考慮すること
4. 冷めても美味しい料理を選ぶこと
5. お弁当箱に詰めやすい料理を選ぶこと
6. **お弁当に不向きな食材は絶対に使わないこと**:
   - 大根おろし（水分が多すぎる）
   - 生野菜サラダ（しおれる）
   - 豆腐（水分が出る）
   - 刺身・生魚（食中毒リスク）
   - マヨネーズベースのサラダ（傷みやすい）
7. 汁気の多い料理は避け、お弁当に適した調理法を選ぶこと

以下のJSON形式で出力してください（他のテキストは一切含めないでください）:

{{
  "recipes": [
    {{
      "name": "お弁当の名前",
      "description": "簡潔な説明",
      "mainDish": {{
        "name": "メインディッシュ名",
        "ingredients": ["材料1", "材料2", ...],
        "instructions": ["手順1", "手順2", ...]
      }},
      "sideDish1": {{
        "name": "副菜1の名前",
        "ingredients": ["材料1", "材料2", ...],
        "instructions": ["手順1", "手順2", ...]
      }},
      "sideDish2": {{
        "name": "副菜2の名前",
        "ingredients": ["材料1", "材料2", ...],
        "instructions": ["手順1", "手順2", ...]
      }},
      "prepTime": 30,
      "calories": 550,
      "difficulty": "簡単",
      "tips": ["コツ1", "コツ2", "コツ3"]
    }}
  ]
}}
"""

    max_retries = 3
    for attempt in range(max_retries):
        try:
            print(f"    🌐 API呼び出し中... (attempt {attempt + 1}/{max_retries})")
            response = client.chat.completions.create(
                model="gpt-4o",
                messages=[
                    {"role": "system", "content": "あなたはお弁当レシピの専門家です。JSON形式でレシピを生成します。"},
                    {"role": "user", "content": prompt}
                ],
                temperature=0.9
            )

            print(f"    ✓ API応答受信")
            response_text = response.choices[0].message.content.strip()

            # JSONの抽出（コードブロックから取り出す）
            if "```json" in response_text:
                response_text = response_text.split("```json")[1].split("```")[0].strip()
            elif "```" in response_text:
                response_text = response_text.split("```")[1].split("```")[0].strip()

            data = json.loads(response_text)
            recipes = data.get("recipes", [])

            if len(recipes) == count:
                return recipes
            else:
                print(f"⚠️ Expected {count} recipes, got {len(recipes)}. Using what we got.")
                return recipes

        except json.JSONDecodeError as e:
            print(f"⚠️ JSON decode error (attempt {attempt + 1}/{max_retries}): {e}")
            if attempt < max_retries - 1:
                time.sleep(3)
                continue
            else:
                return []
        except Exception as e:
            print(f"❌ Error (attempt {attempt + 1}/{max_retries}): {e}")
            if attempt < max_retries - 1:
                time.sleep(3)
                continue
            else:
                return []

    return []

def generate_recipes_for_category(category_key: str, category_info: Dict, total_count: int) -> List[Dict]:
    """指定されたカテゴリの献立を生成（バッチ処理）"""
    print(f"\n🔄 Generating {total_count} recipes for {category_info['name']}...")

    all_recipes = []
    existing_names = []

    # バッチごとに生成
    batches = (total_count + BATCH_SIZE - 1) // BATCH_SIZE
    for batch_num in range(batches):
        remaining = total_count - len(all_recipes)
        batch_size = min(BATCH_SIZE, remaining)

        print(f"  📝 Batch {batch_num + 1}/{batches}: Generating {batch_size} recipes...")

        batch_recipes = generate_recipes_batch(category_key, category_info, batch_size, existing_names)

        if batch_recipes:
            all_recipes.extend(batch_recipes)
            existing_names.extend([r.get("name", "") for r in batch_recipes])
            print(f"  ✅ Total: {len(all_recipes)}/{total_count} recipes generated")
        else:
            print(f"  ⚠️ Batch {batch_num + 1} failed, skipping...")

        # API Rate Limitを避けるため少し待つ
        time.sleep(1)

    print(f"✅ Completed {category_info['name']}: {len(all_recipes)} recipes")
    return all_recipes

def main():
    """メイン処理"""
    all_recipes = {}

    for category_key, category_info in CATEGORIES.items():
        recipes = generate_recipes_for_category(category_key, category_info, RECIPES_PER_CATEGORY)
        all_recipes[category_key] = recipes

    # 結果をJSONファイルに保存
    output_path = "../BentoPlannerClean/PresetRecipes.json"
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(all_recipes, f, ensure_ascii=False, indent=2)

    print(f"\n✅ Successfully generated preset recipes!")
    print(f"📁 Saved to: {output_path}")
    print(f"\n📊 Summary:")
    for category_key, recipes in all_recipes.items():
        print(f"  - {CATEGORIES[category_key]['name']}: {len(recipes)} recipes")

if __name__ == "__main__":
    main()
