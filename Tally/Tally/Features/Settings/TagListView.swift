import SwiftUI
import SwiftData

struct TagListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Tag.name) private var tags: [Tag]
    @State private var newName = ""
    @State private var renaming: Tag?
    @State private var renameText = ""

    var body: some View {
        List {
            Section {
                HStack {
                    TextField("New tag", text: $newName)
                        .submitLabel(.done)
                        .onSubmit(add)
                    Button("Add", action: add)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            Section {
                ForEach(tags) { tag in
                    HStack {
                        Circle().fill(Color(hex: tag.colorHex)).frame(width: 10, height: 10)
                        Text(tag.name)
                        Spacer()
                        Text((tag.entries?.count ?? 0).formatted())
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        renameText = tag.name
                        renaming = tag
                    }
                }
                .onDelete { offsets in
                    for i in offsets { context.delete(tags[i]) }
                    try? context.save()
                }
            } footer: {
                Text("Deleting a tag removes it from transactions; the transactions themselves are kept.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Tags")
        .overlay {
            if tags.isEmpty {
                ContentUnavailableView("No Tags", systemImage: "number", description: Text("Tags group entries across categories, like a trip or a project."))
            }
        }
        .alert("Rename Tag", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Save") {
                let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if let tag = renaming, !trimmed.isEmpty {
                    tag.name = trimmed
                    try? context.save()
                }
                renaming = nil
            }
        }
    }

    private func add() {
        if LedgerStore(context: context).findOrCreateTag(named: newName) != nil {
            newName = ""
            Haptics.success()
        }
    }
}
