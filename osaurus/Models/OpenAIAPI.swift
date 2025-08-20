//
//  OpenAIAPI.swift
//  osaurus
//
//  Created by Terence on 8/17/25.
//

import Foundation

// MARK: - OpenAI API Compatible Structures

/// OpenAI-compatible model object
struct OpenAIModel: Codable {
    let id: String
    var object: String = "model"
    let created: Int
    var owned_by: String = "osaurus"
    var permission: [String] = []
    let root: String
    var parent: String? = nil
}

/// Response for /models endpoint
struct ModelsResponse: Codable {
    var object: String = "list"
    let data: [OpenAIModel]
}

/// Chat message in OpenAI format
struct ChatMessage: Codable {
    let role: String
    let content: String
}

/// Chat completion request
struct ChatCompletionRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Float?
    let max_tokens: Int?
    let stream: Bool?
    let top_p: Float?
    let frequency_penalty: Float?
    let presence_penalty: Float?
    let stop: [String]?
    let n: Int?
}

/// Chat completion choice
struct ChatChoice: Codable {
    let index: Int
    let message: ChatMessage
    let finish_reason: String
}

/// Token usage information
struct Usage: Codable {
    let prompt_tokens: Int
    let completion_tokens: Int
    let total_tokens: Int
}

/// Chat completion response
struct ChatCompletionResponse: Codable {
    let id: String
    var object: String = "chat.completion"
    let created: Int
    let model: String
    let choices: [ChatChoice]
    let usage: Usage
    let system_fingerprint: String?
}

// MARK: - Streaming Response Structures

/// Delta content for streaming
struct DeltaContent: Codable {
    let role: String?
    let content: String?
}

/// Streaming choice
struct StreamChoice: Codable {
    let index: Int
    let delta: DeltaContent
    let finish_reason: String?
}

/// Chat completion chunk for streaming
struct ChatCompletionChunk: Codable {
    let id: String
    var object: String = "chat.completion.chunk"
    let created: Int
    let model: String
    let choices: [StreamChoice]
    let system_fingerprint: String?
}

// MARK: - Error Response

/// OpenAI-compatible error response
struct OpenAIError: Codable {
    let error: ErrorDetail
    
    struct ErrorDetail: Codable {
        let message: String
        let type: String
        let param: String?
        let code: String?
    }
}

// MARK: - Helper Extensions

extension ChatCompletionRequest {
    /// Convert OpenAI format messages to internal Message format
    func toInternalMessages() -> [Message] {
        return messages.map { chatMessage in
            let role: MessageRole = switch chatMessage.role {
            case "system": .system
            case "user": .user
            case "assistant": .assistant
            default: .user
            }
            return Message(role: role, content: chatMessage.content)
        }
    }
}

extension OpenAIModel {
    /// Create an OpenAI model from an internal model name
    init(from modelName: String) {
        self.id = modelName
        self.created = Int(Date().timeIntervalSince1970)
        self.root = modelName
    }
}
