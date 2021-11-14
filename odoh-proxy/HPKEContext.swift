//
//  HPKEBridge.swift
//  odoh-proxy
//
//  Created by Jack Kim-Biggs on 11/13/21.
//

import Foundation
import os.log

enum HPKEError: Error {
    case encryptionError
    case decryptionError
}

struct HPKEContext {
    // A proper implementation would free this in deinit.
    // We don't care because this stays alive for the duration of the proxy provider.
    private let context: UnsafePointer<OdohConfigContext>

    init?(odohConfigData: Data) {
        var context: UnsafePointer<OdohConfigContext>? = nil

        let count = odohConfigData.count
        let nsData = odohConfigData as NSData
        let bytes = nsData.bytes.bindMemory(to: UInt8.self, capacity: count)
        guard odoh_create_context(&context, bytes, count) else {
            return nil
        }

        guard let context = context else {
            return nil
        }

        self.context = context
    }

    func encrypt(query: Data) -> Result<(Data, OdohSecret), HPKEError> {
        var bytes: UnsafeMutablePointer<UInt8>? = nil
        var len: size_t = 0
        var secret: OdohSecret = emptyOdohSecret

        let queryLen = query.count
        let nsData = query as NSData
        let queryPtr = nsData.bytes.bindMemory(to: UInt8.self, capacity: queryLen)
        guard odoh_encrypt_query(&bytes, &len, &secret, queryPtr, queryLen, context) else {
            return .failure(.encryptionError)
        }
        guard let bytes = bytes else {
            return .failure(.encryptionError)
        }
        let data = Data(bytesNoCopy: bytes, count: len, deallocator: .free)
        return .success((data, secret))
    }

    func decrypt(response: Data, originalQuery: Data, withSecret secret: inout OdohSecret) -> Result<Data, HPKEError> {
        var bytes: UnsafeMutablePointer<UInt8>? = nil
        var len: size_t = 0

        let responseCount = response.count
        let responseNsData = response as NSData
        let responsePtr = responseNsData.bytes.bindMemory(to: UInt8.self, capacity: responseCount)
        let queryCount = originalQuery.count
        let queryNsData = originalQuery as NSData
        let queryPtr = queryNsData.bytes.bindMemory(to: UInt8.self, capacity: queryCount)
        guard odoh_decrypt_response(&bytes, &len, queryPtr, queryCount, responsePtr, responseCount, &secret) else {
            return .failure(.decryptionError)
        }
        guard let bytes = bytes else {
            return .failure(.decryptionError)
        }
        let data = Data(bytesNoCopy: bytes, count: len, deallocator: .free)
        return .success(data)
    }
}

extension HPKEContext: CustomStringConvertible {
    var description: String {
        var ptr: UnsafeMutablePointer<UInt8>? = nil
        var len: Int = 0
        guard odoh_describe_config(context, &ptr, &len) else {
            return "Unknown object"
        }
        guard let ptr = ptr else {
            return "Unknown object"
        }
        let data = Data(bytesNoCopy: ptr, count: len, deallocator: .free)
        guard let result = String(data: data, encoding: .utf8) else {
            return "Unknown object"
        }
        return result
    }
}
