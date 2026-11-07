import Foundation
import MapKit
import Observation

/// 全球景点搜索：输入联想（MKLocalSearchCompleter）+ 完整搜索（MKLocalSearch）。
@MainActor
@Observable
final class SearchViewModel {
    enum Phase: Equatable {
        /// 尚未输入。
        case idle
        /// 正在输入，展示联想。
        case suggestions
        case loading
        case results
        case noResults
        case failure(String)
    }

    static let examples = ["Sydney Opera House", "Tokyo Tower", "Eiffel Tower", "故宫博物院", "Grand Canyon"]

    var query = ""
    private(set) var phase: Phase = .idle
    private(set) var suggestions: [SearchSuggestion] = []
    private(set) var results: [PlaceCandidate] = []

    @ObservationIgnored private let completer = SearchCompleter()
    @ObservationIgnored private let searchService = PlaceSearchService()
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var lastTrigger: Trigger?
    /// 最近一次提交搜索时的文本，用于区分「用户继续输入」与「程序填充文本」。
    @ObservationIgnored private var submittedQuery: String?

    private enum Trigger {
        case text(String)
        case suggestion(SearchSuggestion)
    }

    init() {
        completer.onUpdate = { [weak self] suggestions in
            self?.handleSuggestions(suggestions)
        }
        completer.onFailure = { [weak self] _ in
            // 联想失败（多为无匹配）不打断输入，仍可提交完整搜索。
            self?.suggestions = []
        }
    }

    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 由视图在 `query` 变化时调用。
    func queryDidChange() {
        let text = trimmedQuery
        guard text != submittedQuery else { return }
        submittedQuery = nil
        cancelSearch()

        if text.isEmpty {
            completer.update(query: "")
            suggestions = []
            results = []
            phase = .idle
        } else {
            phase = .suggestions
            completer.update(query: text)
        }
    }

    /// 键盘「搜索」按钮。
    func submit() {
        let text = trimmedQuery
        guard !text.isEmpty else { return }
        submittedQuery = text
        run(.text(text))
    }

    func select(_ suggestion: SearchSuggestion) {
        query = suggestion.title
        submittedQuery = trimmedQuery
        run(.suggestion(suggestion))
    }

    func search(example: String) {
        query = example
        submit()
    }

    func retry() {
        guard let lastTrigger else { return }
        run(lastTrigger)
    }

    // MARK: - Private

    private func run(_ trigger: Trigger) {
        cancelSearch()
        completer.cancel()
        lastTrigger = trigger
        phase = .loading

        let request: MKLocalSearch.Request
        switch trigger {
        case .text(let text): request = PlaceSearchService.request(forQuery: text)
        case .suggestion(let suggestion): request = PlaceSearchService.request(for: suggestion.completion)
        }

        searchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let found = try await self.searchService.search(request)
                guard !Task.isCancelled else { return }
                self.results = found
                self.phase = found.isEmpty ? .noResults : .results
            } catch {
                guard !Task.isCancelled, !(error is CancellationError) else { return }
                self.results = []
                self.phase = .failure(error.localizedDescription)
            }
        }
    }

    private func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
        searchService.cancel()
    }

    private func handleSuggestions(_ suggestions: [SearchSuggestion]) {
        guard !trimmedQuery.isEmpty else { return }
        self.suggestions = suggestions
    }
}
