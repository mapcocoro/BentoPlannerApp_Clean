#!/usr/bin/env python3
"""
副菜データを生成するスクリプト
100パターンの副菜を生成します
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

TOTAL_SIDE_DISHES = 100
BATCH_SIZE = 5

# 調理方法のカテゴリー
COOKING_METHODS = [
    "きんぴら", "煮物", "和え物", "炒め物", "焼き物",
    "揚げ物", "蒸し物", "漬物", "サラダ", "マリネ"
]

def generate_side_dishes_batch(count: int, existing_names: List[str], existing_methods: Dict[str, int]) -> List[Dict]:
    """副菜をバッチ生成"""

    existing_names_text = ""
    if existing_names:
        existing_names_text = f"\n重要: 以下の副菜名とは異なるものにしてください:\n" + "\n".join([f"- {name}" for name in existing_names[-20:]])

    # 調理方法のバランスを考慮
    method_distribution = "\n調理方法のバランス（現在の生成数）:\n" + "\n".join([f"- {method}: {count}個" for method, count in existing_methods.items()])

    prompt = f"""
あなたはお弁当の副菜専門家です。以下の条件で{count}個の異なる副菜を生成してください。
{existing_names_text}
{method_distribution}

各副菜には以下を含めてください:
- 副菜の名前（魅力的で具体的なもの）
- 材料リスト（3-5個）
- 調理手順（2-4ステップ）
- 調理時間（分）- 副菜のみの時間、5-15分程度
- カロリー（kcal）- 副菜のみ、50-150kcal程度
- 調理方法（以下から1つを選択）: {', '.join(COOKING_METHODS)}
- 季節（春/夏/秋/冬、または季節を問わない場合はnull）

重要な要件:
1. {count}個すべて異なる副菜にすること
2. 調理方法のバランスを考慮し、偏りがないようにすること
3. 季節の食材を取り入れること（必要に応じて）
4. 冷めても美味しい料理を選ぶこと
5. お弁当箱に詰めやすい料理を選ぶこと
6. **お弁当に不向きな食材は絶対に使わないこと**:
   - 大根おろし（水分が多すぎる）
   - 生野菜サラダ（しおれる）
   - 豆腐（水分が出る）
   - 刺身・生魚（食中毒リスク）
   - マヨネーズベースのサラダ（傷みやすい）
7. 汁気の多い料理は避け、お弁当に適した調理法を選ぶこと
8. 副菜として適度なボリュームであること
9. 彩りが良く、お弁当を華やかにする料理を選ぶこと

以下のJSON形式で出力してください（他のテキストは一切含めないでください）:

{{
  "sideDishes": [
    {{
      "name": "副菜名",
      "dish": {{
        "name": "料理名（副菜名と同じ）",
        "ingredients": ["材料1", "材料2", ...],
        "instructions": ["手順1", "手順2", ...]
      }},
      "prepTime": 10,
      "calories": 80,
      "cookingMethod": "きんぴら",
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
                    {"role": "system", "content": "あなたはお弁当の副菜専門家です。JSON形式で副菜を生成します。"},
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
            side_dishes = data.get("sideDishes", [])

            if len(side_dishes) == count:
                return side_dishes
            else:
                print(f"⚠️ Expected {count} side dishes, got {len(side_dishes)}. Using what we got.")
                return side_dishes

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

def generate_all_side_dishes(total_count: int) -> List[Dict]:
    """すべての副菜を生成（バッチ処理）"""
    print(f"\n🔄 Generating {total_count} side dishes...")

    all_side_dishes = []
    existing_names = []
    existing_methods = {method: 0 for method in COOKING_METHODS}

    # バッチごとに生成
    batches = (total_count + BATCH_SIZE - 1) // BATCH_SIZE
    for batch_num in range(batches):
        remaining = total_count - len(all_side_dishes)
        batch_size = min(BATCH_SIZE, remaining)

        print(f"  📝 Batch {batch_num + 1}/{batches}: Generating {batch_size} side dishes...")

        batch_side_dishes = generate_side_dishes_batch(batch_size, existing_names, existing_methods)

        if batch_side_dishes:
            all_side_dishes.extend(batch_side_dishes)
            existing_names.extend([sd.get("name", "") for sd in batch_side_dishes])

            # 調理方法のカウント更新
            for sd in batch_side_dishes:
                method = sd.get("cookingMethod", "その他")
                if method in existing_methods:
                    existing_methods[method] += 1

            print(f"  ✅ Total: {len(all_side_dishes)}/{total_count} side dishes generated")
        else:
            print(f"  ⚠️ Batch {batch_num + 1} failed, skipping...")

        # API Rate Limitを避けるため少し待つ
        time.sleep(1)

    print(f"✅ Completed: {len(all_side_dishes)} side dishes")
    print(f"\n📊 Cooking method distribution:")
    for method, count in sorted(existing_methods.items(), key=lambda x: x[1], reverse=True):
        print(f"  - {method}: {count} dishes")

    return all_side_dishes

def main():
    """メイン処理"""
    side_dishes = generate_all_side_dishes(TOTAL_SIDE_DISHES)

    # 結果をJSONファイルに保存
    output_path = "../BentoPlannerClean/PresetSideDishes.json"
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump({"sideDishes": side_dishes}, f, ensure_ascii=False, indent=2)

    print(f"\n✅ Successfully generated preset side dishes!")
    print(f"📁 Saved to: {output_path}")
    print(f"\n📊 Summary: {len(side_dishes)} side dishes")

if __name__ == "__main__":
    main()
