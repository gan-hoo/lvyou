import Foundation
import MapKit

/// 搜索错误。
enum PlaceSearchError: LocalizedError, Equatable {
    case network
    case throttled
    case failed(String)

    init(_ error: Error) {
        if let mkError = error as? MKError {
            switch mkError.code {
            case .serverFailure: self = .network
            case .loadingThrottled: self = .throttled
            default: self = .failed(mkError.localizedDescription)
            }
        } else if (error as NSError).domain == NSURLErrorDomain {
            self = .network
        } else {
            self = .failed(error.localizedDescription)
        }
    }

    var errorDescription: String? {
        switch self {
        case .network: String(localized: "网络连接异常，请检查网络后重试。")
        case .throttled: String(localized: "搜索过于频繁，请稍后再试。")
        case .failed(let message): String(localized: "搜索失败：\(message)")
        }
    }
}

/// 使用 MKLocalSearch 获取完整的地点信息。
@MainActor
final class PlaceSearchService {
    private var activeSearch: MKLocalSearch?

    static func request(forQuery query: String) -> MKLocalSearch.Request {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.pointOfInterest, .address]
        return request
    }

    static func request(for completion: MKLocalSearchCompletion) -> MKLocalSearch.Request {
        let request = MKLocalSearch.Request(completion: completion)
        request.resultTypes = [.pointOfInterest, .address]
        return request
    }

    /// 执行搜索。新的搜索会取消尚未完成的旧搜索。
    /// 无结果时返回空数组；网络等错误抛出 `PlaceSearchError`。
    func search(_ request: MKLocalSearch.Request) async throws -> [PlaceCandidate] {
        cancel()
        let search = MKLocalSearch(request: request)
        activeSearch = search
        defer {
            if activeSearch === search { activeSearch = nil }
        }

        do {
            let response = try await search.start()
            try Task.checkCancellation()
            return PlaceCandidate.deduplicated(response.mapItems.compactMap(PlaceCandidate.init(mapItem:)))
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as MKError where error.code == .placemarkNotFound {
            return []
        } catch {
            throw PlaceSearchError(error)
        }
    }

    func cancel() {
        activeSearch?.cancel()
        activeSearch = nil
    }
}
