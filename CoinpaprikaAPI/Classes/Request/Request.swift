//
//  Request.swift
//  Coinpaprika
//
//  Created by Dominique Stranz on 17.09.2018.
//  Copyright © 2018 Grey Wizard sp. z o.o. All rights reserved.
//

import Foundation

public protocol Requestable {
    associatedtype Model: Codable & CodableModel
    func perform(responseQueue: DispatchQueue?, cachePolicy: URLRequest.CachePolicy?, _ callback: @escaping (Response<Model>) -> Void)
}

/// Request representation returned by CoinpaprikaAPI methods.
/// To perform request use .perform() method. It will call callback with error reason or
public struct Request<Model: Codable & CodableModel>: Requestable {
    
    private let baseUrl: URL
    
    public enum Method: String {
        case get
        case post
        case put
        case delete
    }

    private let method: Method
    
    private let path: String
    
    public typealias Params = [String: Any]
    
    private let params: Params?

    private let userAgent: String
    
    public enum BodyEncoding {
        case json
        case urlencode
    }
    
    private let bodyEncoding: BodyEncoding
    
    private let authorisationToken: String?
    
    /// Request initializer that may be used if you want to extend client API with another methods
    ///
    /// - Parameters:
    ///   - baseUrl: Base URL containing base path for API, like https://api.coinpaprika.com/v1/
    ///   - method: HTTP Method
    ///   - path: endpoint path like tickers/btc-bitcoin
    ///   - params: array of parameters appended in URL Query
    public init(baseUrl: URL, method: Method, path: String, params: Params?, userAgent: String = "Coinpaprika API Client - Swift", bodyEncoding: BodyEncoding = .json, authorisationToken: String? = nil) {
        self.baseUrl = baseUrl
        self.method = method
        self.path = path
        self.params = params
        self.userAgent = userAgent
        self.bodyEncoding = bodyEncoding
        self.authorisationToken = authorisationToken
    }
    
    /// Perform API request
    ///
    /// - Parameters:
    ///   - responseQueue: The queue on which the completion handler is dispatched
    ///   - cachePolicy: cache policy that should be used in this request
    ///   - callback: Completion handler triggered on request success & failure
    public func perform(responseQueue: DispatchQueue? = nil, cachePolicy: URLRequest.CachePolicy? = nil, _ callback: @escaping (Response<Model>) -> Void) {
        let onQueue = { (_ block: @escaping () -> Void) -> Void in
            (responseQueue ?? DispatchQueue.main).async(execute: block)
        }
        
        let request: URLRequest
        
        do {
            request = try buildRequest(cachePolicy: cachePolicy)
        } catch RequestError.unableToEncodeParams {
            onQueue {
                callback(Response.failure(RequestError.unableToEncodeParams))
            }
            return
        } catch {
            onQueue {
                callback(Response.failure(RequestError.unableToCreateRequest))
            }
            return
        }
        
        URLSession.shared.dataTask(with: request) { (data, urlResponse, error) in
            if let error = error {
                onQueue {
                    callback(Response.failure(error))
                }
            } else {
                guard let httpResponse = urlResponse as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
                    onQueue {
                        callback(Response.failure(self.findFailureReason(data: data, response: urlResponse)))
                    }
                    return
                }
                
                guard let data = data else {
                    onQueue {
                        callback(Response.failure(ResponseError.emptyResponse))
                    }
                    return
                }
                
                guard let value = self.decodeResponse(data) else {
                    onQueue {
                        callback(Response.failure(ResponseError.unableToDecodeResponse))
                    }
                    return
                }
                
                onQueue {
                    callback(Response.success(value))
                }
            }
        }.resume()
    }
    
    private func buildRequest(cachePolicy: URLRequest.CachePolicy? = nil) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue.uppercased()
        
        if bodyEncoding == .json {
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        
        if let authorisationToken = authorisationToken {
            request.addValue("Bearer \(authorisationToken)", forHTTPHeaderField: "Authorisation")
        }
        
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue(userAgent, forHTTPHeaderField: "User-Agent")
        
        do {
            request.httpBody = try encodeBody()
        } catch {
            throw RequestError.unableToEncodeParams
        }
        
        return request
    }
    
    private var url: URL {
        let url = path.isEmpty ? baseUrl : baseUrl.appendingPathComponent(path)
        
        guard method == .get, let params = params, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        
        var queryItems = components.queryItems ?? []
        
        for (key, value) in params {
            queryItems.append(URLQueryItem(name: key, value: "\(value)"))
        }
        
        components.queryItems = queryItems
        return components.url!
    }
    
    private func encodeBody() throws -> Data? {
        guard method != .get, let params = params else {
            return nil
        }
        
        switch bodyEncoding {
        case .json:
            return try JSONSerialization.data(withJSONObject: params, options: [])
        case .urlencode:
            return params.map({ "\($0.key)=\("\($0.value)".addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? $0.value)" }).joined(separator: "&").data(using: .utf8)
        }
    }

    private func findFailureReason(data: Data?, response: URLResponse?) -> ResponseError {
        guard let response = response as? HTTPURLResponse else {
            return .emptyResponse
        }
        
        switch response.statusCode {
        case 429:
            return .requestsLimitExceeded
        case 400 ..< 500:
            let decoder = JSONDecoder()
            if let data = data, let value = try? decoder.decode(APIError.self, from: data) {
                return .invalidRequest(httpCode: response.statusCode, message: value.error)
            }
            
            return .invalidRequest(httpCode: response.statusCode, message: nil)
        default: break
        }
        
        return .serverError(httpCode: response.statusCode)
    }
    
    private func decodeResponse(_ data: Data) -> Model? {
        let decoder = Model.decoder
        
        do {
            return try decoder.decode(Model.self, from: data)
        } catch DecodingError.dataCorrupted(let context) {
            assertionFailure("\(Model.self): \(context.debugDescription) from \(debugDecodeData(data))")
        } catch DecodingError.keyNotFound(let key, let context) {
            assertionFailure("\(Model.self): \(key.stringValue) was not found, \(context.debugDescription) from \(debugDecodeData(data))")
        } catch DecodingError.typeMismatch(let type, let context) {
            assertionFailure("\(Model.self): \(type) was expected, \(context.debugDescription) from \(debugDecodeData(data))")
        } catch DecodingError.valueNotFound(let type, let context) {
            assertionFailure("\(Model.self): no value was found for \(type), \(context.debugDescription) from \(debugDecodeData(data))")
        } catch {
            assertionFailure("\(Model.self): unknown decoding error from \(debugDecodeData(data))")
        }
        
        return nil
    }
    
    private func debugDecodeData(_ data: Data) -> String {
        return String(data: data, encoding: .utf8) ?? "(empty)"
    }
    
}

extension Request: CustomStringConvertible {
    public var description: String {
        let paramsDescriptor = params?.map({ "\($0.key)=\($0.value)" }).joined(separator: "&") ?? ""
        return "\(method.rawValue.uppercased()): \(baseUrl)\(path) \(paramsDescriptor)"
    }
}

struct APIError: Decodable {
    let error: String
}
