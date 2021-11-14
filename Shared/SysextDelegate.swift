//
//  SysextDelegate.swift
//  odoh-proxy
//
//  Created by Jack Kim-Biggs on 11/13/21.
//

import Foundation
import SystemExtensions
import os.log

@objc class SysextDelegate: NSObject {
    typealias SuccessCallback = (OSSystemExtensionRequest.Result) -> ()
    typealias ErrorCallback = (Error) -> ()

    var success: SuccessCallback? = nil
    var failure: ErrorCallback? = nil
}

extension OSSystemExtensionError.Code: CustomStringConvertible {
    public var description: String {
        switch self {
        case .authorizationRequired:
            return "auth required"
        case .codeSignatureInvalid:
            return "cs invalid"
        case .duplicateExtensionIdentifer:
            return "duplicate identifier"
        case .extensionMissingIdentifier:
            return "extension missing identifier"
        case .extensionNotFound:
            return "extension not found"
        case .forbiddenBySystemPolicy:
            return "syspolicy forbids it!"
        case .missingEntitlement:
            return "missing entitlement"
        case .requestCanceled:
            return "request cancelled"
        case .requestSuperseded:
            return "request superseded"
        case .unknownExtensionCategory:
            return "unknown category"
        default:
            return "unknown error"
        }
    }
}

extension SysextDelegate: OSSystemExtensionRequestDelegate {
    func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties, withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        .replace
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        os_log("Request needs user approval.")
    }

    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        switch result {
        case .completed:
            os_log("Request completed.")
        case .willCompleteAfterReboot:
            os_log("Request will complete after reboot.")
        default:
            os_log("Request completed with unknown status code: %d.", result.rawValue)
        }
        self.success?(result)
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        let code = (error as NSError).code
        guard let sysextErr = OSSystemExtensionError.Code(rawValue: code) else {
            os_log("Request failed with error: %s", error.localizedDescription)
            return
        }
        os_log("Request failed with sysext error: %s", sysextErr.description)
        self.failure?(error)
    }
}
