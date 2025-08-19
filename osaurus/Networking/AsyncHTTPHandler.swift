//
//  AsyncHTTPHandler.swift
//  osaurus
//
//  Created by Osaurus on 1/29/25.
//

import Foundation
import NIOCore
import NIOHTTP1

/// Handles async operations for HTTP endpoints
class AsyncHTTPHandler {
    static let shared = AsyncHTTPHandler()
    
    private init() {}
    
    /// Handle chat completions with streaming support
    func handleChatCompletion(
        request: ChatCompletionRequest,
        context: ChannelHandlerContext,
        handler: HTTPHandler
    ) {
        Task {
            do {
                // Find the model
                guard let model = MLXService.shared.findModel(named: request.model) else {
                    let error = OpenAIError(
                        error: OpenAIError.ErrorDetail(
                            message: "Model not found: \(request.model)",
                            type: "invalid_request_error",
                            param: "model",
                            code: nil
                        )
                    )
                    try await sendJSONResponse(error, status: .notFound, context: context, handler: handler)
                    return
                }
                
                // Convert messages
                let messages = request.toInternalMessages()
                
                // Get generation parameters
                let temperature = request.temperature ?? 0.7
                let maxTokens = request.max_tokens ?? 2048
                
                // Check if streaming is requested
                if request.stream ?? false {
                    try await handleStreamingResponse(
                        messages: messages,
                        model: model,
                        temperature: temperature,
                        maxTokens: maxTokens,
                        requestModel: request.model,
                        context: context,
                        handler: handler
                    )
                } else {
                    try await handleNonStreamingResponse(
                        messages: messages,
                        model: model,
                        temperature: temperature,
                        maxTokens: maxTokens,
                        requestModel: request.model,
                        context: context,
                        handler: handler
                    )
                }
            } catch {
                let errorResponse = OpenAIError(
                    error: OpenAIError.ErrorDetail(
                        message: error.localizedDescription,
                        type: "internal_error",
                        param: nil,
                        code: nil
                    )
                )
                try? await sendJSONResponse(errorResponse, status: .internalServerError, context: context, handler: handler)
            }
        }
    }
    
    private func handleStreamingResponse(
        messages: [Message],
        model: LMModel,
        temperature: Float,
        maxTokens: Int,
        requestModel: String,
        context: ChannelHandlerContext,
        handler: HTTPHandler
    ) async throws {
        // Send SSE headers
        let headers: [(String, String)] = [
            ("Content-Type", "text/event-stream"),
            ("Cache-Control", "no-cache"),
            ("Connection", "keep-alive")
        ]
        
        // Prepare response headers
        var responseHead = HTTPResponseHead(version: .http1_1, status: .ok)
        var nioHeaders = HTTPHeaders()
        for (name, value) in headers {
            nioHeaders.add(name: name, value: value)
        }
        responseHead.headers = nioHeaders
        
        // Ensure header write happens on the channel's event loop
        context.eventLoop.execute {
            context.write(handler.wrapOutboundOut(.head(responseHead)), promise: nil)
            context.flush()
        }
        
        // Generate response ID
        let responseId = "chatcmpl-\(UUID().uuidString.prefix(8))"
        let created = Int(Date().timeIntervalSince1970)
        
        // Stream tokens
        let stream = try await MLXService.shared.generate(
            messages: messages,
            model: model,
            temperature: temperature,
            maxTokens: maxTokens
        )
        
        var fullResponse = ""
        var tokenCount = 0
        
        for await token in stream {
            fullResponse += token
            tokenCount += 1
            
            // Create streaming chunk
            let chunk = ChatCompletionChunk(
                id: responseId,
                created: created,
                model: requestModel,
                choices: [
                    StreamChoice(
                        index: 0,
                        delta: DeltaContent(role: nil, content: token),
                        finish_reason: nil
                    )
                ],
                system_fingerprint: nil
            )
            
            // Send as SSE on the event loop
            if let jsonData = try? JSONEncoder().encode(chunk),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                let sseData = "data: \(jsonString)\n\n"
                context.eventLoop.execute {
                    var buffer = context.channel.allocator.buffer(capacity: sseData.utf8.count)
                    buffer.writeString(sseData)
                    context.write(handler.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
                    context.flush()
                }
            }
        }
        
        // Send final chunk
        let finalChunk = ChatCompletionChunk(
            id: responseId,
            created: created,
            model: requestModel,
            choices: [
                StreamChoice(
                    index: 0,
                    delta: DeltaContent(role: nil, content: nil),
                    finish_reason: "stop"
                )
            ],
            system_fingerprint: nil
        )
        
        if let jsonData = try? JSONEncoder().encode(finalChunk),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            let sseData = "data: \(jsonString)\n\ndata: [DONE]\n\n"
            context.eventLoop.execute {
                var buffer = context.channel.allocator.buffer(capacity: sseData.utf8.count)
                buffer.writeString(sseData)
                context.writeAndFlush(handler.wrapOutboundOut(.body(.byteBuffer(buffer)))).whenComplete { _ in
                    context.writeAndFlush(handler.wrapOutboundOut(.end(nil))).whenComplete { _ in
                        context.close(promise: nil)
                    }
                }
            }
        }
    }
    
    private func handleNonStreamingResponse(
        messages: [Message],
        model: LMModel,
        temperature: Float,
        maxTokens: Int,
        requestModel: String,
        context: ChannelHandlerContext,
        handler: HTTPHandler
    ) async throws {
        // Generate complete response
        let stream = try await MLXService.shared.generate(
            messages: messages,
            model: model,
            temperature: temperature,
            maxTokens: maxTokens
        )
        
        var fullResponse = ""
        var tokenCount = 0
        
        for await token in stream {
            fullResponse += token
            tokenCount += 1
        }
        
        // Create response
        let response = ChatCompletionResponse(
            id: "chatcmpl-\(UUID().uuidString.prefix(8))",
            created: Int(Date().timeIntervalSince1970),
            model: requestModel,
            choices: [
                ChatChoice(
                    index: 0,
                    message: ChatMessage(role: "assistant", content: fullResponse),
                    finish_reason: "stop"
                )
            ],
            usage: Usage(
                prompt_tokens: messages.reduce(0) { $0 + $1.content.count / 4 },
                completion_tokens: tokenCount,
                total_tokens: messages.reduce(0) { $0 + $1.content.count / 4 } + tokenCount
            ),
            system_fingerprint: nil
        )
        
        try await sendJSONResponse(response, status: .ok, context: context, handler: handler)
    }
    
    private func sendJSONResponse<T: Encodable>(
        _ response: T,
        status: HTTPResponseStatus,
        context: ChannelHandlerContext,
        handler: HTTPHandler
    ) async throws {
        let jsonData = try JSONEncoder().encode(response)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"
        
        // Send response on the event loop
        context.eventLoop.execute {
            var responseHead = HTTPResponseHead(version: .http1_1, status: status)
            var buffer = context.channel.allocator.buffer(capacity: jsonString.utf8.count)
            buffer.writeString(jsonString)
            
            var headers = HTTPHeaders()
            headers.add(name: "Content-Type", value: "application/json; charset=utf-8")
            headers.add(name: "Content-Length", value: String(buffer.readableBytes))
            headers.add(name: "Connection", value: "close")
            responseHead.headers = headers
            
            context.write(handler.wrapOutboundOut(.head(responseHead)), promise: nil)
            context.write(handler.wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
            context.writeAndFlush(handler.wrapOutboundOut(.end(nil))).whenComplete { _ in
                context.close(promise: nil)
            }
        }
    }
}
