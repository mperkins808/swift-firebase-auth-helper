// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation
import Alamofire
import FirebaseAuth


public enum ResponseResult {
    case OK
    case ERROR
}

public enum ContentType {
    case json
    case form
}


public struct GenericResponse  {
    var status : ResponseResult
    var code : Int
    var message : String
    var data: Data?
    var errorMessage: String?
}

public struct ErrorMessage : Codable {
    var error : String
}



public class AuthHelper {
    // Function to return Basic Authentication string
    private func basicAuth(user: String, password: String) -> String {
        let credentialData = "\(user):\(password)".data(using: .utf8)!
        let base64Credentials = credentialData.base64EncodedString()
        return "Basic \(base64Credentials)"
    }
    
    // Function to return Bearer Token Authentication string
    private func bearerAuth(token: String) -> String {
        return "Bearer \(token)"
    }
    
    private func normalize(_ inputURL: String) -> String {
        guard var components = URLComponents(string: inputURL) else {
            return inputURL
        }
        
        components.path = ""
        
        // Build the normalized URL string
        return components.url?.absoluteString ?? inputURL
    }
    
    private func urlFormEncoded(from parameters: [String: String]) -> String {
        return parameters.map { key, value in
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            return "\(encodedKey)=\(encodedValue)"
        }.joined(separator: "&")
    }

    
    public static func convertToDictionary<T: Encodable>(_ object: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(object)
        let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
        return jsonObject as? [String: Any] ?? [:]
    }
    
    
    struct EndpointURL {
        let endpoint: String
        let queryParams: [String: String]

        func url() -> String {
            guard !queryParams.isEmpty else { return endpoint }

            var components = URLComponents(string: endpoint)
            components?.queryItems = queryParams.map { URLQueryItem(name: $0.key, value: $0.value) }

            return components?.url?.absoluteString ?? endpoint
        }
    }
    
    // Authenticates with firebase to make request
    public static func SimpleAuthedRequest(endpoint: String, method: HTTPMethod, params : [String : String]? = nil, completion: @Sendable @escaping(GenericResponse) -> Void) {
        if let user = Auth.auth().currentUser {
            user.getIDToken() { token, error in
                if let error = error {
                    return completion(GenericResponse(status: .ERROR, code: 0, message: error.localizedDescription))
                }
                guard let token = token else {
                    return completion(GenericResponse(status: .ERROR, code: 401, message: "Failed to get token"))
                }
                
                var url = endpoint
                if let params = params, !params.isEmpty {
                    var components = URLComponents(string: url)
                    components?.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
                    url = components?.url?.absoluteString ?? url
                }
                
                return AuthHelper.SimpleRequest(endpoint: url, method: method, token: token, completion: completion)
            }
        }
    }
    
    // Authenticates with firebase to make a request with a body attached
    public static func AuthedBodyRequest<T: Codable>(endpoint: String, method: HTTPMethod, data: T, contentType: ContentType, completion: @Sendable @escaping(GenericResponse) -> Void) {
        if let user = Auth.auth().currentUser {
            user.getIDToken() { token, error in
                if let error = error {
                    return completion(GenericResponse(status: .ERROR, code: 0, message: error.localizedDescription))
                }
                guard let token = token else {
                    return completion(GenericResponse(status: .ERROR, code: 401, message: "Failed to get token"))
                }
                return AuthHelper.BodyRequest(endpoint: endpoint, data: data, token: token, contentType: contentType, method: method, completion: completion)
            }
        }
    }
    
    public static func SimpleRequest(endpoint: String, method: HTTPMethod, user: String? = nil, password: String? = nil, token: String? = nil, completion: @Sendable @escaping(GenericResponse) -> Void) {
        guard let url = URL(string: endpoint) else {
            completion(GenericResponse(status: .ERROR, code: 0,  message: "Invalid URL"))
            return
        }
        var headers: HTTPHeaders = [:]
        if let token = token, token != "" {
            headers.add(.authorization(bearerToken: token))
        } else if let user = user, let password = password, user != "", password != "" {
            headers.add(.authorization(username: user, password: password))
        }
        
        AF.request(url, method: method, headers: headers).validate().response { response in
            switch response.result {
            case .success:
                completion(GenericResponse(status: .OK, code: response.response?.statusCode ?? 0, message: "Request succeeded", data: response.data))
                
            case .failure(let error):
                if let httpResponse = response.response {
                    if let data = response.data {
                        completion(GenericResponse(status: .ERROR, code: httpResponse.statusCode, message: String(data: data, encoding: .utf8) ?? "Requested failed with code: \(httpResponse.statusCode)"))
                    } else {
                        completion(GenericResponse(status: .ERROR, code: httpResponse.statusCode, message: "Request failed with code: \(httpResponse.statusCode)"))

                    }
                } else {
                    completion(GenericResponse(status: .ERROR, code: 0, message: "Request failed: \(error.localizedDescription)"))
                }
            }
        }
    }

    
    public static func BodyRequest<T: Codable>(endpoint : String, data : T, user: String? = nil, password: String? = nil, token: String? = nil, contentType: ContentType, method: HTTPMethod, completion: @Sendable @escaping (GenericResponse) -> Void) {
        
        guard let url = URL(string: endpoint) else {
            completion(GenericResponse(status: .ERROR, code: 0,  message: "Invalid URL"))
            return
        }

        // Prepare headers
        var headers: HTTPHeaders = [:]
        
        // Set Content-Type based on the provided contentType
        switch contentType {
        case .json:
            headers.add(name: "Content-Type", value: "application/json")
        case .form:
            headers.add(name: "Content-Type", value: "application/x-www-form-urlencoded")
        }
        
        // Add Authorization header if provided
        if let token = token, token != "" {
            headers.add(.authorization(bearerToken: token))
        } else if let user = user, let password = password, user != "", password != "" {
            headers.add(.authorization(username: user, password: password))
        }

        // Prepare the body for the request based on the content type
        var body: [String: Any] = [:]
        var encoding: ParameterEncoding = URLEncoding.default
        
        switch contentType {
        case .json:
            // JSON encoding
            guard let jsonData = try? JSONEncoder().encode(data),
                  let jsonDict = try? JSONSerialization.jsonObject(with: jsonData, options: []) as? [String: Any] else {
                completion(GenericResponse(status: .ERROR, code: 0, message: "Failed to encode JSON"))
                return
            }
            body = jsonDict
            encoding = JSONEncoding.default
        
        case .form:
            // Form encoding, manually convert the Codable object to a dictionary
            guard let dict = try? AuthHelper.convertToDictionary(data) else {
                completion(GenericResponse(status: .ERROR, code: 0, message: "Failed to encode form data"))
                return
            }
            body = dict
            encoding = URLEncoding.default
        }
        
        // Perform the POST request using Alamofire
        AF.request(url, method: method, parameters: body, encoding: encoding, headers: headers).validate().response { response in
            switch response.result {
            case .success:
                if let resp = response.response {
                    completion(GenericResponse(status: .OK, code: resp.statusCode, message: "Request succeeded", data: response.data))
                }
                
                
            case .failure(let error):
                if let httpResponse = response.response {
                    if let data = response.data {
                        completion(GenericResponse(status: .ERROR, code: httpResponse.statusCode, message: String(data: data, encoding: .utf8) ?? "Requested failed with code: \(httpResponse.statusCode)"))
                    } else {
                        completion(GenericResponse(status: .ERROR, code: httpResponse.statusCode, message: "Request failed with code: \(httpResponse.statusCode)"))

                    }
                } else {
                    completion(GenericResponse(status: .ERROR, code: 0, message: "Request failed: \(error.localizedDescription)"))
                }
            }
        }
        
    }
    

}



