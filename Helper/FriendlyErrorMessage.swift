import Foundation

/// Single chokepoint translating errors into user-facing copy.
///
/// Raw `localizedDescription` strings (e.g. "A server with the specified
/// hostname could not be found.") mean nothing to users, so every list
/// and form routes failures through here instead of surfacing them
/// verbatim. Server-provided API messages are already meaningful and
/// pass through untouched, except 401 (the key itself is dead).
enum FriendlyErrorMessage {
    static func message(for error: Error) -> String {
        if let urlError = error as? URLError {
            return message(for: urlError.code)
        }
        // Errors bridged from Objective-C surface as NSError, not URLError.
        let nsError = error as NSError
        if nsError.domain == (NSURLErrorDomain as String) {
            return message(for: URLError.Code(rawValue: nsError.code))
        }
        if let apiError = error as? APIError {
            if apiError.statusCode == 401 {
                return "Your API key was rejected. Re-add the team with a valid key."
            }
            if let code = apiError.statusCode, (500...599).contains(code) {
                return "App Store Connect is having trouble. Please try again in a bit."
            }
            return apiError.details
        }
        return "Something went wrong. Check your connection and try again."
    }

    private static func message(for code: URLError.Code) -> String {
        switch code {
        case .notConnectedToInternet, .networkConnectionLost,
             .dnsLookupFailed, .cannotFindHost, .cannotConnectToHost,
             .dataNotAllowed:
            return "You're offline. Check your internet connection and try again."
        case .timedOut:
            return "The request timed out. Check your connection and try again."
        case .secureConnectionFailed, .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid,
             .serverCertificateUntrusted:
            return "Couldn't establish a secure connection. Please try again."
        case .userAuthenticationRequired:
            return "Your API key was rejected. Re-add the team with a valid key."
        default:
            return "Something went wrong. Check your connection and try again."
        }
    }
}
