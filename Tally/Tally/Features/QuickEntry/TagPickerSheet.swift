import SwiftUI
import SwiftData

/// Multi-select tag picker with inline tag creation.
struct TagPickerSheet: View {
    var selected: [Tag]
    var onToggle: (Tag) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Tag.name) private var tags: [Tag]
    @State private var newName = ""
    @State private var selection: Set<UUID> = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: "plus.circle.fill").foregroundStyle(DS.Colors.accent)
                        TextField("New tag", text: $newName)
                            .submitLabel(.done)
                            .onSubmit(create)
                        if !newName.trimmingCharacters(in: .whitespaces).isEmpty {
                            Button("Add", action: create).font(.subheadline.weight(.semibold))
                        }
                    }
                }

                if tags.isEmpty {
                    Section {
                        Text("Tags group entries across categories — for example a trip or a project.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        ForEach(tags) { tag in
                            Button {
                                Haptics.selection()
                                toggle(tag)
                            } label: {
                                HStack {
                                    Circle().fill(Color(hex: tag.colorHex)).frame(width: 10, height: 10)
                                    Text(tag.name).foregroundStyle(.primary)
                                    Spacer()
                                    if selection.contains(tag.id) {
                                        Image(systemName: "checkmark")
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(DS.Colors.accent)
                                            .transition(.scale.combined(with: .opacity))
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .accessibilityAddTraits(selection.contains(tag.id) ? .isSelected : [])
                        }
                    }
                }
            }
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear { selection = Set(selected.map(\.id)) }
    }

    private func toggle(_ tag: Tag) {
        withMotion(DS.Motion.snappy) {
            if selection.contains(tag.id) { selection.remove(tag.id) } else { selection.insert(tag.id) }
        }
        onToggle(tag)
    }

    private func create() {
        guard let tag = LedgerStore(context: context).findOrCreateTag(named: newName) else { return }
        newName = ""
        if !selection.contains(tag.id) { toggle(tag) }
    }
}
