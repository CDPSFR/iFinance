import Foundation

/// Lecture des variations annuelles de l'indice des prix dans la base de séries de l'INSEE (BDM).
/// Service public, sans clé : seuls les identifiants des séries partent sur le réseau.
enum InseeIndexClient {
    enum ClientError: LocalizedError {
        case http(Int)
        case empty

        var errorDescription: String? {
            switch self {
            case .http(let code): return "Le site de l'INSEE a répondu par une erreur (\(code))."
            case .empty: return "Le site de l'INSEE n'a renvoyé aucune valeur."
            }
        }
    }

    static func url(for posts: [InflationPost], since year: Int) -> URL {
        let key = posts.map(\.idbank).joined(separator: "+")
        return URL(string: "https://bdm.insee.fr/series/sdmx/data/SERIES_BDM/\(key)?startPeriod=\(year)")!
    }

    /// Variations par poste et par année (0,009 = +0,9 %)
    static func fetch(posts: [InflationPost] = InflationPost.allCases, since year: Int = 2015) async throws -> [InflationPost: [Int: Double]] {
        var request = URLRequest(url: url(for: posts, since: year), timeoutInterval: 30)
        request.setValue("application/xml", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ClientError.http(http.statusCode)
        }
        let byIdbank = parse(data)
        var result: [InflationPost: [Int: Double]] = [:]
        for post in posts {
            if let years = byIdbank[post.idbank], !years.isEmpty { result[post] = years }
        }
        guard !result.isEmpty else { throw ClientError.empty }
        return result
    }

    /// Réponse SDMX : <Series IDBANK="…"> puis <Obs TIME_PERIOD="2025" OBS_VALUE="0.9"/>, en pourcentage
    static func parse(_ data: Data) -> [String: [Int: Double]] {
        let delegate = ParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.result
    }

    private final class ParserDelegate: NSObject, XMLParserDelegate {
        var result: [String: [Int: Double]] = [:]
        private var current: String?

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes: [String: String] = [:]) {
            switch elementName {
            case "Series":
                current = attributes["IDBANK"]
            case "Obs":
                guard let idbank = current,
                      let period = attributes["TIME_PERIOD"], let year = Int(period),
                      let text = attributes["OBS_VALUE"], let value = Double(text) else { return }
                result[idbank, default: [:]][year] = value / 100
            default:
                break
            }
        }
    }
}
