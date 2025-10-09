# Recipe Generation Validation Enhancement

## Date: 2025-10-09

## Problem Summary

The user reported multiple critical issues with the recipe generation system:

1. **Duplicate recipes appearing repeatedly** - Same menus showing up across generations
2. **Recipe name and ingredient mismatch** - Dishes named "レモンタイム" without lemon/thyme in ingredients, "ロゼマリーガーリック" without rosemary/garlic
3. **Side dish duplication within single bentos** - Both side dishes using same cooking method (e.g., both "煮物")
4. **Lack of side dish diversity across all recipes** - When generating 3 bentos, all 6 side dishes must be completely different
5. **Frequently appearing recipes** - "鮭の塩焼き弁当" appearing in every generation

## Solutions Implemented

### 1. Enhanced Logging System (BentoAIService.swift:990-998)

Added comprehensive logging to capture and analyze API responses:

```swift
// 🔍 ENHANCED LOGGING: Complete raw API response
print(String(repeating: "=", count: 80))
print("🔍 RAW API RESPONSE - START")
print(String(repeating: "=", count: 80))
print(jsonString)  // Full raw response from Gemini API
print(String(repeating: "=", count: 80))
print("🔍 RAW API RESPONSE - END")
print(String(repeating: "=", count: 80))

print("🧹 CLEANED JSON - START")
print(cleanedJSON)  // Processed JSON
print("🧹 CLEANED JSON - END")
```

**Purpose**: This allows us to see exactly what Gemini AI is returning and diagnose why recipes don't meet requirements.

### 2. Recipe Name & Ingredient Validation (BentoAIService.swift:1033-1062)

Implemented validation to check if all ingredients mentioned in dish names are present in the ingredient list:

```swift
// Validate main dish
let mainDishErrors = validateDishNameMatchesIngredients(
    dishName: aiRecipe.mainDish.name,
    ingredients: aiRecipe.mainDish.ingredients,
    dishType: "主菜"
)

// Validate side dishes
let side1Errors = validateDishNameMatchesIngredients(...)
let side2Errors = validateDishNameMatchesIngredients(...)
```

**Validation Logic** (BentoAIService.swift:1133-1156):
- Extracts ingredient keywords from dish name (レモン, タイム, ローズマリー, ガーリック, etc.)
- Checks if each keyword exists in the ingredients list
- Reports missing ingredients as validation errors

### 3. Duplicate Cooking Method Detection (BentoAIService.swift:1064-1072)

Checks for duplicate cooking methods within the same bento:

```swift
let cookingMethod1 = extractCookingMethod(aiRecipe.sideDish1.name)
let cookingMethod2 = extractCookingMethod(aiRecipe.sideDish2.name)

if !cookingMethod1.isEmpty && !cookingMethod2.isEmpty && cookingMethod1 == cookingMethod2 {
    let error = "⚠️ 同じ弁当内で調理法が重複: 副菜1「\(aiRecipe.sideDish1.name)」と副菜2「\(aiRecipe.sideDish2.name)」がどちらも「\(cookingMethod1)」"
    validationErrors.append(error)
}
```

**Cooking Methods Detected** (BentoAIService.swift:1182-1192):
- 煮物系: 煮物, 煮付け, 含め煮, 甘露煮, 佃煮, 角煮, 煮込み
- 焼き系: 焼き, 塩焼き, 味噌焼き, 照り焼き, 蒲焼き, 西京焼き
- 揚げ系: 揚げ, 唐揚げ, 竜田揚げ, 天ぷら, フライ, カツ
- 炒め系: 炒め, 炒め物, きんぴら
- 和え系: 和え, 和え物, 胡麻和え, ごま和え, お浸し, おひたし
- 蒸し系: 蒸し, 酒蒸し, ホイル蒸し
- 漬け系: 漬け, 南蛮漬け, マリネ

### 4. Cross-Recipe Side Dish Validation (BentoAIService.swift:1079-1097)

Validates that all 6 side dishes (3 recipes × 2 side dishes each) are completely different:

```swift
// Check for duplicate side dishes across all recipes
let sideDishCounts = Dictionary(grouping: allSideDishes, by: { $0 }).mapValues { $0.count }
for (dish, count) in sideDishCounts where count > 1 {
    let error = "⚠️ 副菜が重複: 「\(dish)」が\(count)回出現"
    validationErrors.append(error)
}

// Check for similar cooking methods across all side dishes
let cookingMethods = allSideDishes.map { extractCookingMethod($0) }.filter { !$0.isEmpty }
let methodCounts = Dictionary(grouping: cookingMethods, by: { $0 }).mapValues { $0.count }
for (method, count) in methodCounts where count > 1 {
    let warning = "⚠️ 調理法が重複: 「\(method)」が\(count)回出現"
    validationErrors.append(warning)
}
```

### 5. Validation Summary Reporting (BentoAIService.swift:1099-1108)

```swift
if !validationErrors.isEmpty {
    print("\n❌ VALIDATION ERRORS DETECTED (\(validationErrors.count) issues):")
    for error in validationErrors {
        print("  - \(error)")
    }
    print("\n⚠️ API response has validation issues but proceeding with recipes...")
} else {
    print("\n✅ All validation checks passed!")
}
```

## How to Use the New Validation System

### Testing the App

1. **Launch the app** in iOS Simulator
2. **Generate recipes** for any category (お任せ, 簡単弁当, がっつり, 魚メイン)
3. **Check Xcode Console** for detailed validation logs:
   - Raw API response from Gemini
   - Validation results for each recipe
   - List of validation errors (if any)

### Reading the Validation Logs

Example output when validation issues are detected:

```
================================================================================
🔍 RAW API RESPONSE - START
================================================================================
{
  "candidates": [{
    "content": {
      "parts": [{
        "text": "{\"recipes\":[...]}"
      }]
    }
  }]
}
================================================================================

🔍 Validating Recipe 1: 鮭のレモンタイム弁当
  主菜 '鮭のレモンタイム' - キーワード: ["レモン", "タイム"]
    ❌ Missing: レモン
    ❌ Missing: タイム
  副菜1 'きんぴらごぼう' - キーワード: []
    ✅ (no special ingredients)
  副菜2 'レンコンのきんぴら' - キーワード: []
    ✅ (no special ingredients)
⚠️ 同じ弁当内で調理法が重複: 副菜1「きんぴらごぼう」と副菜2「レンコンのきんぴら」がどちらも「きんぴら」

🔍 Checking for duplicate side dishes across all 3 recipes:
All side dishes: [きんぴらごぼう, レンコンのきんぴら, ほうれん草の胡麻和え, 小松菜の胡麻和え, ...]
⚠️ 調理法が重複: 「きんぴら」が2回出現
⚠️ 調理法が重複: 「胡麻和え」が2回出現

❌ VALIDATION ERRORS DETECTED (5 issues):
  - Recipe 1 - 主菜: 「鮭のレモンタイム」に「レモン」が含まれているが、材料リストに見つかりません
  - Recipe 1 - 主菜: 「鮭のレモンタイム」に「タイム」が含まれているが、材料リストに見つかりません
  - ⚠️ 同じ弁当内で調理法が重複: 副菜1「きんぴらごぼう」と副菜2「レンコンのきんぴら」がどちらも「きんぴら」
  - ⚠️ 調理法が重複: 「きんぴら」が2回出現
  - ⚠️ 調理法が重複: 「胡麻和え」が2回出現
```

## Next Steps

### If Validation Errors Persist

The current implementation logs errors but still shows the recipes to the user. This was intentional to:
1. First understand what Gemini is actually returning
2. Identify patterns in the validation failures
3. Determine if the issue is with the prompt or the validation logic

### Potential Future Enhancements

1. **Retry Logic**: If validation fails, automatically regenerate recipes
2. **Stricter Validation**: Reject recipes entirely if validation fails (currently just logs warnings)
3. **Enhanced Prompts**: Further strengthen the Gemini API prompts based on validation findings
4. **Post-Processing**: Automatically fix minor issues (e.g., add missing ingredients) before showing to user

## Files Modified

- `BentoPlannerClean/BentoAIService.swift` - Added comprehensive validation and logging system

## Testing Checklist

- [x] Build succeeds with new validation code
- [x] App installs on simulator
- [ ] Test "お任せ" category - verify no duplicate side dishes
- [ ] Test "簡単弁当" category - verify no duplicate side dishes
- [ ] Test "がっつり" category - verify ingredient name matching
- [ ] Test "魚メイン" category - verify cooking method diversity
- [ ] Review console logs for validation errors
- [ ] Analyze patterns in API responses to improve prompts further
