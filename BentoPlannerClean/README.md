# Bento Planner - AI弁当レシピ生成アプリ

## 概要
AIを活用してお弁当のレシピを自動生成するiOSアプリケーションです。冷蔵庫にある食材から最適なレシピを提案し、週間献立の管理も簡単に行えます。

## 技術スタック
- **開発言語**: Swift 5.x
- **フレームワーク**: SwiftUI
- **AI モデル**: Google Gemini 2.5 Flash
- **最小対応バージョン**: iOS 16.6+
- **開発環境**: Xcode 17.0+

## 主な機能
- AIによる自動レシピ生成
- 食材ベースのレシピ検索
- 週間献立プランニング
- お気に入りレシピ管理
- カテゴリ別レシピ表示（主菜、副菜、炭水化物、デザート）
- レシピ生成中の料理豆知識表示

## バージョン履歴

### Version 1.0.3 Build 4 (2025-10-17)
**「簡単弁当」カテゴリの大幅改善とレシピ名の修正**

**「簡単弁当」カテゴリの改善**
- 本当にシンプルなレシピのみを含む専用データセットを生成
  - 調理方法は1種類のみ（焼く・レンジ・炒めるなど）
  - 材料は3-5個まで
  - 調理手順は2-3ステップまで
  - 調理時間は10分以内
- 50個の新しい簡単レシピを追加（レンジレシピ10個を含む）
  - 鮭の塩焼き、照り焼きチキン、レンジ蒸し鶏など
  - 魚焼きグリルやレンジを使った本当に簡単なレシピ

**レシピ名の修正**
- API生成時のレシピ名から不要な文言を削除
  - 「シンプルに」というプレフィックスを削除
  - 「ID:」を「乱数:」に変更してプロンプト内での識別用に統一
- PresetMainDishes.jsonの不整合を修正
  - 4つのアイテムの欠落していた`dish.name`フィールドを追加

**技術的な改善**
- `scripts/gen_simple.py`: 簡単弁当専用の生成スクリプトを新規作成
- `BentoAIService.swift`: APIプロンプトを修正（lines 414-426）
  - .omakaseカテゴリから「シンプルに」を削除
  - .simpleカテゴリに適切な例を追加
  - ID表記を「乱数:」に変更
- `PresetMainDishes.json`: JSONデコーディングエラーを修正

**App Store再審査準備完了**
- レシピ生成の安定性を確認
- プリセットレシピシステムの動作確認
- プロダクション広告IDの設定確認済み

### Version 1.0.3 Build 3 (2025-01-09)
**パフォーマンス改善**
- 食材からレシピ検索の速度が大幅に向上（約40%高速化）
  - プロンプトを簡潔化（120文字 → 30文字）
  - Thinking token削減による生成時間短縮（~52秒 → ~30秒）
- レシピ生成時のレスポンス時間を最適化

**バグ修正**
- 週間プランへのレシピ追加が初回から確実に動作するように修正
  - SwiftUIの`.sheet(isPresented:)`から`.sheet(item:)`パターンに変更
  - `DaySelection`構造体を追加してIdentifiableプロトコルに準拠
  - シートプレゼンテーション時のタイミング問題を解決
- レシピ選択時の安定性を向上

**その他**
- デバッグログのクリーンアップ
- 全体的な安定性とパフォーマンスの向上
- UIの細かな調整と改善

**技術的な改善点**
- `BentoAIService.swift`: `createIngredientBasedPrompt()`の最適化
- `ContentView.swift`: `DaySelection`構造体の追加と週間プランビューの改善
- `BentoStore.swift`: 不要なデバッグログの削除
- `RecipeSelectionView.swift`: コードのクリーンアップ

### Version 1.0.2
- 初回リリース
- 基本的なレシピ生成機能
- 週間プラン機能
- お気に入り機能

## 重要な技術ノート

### AI モデルについて
- **使用モデル**: `gemini-2.5-flash-latest`
- **重要**: Gemini 1.5は非推奨となるため、必ず2.5系を使用すること
- プロンプトの簡潔化により、thinking tokenを削減し高速化を実現

### SwiftUI Sheet Presentation Pattern
週間プランへのレシピ追加で遭遇した問題と解決策：

**問題**: `.sheet(isPresented:)`パターンでは、Booleanフラグがtrueになってからシート内容が初期化されるため、`selectedDay`パラメータが空文字列になる場合がある

**解決策**: `.sheet(item:)`パターンを使用
```swift
// 問題のあったコード
@State private var showRecipeSelection = false
@State private var selectedDayForRecipe = ""

.sheet(isPresented: $showRecipeSelection) {
    RecipeSelectionView(selectedDay: selectedDayForRecipe)
}

// 修正後のコード
struct DaySelection: Identifiable {
    let id = UUID()
    let day: String
}

@State private var selectedDayForRecipe: DaySelection?

.sheet(item: $selectedDayForRecipe) { daySelection in
    RecipeSelectionView(selectedDay: daySelection.day)
}
```

### プロンプトエンジニアリング
食材ベースのレシピ生成プロンプトを簡潔化することで、パフォーマンスが大幅に向上：

**Before** (~120文字):
```swift
"""
以下の食材を使って、お弁当に適したレシピを3つ生成してください。
各レシピは主菜1品、副菜2品の構成にしてください。
...（詳細な指示が続く）
"""
```

**After** (~30文字):
```swift
"""
\(ingredientList)\(additionalNotes.isEmpty ? "" : "。\(additionalNotes)") ID:\(uniqueId)

3レシピ。副菜異なる調理法。
"""
```

結果: 生成時間が約40%短縮（~52秒 → ~30秒）

## 主要ファイル構成
- `BentoPlannerCleanApp.swift` - アプリケーションエントリーポイント
- `ContentView.swift` - メインビュー、週間プラン表示
- `BentoStore.swift` - データ管理、永続化
- `BentoAIService.swift` - Gemini API連携
- `RecipeSelectionView.swift` - レシピ選択画面
- `BentoModels.swift` - データモデル定義

## 環境変数
- `OPENAI_API_KEY`: Gemini APIキー（Info.plistで管理）

## ビルド方法
1. Xcodeでプロジェクトを開く
2. 開発チームを選択
3. シミュレーターまたは実機を選択
4. Command + R でビルド実行

## App Store提出
1. Product → Archive
2. Distribute App → App Store Connect
3. リリースノートとプロモーションテキストを入力
4. 審査に提出

## ライセンス
Copyright (c) 2025 CocoroAI

## 作者
CocoroAI Development Team
