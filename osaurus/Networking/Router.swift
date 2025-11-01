//
//  Router.swift
//  osaurus
//
//  Created by Terence on 8/17/25.
//

import Foundation
import IkigaJSON
@preconcurrency import NIOCore
@preconcurrency import NIOHTTP1

/// Simple routing logic for HTTP requests
public struct Router {
  /// Channel context for async operations (set by HTTPHandler)
  var context: ChannelHandlerContext?
  weak var handler: HTTPHandler?

  /// Create decoders per-request to ensure thread-safety
  private static func makeJSONDecoder() -> IkigaJSONDecoder { IkigaJSONDecoder() }

  /// Create encoders per-response to ensure thread-safety
  private func makeJSONEncoder() -> IkigaJSONEncoder { IkigaJSONEncoder() }

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
  public func route(method: String, path: String, body: Data = Data()) -> (
    status: HTTPResponseStatus, headers: [(String, String)], body: String
  ) {

    let p = normalize(path)
    if method == "HEAD" { return headOkEndpoint() }

    switch (method, p) {
    case ("GET", "/health"):
      return healthEndpoint()

    case ("GET", "/"):
      return rootEndpoint()

    case ("GET", "/models"):
      return modelsEndpoint()

    case ("GET", "/tags"):
      return tagsEndpoint()

    case ("POST", "/chat/completions"):
      return chatCompletionsEndpoint(body: body, context: context, handler: handler)

    case ("POST", "/chat"):
      return chatEndpoint(body: body, context: context, handler: handler)

    default:
      return notFoundEndpoint()
    }
  }

  /// Overload that accepts a ByteBuffer body to enable zero-copy decoding
  public func route(method: String, path: String, bodyBuffer: ByteBuffer) -> (
    status: HTTPResponseStatus, headers: [(String, String)], body: String
  ) {

    let p = normalize(path)
    if method == "HEAD" { return headOkEndpoint() }

    switch (method, p) {
    case ("GET", "/health"):
      return healthEndpoint()

    case ("GET", "/"):
      return rootEndpoint()

    case ("GET", "/models"):
      return modelsEndpoint()

    case ("GET", "/tags"):
      return tagsEndpoint()

    case ("POST", "/chat/completions"):
      return chatCompletionsEndpoint(bodyBuffer: bodyBuffer, context: context, handler: handler)

    case ("POST", "/chat"):
      return chatEndpoint(bodyBuffer: bodyBuffer, context: context, handler: handler)

    default:
      return notFoundEndpoint()
    }
  }

  // MARK: - Private Endpoints

  private func healthEndpoint() -> (HTTPResponseStatus, [(String, String)], String) {
    var obj = JSONObject()
    obj["status"] = "healthy"
    obj["timestamp"] = Date().ISO8601Format()
    return (.ok, [("Content-Type", "application/json; charset=utf-8")], obj.string)
  }

  private func rootEndpoint() -> (HTTPResponseStatus, [(String, String)], String) {
    return (.ok, [("Content-Type", "text/plain; charset=utf-8")], "Osaurus Server is running! 🦕")
  }

  private func notFoundEndpoint() -> (HTTPResponseStatus, [(String, String)], String) {
    return (.notFound, [("Content-Type", "text/plain; charset=utf-8")], "Not Found")
  }

  private func headOkEndpoint() -> (HTTPResponseStatus, [(String, String)], String) {
    return (.noContent, [("Content-Type", "text/plain; charset=utf-8")], "")
  }

  private func modelsEndpoint() -> (HTTPResponseStatus, [(String, String)], String) {
    var models = MLXService.getAvailableModels().map { modelName in
      OpenAIModel(from: modelName)
    }

    // Expose the system default Foundation model when available
    if FoundationModelService.isDefaultModelAvailable() {
      let foundation = OpenAIModel(from: "foundation")
      // Prepend so clients see a usable choice even with no local models
      models.insert(foundation, at: 0)
    }

    let response = ModelsResponse(data: models)

    if let json = encodeJSONString(response) {
      return (.ok, [("Content-Type", "application/json; charset=utf-8")], json)
    }
    return errorResponse(message: "Failed to encode models", statusCode: .internalServerError)
  }

  private func tagsEndpoint() -> (HTTPResponseStatus, [(String, String)], String) {
    let now = Date().ISO8601Format()
    var models = MLXService.getAvailableModels().map { modelName in
      var model = OpenAIModel(from: modelName)
      // Fields for "/tags" compatibility
      model.name = modelName
      model.model = modelName
      model.modified_at = now
      model.size = 0
      model.digest = ""
      model.details = ModelDetails(
        parent_model: "",
        format: "safetensors",
        family: "unknown",
        families: ["unknown"],
        parameter_size: "",
        quantization_level: ""
      )
      return model
    }

    // Expose the system default Foundation model when available for Ollama-compatible /tags
    if FoundationModelService.isDefaultModelAvailable() {
      var foundation = OpenAIModel(from: "foundation")
      foundation.name = "foundation"
      foundation.model = "foundation"
      foundation.modified_at = now
      foundation.size = 0
      foundation.digest = ""
      foundation.details = ModelDetails(
        parent_model: "",
        format: "native",
        family: "foundation",
        families: ["foundation"],
        parameter_size: "",
        quantization_level: ""
      )
      models.insert(foundation, at: 0)
    }

    let response: [String: [OpenAIModel]] = ["models": models]

    if let json = encodeJSONString(response) {
      return (.ok, [("Content-Type", "application/json; charset=utf-8")], json)
    }
    return errorResponse(message: "Failed to encode models", statusCode: .internalServerError)
  }

  private func chatCompletionsEndpoint(
    body: Data, context: ChannelHandlerContext?, handler: HTTPHandler?
  ) -> (HTTPResponseStatus, [(String, String)], String) {
    // In the simplified architecture, this path is handled directly by HTTPHandler.
    // Router no longer supports async streaming; return a server error when called directly.
    return errorResponse(message: "Server configuration error", statusCode: .internalServerError)
  }

  private func chatCompletionsEndpoint(
    bodyBuffer: ByteBuffer, context: ChannelHandlerContext?, handler: HTTPHandler?
  ) -> (HTTPResponseStatus, [(String, String)], String) {
    return errorResponse(message: "Server configuration error", statusCode: .internalServerError)
  }

  private func chatEndpoint(body: Data, context: ChannelHandlerContext?, handler: HTTPHandler?) -> (
    HTTPResponseStatus, [(String, String)], String
  ) {
    return errorResponse(message: "Server configuration error", statusCode: .internalServerError)
  }

  private func chatEndpoint(
    bodyBuffer: ByteBuffer, context: ChannelHandlerContext?, handler: HTTPHandler?
  ) -> (HTTPResponseStatus, [(String, String)], String) {
    return errorResponse(message: "Server configuration error", statusCode: .internalServerError)
  }

  private func errorResponse(message: String, statusCode: HTTPResponseStatus) -> (
    HTTPResponseStatus, [(String, String)], String
  ) {
    let error = OpenAIError(
      error: OpenAIError.ErrorDetail(
        message: message,
        type: "invalid_request_error",
        param: nil,
        code: nil
      )
    )

    if let json = encodeJSONString(error) {
      return (statusCode, [("Content-Type", "application/json; charset=utf-8")], json)
    }
    return (
      statusCode, [("Content-Type", "application/json; charset=utf-8")],
      "{\"error\":{\"message\":\"Internal error\"}}"
    )
  }

  // MARK: - Helpers
  private func encodeJSONString<T: Encodable>(_ value: T) -> String? {
    let encoder = makeJSONEncoder()
    var buffer = ByteBufferAllocator().buffer(capacity: 1024)
    do {
      try encoder.encodeAndWrite(value, into: &buffer)
      return buffer.readString(length: buffer.readableBytes)
    } catch {
      return nil
    }
  }

  // Normalize common provider prefixes so we cover /, /v1, /api, /v1/api
  private func normalize(_ path: String) -> String {
    func stripPrefix(_ prefix: String, from s: String) -> String? {
      if s == prefix { return "/" }
      if s.hasPrefix(prefix + "/") {
        let idx = s.index(s.startIndex, offsetBy: prefix.count)
        let rest = String(s[idx...])
        return rest.isEmpty ? "/" : rest
      }
      return nil
    }
    // Try in most-specific order
    if let r = stripPrefix("/v1/api", from: path) { return r }
    if let r = stripPrefix("/api", from: path) { return r }
    if let r = stripPrefix("/v1", from: path) { return r }
    return path
  }
}
