//
//  AnyLMService.swift
//  osaurus
//
//  Unified model service backed by AnyLanguageModel (Foundation + MLX)
//

import Foundation

#if canImport(AnyLanguageModel)
  import AnyLanguageModel
#endif

enum AnyLMServiceError: Error {
  case notAvailable
  case invalidModel(String)
}

extension AnyLMServiceError: LocalizedError {
  var errorDescription: String? {
    switch self {
    case .notAvailable:
      return "Requested model provider is not available on this system."
    case .invalidModel(let name):
      return "Unknown or unsupported model: \(name)."
    }
  }
}

final class AnyLMService: ToolCapableService {
  let id: String = "anylm"

  // MARK: - Availability & Model Handling

  static func isFoundationAvailable() -> Bool {
    #if canImport(AnyLanguageModel)
      if #available(macOS 26.0, *) {
        return SystemLanguageModel.default.isAvailable
      } else {
        return false
      }
    #else
      return false
    #endif
  }

  func isAvailable() -> Bool {
    return Self.isFoundationAvailable() || !LocalMLXModels.getAvailableModels().isEmpty
  }

  func handles(requestedModel: String?) -> Bool {
    let trimmed = (requestedModel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return Self.isFoundationAvailable() }
    if trimmed.caseInsensitiveCompare("default") == .orderedSame {
      return Self.isFoundationAvailable()
    }
    if trimmed.caseInsensitiveCompare("foundation") == .orderedSame {
      return Self.isFoundationAvailable()
    }
    if LocalMLXModels.modelId(forName: trimmed) != nil { return true }
    if trimmed.contains("/") { return true }
    return false
  }

  // MARK: - ModelService

  func streamDeltas(
    prompt: String,
    parameters: GenerationParameters,
    requestedModel: String?
  ) async throws -> AsyncStream<String> {
    #if canImport(AnyLanguageModel)
      if #available(macOS 26.0, *) {
        let model = try resolveModel(requestedModel)
        let options = GenerationOptions(
          sampling: nil,
          temperature: Double(parameters.temperature),
          maximumResponseTokens: parameters.maxTokens
        )

        let session = LanguageModelSession(model: model)
        let stream = session.streamResponse(to: prompt, options: options)

        return AsyncStream<String> { continuation in
          Task {
            var previous = ""
            do {
              for try await snapshot in stream {
                let current = snapshot.content
                let delta: String
                if current.hasPrefix(previous) {
                  delta = String(current.dropFirst(previous.count))
                } else {
                  delta = current
                }
                if !delta.isEmpty {
                  continuation.yield(delta)
                }
                previous = current
              }
            } catch {
              let prefix = "__OS_ERROR__:"
              continuation.yield(prefix + error.localizedDescription)
            }
            continuation.finish()
          }
        }
      } else {
        throw AnyLMServiceError.notAvailable
      }
    #else
      throw AnyLMServiceError.notAvailable
    #endif
  }

  func generateOneShot(
    prompt: String,
    parameters: GenerationParameters,
    requestedModel: String?
  ) async throws -> String {
    #if canImport(AnyLanguageModel)
      if #available(macOS 26.0, *) {
        let model = try resolveModel(requestedModel)
        let options = GenerationOptions(
          sampling: nil,
          temperature: Double(parameters.temperature),
          maximumResponseTokens: parameters.maxTokens
        )
        let session = LanguageModelSession(model: model)
        let response = try await session.respond(to: prompt, options: options)
        return response.content
      } else {
        throw AnyLMServiceError.notAvailable
      }
    #else
      throw AnyLMServiceError.notAvailable
    #endif
  }

  // MARK: - ToolCapableService

  func respondWithTools(
    prompt: String,
    parameters: GenerationParameters,
    stopSequences: [String],
    tools: [Tool],
    toolChoice: ToolChoiceOption?,
    requestedModel: String?
  ) async throws -> String {
    #if canImport(AnyLanguageModel)
      if #available(macOS 26.0, *) {
        let amlTools: [any AnyLanguageModel.Tool] =
          tools
          .filter { self.shouldEnableTool($0, choice: toolChoice) }
          .map { self.toAnyLMTool($0) }

        let options = GenerationOptions(
          sampling: nil,
          temperature: Double(parameters.temperature),
          maximumResponseTokens: parameters.maxTokens
        )

        do {
          let model = try resolveModel(requestedModel)
          let session = LanguageModelSession(model: model, tools: amlTools, instructions: nil)
          let response = try await session.respond(to: prompt, options: options)
          var reply = response.content
          if !stopSequences.isEmpty {
            for s in stopSequences {
              if let r = reply.range(of: s) {
                reply = String(reply[..<r.lowerBound])
                break
              }
            }
          }
          return reply
        } catch let error as LanguageModelSession.ToolCallError {
          if let inv = error.underlyingError as? ToolInvocationError {
            throw ServiceToolInvocation(toolName: inv.toolName, jsonArguments: inv.jsonArguments)
          }
          throw error
        }
      } else {
        throw AnyLMServiceError.notAvailable
      }
    #else
      throw AnyLMServiceError.notAvailable
    #endif
  }

  func streamWithTools(
    prompt: String,
    parameters: GenerationParameters,
    stopSequences: [String],
    tools: [Tool],
    toolChoice: ToolChoiceOption?,
    requestedModel: String?
  ) async throws -> AsyncThrowingStream<String, Error> {
    #if canImport(AnyLanguageModel)
      if #available(macOS 26.0, *) {
        let amlTools: [any AnyLanguageModel.Tool] =
          tools
          .filter { self.shouldEnableTool($0, choice: toolChoice) }
          .map { self.toAnyLMTool($0) }

        let options = GenerationOptions(
          sampling: nil,
          temperature: Double(parameters.temperature),
          maximumResponseTokens: parameters.maxTokens
        )

        let model = try resolveModel(requestedModel)
        let session = LanguageModelSession(model: model, tools: amlTools, instructions: nil)
        let stream = session.streamResponse(to: prompt, options: options)

        return AsyncThrowingStream<String, Error> { continuation in
          Task {
            var previous = ""
            do {
              var iterator = stream.makeAsyncIterator()
              while let snapshot = try await iterator.next() {
                var current = snapshot.content
                if !stopSequences.isEmpty,
                  let r = stopSequences.compactMap({ current.range(of: $0)?.lowerBound }).first
                {
                  current = String(current[..<r])
                }
                let delta: String
                if current.hasPrefix(previous) {
                  delta = String(current.dropFirst(previous.count))
                } else {
                  delta = current
                }
                if !delta.isEmpty {
                  continuation.yield(delta)
                }
                previous = current
              }
              continuation.finish()
            } catch let error as LanguageModelSession.ToolCallError {
              if let inv = error.underlyingError as? ToolInvocationError {
                continuation.finish(
                  throwing: ServiceToolInvocation(
                    toolName: inv.toolName, jsonArguments: inv.jsonArguments)
                )
              } else {
                continuation.finish(throwing: error)
              }
            } catch {
              continuation.finish(throwing: error)
            }
          }
        }
      } else {
        throw AnyLMServiceError.notAvailable
      }
    #else
      throw AnyLMServiceError.notAvailable
    #endif
  }

  // MARK: - Private helpers

  #if canImport(AnyLanguageModel)
    @available(macOS 26.0, *)
    private func resolveModel(_ requestedModel: String?) throws -> any LanguageModel {
      let trimmed = (requestedModel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.isEmpty || trimmed.caseInsensitiveCompare("default") == .orderedSame
        || trimmed.caseInsensitiveCompare("foundation") == .orderedSame
      {
        guard Self.isFoundationAvailable() else { throw AnyLMServiceError.notAvailable }
        return SystemLanguageModel.default
      }

      if let id = LocalMLXModels.modelId(forName: trimmed) {
        #if AML_WITH_MLX
          return MLXLanguageModel(modelId: id)
        #else
          throw AnyLMServiceError.notAvailable
        #endif
      }

      if trimmed.contains("/") {
        #if AML_WITH_MLX
          return MLXLanguageModel(modelId: trimmed)
        #else
          throw AnyLMServiceError.notAvailable
        #endif
      }

      throw AnyLMServiceError.invalidModel(trimmed)
    }

    @available(macOS 26.0, *)
    private struct ToolInvocationError: Error {
      let toolName: String
      let jsonArguments: String
    }

    @available(macOS 26.0, *)
    private struct OpenAIToolAdapter: AnyLanguageModel.Tool {
      typealias Output = String
      typealias Arguments = GeneratedContent

      let name: String
      let description: String
      let parameters: GenerationSchema
      var includesSchemaInInstructions: Bool { true }

      func call(arguments: GeneratedContent) async throws -> String {
        let json = arguments.jsonString
        throw ToolInvocationError(toolName: name, jsonArguments: json)
      }
    }

    @available(macOS 26.0, *)
    private func toAnyLMTool(_ tool: Tool) -> any AnyLanguageModel.Tool {
      let desc = tool.function.description ?? ""
      let schema: GenerationSchema = makeGenerationSchema(
        from: tool.function.parameters, toolName: tool.function.name, description: desc)
      return OpenAIToolAdapter(name: tool.function.name, description: desc, parameters: schema)
    }

    // Convert OpenAI JSON Schema (as JSONValue) to AnyLanguageModel GenerationSchema
    @available(macOS 26.0, *)
    private func makeGenerationSchema(
      from parameters: JSONValue?,
      toolName: String,
      description: String?
    ) -> GenerationSchema {
      guard let parameters else {
        return GenerationSchema(
          type: GeneratedContent.self, description: description, properties: [])
      }
      if let root = dynamicSchema(from: parameters, name: toolName) {
        if let schema = try? GenerationSchema(root: root, dependencies: []) {
          return schema
        }
      }
      return GenerationSchema(type: GeneratedContent.self, description: description, properties: [])
    }

    // Build a DynamicGenerationSchema recursively from a minimal subset of JSON Schema
    @available(macOS 26.0, *)
    private func dynamicSchema(from json: JSONValue, name: String) -> DynamicGenerationSchema? {
      switch json {
      case .object(let dict):
        if case .array(let enumVals)? = dict["enum"],
          case .string = enumVals.first
        {
          let choices: [String] = enumVals.compactMap { v in
            if case .string(let s) = v { return s } else { return nil }
          }
          return DynamicGenerationSchema(
            name: name, description: jsonStringOrNil(dict["description"]), anyOf: choices)
        }

        var typeString: String? = nil
        if let t = dict["type"] {
          switch t {
          case .string(let s): typeString = s
          case .array(let arr):
            typeString =
              arr.compactMap { v in
                if case .string(let s) = v, s != "null" { return s } else { return nil }
              }.first
          default: break
          }
        }

        let desc = jsonStringOrNil(dict["description"])

        switch typeString ?? "object" {
        case "string":
          return DynamicGenerationSchema(type: String.self)
        case "integer":
          return DynamicGenerationSchema(type: Int.self)
        case "number":
          return DynamicGenerationSchema(type: Double.self)
        case "boolean":
          return DynamicGenerationSchema(type: Bool.self)
        case "array":
          if let items = dict["items"],
            let itemSchema = dynamicSchema(from: items, name: name + "Item")
          {
            let minItems = jsonIntOrNil(dict["minItems"])
            let maxItems = jsonIntOrNil(dict["maxItems"])
            return DynamicGenerationSchema(
              arrayOf: itemSchema, minimumElements: minItems, maximumElements: maxItems)
          }
          return DynamicGenerationSchema(
            arrayOf: DynamicGenerationSchema(type: String.self), minimumElements: nil,
            maximumElements: nil)
        case "object": fallthrough
        default:
          var required: Set<String> = []
          if case .array(let reqArr)? = dict["required"] {
            required = Set(
              reqArr.compactMap { v in if case .string(let s) = v { return s } else { return nil } }
            )
          }
          var properties: [DynamicGenerationSchema.Property] = []
          if case .object(let propsDict)? = dict["properties"] {
            for (propName, propSchemaJSON) in propsDict {
              let propSchema =
                dynamicSchema(from: propSchemaJSON, name: name + "." + propName)
                ?? DynamicGenerationSchema(type: String.self)
              let isOptional = !required.contains(propName)
              let prop = DynamicGenerationSchema.Property(
                name: propName,
                description: nil,
                schema: propSchema,
                isOptional: isOptional
              )
              properties.append(prop)
            }
          }
          return DynamicGenerationSchema(name: name, description: desc, properties: properties)
        }

      case .string:
        return DynamicGenerationSchema(type: String.self)
      case .number:
        return DynamicGenerationSchema(type: Double.self)
      case .bool:
        return DynamicGenerationSchema(type: Bool.self)
      case .array(let arr):
        if let first = arr.first, let item = dynamicSchema(from: first, name: name + "Item") {
          return DynamicGenerationSchema(arrayOf: item, minimumElements: nil, maximumElements: nil)
        }
        return DynamicGenerationSchema(
          arrayOf: DynamicGenerationSchema(type: String.self), minimumElements: nil,
          maximumElements: nil)
      case .null:
        return DynamicGenerationSchema(type: String.self)
      }
    }

    private func jsonStringOrNil(_ value: JSONValue?) -> String? {
      guard let value else { return nil }
      if case .string(let s) = value { return s }
      return nil
    }
    private func jsonIntOrNil(_ value: JSONValue?) -> Int? {
      guard let value else { return nil }
      switch value {
      case .number(let d): return Int(d)
      case .string(let s): return Int(s)
      default: return nil
      }
    }

    @available(macOS 26.0, *)
    private func shouldEnableTool(_ tool: Tool, choice: ToolChoiceOption?) -> Bool {
      guard let choice else { return true }
      switch choice {
      case .auto: return true
      case .none: return false
      case .function(let n):
        return n.function.name == tool.function.name
      }
    }
  #endif
}
