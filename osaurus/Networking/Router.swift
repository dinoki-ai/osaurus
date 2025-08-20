//
//  Router.swift
//  osaurus
//
//  Created by Terence on 8/17/25.
//

import Foundation
import NIOHTTP1
import NIOCore

/// Simple routing logic for HTTP requests
public struct Router {
    /// Channel context for async operations (set by HTTPHandler)
    var context: ChannelHandlerContext?
    weak var handler: HTTPHandler?
    
    init(context: ChannelHandlerContext? = nil, handler: HTTPHandler? = nil) {
        self.context = context
        self.handler = handler
    }
    /// Routes incoming HTTP requests to appropriate responses
    /// - Parameters:
    ///   - method: HTTP method (GET, POST, etc.)
    ///   - path: URL path
    ///   - body: Request body data
    /// - Returns: Tuple containing status, headers, and response body
    public func route(method: String, path: String, body: Data = Data()) -> (status: HTTPResponseStatus, headers: [(String, String)], body: String) {
        switch (method, path) {
        case ("GET", "/health"):
            return healthEndpoint()
            
        case ("GET", "/"):
            return rootEndpoint()
            
        case ("POST", "/echo"):
            return echoEndpoint()
            
        case ("POST", "/transcribe"):
            return transcribeEndpoint()
            
        case ("GET", "/transcribe/status"):
            return transcriptionStatusEndpoint()
            
        case ("GET", "/models"):
            return modelsEndpoint()
        case ("GET", "/v1/models"):
            return modelsEndpoint()
            
        case ("POST", "/chat/completions"):
            return chatCompletionsEndpoint(body: body, context: context, handler: handler)
        case ("POST", "/v1/chat/completions"):
            return chatCompletionsEndpoint(body: body, context: context, handler: handler)
            
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
    
    private func transcribeEndpoint() -> (HTTPResponseStatus, [(String, String)], String) {
        // Note: This is a placeholder. Actual implementation would need to handle file uploads
        // and integrate with WhisperController
        let response = [
            "message": "Transcription endpoint ready",
            "note": "Implement audio file handling in HTTPHandler"
        ]
        
        let jsonData = try! JSONSerialization.data(withJSONObject: response)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        
        return (.ok, [("Content-Type", "application/json; charset=utf-8")], jsonString)
    }
    
    private func transcriptionStatusEndpoint() -> (HTTPResponseStatus, [(String, String)], String) {
        let statusResponse = [
            "status": "ready",
            "model": "whisper-base",
            "supportedFormats": ["wav", "mp3", "m4a"],
            "maxFileSizeMB": 25
        ] as [String : Any]
        
        let jsonData = try! JSONSerialization.data(withJSONObject: statusResponse)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        
        return (.ok, [("Content-Type", "application/json; charset=utf-8")], jsonString)
    }
    
    private func modelsEndpoint() -> (HTTPResponseStatus, [(String, String)], String) {
        let models = MLXService.shared.getAvailableModels().map { modelName in
            OpenAIModel(from: modelName)
        }
        
        let response = ModelsResponse(data: models)
        
        do {
            let jsonData = try JSONEncoder().encode(response)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
            return (.ok, [("Content-Type", "application/json; charset=utf-8")], jsonString)
        } catch {
            return errorResponse(message: "Failed to encode models", statusCode: .internalServerError)
        }
    }
    
    private func chatCompletionsEndpoint(body: Data, context: ChannelHandlerContext?, handler: HTTPHandler?) -> (HTTPResponseStatus, [(String, String)], String) {
        // Decode the request
        let decoder = JSONDecoder()
        guard let request = try? decoder.decode(ChatCompletionRequest.self, from: body) else {
            return errorResponse(message: "Invalid request format", statusCode: .badRequest)
        }
        
        // Async operations require context and handler
        guard let context = context, let handler = handler else {
            return errorResponse(message: "Server configuration error", statusCode: .internalServerError)
        }
        
        // Handle async generation without MainActor; writes will be marshaled to the event loop
        Task {
            AsyncHTTPHandler.shared.handleChatCompletion(
                request: request,
                context: context,
                handler: handler
            )
        }
        
        // Return empty response - actual response will be sent asynchronously
        return (.ok, [], "")
    }
    
    private func errorResponse(message: String, statusCode: HTTPResponseStatus) -> (HTTPResponseStatus, [(String, String)], String) {
        let error = OpenAIError(
            error: OpenAIError.ErrorDetail(
                message: message,
                type: "invalid_request_error",
                param: nil,
                code: nil
            )
        )
        
        do {
            let jsonData = try JSONEncoder().encode(error)
            let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
            return (statusCode, [("Content-Type", "application/json; charset=utf-8")], jsonString)
        } catch {
            return (statusCode, [("Content-Type", "application/json; charset=utf-8")], "{\"error\":{\"message\":\"Internal error\"}}")
        }
    }
}
