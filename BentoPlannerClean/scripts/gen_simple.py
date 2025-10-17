#!/usr/bin/env python3
"""
「簡単弁当」カテゴリ専用のメインディッシュ生成スクリプト
焼くだけ・レンジだけなど、本当にシンプルなレシピ50個を生成します
"""

import json
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

BATCH_SIZE = 5
TOTAL_COUNT = 50

def generate_simple_main_dishes_batch(count: int, existing_names: List[str]) -> List[Dict]:
    """「簡単弁当」専用のメインディッシュをバッチ生成"""

    existing_names_text = ""
    if existing_names:
        existing_names_text = f"\n重要: 以下のメインディッシュ名とは異なるものにしてください:\n" + "\n".join([f"- {name}" for name in existing_names])

    prompt = f"""
あなたはお弁当のメインディッシュ専門家です。以下の条件で{count}個の異なる「簡単弁当」メインディッシュを生成してください。
{existing_names_text}

カテゴリ: 簡単弁当
説明: 時短・簡単に作れるお弁当

**「簡単弁当」の重要な条件**:
1. **調理方法は1種類のみ**: 焼く・レンジ・炒めるなど、1つの調理法だけで完結すること
2. **材料は3-5個まで**: 最小限の材料で作れること
3. **調理手順は2-3ステップまで**: 複雑な工程は不要
4. **調理時間は10分以内**: メインディッシュのみの時間
5. **特に推奨される調理法**:
   - グリルや魚焼き器で焼くだけ（例: 鮭の塩焼き、サバの塩焼き）
   - フライパンで焼くだけ（例: 照り焼きチキン、豚肉の生姜焼き）
   - 電子レンジで加熱するだけ（例: レンジ蒸し鶏、レンジハンバーグ）
   - フライパンで炒めるだけ（例: 野菜炒め、卵とじ）

**良い例**:
- 鮭の塩焼き（焼くだけ）
- 照り焼きチキン（フライパンで焼いてタレを絡めるだけ）
- レンジ蒸し鶏（レンジで加熱するだけ）
- 豚肉の生姜焼き（漬けて焼くだけ）
- サバの味噌煮（缶詰使用）

**避けるべき例**:
- 複数の調理法が必要（揚げてから煮るなど）
- 材料が多い（6個以上）
- 手順が多い（4ステップ以上）
- 時間がかかる（15分以上）

各メインディッシュには以下を含めてください:
- メインディッシュの名前（シンプルで分かりやすいもの）
- 簡潔な説明（1文）
- 材料リスト（3-5個）
- 調理手順（2-3ステップ）
- 調理時間（分）- 10分以内
- カロリー（kcal）- メインディッシュのみ
- 難易度（「簡単」固定）
- 季節（春/夏/秋/冬、または季節を問わない場合はnull）

以下のJSON形式で出力してください（他のテキストは一切含めないでください）:

{{
  "mainDishes": [
    {{
      "name": "鮭の塩焼き",
      "description": "シンプルな塩焼きで素材の旨味を引き出したメインディッシュ",
      "dish": {{
        "name": "鮭の塩焼き",
        "ingredients": ["鮭の切り身", "塩", "レモン"],
        "instructions": ["鮭に塩をふる", "魚焼きグリルで8分焼く"]
      }},
      "prepTime": 10,
      "calories": 180,
      "difficulty": "簡単",
      "season": null
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
                    {"role": "system", "content": "あなたは「簡単弁当」専門家です。本当にシンプルで時短できるメインディッシュをJSON形式で生成します。"},
                    {"role": "user", "content": prompt}
                ],
                temperature=0.8
            )

            print(f"    ✓ API応答受信")
            response_text = response.choices[0].message.content.strip()

            # JSONの抽出（コードブロックから取り出す）
            if "```json" in response_text:
                response_text = response_text.split("```json")[1].split("```")[0].strip()
            elif "```" in response_text:
                response_text = response_text.split("```")[1].split("```")[0].strip()

            data = json.loads(response_text)
            main_dishes = data.get("mainDishes", [])

            if len(main_dishes) == count:
                return main_dishes
            else:
                print(f"⚠️ Expected {count} main dishes, got {len(main_dishes)}. Using what we got.")
                return main_dishes

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

def main():
    """メイン処理"""
    print(f"\n🔄 Generating {TOTAL_COUNT} SIMPLE main dishes for 簡単弁当...")

    all_main_dishes = []
    existing_names = []

    # バッチごとに生成
    batches = (TOTAL_COUNT + BATCH_SIZE - 1) // BATCH_SIZE
    for batch_num in range(batches):
        remaining = TOTAL_COUNT - len(all_main_dishes)
        batch_size = min(BATCH_SIZE, remaining)

        print(f"\n  📝 Batch {batch_num + 1}/{batches}: Generating {batch_size} simple main dishes...")

        batch_main_dishes = generate_simple_main_dishes_batch(batch_size, existing_names)

        if batch_main_dishes:
            all_main_dishes.extend(batch_main_dishes)
            existing_names.extend([md.get("name", "") for md in batch_main_dishes])
            print(f"  ✅ Total: {len(all_main_dishes)}/{TOTAL_COUNT} simple main dishes generated")
        else:
            print(f"  ⚠️ Batch {batch_num + 1} failed, skipping...")

        # API Rate Limitを避けるため少し待つ
        time.sleep(1)

    print(f"\n✅ Completed 簡単弁当: {len(all_main_dishes)} simple main dishes")

    # 既存のPresetMainDishes.jsonを読み込む
    input_path = "../BentoPlannerClean/PresetMainDishes.json"
    try:
        with open(input_path, "r", encoding="utf-8") as f:
            all_categories = json.load(f)
    except FileNotFoundError:
        print("⚠️ PresetMainDishes.json not found. Creating new file.")
        all_categories = {
            "omakase": [],
            "hearty": [],
            "fishMain": [],
            "simple": []
        }

    # 簡単弁当カテゴリのみを更新
    all_categories["simple"] = all_main_dishes

    # 結果をJSONファイルに保存
    output_path = "../BentoPlannerClean/PresetMainDishes.json"
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(all_categories, f, ensure_ascii=False, indent=2)

    print(f"\n✅ Successfully updated preset main dishes!")
    print(f"📁 Saved to: {output_path}")
    print(f"\n📊 Summary:")
    for category_key, main_dishes in all_categories.items():
        category_names = {
            "omakase": "おまかせ",
            "hearty": "がっつり",
            "fishMain": "お魚弁当",
            "simple": "簡単弁当"
        }
        print(f"  - {category_names.get(category_key, category_key)}: {len(main_dishes)} main dishes")

if __name__ == "__main__":
    main()
