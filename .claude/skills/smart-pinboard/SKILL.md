---
name: smart-pinboard
description: Recipe for extending Pesto's smart-collection predicate DSL — new PredicateRule field or operator, evaluation, builder UI, tests, and the exhaustive switches that must all be updated. No raw NSPredicate strings. Use when adding a smart-collection filter or changing PredicateBuilder / SmartCollectionBuilder.
---

# Extending the Smart-Collection DSL

The DSL is intentionally constrained — no raw `NSPredicate` format strings (injection + migration risk). A rule set is Codable, stored as `Pinboard.smartPredicateData`, and evaluated in Swift against `PredicateEvaluatable`.

Touch exactly these files:

1. **`Sources/Core/Predicate/PredicateRule.swift`** — add the `Field` (or `Operator`) case; if the rule reads a new property, add it to `PredicateEvaluatable` (with an extension default if other conformers should not all change; `ClipboardItem` satisfies it by having the property). Field raw values are stored in saved rules, so never rename one.
2. **Same file, the exhaustive switches** — `PredicateValidator.allowedOperators(for:)` and `PredicateRuleSet.evaluateRule`.
3. **`Sources/Features/Collections/SmartCollectionBuilder.swift`** — `valueField` (the value editor; a bool field shows `EmptyView` and sets `.none`), `resetValue(for:)` (a bool field must reset to `.none`: it has a `default:`, so the compiler will not flag a miss) and `PredicateRule.Field.displayName`.
4. **Tests** — `Tests/PestoCoreTests/PredicateBuilderTests.swift` (allowed operators), `PredicateRuleSetTests.swift` (match by origin and Codable round trip; add the property to `MockItem`), `SmartCollectionPredicateTests.swift`.

Missing a switch is a compiler error (the gate builds with warnings as errors).
