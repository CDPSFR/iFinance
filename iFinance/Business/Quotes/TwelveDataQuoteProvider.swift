import Foundation

/// Cours via Twelve Data (https://twelvedata.com), endpoint /quote.
/// Offre gratuite (Basic) : actions et ETF américains, devises et cryptos ; 8 requêtes par minute
/// et 800 par jour ; usage personnel. Les places européennes (Euronext…) demandent l'offre Grow
/// ou supérieure, et la recherche par ISIN l'option « Data ».
struct TwelveDataQuoteProvider: QuoteProvider {
    let id = "twelvedata"
    let displayName = "Twelve Data"
    let signupURL = URL(string: "https://twelvedata.com/pricing")
    let requiresAPIKey = true
    /// 8 requêtes par minute : une toutes les 8 secondes laisse une marge
    let minimumInterval: TimeInterval = 8
    let summary = "Offre gratuite : actions et ETF américains, devises et cryptos, 8 requêtes par minute et 800 par jour, usage personnel. Les titres européens (Euronext Paris…) et la recherche par code ISIN demandent une offre payante."

    private static let endpoint = "https://api.twelvedata.com/quote"

    func quote(for request: QuoteRequest, apiKey: String?) async throws -> Quote {
        guard let apiKey, !apiKey.isEmpty else { throw QuoteError.missingAPIKey }

        var components = URLComponents(string: Self.endpoint)
        let symbol = request.symbol.trimmingCharacters(in: .whitespaces).uppercased()
        var items = [URLQueryItem(name: "apikey", value: apiKey)]

        if request.looksLikeISIN {
            // Recherche par code ISIN
            items.append(URLQueryItem(name: "isin", value: symbol))
        } else if let separator = symbol.firstIndex(of: ":") {
            // « AI:XPAR », « AI:EPA » ou « AI:EURONEXT » : symbole, puis code MIC ou nom de place
            items.append(URLQueryItem(name: "symbol", value: String(symbol[..<separator])))
            items.append(Self.venue(String(symbol[symbol.index(after: separator)...])))
        } else {
            items.append(URLQueryItem(name: "symbol", value: symbol))
        }
        components?.queryItems = items

        guard let url = components?.url else { throw QuoteError.provider("Adresse de requête invalide.") }

        var urlRequest = URLRequest(url: url)
        urlRequest.timeoutInterval = 20
        urlRequest.cachePolicy = .reloadIgnoringLocalCacheData

        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(for: urlRequest)
        } catch {
            throw QuoteError.network(error.localizedDescription)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw QuoteError.provider("Réponse illisible du fournisseur.")
        }

        // Les erreurs arrivent avec un statut HTTP 200 et un champ « code »
        if let status = json["status"] as? String, status == "error" {
            let code = (json["code"] as? Int) ?? 0
            let message = (json["message"] as? String) ?? "Erreur du fournisseur."
            switch code {
            case 401:
                throw QuoteError.invalidAPIKey
            case 403:
                // Clé valide, mais offre insuffisante pour ce titre ou cet identifiant
                throw QuoteError.notInPlan(request.looksLikeISIN
                    ? "La recherche par code ISIN n'est pas incluse dans votre offre Twelve Data. Indiquez plutôt le symbole et la place (ex. « AI:XPAR »)."
                    : "Ce titre n'est pas couvert par votre offre Twelve Data (l'offre gratuite se limite aux places américaines).")
            case 400, 404:
                throw QuoteError.symbolNotFound(request.symbol)
            case 429:
                throw QuoteError.rateLimited
            default:
                throw QuoteError.provider(message)
            }
        }

        guard let price = Self.decimal(json["close"]) ?? Self.decimal(json["price"]), price > 0 else {
            throw QuoteError.symbolNotFound(request.symbol)
        }

        let currency = json["currency"] as? String
        if let currency, !currency.isEmpty, currency.uppercased() != request.currency.uppercased() {
            throw QuoteError.currencyMismatch(expected: request.currency, received: currency)
        }

        return Quote(
            price: price,
            currency: currency,
            date: Self.date(json) ?? Date(),
            dayChangePercent: (json["percent_change"] as? String).flatMap { Double($0) }
        )
    }

    /// Codes de place courants (notations Google Finance ou Yahoo) convertis en code MIC
    private static let micAliases: [String: String] = [
        "EPA": "XPAR", "PA": "XPAR", "PAR": "XPAR",
        "AMS": "XAMS", "AS": "XAMS",
        "EBR": "XBRU", "BR": "XBRU",
        "ELI": "XLIS", "LS": "XLIS",
        "ETR": "XETR", "DE": "XETR", "FRA": "XFRA", "F": "XFRA",
        "LON": "XLON", "L": "XLON",
        "SWX": "XSWX", "SW": "XSWX",
        "BIT": "XMIL", "MI": "XMIL",
        "BME": "XMAD", "MC": "XMAD"
    ]

    /// Paramètre de place : `mic_code` pour un code MIC (ou un alias connu), sinon `exchange` (nom de place)
    private static func venue(_ code: String) -> URLQueryItem {
        if let mic = micAliases[code] {
            return URLQueryItem(name: "mic_code", value: mic)
        }
        if code.count == 4, code.hasPrefix("X") {
            return URLQueryItem(name: "mic_code", value: code)
        }
        return URLQueryItem(name: "exchange", value: code)
    }

    private static func decimal(_ value: Any?) -> Decimal? {
        if let string = value as? String {
            return Decimal(string: string, locale: Locale(identifier: "en_US_POSIX"))
        }
        if let number = value as? NSNumber {
            return Decimal(string: number.stringValue, locale: Locale(identifier: "en_US_POSIX"))
        }
        return nil
    }

    /// « timestamp » (secondes) si présent, sinon « datetime » (yyyy-MM-dd ou yyyy-MM-dd HH:mm:ss)
    private static func date(_ json: [String: Any]) -> Date? {
        if let timestamp = json["timestamp"] as? Double {
            return Date(timeIntervalSince1970: timestamp)
        }
        if let timestamp = json["timestamp"] as? Int {
            return Date(timeIntervalSince1970: TimeInterval(timestamp))
        }
        guard let text = json["datetime"] as? String else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }
}
