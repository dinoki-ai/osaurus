//
//  FoundationModelService.swift
//  osaurus
//
//  Created by Terence on 10/14/25.
//

import Foundation

#if canImport(FoundationModels)
  import FoundationModels
#endif

enum FoundationModelServiceError: Error {
  case notAvailable
  case generationFailed
}

final class FoundationModelService: ToolCapableService {
  let id: String = "foundation"

  /// Returns true if the system default language model is available on this device/OS.
  static func isDefaultModelAvailable() -> Bool {
    #if canImport(FoundationModels)
      if #available(macOS 26.0, *) {
        return SystemLanguageModel.default.isAvailable
      } else {
        return false
      }
    #else
      return false
    #endif
  }

  func isAvailable() -> Bool { Self.isDefaultModelAvailable() }

  func handles(requestedModel: String?) -> Bool {
    let t = (requestedModel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    return t.isEmpty || t.caseInsensitiveCompare("default") == .orderedSame
      || t.caseInsensitiveCompare("foundation") == .orderedSame
  }

  /// Generate a single response from the system default language model.
  /// Falls back to throwing when the framework is unavailable.
  static func generateOneShot(
    prompt: String,
    temperature: Float,
    maxTokens: Int
  ) async throws -> String {
    #if canImport(FoundationModels)
      if #available(macOS 26.0, *) {
        let session = LanguageModelSession()

        let options = GenerationOptions(
          sampling: nil,
          temperature: Double(temperature),
          maximumResponseTokens: maxTokens
        )
        let response = try await session.respond(to: prompt, options: options)
        return response.content
      } else {
        throw FoundationModelServiceError.notAvailable
      }
    #else
      throw FoundationModelServiceError.notAvailable
    #endif
  }

  func streamDeltas(
    prompt: String,
    parameters: GenerationParameters,
    requestedModel: String?
  ) async throws -> AsyncStream<String> {
    #if canImport(FoundationModels)
      if #available(macOS 26.0, *) {
        let session = LanguageModelSession()

        let options = GenerationOptions(
          sampling: nil,
          temperature: Double(parameters.temperature),
          maximumResponseTokens: parameters.maxTokens
        )
        let stream = session.streamResponse(to: prompt, options: options)
        let streamBox = UncheckedSendableBox(value: stream)

        return AsyncStream<String> { continuation in
          let continuationBox = UncheckedSendableBox(value: continuation)
          Task {
            var previous = ""
            do {
              for try await snapshot in streamBox.value {
                let current = snapshot.content
                let delta: String
                if current.hasPrefix(previous) {
                  delta = String(current.dropFirst(previous.count))
                } else {
                  delta = current
                }
                if !delta.isEmpty {
                  continuationBox.value.yield(delta)
                }
                previous = current
              }
            } catch {
              // Surface stream error as an out-of-band message for the HTTP layer to convert to an error
              let prefix = "__OS_ERROR__:"
              continuationBox.value.yield(prefix + error.localizedDescription)
            }
            continuationBox.value.finish()
          }
        }
      } else {
        throw FoundationModelServiceError.notAvailable
      }
    #else
      throw FoundationModelServiceError.notAvailable
    #endif
  }

  func generateOneShot(
    prompt: String,
    parameters: GenerationParameters,
    requestedModel: String?
  ) async throws -> String {
    return try await Self.generateOneShot(
      prompt: prompt, temperature: parameters.temperature, maxTokens: parameters.maxTokens)
  }

  // MARK: - Tool calling bridge (OpenAI tools -> FoundationModels)

  func respondWithTools(
    prompt: String,
    parameters: GenerationParameters,
    stopSequences: [String],
    tools: [Tool],
    toolChoice: ToolChoiceOption?,
    requestedModel: String?
  ) async throws -> String {
    #if canImport(FoundationModels)
      if #available(macOS 26.0, *) {
        let appleTools: [any FoundationModels.Tool] =
          tools
          .filter { self.shouldEnableTool($0, choice: toolChoice) }
          .map { self.toAppleTool($0) }

        let options = GenerationOptions(
          sampling: nil,
          temperature: Double(parameters.temperature),
          maximumResponseTokens: parameters.maxTokens
        )

        do {
          let session = LanguageModelSession(model: .default, tools: appleTools, instructions: nil)
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
            // Re-throw using shared ServiceToolInvocation so callers don't need Foundation type
            throw ServiceToolInvocation(toolName: inv.toolName, jsonArguments: inv.jsonArguments)
          }
          throw error
        }
      } else {
        throw FoundationModelServiceError.notAvailable
      }
    #else
      throw FoundationModelServiceError.notAvailable
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
    #if canImport(FoundationModels)
      if #available(macOS 26.0, *) {
        let appleTools: [any FoundationModels.Tool] =
          tools
          .filter { self.shouldEnableTool($0, choice: toolChoice) }
          .map { self.toAppleTool($0) }

        let options = GenerationOptions(
          sampling: nil,
          temperature: Double(parameters.temperature),
          maximumResponseTokens: parameters.maxTokens
        )

        let session = LanguageModelSession(model: .default, tools: appleTools, instructions: nil)
        let stream = session.streamResponse(to: prompt, options: options)
        let streamBox = UncheckedSendableBox(value: stream)

        return AsyncThrowingStream<String, Error> { continuation in
          let continuationBox = UncheckedSendableBox(value: continuation)
          Task {
            var previous = ""
            do {
              var iterator = streamBox.value.makeAsyncIterator()
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
                  continuationBox.value.yield(delta)
                }
                previous = current
              }
              continuationBox.value.finish()
            } catch let error as LanguageModelSession.ToolCallError {
              if let inv = error.underlyingError as? ToolInvocationError {
                // Surface as shared ServiceToolInvocation
                continuationBox.value.finish(
                  throwing: ServiceToolInvocation(
                    toolName: inv.toolName, jsonArguments: inv.jsonArguments)
                )
              } else {
                continuationBox.value.finish(throwing: error)
              }
            } catch {
              continuationBox.value.finish(throwing: error)
            }
          }
        }
      } else {
        throw FoundationModelServiceError.notAvailable
      }
    #else
      throw FoundationModelServiceError.notAvailable
    #endif
  }

  // MARK: - Private helpers

  #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private struct ToolInvocationError: Error {
      let toolName: String
      let jsonArguments: String
    }

    @available(macOS 26.0, *)
    private struct OpenAIToolAdapter: FoundationModels.Tool {
      typealias Output = String
      typealias Arguments = GeneratedContent

      let name: String
      let description: String
      let parameters: GenerationSchema
      var includesSchemaInInstructions: Bool { true }

      func call(arguments: GeneratedContent) async throws -> String {
        // Serialize arguments as JSON and throw to signal a tool call back to the server
        let json = arguments.jsonString
        throw ToolInvocationError(toolName: name, jsonArguments: json)
      }
    }

    @available(macOS 26.0, *)
    private func toAppleTool(_ tool: Tool) -> any FoundationModels.Tool {
      let desc = tool.function.description ?? ""
      let schema: GenerationSchema = makeGenerationSchema(
        from: tool.function.parameters, toolName: tool.function.name, description: desc)
      return OpenAIToolAdapter(name: tool.function.name, description: desc, parameters: schema)
    }

    // Convert OpenAI JSON Schema (as JSONValue) to FoundationModels GenerationSchema
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
        // enum of strings
        if case .array(let enumVals)? = dict["enum"],
          case .string = enumVals.first
        {
          let choices: [String] = enumVals.compactMap { v in
            if case .string(let s) = v { return s } else { return nil }
          }
          return DynamicGenerationSchema(
            name: name, description: jsonStringOrNil(dict["description"]), anyOf: choices)
        }

        // type can be string or array
        var typeString: String? = nil
        if let t = dict["type"] {
          switch t {
          case .string(let s): typeString = s
          case .array(let arr):
            // Prefer first non-null type
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
          // Fallback to array of strings
          return DynamicGenerationSchema(
            arrayOf: DynamicGenerationSchema(type: String.self), minimumElements: nil,
            maximumElements: nil)
        case "object": fallthrough
        default:
          // Build object properties
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
        // Attempt array of first element type
        if let first = arr.first, let item = dynamicSchema(from: first, name: name + "Item") {
          return DynamicGenerationSchema(arrayOf: item, minimumElements: nil, maximumElements: nil)
        }
        return DynamicGenerationSchema(
          arrayOf: DynamicGenerationSchema(type: String.self), minimumElements: nil,
          maximumElements: nil)
      case .null:
        // Default to string when null only
        return DynamicGenerationSchema(type: String.self)
      }
    }

    // Helpers to extract primitive values from JSONValue
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
