import Foundation

enum HardwareControlError: Error {
    case unavailable
    case smc(String)
}

extension HardwareControlError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "不可用"
        case .smc(let message):
            return message
        }
    }
}
