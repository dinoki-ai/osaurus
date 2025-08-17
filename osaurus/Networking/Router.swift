//
//  Router.swift
//  osaurus
//
//  Created by Terence on 8/17/25.
//

import Foundation
import NIOHTTP1

/// Simple routing logic for HTTP requests
public struct Router {
    /// Routes incoming HTTP requests to appropriate responses
    /// - Parameters:
    ///   - method: HTTP method (GET, POST, etc.)
    ///   - path: URL path
    /// - Returns: Tuple containing status, headers, and response body
    public func route(method: String, path: String) -> (status: HTTPResponseStatus, headers: [(String, String)], body: String) {
        switch (method, path) {
        case ("GET", "/health"):
            return healthEndpoint()
            
        case ("GET", "/"):
            return rootEndpoint()
            
        case ("POST", "/echo"):
            return echoEndpoint()
            
        default:
            return notFoundEndpoint()
        }
    }
    
    // MARK: - Private Endpoints
    
    private func healthEndpoint() -> (HTTPResponseStatus, [(String, String)], String) {
        let healthResponse = [
            "status": "healthy",
            "timestamp": Date().ISO8601Format()
        ]
        
        let jsonData = try! JSONSerialization.data(withJSONObject: healthResponse)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        
        return (.ok, [("Content-Type", "application/json; charset=utf-8")], jsonString)
    }
    
    private func rootEndpoint() -> (HTTPResponseStatus, [(String, String)], String) {
        return (.ok, [("Content-Type", "text/plain; charset=utf-8")], "Osaurus Server is running! 🦕")
    }
    
    private func echoEndpoint() -> (HTTPResponseStatus, [(String, String)], String) {
        return (.ok, [("Content-Type", "text/plain; charset=utf-8")], "Echo endpoint received request")
    }
    
    private func notFoundEndpoint() -> (HTTPResponseStatus, [(String, String)], String) {
        return (.notFound, [("Content-Type", "text/plain; charset=utf-8")], "Not Found")
    }
}
