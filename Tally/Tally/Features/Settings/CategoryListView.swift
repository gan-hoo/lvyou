import SwiftUI
import SwiftData

struct CategoryListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \LedgerCategory.sortOrder) private var categories: [LedgerCategory]
    @State private var kind: CategoryKind
    @State private var editor: CategoryEditorRequest?

    init(initialKind: CategoryKind) {
        _kind = State(initialValue: initialKind)
    }

    private var visible: [LedgerCategory] { categories.filter { $0.kind == kind && !$0.isArchived } }
    private var archived: [LedgerCategory] { categories.filter { $0.kind == kind && $0.isArchived } }

    var body: some View {
        List {
            Section {
                Picker("Type", selection: $kind) {
                    ForEach(CategoryKind.allCases) { k in Text(k.title).tag(k) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            Section {
                ForEach(visible) { category in
                    Button {
                        editor = CategoryEditorRequest(category: category, kind: kind)
                    } label: {
                        row(category)
                    }
                    .swipeActions {
                        Button { setArchived(category, true) } label: { Label("Hide", systemImage: "eye.slash") }
                            .tint(.gray)
                    }
                }
                .onMove(perform: move)

                Button {
                    editor = CategoryEditorRequest(category: nil, kind: kind)
                } label: {
                    Label("New Category", systemImage: "plus.circle.fill")
                }
            } footer: {
                Text("Drag to reorder. The order here is the order in quick entry.")
            }

            if !archived.isEmpty {
                Section("Hidden") {
                    ForEach(archived) { category in
                        Button {
                            editor = CategoryEditorRequest(category: category, kind: kind)
                        } label: {
                            row(category).opacity(0.55)
                        }
                        .swipeActions {
                            Button { setArchived(category, false) } label: { Label("Show", systemImage: "eye") }
                                .tint(DS.Colors.accent)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Categories")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
        }
        .sheet(item: $editor) { request in
            CategoryEditorSheet(request: request)
        }
        .animation(DS.Motion.adaptive(DS.Motion.spring), value: kind)
    }

    private func row(_ category: LedgerCategory) -> some View {
        HStack(spacing: DS.Spacing.m) {
            SymbolBadge(symbol: category.symbolName, colorHex: category.colorHex, size: 34)
            Text(category.name).foregroundStyle(.primary)
            Spacer()
            Text((category.entries?.count ?? 0).formatted())
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    private func move(from source: IndexSet, to destination: Int) {
        var list = visible
        list.move(fromOffsets: source, toOffset: destination)
        for (i, c) in list.enumerated() { c.sortOrder = i }
        try? context.save()
    }

    private func setArchived(_ category: LedgerCategory, _ value: Bool) {
        withMotion { category.isArchived = value }
        try? context.save()
        Haptics.selection()
    }
}

struct CategoryEditorRequest: Identifiable {
    let id = UUID()
    var category: LedgerCategory?
    var kind: CategoryKind
}

struct CategoryEditorSheet: View {
    let request: CategoryEditorRequest

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \LedgerCategory.sortOrder) private var categories: [LedgerCategory]

    @State private var name = ""
    @State private var symbol = "tag"
    @State private var colorHex = "3E7BFA"
    @State private var reassignID: UUID?
    @State private var confirmDelete = false
    @State private var loaded = false

    private var kind: CategoryKind { request.category?.kind ?? request.kind }

    private var reassignTargets: [LedgerCategory] {
        categories.filter { $0.kind == kind && $0.id != request.category?.id }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: DS.Spacing.m) {
                        SymbolBadge(symbol: symbol, colorHex: colorHex, size: 44, style: .solid)
                        TextField("Category name", text: $name)
                            .font(.title3.weight(.semibold))
                    }
                    .padding(.vertical, 4)
                }
                Section("Color") {
                    ColorSwatchPicker(selection: $colorHex)
                }
                Section("Icon") {
                    SymbolPickerGrid(symbols: SymbolLibrary.categories, selection: $symbol, colorHex: colorHex)
                }
                if let category = request.category {
                    Section {
                        Button("Delete Category", role: .destructive) { confirmDelete = true }
                    } footer: {
                        Text("\(category.entries?.count ?? 0) transactions use this category.")
                    }
                }
            }
            .navigationTitle(request.category == nil ? String(localized: "New Category") : String(localized: "Edit Category"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .sheet(isPresented: $confirmDelete) {
                deleteSheet
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let category = request.category {
                name = category.name
                symbol = category.symbolName
                colorHex = category.colorHex
            } else {
                colorHex = DS.Palette.swatches.randomElement() ?? "3E7BFA"
            }
        }
    }

    private var deleteSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Move transactions to", selection: $reassignID) {
                        Text("Uncategorized").tag(UUID?.none)
                        ForEach(reassignTargets) { c in
                            Label(c.name, systemImage: c.symbolName).tag(UUID?.some(c.id))
                        }
                    }
                    .pickerStyle(.inline)
                } footer: {
                    Text("Budgets for this category are removed.")
                }
            }
            .navigationTitle("Delete Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { confirmDelete = false }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Delete", role: .destructive) {
                        guard let category = request.category else { return }
                        let target = reassignTargets.first { $0.id == reassignID }
                        let store = LedgerStore(context: context)
                        confirmDelete = false
                        dismiss()
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(450))
                            store.deleteCategory(category, reassignTo: target)
                            Haptics.success()
                        }
                    }
                    .foregroundStyle(DS.Colors.danger)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let category = request.category {
            category.name = trimmed
            category.symbolName = symbol
            category.colorHex = colorHex
        } else {
            let store = LedgerStore(context: context)
            context.insert(LedgerCategory(name: trimmed, kind: kind, symbolName: symbol, colorHex: colorHex, sortOrder: store.nextCategorySortOrder(kind: kind)))
        }
        try? context.save()
        Haptics.success()
        dismiss()
    }
}
