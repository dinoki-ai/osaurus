//
//  ServerConfiguration.swift
//  osaurus
//
//  Created by Terence on 8/17/25.
//

import Foundation

/// Configuration settings for the server
public struct ServerConfiguration {
    /// Server port (1-65535)
    public var port: Int
    
    /// Server host (default: localhost)
    public let host: String
    
    /// Number of threads for the event loop group
    public let numberOfThreads: Int
    
    /// Server backlog size
    public let backlog: Int32
    
    /// Default configuration
    public static var `default`: ServerConfiguration {
        ServerConfiguration(
            port: 8080,
            host: "127.0.0.1",
            numberOfThreads: ProcessInfo.processInfo.activeProcessorCount,
            backlog: 256
        )
    }
    
    /// Validates if the port is in valid range
    public var isValidPort: Bool {
        (1..<65536).contains(port)
    }
}
