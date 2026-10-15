import Foundation

enum AppStoreConnectPermission {
    case apps
    case testFlight
    case appInfo
    case reviews
    case resources
    case users

    var deniedMessage: String {
        switch self {
        case .apps:
            return "This API key can't access the team's apps. Check that the key is active and has access to at least one app, or ask an App Store Connect Admin to update its app scope."
        case .testFlight:
            return "This API key can't access TestFlight builds. Use a key with TestFlight access (Developer, App Manager, or Admin) and make sure the app is included in its scope."
        case .appInfo:
            return "This API key can't access App Info for this app. Check the key's app scope; saving App Info requires the App Manager or Admin role."
        case .reviews:
            return "This API key can't access customer reviews for this app. Use a key with Customer Support, App Manager, or Admin access and make sure the app is included in its scope."
        case .resources:
            return "This API key can't access certificates, identifiers, devices, or profiles. These team resources require an Admin key with provisioning access."
        case .users:
            return "This API key can't access users and invitations. User management requires an Admin key for this team."
        }
    }
}

/// Single chokepoint translating errors into user-facing copy.
///
/// Raw `localizedDescription` strings (e.g. "A server with the specified
/// hostname could not be found.") mean nothing to users, so every list
/// and form routes failures through here instead of surfacing them
/// verbatim. Server-provided API messages are already meaningful and
/// pass through untouched, except 401 (the key itself is dead).
enum FriendlyErrorMessage {
    static func message(for error: Error, requiring permission: AppStoreConnectPermission) -> String {
        if let apiError = error as? APIError, apiError.statusCode == 403 {
            return permission.deniedMessage
        }
        return message(for: error)
    }

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
            if apiError.statusCode == 403 {
                return "This API key doesn't have permission for that request. Check its role and app scope in App Store Connect, or ask an Admin to create a key with broader access."
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
