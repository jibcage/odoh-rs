//
//  HTTPSupport.swift
//  odoh-proxy
//
//  Created by Jack Kim-Biggs on 11/13/21.
//

import Foundation
import NetworkExtension
import os.log

enum HTTPError: Error {
    case invalidEndpoint
    case invalidResponse
    case httpError(statusCode: Int)
}

class HTTPRequest {
    enum HTTPHeader {
        case accept(String)
        case contentType(String)
        case cacheControl(String)

        var headerString: String {
            switch self {
            case .accept:
                return "Accept"
            case .contentType:
                return "Content-Type"
            case .cacheControl:
                return "Cache-Control"
            }
        }

        var headerValue: String {
            switch self {
            case .accept(let val), .contentType(let val), .cacheControl(let val):
                return val
            }
        }
    }
    var headers: [HTTPHeader] {
        []
    }

    enum HTTPMethod: String {
        case get = "GET"
        case post = "POST"
    }
    var method: HTTPMethod {
        .get
    }

    var httpBody: Data?

    func path() -> String {
        return ""
    }

    func asURLRequest() throws -> URLRequest {
        guard let endpoint = URL(string: self.path()) else {
            throw HTTPError.invalidEndpoint
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = method.rawValue
        for header in headers {
            request.addValue(header.headerValue, forHTTPHeaderField: header.headerString)
        }

        request.httpBody = self.httpBody
        return request
    }

    typealias SuccessHandler = (Data) -> ()
    typealias ErrorHandler = (Error) -> ()
    func send(success: @escaping SuccessHandler, failure: @escaping ErrorHandler) throws {
        let task = URLSession.shared.dataTask(with: try self.asURLRequest()) { data, response, error in
            if let error = error {
                failure(error)
                return
            }
            guard let response = response as? HTTPURLResponse else {
                failure(HTTPError.invalidResponse)
                return
            }
            if response.statusCode == 200, let data = data {
                success(data)
            } else {
                if let data = data, let responseString = String(data: data, encoding: .utf8) {
                    os_log(.error, "Received HTTP error code %d: %s", response.statusCode, responseString)
                }
                failure(HTTPError.httpError(statusCode: response.statusCode))
            }
        }
        task.resume()
    }
}

class DNSDataRequest: HTTPRequest {
    override var headers: [HTTPRequest.HTTPHeader] {
        [.accept("application/octet-stream")]
    }

    init(requestData: Data? = nil) {
        super.init()
        self.httpBody = requestData
    }
}
