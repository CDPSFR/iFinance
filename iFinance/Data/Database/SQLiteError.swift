import Foundation

enum SQLiteError: Error, LocalizedError {
    case openDatabase(message: String)
    case prepare(message: String)
    case step(message: String)
    case bind(message: String)
    case executeQuery(message: String)
    
    var errorDescription: String? {
        switch self {
        case .openDatabase(let message):
            return "Impossible d'ouvrir la base de données: \(message)"
        case .prepare(let message):
            return "Erreur de préparation de la requête: \(message)"
        case .step(let message):
            return "Erreur d'exécution: \(message)"
        case .bind(let message):
            return "Erreur de binding: \(message)"
        case .executeQuery(let message):
            return "Erreur d'exécution de la requête: \(message)"
        }
    }
}
