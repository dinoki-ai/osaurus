//
//  AnyLMSelection.swift
//  osaurus
//
//  Model selection between SystemLanguageModel and MLXLanguageModel.
//

import AnyLanguageModel
import Foundation

enum AnyLMSelectionError: Error, LocalizedError {
  case notAvailable(String)

  var errorDescription: String? {
    switch self {
    case .notAvailable(let reason): return reason
    }
  }
}

enum AnyLMSelection {
  static func resolveModel(
    requested: String?
  ) throws -> (model: any LanguageModel, effectiveModel: String) {
    let trimmed = (requested ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let isDefault =
      trimmed.isEmpty || trimmed.caseInsensitiveCompare("default") == .orderedSame
      || trimmed.caseInsensitiveCompare("foundation") == .orderedSame

    if isDefault {
      // Prefer the system model when available (macOS 26+)
      #if canImport(AnyLanguageModel)
        if #available(macOS 26.0, *) {
          let system = AnyLanguageModel.SystemLanguageModel.default
          if system.isAvailable {
            return (system, "foundation")
          }
        }
      #endif
      throw AnyLMSelectionError.notAvailable("System language model is unavailable on this OS.")
    }

    // Resolve MLX model by installed model names
    if let match = ModelManager.findInstalledModel(named: trimmed) {
      let mlx = AnyLanguageModel.MLXLanguageModel(modelId: match.id)
      return (mlx, match.name)
    }

    throw AnyLMSelectionError.notAvailable("Requested model not found: \(trimmed)")
  }
}
