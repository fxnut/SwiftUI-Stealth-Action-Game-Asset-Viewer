import Foundation

public enum MeshParseError: Error, CustomStringConvertible {
    case unexpectedEOF
    case invalidHeader(String)
    case invalidToken(line: Int, message: String)
    case invalidCount(line: Int, message: String)
    case validationFailed(String)
    
    public var description: String {
        switch self {
        case .unexpectedEOF:
            return "Unexpected end of file."
        case .invalidHeader(let s):
            return "Invalid header: \(s)"
        case .invalidToken(let line, let message):
            return "Line \(line): \(message)"
        case .invalidCount(let line, let message):
            return "Line \(line): \(message)"
        case .validationFailed(let s):
            return "Validation failed: \(s)"
        }
    }
}
