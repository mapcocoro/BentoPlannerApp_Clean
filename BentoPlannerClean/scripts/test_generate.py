#!/usr/bin/env python3
import json
import os
from openai import OpenAI

# OpenAI APIの設定
OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY")
if not OPENAI_API_KEY:
    print("❌ Error: OPENAI_API_KEY environment variable not set")
    exit(1)

client = OpenAI(api_key=OPENAI_API_KEY)

prompt = '''
お弁当レシピを2個生成してください。以下のJSON形式で出力してください:

{
  "recipes": [
    {
      "name": "お弁当の名前",
      "description": "簡潔な説明",
      "mainDish": {
        "name": "メインディッシュ名",
        "ingredients": ["材料1", "材料2"],
        "instructions": ["手順1", "手順2"]
      },
      "sideDish1": {
        "name": "副菜1の名前",
        "ingredients": ["材料1", "材料2"],
        "instructions": ["手順1", "手順2"]
      },
      "sideDish2": {
        "name": "副菜2の名前",
        "ingredients": ["材料1", "材料2"],
        "instructions": ["手順1", "手順2"]
      },
      "prepTime": 30,
      "calories": 550,
      "difficulty": "簡単",
      "tips": ["コツ1", "コツ2"]
    }
  ]
}
'''

print('Generating recipe...')
response = client.chat.completions.create(
    model='gpt-4o',
    messages=[
        {'role': 'system', 'content': 'あなたはお弁当レシピの専門家です。JSON形式でレシピを生成します。'},
        {'role': 'user', 'content': prompt}
    ],
    temperature=0.9
)

print('Response received')
response_text = response.choices[0].message.content.strip()

if '```json' in response_text:
    response_text = response_text.split('```json')[1].split('```')[0].strip()
elif '```' in response_text:
    response_text = response_text.split('```')[1].split('```')[0].strip()

data = json.loads(response_text)
print(f'Generated {len(data.get("recipes", []))} recipes')
print('Success!')
print(json.dumps(data, ensure_ascii=False, indent=2))
