//
//  APIManager.swift
//  App Store
//
//  Created by Nayan Bhut on 13/05/25.
//

import Foundation
import JSONAPI

final class APIClient {
    typealias JSONTaskCompletionHandler = (Data?, APIError?) -> Void
    
    static let shared = APIClient()
    private let baseURL = "https://api.appstoreconnect.apple.com/"
    
    private init() { }
    
    private func decodingTask(with request: URLRequest, completionHandler completion: @escaping JSONTaskCompletionHandler) -> URLSessionDataTask {
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(nil, .requestFailed)
                return
            }
            
            print("\n🟢🟢🟢 API Details ❇️❇️❇️")
            print("\nAPI URL: \(request)\n")
            print("API Method: \(request.httpMethod ?? "GET") Status Code: \(httpResponse.statusCode)\n")
            print("API Header:\n\(String(describing: request.allHTTPHeaderFields))\n")
            print("Response Header:\n \(httpResponse.allHeaderFields)")
            
            // Print request body
            if let body = request.httpBody, let json = body.getJsonValue() {
                json.printJson()
            }
            
            // Print api request
            if let data = data, let jsonResponse = data.getJsonValue() {
                jsonResponse.printJsonResponse()
            }
            
            completion(data, nil)
        }
        return task
    }
    
    func callAPI(with request: URLRequest, completion: @escaping (Result<Data, APIError>) -> Void) {
        let task = self.decodingTask(with: request) { data, error in
            // MARK: change to main queue
            DispatchQueue.main.async {
                if let data = data {
                    completion(Result.success(data))
                } else {
                  if let error = error {
                      completion(Result.failure(APIError.apiError(error: error.localizedDescription)))
                  } else {
                      completion(Result.failure(APIError.invalidData))
                  }
                }
            }
        }
        task.resume()
    }
    
    func getRequest(api: APIMethod, apiVersion: APIVersion = .v1) -> URLRequest? {
        guard let team = CredentialStorage.shared.selectedTeam else { return nil }
        
        if let url = getURL(api: api, apiVersion: apiVersion) {
            var request = URLRequest(url: url)
            request.allHTTPHeaderFields = getHeader(team: team)
            request.httpMethod = api.httpMethod.0
            request.httpBody = getAPIBody(httpMethod: api)
            return request
        }
        return nil
    }
    
    func getRequest(header: [String: String], api: APIMethod, apiVersion: APIVersion = .v1) -> URLRequest? {
        if let url = getURL(api: api, apiVersion: apiVersion) {
            var request = URLRequest(url: url)
            request.allHTTPHeaderFields = header
            request.httpMethod = api.httpMethod.0
            request.httpBody = getAPIBody(httpMethod: api)
            return request
        }
        return nil
    }
    
    private func getAPIBody(httpMethod: APIMethod) -> Data? {
        switch httpMethod {
        case .post(_ ,let body, _, _), .put(_, let body, _, _), .patch(_, let body, _, _):
            return body
        default:
            return nil
        }
    }
    
    private func getHeader(team: Credential?) -> [String: String] {
        var requestHeader = ["Content-Type": "application/json"]
        
        guard let credential = team else { return requestHeader }
        
        if let token = try? JWT(keyIdentifier: credential.keyID, issuerIdentifier: credential.issuerID, expireDuration: 60 * 20).signedToken(using: credential.privateKey) {
            requestHeader["Authorization"] = "Bearer " + token
        }
        return requestHeader
    }
    
    private func getURL(api: APIMethod, apiVersion: APIVersion = .v1) -> URL? {
        let strUrl = baseURL + apiVersion.rawValue + api.httpMethod.1 + api.apiPath
        
        if let queryItems = api.queryItems, var components = URLComponents(string: strUrl) {
            if queryItems.isEmpty == false {
                components.queryItems =  queryItems
            }
            return components.url
        }
        
        return nil
    }
}

extension Dictionary {
    var json: String {
        let invalidJson = "Not a valid JSON"
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: self, options: .prettyPrinted)
            return String(bytes: jsonData, encoding: String.Encoding.utf8) ?? invalidJson
        } catch {
            return invalidJson
        }
    }

    func printJson() {
        print("======= API Body Params:======= \n\(json)\n\n")
    }

    func printJsonResponse() {
        print("======= API Response:======= \n\(json)\n=====================\n\n")
    }

    func printHeader() {
        print("======= API Header:======= \n\(json)\n")
    }
}

extension Data {
    func getJsonValue() -> [String: AnyObject]? {
        do {
            if let jsonResult = try JSONSerialization.jsonObject(with: self, options:
                                                                    JSONSerialization.ReadingOptions.allowFragments) as? NSDictionary {
                if let responseDict = jsonResult as? [String: AnyObject] {
                    return responseDict
                }
            }
        } catch {
            print("❌ \(String(data: self, encoding: .utf8) ?? error.localizedDescription)")
        }
        return nil
    }
}

enum APIError: Error {
    case requestFailed
    case jsonConversionFailure
    case invalidData
    case responseUnsuccessful
    case jsonParsingFailure
    case apiErrorWithCode(error: String, _ statusCode: Int? = nil, _ apiError: Error? = nil)
    case apiError(error: String)
    case noResponse(statusCode: String)
    case otherResponse(statusCode: String)
    case statusResponse(error: String)

    var details: String {
        switch self {
        case .requestFailed:
            return "Request Failed"
        case .invalidData:
            return "Invalid Data"
        case .responseUnsuccessful:
            return "Response Unsuccessful"
        case .jsonParsingFailure:
            return "JSON Parsing Failure"
        case .jsonConversionFailure:
            return "JSON Conversion Failure"
        case .apiErrorWithCode(let error, _, _):
            return error.localizedLowercase
        case .apiError(let error):
            return error
        case .noResponse(let statusCode):
            return statusCode
        case .otherResponse(let statusCode):
            return statusCode
        case .statusResponse(let error):
            return error.localizedLowercase
        }
    }

    var statusCode: Int? {
        switch self {
        case .apiErrorWithCode(_, let code, _):
            return code

        default:
            return nil
        }
    }
}

enum APIName: String {
    case getAllApps = "/apps"
    case getAppVersions = "/preReleaseVersions"
    case getVersionBuilds = "/builds"
    case postReleaseNote = "/betaBuildLocalizations"
}

enum APIVersion: String {
    case v1 = "v1"
    case v2 = "v2"
    case v3 = "v3"
}

enum APIMethod {
    case get(name: APIName, queryParams: [String: String] = [:], path: String = "")
    case post(name: APIName, body: Data, queryParams: [String: String] = [:], path: String = "")
    case put(name: APIName, body: Data, queryParams: [String: String] = [:], path: String = "")
    case patch(name: APIName, body: Data, queryParams: [String: String] = [:], path: String = "")
    case delete(name: APIName, queryParams: [String: String] = [:], path: String = "")
    
    var httpMethod:(String, String) {
        switch self {
        case .get(let apiName, _, _):
            return ("GET",apiName.rawValue)
        case .post(let apiName, _, _, _):
            return ("POST",apiName.rawValue)
        case .put(let apiName, _, _, _):
            return ("PUT",apiName.rawValue)
        case .patch(let apiName, _, _, _):
            return ("PATCH",apiName.rawValue)
        case .delete(let apiName, _, _):
            return ("DELETE",apiName.rawValue)
        }
    }
    
    var queryItems:[URLQueryItem]? {
        switch self {
        case .get(_, let params, _), .delete(_, let params, _):
            return params.map{ URLQueryItem(name: $0, value: String(describing: $1)) }
        case .post(_, _, let params, _), .put(_, _, let params, _), .patch(_, _, let params, _):
            return params.map{ URLQueryItem(name: $0, value: String(describing: $1)) }
        }
    }
    
    var apiPath: String {
        switch self {
        case .get(_,  _, let path), .delete(_, _, let path), .post(_, _, _, let path), .put(_, _, _, let path), .patch(_, _, _, let path):
            return path.isEmpty ? "" : "/\(path)"
        }
    }
}


func getDecoder() -> JSONAPIDecoder {
    let decoder = JSONAPIDecoder()
    decoder.ignoresMissingResources = true
    decoder.ignoresUnhandledResourceTypes = true
    
    return decoder
}
