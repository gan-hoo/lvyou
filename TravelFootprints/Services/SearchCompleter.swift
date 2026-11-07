import Foundation
import MapKit

/// 输入联想条目。
struct SearchSuggestion: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let completion: MKLocalSearchCompletion

    init(completion: MKLocalSearchCompletion) {
        self.completion = completion
        self.title = completion.title
        self.subtitle = completion.subtitle
        self.id = completion.title + "\n" + completion.subtitle
    }

    static func == (lhs: SearchSuggestion, rhs: SearchSuggestion) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// MKLocalSearchCompleter 的轻量封装。
/// MKLocalSearchCompleter 自带节流，无需额外防抖。
@MainActor
final class SearchCompleter: NSObject {
    var onUpdate: (@MainActor ([SearchSuggestion]) -> Void)?
    var onFailure: (@MainActor (Error) -> Void)?

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.pointOfInterest, .address]
    }

    func update(query: String) {
        if query.isEmpty {
            completer.cancel()
            onUpdate?([])
        } else {
            completer.queryFragment = query
        }
    }

    func cancel() {
        completer.cancel()
    }

    private func publish(_ completions: [MKLocalSearchCompletion]) {
        var seen = Set<String>()
        let suggestions = completions
            .map(SearchSuggestion.init(completion:))
            .filter { seen.insert($0.id).inserted }
        onUpdate?(suggestions)
    }
}

extension SearchCompleter: MKLocalSearchCompleterDelegate {
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = completer.results
        Task { @MainActor [weak self] in
            self?.publish(results)
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.onFailure?(error)
        }
    }
}
