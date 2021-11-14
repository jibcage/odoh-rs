//
//  DNSProxyProvider.swift
//  odoh-proxy
//
//  Created by Jack Kim-Biggs on 11/13/21.
//

import NetworkExtension
import os.log

public enum SecureDNSError: Error {
    case missingData
    case invalidRequest
    case invalidContext
}

struct ObliviousDNSProxyServer {
    /// Which proxy to direct traffic to. Can be `nil`, but this defeats the purpose of ODoH.
    public let proxy: String?
    public let target: String

    /// CloudFlare is at present the only ODoH provider that I know of.
    /// See: https://blog.cloudflare.com/oblivious-dns/
    static let cloudFlare: Self = Self(proxy: "https://odoh1.surfdomeinen.nl/proxy",
                                       target: "https://odoh.cloudflare-dns.com")
}

class ObliviousDNSQuery: DNSDataRequest {
    static let queryPath = "dns-query"
    override var headers: [HTTPHeader] {
        [.contentType("application/oblivious-dns-message"),
         .accept("application/oblivious-dns-message"),
         .cacheControl("no-cache, no-store")]
    }

    override var method: HTTPMethod {
        .post
    }

    override func path() -> String {
        endpointURL.absoluteString
    }

    let endpointURL: URL

    init?(endpoint: ObliviousDNSProxyServer, encryptedRequest: Data) {
        guard let targetURL = URL(string: endpoint.target) else {
            return nil
        }

        if let proxyURLString = endpoint.proxy {
            let escapedPath = "/\(Self.queryPath)"
                .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
            guard var proxyURLComponents = URLComponents(string: proxyURLString) else {
                return nil
            }
            proxyURLComponents.queryItems = [
                URLQueryItem(name: "targethost", value: targetURL.host),
                URLQueryItem(name: "targetpath", value: escapedPath)
            ]
            guard let proxyURL = proxyURLComponents.url else {
                return nil
            }
            self.endpointURL = proxyURL
        } else {
            self.endpointURL = targetURL.appendingPathComponent(Self.queryPath)
        }
        super.init(requestData: encryptedRequest)
    }
}

class ObliviousDNSConfigRequest: DNSDataRequest {
    static let pathComponents = [".well-known", "odohconfigs"]

    override var method: HTTPMethod {
        .get
    }

    override func path() -> String {
        Self.pathComponents.reduce(endpointURL) { partialResult, pathComponent in
            partialResult.appendingPathComponent(pathComponent)
        }
        .absoluteString
    }

    let endpointURL: URL

    init?(endpoint: ObliviousDNSProxyServer) {
        // NB: Connecting to target here, instead of proxy.
        guard let endpointURL = URL(string: endpoint.target) else {
            return nil
        }
        self.endpointURL = endpointURL
        super.init()
    }
}

public class DNSProxyProvider: NEDNSProxyProvider {
    private let server: ObliviousDNSProxyServer
    private var hpkeContext: HPKEContext?

    override public init() {
        self.server = .cloudFlare
        super.init()
    }

    override public func startProxy(options: [String: Any]? = nil, completionHandler: @escaping (Error?) -> Void) {
        guard let request = ObliviousDNSConfigRequest(endpoint: self.server) else {
            completionHandler(SecureDNSError.invalidRequest)
            return
        }

        do {
            try request.send { (configData: Data) in
                guard let context = HPKEContext(odohConfigData: configData) else {
                    completionHandler(SecureDNSError.invalidContext)
                    return
                }
                self.hpkeContext = context
                completionHandler(nil)
            } failure: { err in
                completionHandler(err)
            }
        } catch let err {
            completionHandler(err)
        }
    }

    override public func stopProxy(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    typealias DNSSuccessCallback = (Data) -> ()
    typealias DNSErrorCallback = (Error) -> ()
    func encryptAndSend(request: Data,
                        success: @escaping DNSSuccessCallback,
                        failure: @escaping DNSErrorCallback)
    {
        do {
            guard let context = hpkeContext else {
                throw SecureDNSError.invalidContext
            }
            let encResult = context.encrypt(query: request)

            let (encryptedRequest, clientSecret) = try encResult.get()
            guard let req = ObliviousDNSQuery(endpoint: self.server,
                                              encryptedRequest: encryptedRequest) else {
                throw SecureDNSError.invalidRequest
            }

            try req.send { (responseData: Data) in
                var secret = clientSecret
                let decryptedResponse: Data
                do {
                    decryptedResponse = try context.decrypt(response: responseData,
                                                            originalQuery: request,
                                                            withSecret: &secret).get()
                } catch {
                    failure(error)
                    return
                }

                success(decryptedResponse)
            } failure: { error in
                failure(error)
            }
        } catch {
            failure(error)
        }
    }

    func handleFlow(tcp: NEAppProxyTCPFlow) {
        tcp.open(withLocalEndpoint: nil) { [weak self] maybeErr in
            if let err = maybeErr {
                os_log("Received error when proxying TCP request: %s", err.localizedDescription)
                return
            }
            tcp.readData { [weak self] data, error in
                guard let data = data else {
                    tcp.closeReadWithError(SecureDNSError.missingData)
                    return
                }
                self?.encryptAndSend(request: data, success: { response in
                    tcp.write(response) { error in
                        if let error = error {
                            tcp.closeReadWithError(error)
                        }
                        tcp.closeReadWithError(nil)
                        tcp.closeWriteWithError(nil)
                    }
                }, failure: { error in
                    tcp.closeReadWithError(error)
                })
            }
        }
    }

    func splitDatagrams(responseData: Data) -> [Data] {
        let datagramSize = 512
        let count = responseData.count
        var curr = 0
        var result: [Data] = []

        while curr < count {
            let end = min(curr + datagramSize, count)
            result.append(responseData[curr..<end])
            curr += datagramSize
        }
        return result
    }

    func encryptAndSend(datagrams: [Data],
                        success: @escaping DNSSuccessCallback,
                        failure: @escaping DNSErrorCallback)
    {
        // Flatten datagrams into one collection
        let data: Data = datagrams.reduce(into: Data()) { partialResult, datagram in
            partialResult.append(datagram)
        }

        self.encryptAndSend(request: data) { response in
            success(response)
        } failure: { error in
            failure(error)
        }
    }

    func handleFlow(udp: NEAppProxyUDPFlow) {
        udp.open(withLocalEndpoint: nil) { [weak self] maybeErr in
            if let err = maybeErr {
                os_log("Received error when proxying UDP request: %s", err.localizedDescription)
                return
            }
            udp.readDatagrams { [weak self] datagrams, endpoints, error in
                guard let datagrams = datagrams, let endpoint = endpoints?.first else {
                    udp.closeReadWithError(SecureDNSError.missingData)
                    return
                }
                self?.encryptAndSend(datagrams: datagrams, success: { dnsResponse in
                    guard let `self` = self else { return }
                    // Split up data into chunks that will fit into udp packets.. kind of weird, but
                    // we fudge each chunk as coming from the requested endpoint
                    let datagrams = self.splitDatagrams(responseData: dnsResponse)
                    udp.writeDatagrams(datagrams, sentBy: Array(repeating: endpoint, count: datagrams.count)) { error in
                        if let error = error {
                            udp.closeReadWithError(error)
                        }
                        udp.closeReadWithError(nil)
                        udp.closeWriteWithError(nil)
                    }
                }, failure: { error in
                    udp.closeReadWithError(error)
                })
            }
        }
    }

    override public func handleNewFlow(_ flow: NEAppProxyFlow) -> Bool {
        switch flow {
        case let tcp as NEAppProxyTCPFlow:
            handleFlow(tcp: tcp)
            return true
        case let udp as NEAppProxyUDPFlow:
            handleFlow(udp: udp)
            return true
        default:
            return false
        }
    }
}
