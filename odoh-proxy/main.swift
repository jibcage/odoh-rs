//
//  main.swift
//  odoh-proxy-macos
//
//  Created by Jack Kim-Biggs on 11/13/21.
//

import Foundation
import NetworkExtension

autoreleasepool {
    NEProvider.startSystemExtensionMode()
}

dispatchMain()
