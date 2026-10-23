// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// Grouped UI for building a `PredicateRuleSet`. Supports AND/OR at both the top-level
/// (between groups) and within each group.
struct SmartCollectionBuilder: View {
    @Environment(\.pestoAccent) private var accent
    @Binding var ruleSet: PredicateRuleSet

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Match")
                    .pestoQuiet()
                Picker("Match groups", selection: $ruleSet.combinator) {
                    Text("all").tag(PredicateRuleSet.Combinator.and)
                    Text("any").tag(PredicateRuleSet.Combinator.or)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 90)
                Text("of these groups")
                    .pestoQuiet()
            }
            .font(.subheadline)

            ForEach(ruleSet.groups.indices, id: \.self) { gIdx in
                GroupCard(
                    group: $ruleSet.groups[gIdx],
                    onDelete: ruleSet.groups.count > 1 ? { ruleSet.groups.remove(at: gIdx) } : nil
                )
            }

            Button {
                ruleSet.groups.append(
                    PredicateRuleSet.Group(
                        combinator: .and,
                        rules: [PredicateRule(field: .type, op: .equals, value: .string("text"))]
                    )
                )
            } label: {
                Label("Add Group", systemImage: "plus.rectangle.on.rectangle")
                    .font(.subheadline)
            }
            .buttonStyle(.plain)
            .foregroundStyle(accent)
            .padding(.top, 2)
        }
    }
}

// MARK: - Group card

private struct GroupCard: View {
    @Binding var group: PredicateRuleSet.Group
    var onDelete: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("Match")
                    .pestoQuiet()
                    .font(.caption)
                Picker("Match rules in this group", selection: $group.combinator) {
                    Text("all").tag(PredicateRuleSet.Combinator.and)
                    Text("any").tag(PredicateRuleSet.Combinator.or)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 80)
                Text("of the following")
                    .pestoQuiet()
                    .font(.caption)
                Spacer()
                if let onDelete {
                    Button(action: onDelete) {
                        Image(systemName: "minus.circle.fill")
                            .pestoQuiet()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove group")
                }
            }

            ForEach(group.rules.indices, id: \.self) { rIdx in
                RuleRow(
                    rule: $group.rules[rIdx],
                    onDelete: group.rules.count > 1 ? { group.rules.remove(at: rIdx) } : nil
                )
            }

            Button {
                group.rules.append(PredicateRule(field: .type, op: .equals, value: .string("text")))
            } label: {
                Label("Add Rule", systemImage: "plus")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .pestoQuiet()
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Rule row

private struct RuleRow: View {
    @Binding var rule: PredicateRule
    var onDelete: (() -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            Picker("Field", selection: $rule.field) {
                ForEach(PredicateRule.Field.allCases, id: \.self) { f in
                    Text(f.displayName).tag(f)
                }
            }
            .frame(width: 110)
            .onChange(of: rule.field) { _, newField in
                // Reset op to first allowed and reset value when field changes.
                let ops = allowedOps(for: newField)
                if !ops.contains(rule.op) { rule.op = ops[0] }
                resetValue(for: newField)
            }

            Picker("Condition", selection: $rule.op) {
                ForEach(allowedOps(for: rule.field), id: \.self) { op in
                    Text(op.displayName).tag(op)
                }
            }
            .frame(width: 100)

            valueField

            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "minus.circle.fill")
                        .pestoQuiet()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove rule")
            }
        }
        .labelsHidden()
    }

    @ViewBuilder
    private var valueField: some View {
        switch rule.field {
        case .type:
            Picker("Value", selection: Binding(
                get: { rule.value.stringValue ?? "text" },
                set: { rule.value = .string($0) }
            )) {
                Text("Text").tag("text")
                Text("URL").tag("url")
                Text("Image").tag("image")
                Text("Code").tag("code")
                Text("Color").tag("color")
                Text("File").tag("file")
            }
            .frame(width: 90)

        case .contentShape:
            Picker("Value", selection: Binding(
                get: { rule.value.stringValue ?? "text" },
                set: { rule.value = .string($0) }
            )) {
                Text("Text").tag("text")
                Text("Link").tag("link")
                Text("Code").tag("code")
                Text("JSON").tag("json")
                Text("cURL").tag("curl")
                Text("Image").tag("image")
                Text("GIF").tag("gif")
                Text("Color").tag("color")
                Text("File").tag("file")
            }
            .frame(width: 90)

        case .sourceBundleID, .sourceAppName, .previewText, .detectedLanguage, .sensitivity, .tags:
            TextField("Value", text: Binding(
                get: { rule.value.stringValue ?? "" },
                set: { rule.value = .string($0) }
            ))
            .frame(width: 130)
            .textFieldStyle(.roundedBorder)

        case .timestamp:
            HStack(spacing: 4) {
                TextField("Seconds", value: Binding(
                    get: { rule.value.intValue ?? 86_400 },
                    set: { rule.value = .int($0) }
                ), format: .number)
                    .frame(width: 70)
                    .textFieldStyle(.roundedBorder)
                Text("sec").pestoQuiet().font(.caption)
            }

        case .isPinned, .isRemote:
            EmptyView()
                .onAppear { rule.value = .none }
        }
    }

    private func allowedOps(for field: PredicateRule.Field) -> [PredicateRule.Operator] {
        Array(PredicateValidator.allowedOperators(for: field))
            .sorted { $0.rawValue < $1.rawValue }
    }

    private func resetValue(for field: PredicateRule.Field) {
        switch field {
        case .isPinned, .isRemote: rule.value = .none
        case .timestamp: rule.value = .int(86_400)
        default: rule.value = .string("")
        }
    }
}

// MARK: - Display name helpers

extension PredicateRule.Field {
    var displayName: String {
        switch self {
        case .type: "Type"
        case .sourceBundleID: "Bundle ID"
        case .sourceAppName: "Source App"
        case .previewText: "Text"
        case .timestamp: "Date"
        case .isPinned: "Pinned"
        case .isRemote: "From Another Device"
        case .detectedLanguage: "Language"
        case .sensitivity: "Sensitivity"
        case .tags: "Tag"
        case .contentShape: "Content Shape"
        }
    }
}

extension PredicateRule.Operator {
    var displayName: String {
        switch self {
        case .equals: "is"
        case .notEquals: "is not"
        case .contains: "contains"
        case .beginsWith: "starts with"
        case .endsWith: "ends with"
        case .olderThanSeconds: "older than"
        case .newerThanSeconds: "newer than"
        case .isTrue: "is pinned"
        case .isFalse: "is not pinned"
        }
    }
}
