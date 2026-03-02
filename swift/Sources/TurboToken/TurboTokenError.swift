import Foundation

/// Errors thrown by TurboToken.
public enum TurboTokenError: Error, LocalizedError {
    case unknownEncoding(String)
    case unknownModel(String)
    case encodingFailed(String)
    case decodingFailed(String)
    case tokenLimitExceeded(limit: Int)
    case downloadFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unknownEncoding(let msg): return msg
        case .unknownModel(let msg): return msg
        case .encodingFailed(let msg): return msg
        case .decodingFailed(let msg): return msg
        case .tokenLimitExceeded(let limit): return "Token limit of \(limit) exceeded"
        case .downloadFailed(let msg): return msg
        }
    }
}
