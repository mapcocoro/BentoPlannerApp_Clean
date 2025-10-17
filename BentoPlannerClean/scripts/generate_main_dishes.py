#!/usr/bin/env python3
"""
メインディッシュデータを生成するスクリプト
各カテゴリ50パターンずつ、合計200パターンのメインディッシュを生成します
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

MAIN_DISHES_PER_CATEGORY = 50
BATCH_SIZE = 5

def generate_main_dishes_batch(category_key: str, category_info: Dict, count: int, existing_names: List[str]) -> List[Dict]:
    """指定されたカテゴリのメインディッシュをバッチ生成"""

    existing_names_text = ""
    if existing_names:
        existing_names_text = f"\n重要: 以下のメインディッシュ名とは異なるものにしてください:\n" + "\n".join([f"- {name}" for name in existing_names])

    prompt = f"""
あなたはお弁当のメインディッシュ専門家です。以下の条件で{count}個の異なるメインディッシュを生成してください。
{existing_names_text}

カテゴリ: {category_info['name']}
説明: {category_info['description']}

各メインディッシュには以下を含めてください:
- メインディッシュの名前（魅力的で具体的なもの）
- 簡潔な説明（1文）
- 材料リスト（5-8個）
- 調理手順（3-5ステップ）
- 調理時間（分）- メインディッシュのみの時間
- カロリー（kcal）- メインディッシュのみ
- 難易度（簡単/普通/上級）
- 季節（春/夏/秋/冬、または季節を問わない場合はnull）

重要な要件:
1. {count}個すべて異なるメインディッシュにすること
2. 季節の食材を取り入れること（必要に応じて）
3. 冷めても美味しい料理を選ぶこと
4. お弁当箱に詰めやすい料理を選ぶこと
5. **お弁当に不向きな食材は絶対に使わないこと**:
   - 大根おろし（水分が多すぎる）
   - 生野菜サラダ（しおれる）
   - 豆腐（水分が出る）
   - 刺身・生魚（食中毒リスク）
   - マヨネーズベースのサラダ（傷みやすい）
6. 汁気の多い料理は避け、お弁当に適した調理法を選ぶこと
7. メインディッシュとしてボリュームがあること

以下のJSON形式で出力してください（他のテキストは一切含めないでください）:

{{
  "mainDishes": [
    {{
      "name": "メインディッシュ名",
      "description": "簡潔な説明",
      "dish": {{
        "name": "料理名（メインディッシュ名と同じ）",
        "ingredients": ["材料1", "材料2", ...],
        "instructions": ["手順1", "手順2", ...]
      }},
      "prepTime": 15,
      "calories": 300,
      "difficulty": "簡単",
      "season": "秋"
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
                    {"role": "system", "content": "あなたはお弁当のメインディッシュ専門家です。JSON形式でメインディッシュを生成します。"},
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

def generate_main_dishes_for_category(category_key: str, category_info: Dict, total_count: int) -> List[Dict]:
    """指定されたカテゴリのメインディッシュを生成（バッチ処理）"""
    print(f"\n🔄 Generating {total_count} main dishes for {category_info['name']}...")

    all_main_dishes = []
    existing_names = []

    # バッチごとに生成
    batches = (total_count + BATCH_SIZE - 1) // BATCH_SIZE
    for batch_num in range(batches):
        remaining = total_count - len(all_main_dishes)
        batch_size = min(BATCH_SIZE, remaining)

        print(f"  📝 Batch {batch_num + 1}/{batches}: Generating {batch_size} main dishes...")

        batch_main_dishes = generate_main_dishes_batch(category_key, category_info, batch_size, existing_names)

        if batch_main_dishes:
            all_main_dishes.extend(batch_main_dishes)
            existing_names.extend([md.get("name", "") for md in batch_main_dishes])
            print(f"  ✅ Total: {len(all_main_dishes)}/{total_count} main dishes generated")
        else:
            print(f"  ⚠️ Batch {batch_num + 1} failed, skipping...")

        # API Rate Limitを避けるため少し待つ
        time.sleep(1)

    print(f"✅ Completed {category_info['name']}: {len(all_main_dishes)} main dishes")
    return all_main_dishes

def main():
    """メイン処理"""
    all_main_dishes = {}

    for category_key, category_info in CATEGORIES.items():
        main_dishes = generate_main_dishes_for_category(category_key, category_info, MAIN_DISHES_PER_CATEGORY)
        all_main_dishes[category_key] = main_dishes

    # 結果をJSONファイルに保存
    output_path = "../BentoPlannerClean/PresetMainDishes.json"
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(all_main_dishes, f, ensure_ascii=False, indent=2)

    print(f"\n✅ Successfully generated preset main dishes!")
    print(f"📁 Saved to: {output_path}")
    print(f"\n📊 Summary:")
    for category_key, main_dishes in all_main_dishes.items():
        print(f"  - {CATEGORIES[category_key]['name']}: {len(main_dishes)} main dishes")

if __name__ == "__main__":
    main()
