// SPDX-License-Identifier: MIT
import PestoCore
import SwiftUI

struct TransformRows: View {
    static let flatLimit = 8

    let transforms: [TextTransform]
    let perform: (TextTransform) -> Void

    var body: some View {
        if transforms.count <= Self.flatLimit {
            rows(transforms)
        } else {
            let sections = TextTransform.grouped(transforms)
            let primary = sections.filter { !$0.group.isSubmenu }
            let submenus = sections.filter(\.group.isSubmenu)
            ForEach(primary, id: \.group) { section in
                rows(section.transforms)
            }
            if !primary.isEmpty, !submenus.isEmpty {
                Divider()
            }
            ForEach(submenus, id: \.group) { section in
                Menu(section.group.title) { rows(section.transforms) }
            }
        }
    }

    private func rows(_ transforms: [TextTransform]) -> some View {
        ForEach(transforms, id: \.self) { transform in
            Button { perform(transform) } label: {
                Label(transform.rawValue, systemImage: transform.symbolName)
            }
        }
    }
}
