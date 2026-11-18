// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

/// The rules of a smart collection as Form sections: groups of rules, each group matching all or any of its rules, and
/// the groups matching all or any together, as the Mac's builder does it. Every control offers only what
/// `PredicateValidator` accepts.
struct SmartRulesEditor: View {
    @Binding var draft: SmartRulesDraft

    var body: some View {
        if draft.ruleSet.groups.count > 1 {
            Section {
                Picker("Match", selection: $draft.ruleSet.combinator) {
                    Text("All groups").tag(PredicateRuleSet.Combinator.and)
                    Text("Any group").tag(PredicateRuleSet.Combinator.or)
                }
                .accessibilityIdentifier(MobileAccessibilityID.smartGroupsMatch)
            }
        }
        ForEach(draft.ruleSet.groups.indices, id: \.self) { index in
            groupSection(index)
        }
        Section {
            Button("Add Group", systemImage: "plus.rectangle.on.rectangle") {
                draft.ruleSet.groups.append(PredicateRuleSet.Group(
                    combinator: .and, rules: [SmartRulesDraft.newRule()]
                ))
            }
            .accessibilityIdentifier(MobileAccessibilityID.smartAddGroup)
        }
    }

    @ViewBuilder
    private func groupSection(_ index: Int) -> some View {
        let group = $draft.ruleSet.groups[index]
        Section {
            if group.wrappedValue.rules.count > 1 {
                Picker("Match", selection: group.combinator) {
                    Text("All of these").tag(PredicateRuleSet.Combinator.and)
                    Text("Any of these").tag(PredicateRuleSet.Combinator.or)
                }
            }
            ForEach(group.wrappedValue.rules.indices, id: \.self) { ruleIndex in
                SmartRuleRow(
                    rule: group.rules[ruleIndex], fields: draft.fields,
                    onRemove: group.wrappedValue.rules
                        .count > 1 ? { group.wrappedValue.rules.remove(at: ruleIndex) } : nil
                )
            }
            Button("Add Rule", systemImage: "plus") {
                group.wrappedValue.rules.append(SmartRulesDraft.newRule())
            }
            .accessibilityIdentifier(MobileAccessibilityID.smartAddRule)
            if draft.ruleSet.groups.count > 1 {
                Button("Remove Group", systemImage: "minus.circle", role: .destructive) {
                    draft.ruleSet.groups.remove(at: index)
                }
            }
        } header: {
            if index == 0, draft.ruleSet.groups.count == 1 {
                Text("Rules")
            } else {
                Text("Group \(index + 1)")
            }
        } footer: {
            if index == draft.ruleSet.groups.count - 1 {
                Text("A smart collection fills itself with the clips that match, and keeps filling as you copy.")
            }
        }
    }
}

private struct SmartRuleRow: View {
    @Binding var rule: PredicateRule
    let fields: [PredicateRule.Field]
    let onRemove: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Field", selection: fieldBinding) {
                    ForEach(fields, id: \.self) { Text(SmartRuleWords.title(of: $0)).tag($0) }
                }
                .labelsHidden()
                .accessibilityIdentifier(MobileAccessibilityID.smartRuleField)
                Picker("Condition", selection: $rule.op) {
                    ForEach(SmartRulesDraft.operators(for: rule.field), id: \.self) {
                        Text(SmartRuleWords.title(of: $0, field: rule.field)).tag($0)
                    }
                }
                .labelsHidden()
                .accessibilityIdentifier(MobileAccessibilityID.smartRuleCondition)
                Spacer(minLength: 0)
                if let onRemove {
                    Button("Remove Rule", systemImage: "minus.circle.fill", action: onRemove)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .frame(minWidth: TouchTarget.minimum, minHeight: TouchTarget.minimum)
                }
            }
            valueEditor
        }
        .padding(.vertical, 2)
    }

    private var fieldBinding: Binding<PredicateRule.Field> {
        Binding(
            get: { rule.field },
            set: { field in
                guard field != rule.field else { return }
                rule = SmartRulesDraft.rule(for: field)
            }
        )
    }

    @ViewBuilder
    private var valueEditor: some View {
        if let choices = SmartRuleWords.choices(for: rule.field) {
            Picker("Value", selection: stringBinding(default: choices.first?.value ?? "")) {
                ForEach(choices, id: \.value) { Text($0.title).tag($0.value) }
            }
            .labelsHidden()
            .accessibilityIdentifier(MobileAccessibilityID.smartRuleValue)
        } else if rule.field == .timestamp {
            Picker("Value", selection: ageBinding) {
                ForEach(SmartRuleWords.ageChoices, id: \.seconds) { Text($0.title).tag($0.seconds) }
                if !SmartRuleWords.ageChoices.contains(where: { $0.seconds == ageBinding.wrappedValue }) {
                    Text(SmartRuleWords.ageTitle(seconds: ageBinding.wrappedValue)).tag(ageBinding.wrappedValue)
                }
            }
            .labelsHidden()
            .accessibilityIdentifier(MobileAccessibilityID.smartRuleValue)
        } else if rule.field != .isPinned, rule.field != .isRemote {
            TextField(SmartRuleWords.placeholder(for: rule.field), text: stringBinding(default: ""))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier(MobileAccessibilityID.smartRuleValue)
        }
    }

    private func stringBinding(default fallback: String) -> Binding<String> {
        Binding(get: { rule.value.stringValue ?? fallback }, set: { rule.value = .string($0) })
    }

    private var ageBinding: Binding<Int> {
        Binding(
            get: { rule.value.intValue ?? SmartRuleWords.ageChoices[1].seconds },
            set: { rule.value = .int($0) }
        )
    }
}
