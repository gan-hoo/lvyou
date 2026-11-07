import SwiftUI

/// 全球景点搜索页。
struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = SearchViewModel()
    @State private var isSearchPresented = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("搜索景点")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") { dismiss() }
                    }
                }
                .searchable(
                    text: $viewModel.query,
                    isPresented: $isSearchPresented,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text("搜索景点、城市或地址")
                )
                .autocorrectionDisabled()
                .onSubmit(of: .search) { viewModel.submit() }
                .onChange(of: viewModel.query) { viewModel.queryDidChange() }
                .onAppear { isSearchPresented = true }
                .travelDestinations()
        }
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .idle:
            examplesList
        case .suggestions:
            suggestionsList
        case .loading:
            ProgressView("正在搜索…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .results:
            resultsList
        case .noResults:
            ContentUnavailableView.search(text: viewModel.trimmedQuery)
        case .failure(let message):
            ContentUnavailableView {
                Label("搜索失败", systemImage: "wifi.exclamationmark")
            } description: {
                Text(message)
            } actions: {
                Button("重试") { viewModel.retry() }
                    .buttonStyle(.bordered)
            }
        }
    }

    private var examplesList: some View {
        List {
            Section {
                ForEach(SearchViewModel.examples, id: \.self) { example in
                    Button {
                        viewModel.search(example: example)
                    } label: {
                        Label(example, systemImage: "magnifyingglass")
                            .foregroundStyle(.primary)
                    }
                }
            } header: {
                Text("试试搜索")
            } footer: {
                Text("支持国家、城市、自然景观、博物馆、建筑、公园、海滩等 Apple 地图收录的地点。")
            }
        }
    }

    private var suggestionsList: some View {
        List {
            Button {
                viewModel.submit()
            } label: {
                Label("搜索“\(viewModel.trimmedQuery)”", systemImage: "magnifyingglass")
                    .foregroundStyle(.tint)
            }

            ForEach(viewModel.suggestions) { suggestion in
                Button {
                    viewModel.select(suggestion)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.title)
                                .foregroundStyle(.primary)
                            if !suggestion.subtitle.isEmpty {
                                Text(suggestion.subtitle)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.immediately)
    }

    private var resultsList: some View {
        List(viewModel.results) { candidate in
            NavigationLink(value: candidate) {
                SearchResultRow(candidate: candidate)
            }
        }
        .listStyle(.plain)
        .scrollDismissesKeyboard(.immediately)
    }
}

#if DEBUG
#Preview {
    SearchView()
        .environment(LocationService())
        .modelContainer(PreviewSampleData.container)
}
#endif
