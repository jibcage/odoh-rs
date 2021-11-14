//
//  ContentView.swift
//  Shared
//
//  Created by Jack Kim-Biggs on 11/13/21.
//
//  CAVEAT EMPTOR: This app's code is prototype-quality at best. Please don't use it.

import SwiftUI
import NetworkExtension
import os.log

let extensionIdentifierRoot = "org.kbiggs.testing.odoh-proxy-app.odoh-proxy"

#if os(macOS)
let extensionIdentifier = "\(extensionIdentifierRoot)-macos"
#elseif os(iOS)
let extensionIdentifier = "\(extensionIdentifierRoot)-ios"
#else
let extensionIdentifier = extensionIdentifierRoot
#endif

#if canImport(SystemExtensions)
import SystemExtensions
// this is not even remotely thread-safe, please don't use this in your app
var delegates: Set<SysextDelegate> = []
#endif

// WIP :)
func installExtension_iOS() {

}

func installExtension_macOS() {
#if canImport(SystemExtensions)
    let manager = OSSystemExtensionManager.shared
    let request = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: extensionIdentifier, queue: .main)

    let delegate = SysextDelegate()
    let success: SysextDelegate.SuccessCallback = { _ in
        setProvider()
        delegates.remove(delegate)
    }
    let failure: SysextDelegate.ErrorCallback = { _ in
        delegates.remove(delegate)
    }
    delegate.success = success
    delegate.failure = failure
    delegates.insert(delegate)
    
    request.delegate = delegate
    manager.submitRequest(request)
#endif
}

func setProvider() {
    let proxyManager = NEDNSProxyManager.shared()

    let proto = NEDNSProxyProviderProtocol()
    proto.providerBundleIdentifier = extensionIdentifier

    proxyManager.loadFromPreferences { maybeErr in
        if let err = maybeErr {
            os_log("Unable to load system preferences: %s", err.localizedDescription)
            return
        }

        proxyManager.providerProtocol = proto
        proxyManager.isEnabled = true

        proxyManager.saveToPreferences { maybeErr in
            if let err = maybeErr {
                os_log("Unable to save system preferences: %s", err.localizedDescription)
                return
            }
        }
    }
}

func installExtension() {
    #if os(macOS)
    installExtension_macOS()
    #elseif os(iOS)
    installExtension_iOS()
    #else
    fatalError("Not implemented on this platform.")
    #endif
}

struct ContentView: View {
    var body: some View {
        Button("Install this DNS proxy!", action: installExtension).padding()
    }
}

#if DEBUG
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
#endif
