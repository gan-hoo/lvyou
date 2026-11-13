import Foundation

/// Optional, user-initiated download of daily reference rates published by the
/// European Central Bank (via the free Frankfurter API). The app never needs the
/// network: every conversion works offline from the locally stored rate history.
struct ExchangeRateFetcher: Sendable {
    struct Quote: Sendable, Equatable {
        let base: String
        let quote: String
        let rate: Decimal
        let date: Date
    }

    enum FetchError: LocalizedError {
        case badResponse
        case noRates

        var errorDescription: String? {
            switch self {
            case .badResponse: String(localized: "The rate service is unavailable. Please try again later.")
            case .noRates: String(localized: "No rates were returned.")
            }
        }
    }

    private struct Payload: Decodable {
        let base: String
        let date: String
        let rates: [String: Decimal]
    }

    /// Currencies published by the ECB reference feed.
    static let supported: Set<String> = ["AUD", "CAD", "CNY", "EUR", "GBP", "HKD", "JPY", "KRW", "NZD", "SGD", "USD"]

    var session: URLSession = .shared

    func fetchLatest(base: String = "USD") async throws -> [Quote] {
        let symbols = CurrencyInfo.all.map(\.code).filter { $0 != base && Self.supported.contains($0) }
        let joined = symbols.joined(separator: ",")
        let endpoints = [
            "https://api.frankfurter.dev/v1/latest?base=\(base)&symbols=\(joined)",
            "https://api.frankfurter.app/latest?from=\(base)&to=\(joined)",
        ].compactMap(URL.init(string:))

        var lastError: Error = FetchError.badResponse
        for url in endpoints {
            do {
                var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    throw FetchError.badResponse
                }
                return try Self.decode(data)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    static func decode(_ data: Data) throws -> [Quote] {
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        let date = f.date(from: payload.date) ?? .now
        let quotes = payload.rates
            .filter { $0.value > 0 }
            .map { Quote(base: payload.base, quote: $0.key, rate: $0.value, date: date) }
            .sorted { $0.quote < $1.quote }
        guard !quotes.isEmpty else { throw FetchError.noRates }
        return quotes
    }
}
