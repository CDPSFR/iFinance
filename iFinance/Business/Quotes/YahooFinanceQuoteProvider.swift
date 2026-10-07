import Foundation

/// Cours via Yahoo Finance, sans clé d'API. Couvre les places européennes (Euronext Paris…),
/// les ETF, une partie des OPCVM et les cryptos, avec un différé d'environ 15 minutes.
///
/// Yahoo ne publie pas d'API officielle : on utilise les points d'accès de son site
/// (`v8/finance/chart` pour le cours, `v1/finance/search` pour retrouver un symbole à partir
/// d'un code ISIN). Ils peuvent changer ou être limités sans préavis ; usage personnel seulement.
///
/// Symboles acceptés :
/// - notation Yahoo : « AI.PA », « CW8.PA », « BTC-EUR » ;
/// - symbole et place : « AI:XPAR », « AI:EPA » (converti en « AI.PA ») ;
/// - code ISIN : « FR0000120073 » (recherché, puis converti en symbole Yahoo) ;
/// - crypto sans devise : « BTC » devient « BTC-EUR » pour une position en euros.
struct YahooFinanceQuoteProvider: QuoteProvider {
    let id = "yahoo"
    let displayName = "Yahoo Finance"
    let signupURL: URL? = nil
    let requiresAPIKey = false
    /// Yahoo limite vite les rafales : une requête toutes les 2 secondes
    let minimumInterval: TimeInterval = 2
    let summary = "Sans clé. Actions et ETF européens (Euronext Paris…) et américains, cryptos, une partie des OPCVM ; cours différés d'environ 15 minutes. Service non officiel : il peut être limité ou cesser de fonctionner sans préavis. Usage personnel."

    private static let chartEndpoint = "https://query1.finance.yahoo.com/v8/finance/chart/"
    private static let searchEndpoint = "https://query2.finance.yahoo.com/v1/finance/search"
    /// Yahoo refuse les requêtes sans en-tête de navigateur
    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    func quote(for request: QuoteRequest, apiKey: String?) async throws -> Quote {
        let symbol = try await yahooSymbol(for: request)

        guard let encoded = symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              var components = URLComponents(string: Self.chartEndpoint + encoded) else {
            throw QuoteError.provider("Adresse de requête invalide.")
        }
        components.queryItems = [
            URLQueryItem(name: "range", value: "1d"),
            URLQueryItem(name: "interval", value: "1d")
        ]
        guard let url = components.url else { throw QuoteError.provider("Adresse de requête invalide.") }

        let json = try await Self.fetch(url, symbol: request.symbol)

        let chart = json["chart"] as? [String: Any]
        if let error = chart?["error"] as? [String: Any] {
            let code = (error["code"] as? String) ?? ""
            if code == "Not Found" { throw QuoteError.symbolNotFound(request.symbol) }
            throw QuoteError.provider((error["description"] as? String) ?? "Erreur du fournisseur.")
        }
        guard let result = (chart?["result"] as? [[String: Any]])?.first,
              let meta = result["meta"] as? [String: Any],
              var price = Self.decimal(meta["regularMarketPrice"]), price > 0 else {
            throw QuoteError.symbolNotFound(request.symbol)
        }

        var currency = meta["currency"] as? String
        var previousClose = Self.decimal(meta["chartPreviousClose"]) ?? Self.decimal(meta["previousClose"])
        // Places de Londres : cours en pence (« GBp ») pour une position en livres
        if currency == "GBp", request.currency.uppercased() == "GBP" {
            price /= 100
            previousClose = previousClose.map { $0 / 100 }
            currency = "GBP"
        }
        if let currency, !currency.isEmpty, currency.uppercased() != request.currency.uppercased() {
            throw QuoteError.currencyMismatch(expected: request.currency, received: currency)
        }

        let date = Self.double(meta["regularMarketTime"]).map { Date(timeIntervalSince1970: $0) } ?? Date()
        let change: Double? = previousClose.flatMap { previous in
            guard previous > 0 else { return nil }
            return NSDecimalNumber(decimal: (price - previous) / previous * 100).doubleValue
        }

        return Quote(price: price, currency: currency, date: date, dayChangePercent: change)
    }

    // MARK: - Symboles

    /// Symbole Yahoo correspondant à la saisie de la position
    private func yahooSymbol(for request: QuoteRequest) async throws -> String {
        let symbol = request.symbol.trimmingCharacters(in: .whitespaces).uppercased()

        if request.looksLikeISIN {
            return try await searchSymbol(isin: symbol, request: request)
        }
        if let separator = symbol.firstIndex(of: ":") {
            let ticker = String(symbol[..<separator])
            let venue = String(symbol[symbol.index(after: separator)...])
            let suffix = Self.suffixes[venue] ?? ""
            return suffix.isEmpty ? ticker : "\(ticker).\(suffix)"
        }
        if request.assetType == .crypto, !symbol.contains("-") {
            return "\(symbol)-\(request.currency.uppercased())"
        }
        return symbol
    }

    /// Code de place (MIC, notation Google ou Yahoo) → suffixe Yahoo
    private static let suffixes: [String: String] = [
        "XPAR": "PA", "EPA": "PA", "PA": "PA", "PAR": "PA",
        "XAMS": "AS", "AMS": "AS", "AS": "AS",
        "XBRU": "BR", "EBR": "BR", "BR": "BR",
        "XLIS": "LS", "ELI": "LS", "LS": "LS",
        "XETR": "DE", "ETR": "DE", "DE": "DE",
        "XFRA": "F", "FRA": "F", "F": "F",
        "XLON": "L", "LON": "L", "L": "L",
        "XSWX": "SW", "SWX": "SW", "SW": "SW",
        "XMIL": "MI", "BIT": "MI", "MI": "MI",
        "XMAD": "MC", "BME": "MC", "MC": "MC",
        // Places américaines : pas de suffixe chez Yahoo
        "XNAS": "", "NASDAQ": "", "XNYS": "", "NYSE": "", "ARCX": "", "NYSEARCA": ""
    ]

    /// Recherche du symbole Yahoo d'un code ISIN. Préfère, parmi les titres trouvés, une place
    /// cotant dans la devise de la position (un même ISIN est souvent coté sur plusieurs places).
    private func searchSymbol(isin: String, request: QuoteRequest) async throws -> String {
        guard var components = URLComponents(string: Self.searchEndpoint) else {
            throw QuoteError.provider("Adresse de requête invalide.")
        }
        components.queryItems = [
            URLQueryItem(name: "q", value: isin),
            URLQueryItem(name: "quotesCount", value: "10"),
            URLQueryItem(name: "newsCount", value: "0")
        ]
        guard let url = components.url else { throw QuoteError.provider("Adresse de requête invalide.") }

        let json = try await Self.fetch(url, symbol: isin)
        let quotes = (json["quotes"] as? [[String: Any]] ?? []).filter {
            let type = ($0["quoteType"] as? String) ?? ""
            return ["EQUITY", "ETF", "MUTUALFUND", "INDEX", "CRYPTOCURRENCY"].contains(type) && $0["symbol"] is String
        }
        guard !quotes.isEmpty else { throw QuoteError.symbolNotFound(request.symbol) }

        // Places européennes en euros : on privilégie Paris, puis les autres places de la zone euro
        let preferred: [String] = request.currency.uppercased() == "EUR"
            ? [".PA", ".AS", ".BR", ".LS", ".DE", ".MI", ".MC", ".F"]
            : []
        for suffix in preferred {
            if let match = quotes.first(where: { ($0["symbol"] as? String)?.hasSuffix(suffix) == true }) {
                return match["symbol"] as! String
            }
        }
        return quotes[0]["symbol"] as! String
    }

    // MARK: - Réseau

    private static func fetch(_ url: URL, symbol: String) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw QuoteError.network(error.localizedDescription)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        if status == 429 { throw QuoteError.rateLimited }
        if status == 401 || status == 403 {
            throw QuoteError.provider("Yahoo Finance refuse la requête (code \(status)). Le service a peut-être changé ; réessayez plus tard ou saisissez le cours à la main.")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            if status == 404 { throw QuoteError.symbolNotFound(symbol) }
            throw QuoteError.provider("Réponse illisible du fournisseur (code \(status)).")
        }
        return json
    }

    // MARK: - Lecture des valeurs

    private static func decimal(_ value: Any?) -> Decimal? {
        if let number = value as? NSNumber {
            return Decimal(string: number.stringValue, locale: Locale(identifier: "en_US_POSIX"))
        }
        if let string = value as? String {
            return Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))
        }
        return nil
    }

    private static func double(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }
}
