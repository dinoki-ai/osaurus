//
//  MLXModel.swift
//  osaurus
//
//  Created by Terence on 8/17/25.
//

import Foundation

/// Represents an MLX-compatible LLM that can be downloaded and used
struct MLXModel: Identifiable, Codable {
  let id: String
  let name: String
  let description: String
  let downloadURL: String

  // Optional override for models root directory; when nil we consult the
  // DirectoryPickerService at access time (on the main actor).
  private let rootDirectoryOverride: URL?

  init(
    id: String,
    name: String,
    description: String,
    downloadURL: String,
    rootDirectory: URL? = nil
  ) {
    self.id = id
    self.name = name
    self.description = description
    self.downloadURL = downloadURL
    self.rootDirectoryOverride = rootDirectory
  }

  /// Local directory where this model should be stored
  @MainActor var localDirectory: URL {
    let root = rootDirectoryOverride ?? DirectoryPickerService.shared.effectiveModelsDirectory
    let components = id.split(separator: "/").map(String.init)
    return components.reduce(root) { partial, component in
      partial.appendingPathComponent(component, isDirectory: true)
    }
  }

  /// Check if model is downloaded
  /// A model is considered complete if:
  /// - Core config exists: config.json
  /// - Tokenizer assets exist in ANY of the supported variants:
  ///   - tokenizer.json (HF consolidated JSON)
  ///   - BPE: merges.txt + (vocab.json OR vocab.txt)
  ///   - SentencePiece: tokenizer.model OR spiece.model
  /// - At least one *.safetensors file exists (weights)
  @MainActor var isDownloaded: Bool {
    let fileManager = FileManager.default
    let directory = localDirectory

    func exists(_ name: String) -> Bool {
      fileManager.fileExists(atPath: directory.appendingPathComponent(name).path)
    }

    // Core config
    guard exists("config.json") else { return false }

    // Tokenizer variants
    let hasTokenizerJSON = exists("tokenizer.json")
    let hasBPE = exists("merges.txt") && (exists("vocab.json") || exists("vocab.txt"))
    let hasSentencePiece = exists("tokenizer.model") || exists("spiece.model")
    let hasTokenizerAssets = hasTokenizerJSON || hasBPE || hasSentencePiece
    guard hasTokenizerAssets else { return false }

    // Weights
    if let items = try? fileManager.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: nil)
    {
      let hasWeights = items.contains { $0.pathExtension == "safetensors" }
      return hasWeights
    }
    return false
  }

  /// Approximate download timestamp based on directory creation/modification time
  /// Newer downloads should have more recent dates.
  @MainActor var downloadedAt: Date? {
    let directory = localDirectory
    let values = try? directory.resourceValues(forKeys: [
      .creationDateKey, .contentModificationDateKey,
    ])
    return values?.creationDate ?? values?.contentModificationDate
  }
}

/// Download state for tracking progress
enum DownloadState: Equatable {
  case notStarted
  case downloading(progress: Double)
  case completed
  case failed(error: String)
}
