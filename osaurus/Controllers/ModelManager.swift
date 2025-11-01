//
//  ModelManager.swift
//  osaurus
//
//  Created by Terence on 8/17/25.
//

import Combine
import Foundation
import Hub
import MLXLLM
import SwiftUI

enum ModelListTab: CaseIterable {
  /// All available models from Hugging Face
  case all

  /// Curated list of recommended models
  case suggested

  /// Only models downloaded locally
  case downloaded

  /// Display name for the tab
  var title: String {
    switch self {
    case .all: return "All Models"
    case .suggested: return "Suggested"
    case .downloaded: return "Downloaded"
    }
  }
}

/// Manages MLX model downloads and storage
@MainActor
final class ModelManager: NSObject, ObservableObject {
  static let shared = ModelManager()

  /// Detailed metrics for an in-flight download
  struct DownloadMetrics: Equatable {
    let bytesReceived: Int64?
    let totalBytes: Int64?
    let bytesPerSecond: Double?
    let etaSeconds: Double?
  }

  // MARK: - Published Properties
  @Published var availableModels: [MLXModel] = []
  @Published var downloadStates: [String: DownloadState] = [:]
  @Published var isLoadingModels: Bool = false
  @Published var suggestedModels: [MLXModel] = ModelManager.curatedSuggestedModels
  @Published var downloadMetrics: [String: DownloadMetrics] = [:]

  // MARK: - Properties
  /// Globs for files to download from Hugging Face snapshots
  static let snapshotDownloadPatterns: [String] = [
    "config.json",
    "tokenizer.json",
    "tokenizer_config.json",
    "special_tokens_map.json",
    "generation_config.json",
    "chat_template.jinja",
    "*.safetensors",
  ]
  /// Current models directory (uses DirectoryPickerService for user selection)
  var modelsDirectory: URL {
    return DirectoryPickerService.shared.effectiveModelsDirectory
  }

  private var activeDownloadTasks: [String: Task<Void, Never>] = [:]  // modelId -> Task
  private var downloadTokens: [String: UUID] = [:]  // modelId -> token to gate progress/state updates
  private var cancellables = Set<AnyCancellable>()
  private var progressSamples: [String: [(timestamp: TimeInterval, completed: Int64)]] = [:]
  /// Cached estimated total bytes for active downloads
  private var downloadSizeEstimates: [String: Int64] = [:]
  private var remoteSearchTask: Task<Void, Never>? = nil

  // MARK: - Initialization
  override init() {
    super.init()

    loadAvailableModels()
  }

  // MARK: - Public Methods

  /// Load popular MLX models
  func loadAvailableModels() {
    // Use full curated suggestions regardless of SDK allowlist so they are visible in All & Suggested
    let curated = Self.curatedSuggestedModels

    suggestedModels = curated
    availableModels = curated
    downloadStates = [:]
    for model in availableModels {
      downloadStates[model.id] = model.isDownloaded ? .completed : .notStarted
    }
    for sm in suggestedModels {
      downloadStates[sm.id] = sm.isDownloaded ? .completed : .notStarted
    }
    // Merge MLX registry-supported models into All
    let registry = Self.registryModels()
    mergeAvailable(with: registry)
    // Also surface any locally-downloaded models even if not on the SDK allowlist
    let localModels = Self.discoverLocalModels()
    mergeAvailable(with: localModels)

    isLoadingModels = false
  }

  /// Fetch MLX-compatible models from Hugging Face and merge into availableModels.
  /// If searchText is empty, fetches top repos from `mlx-community`. Otherwise performs a broader query.
  func fetchRemoteMLXModels(searchText: String) {
    // Cancel any in-flight search
    remoteSearchTask?.cancel()

    // Mark loading to show spinner if needed
    isLoadingModels = true

    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

    // If user pasted a direct HF URL or "org/repo", immediately surface it without requiring SDK allowlist
    if let directId = Self.parseHuggingFaceRepoId(from: query), !directId.isEmpty {
      let exists = (availableModels + suggestedModels)
        .contains { $0.id.caseInsensitiveCompare(directId) == .orderedSame }
      if !exists {
        let friendly = Self.friendlyName(from: directId)
        var desc = "Imported from input"
        var model = MLXModel(
          id: directId,
          name: friendly,
          description: desc,
          downloadURL: "https://huggingface.co/\(directId)"
        )
        if model.isDownloaded {
          desc = "Local model (detected)"
          model = MLXModel(
            id: directId,
            name: friendly,
            description: desc,
            downloadURL: "https://huggingface.co/\(directId)"
          )
        }
        availableModels.insert(model, at: 0)
        downloadStates[model.id] = model.isDownloaded ? .completed : .notStarted
      }
    }

    remoteSearchTask = Task { [weak self] in
      guard let self else { return }

      // Build candidate URLs
      let limit = 100
      var urls: [URL] = []
      // Always query mlx-community
      if let url = Self.makeHFModelsURL(author: "mlx-community", search: query, limit: limit) {
        urls.append(url)
      }
      // Additional default seeds to find MLX repos outside mlx-community when query is empty
      let defaultSeeds = ["mlx", "mlx 4bit", "MLX"]
      if query.isEmpty {
        for seed in defaultSeeds {
          if let url = Self.makeHFModelsURL(author: nil, search: seed, limit: limit) {
            urls.append(url)
          }
        }
      } else {
        // Broader search across all repos when query present
        if let url = Self.makeHFModelsURL(author: nil, search: query, limit: limit) {
          urls.append(url)
        }
      }

      // Fetch in parallel
      let results: [[HFModel]] = await withTaskGroup(of: [HFModel].self) { group in
        for u in urls { group.addTask { (try? await Self.requestHFModels(at: u)) ?? [] } }
        var collected: [[HFModel]] = []
        for await arr in group { collected.append(arr) }
        return collected
      }

      // Merge and unique by id
      var byId: [String: HFModel] = [:]
      for arr in results { for m in arr { byId[m.id] = m } }

      // Filter to likely MLX-compatible
      let filtered = byId.values.filter { Self.isLikelyMLXCompatible($0) }

      // Map to MLXModel
      let mapped: [MLXModel] = filtered.map { hf in
        MLXModel(
          id: hf.id,
          name: Self.friendlyName(from: hf.id),
          description: "Discovered on Hugging Face",
          downloadURL: "https://huggingface.co/\(hf.id)",
          rootDirectory: nil
        )
      }

      // Keep only SDK-supported models
      let allow = Self.sdkSupportedModelIds()
      let allowedMapped = mapped.filter { allow.contains($0.id.lowercased()) }

      // Publish to UI on main actor (we already are, but be explicit about ordering)
      await MainActor.run {
        self.mergeAvailable(with: allowedMapped)
        self.isLoadingModels = false
      }
    }
  }

  /// Resolve or construct an MLXModel by Hugging Face repo id (e.g., "mlx-community/Qwen3-1.7B-4bit").
  /// Returns nil if the repo id does not appear MLX-compatible.
  func resolveModel(byRepoId repoId: String) -> MLXModel? {
    let trimmed = repoId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    // If the model exists locally, allow it regardless of allowlist membership
    let localModel = MLXModel(
      id: trimmed,
      name: Self.friendlyName(from: trimmed),
      description: "Local model (detected)",
      downloadURL: "https://huggingface.co/\(trimmed)"
    )
    if localModel.isDownloaded {
      if let existing = availableModels.first(where: {
        $0.id.caseInsensitiveCompare(trimmed) == .orderedSame
      }) {
        return existing
      }
      if let existing = suggestedModels.first(where: {
        $0.id.caseInsensitiveCompare(trimmed) == .orderedSame
      }) {
        return existing
      }
      availableModels.insert(localModel, at: 0)
      downloadStates[localModel.id] = .completed
      return localModel
    }
    // Validate MLX compatibility heuristically: org contains "mlx" or id contains "mlx"
    let lower = trimmed.lowercased()
    guard lower.contains("mlx") || lower.hasPrefix("mlx-community/") || lower.contains("-mlx")
    else {
      return nil
    }

    // Only allow models supported by the SDK
    let allow = Self.sdkSupportedModelIds()
    guard allow.contains(lower) else { return nil }

    // If already present in available or suggested (case-insensitive), return that instance
    if let existing = availableModels.first(where: { $0.id.lowercased() == trimmed.lowercased() }) {
      return existing
    }
    if let existing = suggestedModels.first(where: { $0.id.lowercased() == trimmed.lowercased() }) {
      return existing
    }

    // Construct a minimal MLXModel entry
    let name = Self.friendlyName(from: trimmed)
    let model = MLXModel(
      id: trimmed,
      name: name,
      description: "Imported from deeplink",
      downloadURL: "https://huggingface.co/\(trimmed)"
    )
    // Add to available list for UI visibility
    availableModels.insert(model, at: 0)
    // Initialize download state entry
    downloadStates[model.id] = model.isDownloaded ? .completed : .notStarted
    return model
  }

  /// Resolve a model only if the Hugging Face repository is MLX-compatible.
  /// Uses network metadata from Hugging Face for a reliable determination.
  /// Returns the existing or newly inserted `MLXModel` when compatible; otherwise nil.
  func resolveModelIfMLXCompatible(byRepoId repoId: String) async -> MLXModel? {
    let trimmed = repoId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    // Only allow models supported by the SDK
    let allow = Self.sdkSupportedModelIds()
    guard allow.contains(trimmed.lowercased()) else { return nil }

    // If already present, return immediately
    if let existing = availableModels.first(where: {
      $0.id.caseInsensitiveCompare(trimmed) == .orderedSame
    }) {
      return existing
    }
    if let existing = suggestedModels.first(where: {
      $0.id.caseInsensitiveCompare(trimmed) == .orderedSame
    }) {
      return existing
    }

    // Ask HF for definitive compatibility
    let isCompatible = await HuggingFaceService.shared.isMLXCompatible(repoId: trimmed)
    guard isCompatible else { return nil }

    // Insert minimal entry so it appears in UI and can be downloaded
    let model = MLXModel(
      id: trimmed,
      name: Self.friendlyName(from: trimmed),
      description: "Imported from deeplink",
      downloadURL: "https://huggingface.co/\(trimmed)"
    )
    availableModels.insert(model, at: 0)
    downloadStates[model.id] = model.isDownloaded ? .completed : .notStarted
    return model
  }

  /// Kick off a download for a given Hugging Face repo id if resolvable to MLX.
  func downloadModel(withRepoId repoId: String) {
    guard let model = resolveModel(byRepoId: repoId) else { return }
    downloadModel(model)
  }

  /// Estimate total download size for a model using the Hugging Face API.
  /// This is only called from the detail view to avoid spamming the API from the list.
  func estimateDownloadSize(for model: MLXModel) async -> Int64? {
    return await HuggingFaceService.shared.estimateTotalSize(
      repoId: model.id,
      patterns: Self.snapshotDownloadPatterns
    )
  }

  /// Download a model using Hugging Face Hub snapshot API
  func downloadModel(_ model: MLXModel) {
    // Patterns for files to download (shared with estimator)
    let patterns = Self.snapshotDownloadPatterns

    // If core assets are present but optional files from patterns are missing, we'll top-up.
    let needsTopUp = Self.isMissingExactPatternFiles(at: model.localDirectory, patterns: patterns)
    if model.isDownloaded && !needsTopUp {
      downloadStates[model.id] = .completed
      return
    }
    let state = downloadStates[model.id] ?? .notStarted
    switch state {
    case .downloading, .completed:
      return
    default:
      break
    }

    // Reset any previous task
    activeDownloadTasks[model.id]?.cancel()
    // Create a new token for this download session
    let token = UUID()
    downloadTokens[model.id] = token

    downloadStates[model.id] = .downloading(progress: 0.0)
    downloadMetrics[model.id] = DownloadMetrics(
      bytesReceived: 0,
      totalBytes: nil,
      bytesPerSecond: nil,
      etaSeconds: nil
    )
    progressSamples[model.id] = []

    // Kick off an asynchronous size estimate (used to compute byte progress & speed)
    Task { [weak self] in
      guard let self = self else { return }
      let est = await self.estimateDownloadSize(for: model)
      await MainActor.run {
        if let est {
          self.downloadSizeEstimates[model.id] = est
          // Seed metrics immediately using current UI fraction so bytes show up ASAP
          let currentFraction: Double = {
            if case .downloading(let p) = (self.downloadStates[model.id] ?? .notStarted) {
              return max(0.0, min(1.0, p))
            }
            return 0.0
          }()
          let received = Int64((Double(est) * currentFraction).rounded())
          self.downloadMetrics[model.id] = DownloadMetrics(
            bytesReceived: received > 0 ? received : nil,
            totalBytes: est,
            bytesPerSecond: self.downloadMetrics[model.id]?.bytesPerSecond,
            etaSeconds: self.downloadMetrics[model.id]?.etaSeconds
          )
        }
      }
    }

    // Ensure local directory exists
    do {
      try FileManager.default.createDirectory(
        at: model.localDirectory,
        withIntermediateDirectories: true
      )
    } catch {
      downloadStates[model.id] = .failed(
        error: "Failed to create directory: \(error.localizedDescription)")
      return
    }

    // Start snapshot download task
    let task = Task { [weak self] in
      guard let self = self else { return }
      let repo = Hub.Repo(id: model.id)

      do {
        // Download a snapshot to a temporary location managed by Hub
        let progressHandlerBox: UncheckedSendableBox<(Progress) -> Void> = UncheckedSendableBox(
          value: { (progress: Progress) in
            Task { @MainActor [weak self] in
              guard let self = self else { return }
              guard self.downloadTokens[model.id] == token else { return }
              let fraction = max(0.0, min(1.0, progress.fractionCompleted))
              self.downloadStates[model.id] = .downloading(progress: fraction)
              let estTotalBytes = self.downloadSizeEstimates[model.id]
              let completedUnits = progress.completedUnitCount
              let totalUnits = progress.totalUnitCount
              let bytesCompleted: Int64? = {
                if let est = estTotalBytes, est > 0 {
                  return Int64((Double(est) * fraction).rounded())
                } else {
                  return completedUnits > 0 ? completedUnits : nil
                }
              }()
              let totalBytesForDisplay: Int64? = {
                if let est = estTotalBytes, est > 0 {
                  return est
                } else {
                  return totalUnits > 0 ? totalUnits : nil
                }
              }()
              let now = Date().timeIntervalSince1970
              var samples = self.progressSamples[model.id] ?? []
              samples.append((timestamp: now, completed: bytesCompleted ?? completedUnits))
              // Keep only the last 5s of samples
              let window: TimeInterval = 5.0
              samples = samples.filter { now - $0.timestamp <= window }
              self.progressSamples[model.id] = samples
              var speed: Double? = nil
              if let first = samples.first, let last = samples.last,
                last.timestamp > first.timestamp
              {
                let bytesDelta = Double(last.completed - first.completed)
                let timeDelta = last.timestamp - first.timestamp
                if timeDelta > 0 { speed = max(0, bytesDelta / timeDelta) }
              }
              var eta: Double? = nil
              if let speed, speed > 0, let totalBytesForDisplay,
                let bytesCompleted = bytesCompleted,
                totalBytesForDisplay > 0
              {
                let remaining = Double(totalBytesForDisplay - bytesCompleted)
                if remaining > 0 { eta = remaining / speed }
              }
              self.downloadMetrics[model.id] = DownloadMetrics(
                bytesReceived: bytesCompleted,
                totalBytes: totalBytesForDisplay,
                bytesPerSecond: speed,
                etaSeconds: eta
              )
            }
          })

        let snapshotDirectory = try await Hub.snapshot(
          from: repo,
          matching: patterns,
          progressHandler: progressHandlerBox.value)

        // Copy snapshot contents into our managed models directory
        try self.copyContents(of: snapshotDirectory, to: model.localDirectory)

        // Attempt to remove the Hub snapshot cache directory to free disk space
        // This directory is a cached snapshot; we've already copied the contents
        // into our app-managed models directory above, so it's safe to delete.
        do {
          try FileManager.default.removeItem(at: snapshotDirectory)
        } catch {
          // Non-fatal cleanup failure
          print(
            "Warning: failed to remove Hub snapshot cache at \(snapshotDirectory.path): \(error)")
        }

        // Verify
        let completed = model.isDownloaded
        await MainActor.run {
          // Only update state if this session is still current
          if self.downloadTokens[model.id] == token {
            self.downloadStates[model.id] =
              completed ? .completed : .failed(error: "Downloaded snapshot incomplete")
            self.downloadTokens[model.id] = nil
            self.downloadMetrics[model.id] = nil
            self.progressSamples[model.id] = nil
            self.downloadSizeEstimates[model.id] = nil
            if completed {
              NotificationService.shared.postModelReady(modelId: model.id, modelName: model.name)
            }
          }
        }
      } catch is CancellationError {
        await MainActor.run {
          if self.downloadTokens[model.id] == token {
            self.downloadStates[model.id] = .notStarted
            self.downloadTokens[model.id] = nil
            self.downloadMetrics[model.id] = nil
            self.progressSamples[model.id] = nil
            self.downloadSizeEstimates[model.id] = nil
          }
        }
      } catch {
        await MainActor.run {
          if self.downloadTokens[model.id] == token {
            self.downloadStates[model.id] = .failed(error: error.localizedDescription)
            self.downloadTokens[model.id] = nil
            self.downloadMetrics[model.id] = nil
            self.progressSamples[model.id] = nil
            self.downloadSizeEstimates[model.id] = nil
          }
        }
      }

      await MainActor.run {
        self.activeDownloadTasks[model.id] = nil
      }
    }

    activeDownloadTasks[model.id] = task
  }

  /// Cancel a download
  func cancelDownload(_ modelId: String) {
    // Cancel active snapshot task if any
    activeDownloadTasks[modelId]?.cancel()
    activeDownloadTasks[modelId] = nil
    downloadTokens[modelId] = nil
    downloadStates[modelId] = .notStarted
    downloadMetrics[modelId] = nil
    progressSamples[modelId] = nil
  }

  /// Delete a downloaded model
  func deleteModel(_ model: MLXModel) {
    // Cancel any active download task and reset state first
    activeDownloadTasks[model.id]?.cancel()
    activeDownloadTasks[model.id] = nil
    downloadTokens[model.id] = nil
    downloadStates[model.id] = .notStarted
    downloadMetrics[model.id] = nil
    progressSamples[model.id] = nil

    // Remove local files if present
    let fm = FileManager.default
    let path = model.localDirectory.path
    if fm.fileExists(atPath: path) {
      do {
        try fm.removeItem(atPath: path)
      } catch {
        // Log but keep state reset
        print("Failed to delete model: \(error)")
      }
    }
  }

  /// Get download progress for a model
  func downloadProgress(for modelId: String) -> Double {
    switch downloadStates[modelId] {
    case .downloading(let progress):
      return progress
    case .completed:
      return 1.0
    default:
      return 0.0
    }
  }

  /// Get total size of downloaded models
  var totalDownloadedSize: Int64 {
    // Build a unique list of models by id from both available and suggested
    let combined = (availableModels + suggestedModels)
    let uniqueById: [String: MLXModel] = combined.reduce(into: [:]) { dict, model in
      if dict[model.id] == nil { dict[model.id] = model }
    }
    // Sum actual on-disk sizes for models that are fully downloaded
    return uniqueById.values
      .filter { $0.isDownloaded }
      .reduce(Int64(0)) { partial, model in
        partial + (Self.directoryAllocatedSize(at: model.localDirectory) ?? 0)
      }
  }

  /// Effective state for a model combining in-memory state with on-disk detection
  func effectiveDownloadState(for model: MLXModel) -> DownloadState {
    if case .downloading = downloadStates[model.id] {
      return downloadStates[model.id] ?? .notStarted
    }
    return model.isDownloaded ? .completed : (downloadStates[model.id] ?? .notStarted)
  }

  var totalDownloadedSizeString: String {
    ByteCountFormatter.string(fromByteCount: totalDownloadedSize, countStyle: .file)
  }

  // MARK: - Private Methods

  /// Compute the set of SDK-supported model ids from MLXLLM's registry
  static func sdkSupportedModelIds() -> Set<String> {
    // The registry contains Apple-curated supported configurations.
    // We normalize to lowercase for comparison.
    var allowed: Set<String> = []
    for config in LLMRegistry.shared.models {
      allowed.insert(config.name.lowercased())
    }
    return allowed
  }

  /// Build MLXModel entries from the MLX registry of supported models
  static func registryModels() -> [MLXModel] {
    return LLMRegistry.shared.models.map { cfg in
      let id = cfg.name
      return MLXModel(
        id: id,
        name: friendlyName(from: id),
        description: "From MLX registry",
        downloadURL: "https://huggingface.co/\(id)"
      )
    }
  }

  private func copyContents(of sourceDirectory: URL, to destinationDirectory: URL) throws {
    let fileManager = FileManager.default

    // Ensure destination exists (do not wipe; we will merge/overwrite files)
    if !fileManager.fileExists(atPath: destinationDirectory.path) {
      try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
    }

    // Copy/overwrite all items
    let items = try fileManager.contentsOfDirectory(atPath: sourceDirectory.path)
    for item in items {
      let src = sourceDirectory.appendingPathComponent(item)
      let dst = destinationDirectory.appendingPathComponent(item)

      var isDir: ObjCBool = false
      fileManager.fileExists(atPath: src.path, isDirectory: &isDir)

      if isDir.boolValue {
        // Ensure directory exists at destination, then recurse
        if !fileManager.fileExists(atPath: dst.path) {
          try fileManager.createDirectory(at: dst, withIntermediateDirectories: true)
        }
        try copyContents(of: src, to: dst)
      } else {
        // If a file exists at destination, remove it before copying to allow overwrite
        if fileManager.fileExists(atPath: dst.path) {
          try fileManager.removeItem(at: dst)
        }
        try fileManager.copyItem(at: src, to: dst)
      }
    }
  }

  /// Check for any missing exact files from the provided patterns.
  /// Only exact filenames are considered (globs like *.safetensors are ignored here).
  private static func isMissingExactPatternFiles(at directory: URL, patterns: [String]) -> Bool {
    let fileManager = FileManager.default
    let exactNames = patterns.filter { !$0.contains("*") && !$0.contains("?") }
    for name in exactNames {
      let path = directory.appendingPathComponent(name).path
      if !fileManager.fileExists(atPath: path) {
        return true
      }
    }
    return false
  }

  /// Compute allocated size on disk for a directory (recursively)
  /// Falls back to logical file size when allocated size is unavailable
  private static func directoryAllocatedSize(at url: URL) -> Int64? {
    let fileManager = FileManager.default
    var total: Int64 = 0
    guard
      let enumerator = fileManager.enumerator(
        at: url,
        includingPropertiesForKeys: [
          .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey,
        ], options: [], errorHandler: nil)
    else {
      return nil
    }
    for case let fileURL as URL in enumerator {
      do {
        let resourceValues = try fileURL.resourceValues(forKeys: [
          .isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey,
        ])
        guard resourceValues.isRegularFile == true else { continue }
        if let allocated = resourceValues.totalFileAllocatedSize ?? resourceValues.fileAllocatedSize
        {
          total += Int64(allocated)
        } else if let size = resourceValues.fileSize {
          total += Int64(size)
        }
      } catch {
        continue
      }
    }
    return total
  }
}

// MARK: - Dynamic model discovery (Hugging Face)

extension ModelManager {
  /// Fully curated models with descriptions we control. Order matters.
  fileprivate static let curatedSuggestedModels: [MLXModel] = [
    // Top suggestion — Gemma 3n E4B IT LM (4-bit)
    MLXModel(
      id: "mlx-community/gemma-3n-E4B-it-lm-4bit",
      name: friendlyName(from: "mlx-community/gemma-3n-E4B-it-lm-4bit"),
      description:
        "Gemma 3n E4B IT LM (4-bit). Excellent quality/speed balance on Apple Silicon; great general assistant.",
      downloadURL: "https://huggingface.co/mlx-community/gemma-3n-E4B-it-lm-4bit"
    ),

    // Qwen3 Coder — top pick for coding
    MLXModel(
      id: "lmstudio-community/qwen3-coder-30b-a3b-instruct-mlx-4bit",
      name: friendlyName(from: "lmstudio-community/qwen3-coder-30b-a3b-instruct-mlx-4bit"),
      description:
        "Qwen3 Coder 30B A3B Instruct (MLX 4-bit). Exceptional coding model; very large download and memory usage.",
      downloadURL:
        "https://huggingface.co/lmstudio-community/qwen3-coder-30b-a3b-instruct-mlx-4bit"
    ),

    // Popular general models (extra variety)
    MLXModel(
      id: "mlx-community/Mistral-7B-Instruct-4bit",
      name: friendlyName(from: "mlx-community/Mistral-7B-Instruct-4bit"),
      description: "Popular 7B instruct model. Good general assistant with efficient runtime.",
      downloadURL: "https://huggingface.co/mlx-community/Mistral-7B-Instruct-4bit"
    ),
    MLXModel(
      id: "mlx-community/Phi-3-mini-4k-instruct-4bit",
      name: friendlyName(from: "mlx-community/Phi-3-mini-4k-instruct-4bit"),
      description: "Very small and speedy. Great for lightweight tasks and constrained devices.",
      downloadURL: "https://huggingface.co/mlx-community/Phi-3-mini-4k-instruct-4bit"
    ),

    // Qwen family — 3 sizes
    MLXModel(
      id: "mlx-community/Qwen3-1.7B-4bit",
      name: friendlyName(from: "mlx-community/Qwen3-1.7B-4bit"),
      description:
        "Qwen3 1.7B (4-bit). Tiny and fast. Great for quick tests, code helpers, and lightweight tasks.",
      downloadURL: "https://huggingface.co/mlx-community/Qwen3-1.7B-4bit"
    ),
    MLXModel(
      id: "mlx-community/Qwen3-4B-4bit",
      name: friendlyName(from: "mlx-community/Qwen3-4B-4bit"),
      description: "Qwen3 4B (4-bit). Modern small model with strong instruction following.",
      downloadURL: "https://huggingface.co/mlx-community/Qwen3-4B-4bit"
    ),
    MLXModel(
      id: "mlx-community/Qwen3-235B-A22B-4bit",
      name: friendlyName(from: "mlx-community/Qwen3-235B-A22B-4bit"),
      description: "Qwen3 235B MoE A22B (4-bit). High quality; heavy memory requirements.",
      downloadURL: "https://huggingface.co/mlx-community/Qwen3-235B-A22B-4bit"
    ),

    // New additions — Gemma 3, Qwen3, GPT-OSS
    MLXModel(
      id: "lmstudio-community/gemma-3-270m-it-MLX-8bit",
      name: friendlyName(from: "lmstudio-community/gemma-3-270m-it-MLX-8bit"),
      description: "Gemma 3 270M IT (8-bit MLX). Extremely small and fast for experimentation.",
      downloadURL: "https://huggingface.co/lmstudio-community/gemma-3-270m-it-MLX-8bit"
    ),

    // Reasoning-focused choices
    MLXModel(
      id: "mlx-community/DeepSeek-R1-Distill-Qwen-1.5B-4bit",
      name: friendlyName(from: "mlx-community/DeepSeek-R1-Distill-Qwen-1.5B-4bit"),
      description:
        "Reasoning-focused distilled model. Good for structured steps and chain-of-thought style prompts.",
      downloadURL: "https://huggingface.co/mlx-community/DeepSeek-R1-Distill-Qwen-1.5B-4bit"
    ),

    MLXModel(
      id: "mlx-community/Qwen3-Next-80B-A3B-Thinking-4bit",
      name: friendlyName(from: "mlx-community/Qwen3-Next-80B-A3B-Thinking-4bit"),
      description:
        "Qwen3-Next 80B A3B Thinking (4-bit). Reasoning-focused assistant; heavy memory requirements.",
      downloadURL: "https://huggingface.co/mlx-community/Qwen3-Next-80B-A3B-Thinking-4bit"
    ),

    MLXModel(
      id: "lmstudio-community/gpt-oss-20b-MLX-8bit",
      name: friendlyName(from: "lmstudio-community/gpt-oss-20b-MLX-8bit"),
      description: "GPT-OSS 20B (8-bit MLX) by OpenAI. High-quality general model in MLX format.",
      downloadURL: "https://huggingface.co/lmstudio-community/gpt-oss-20b-MLX-8bit"
    ),

    MLXModel(
      id: "lmstudio-community/gpt-oss-120b-MLX-8bit",
      name: friendlyName(from: "lmstudio-community/gpt-oss-120b-MLX-8bit"),
      description:
        "GPT-OSS 120B (MLX 8-bit). ~117B parameters; premium general assistant with strong reasoning and coding. Optimized for Apple Silicon via MLX; requires 64GB+ unified memory; very large download.",
      downloadURL: "https://huggingface.co/lmstudio-community/gpt-oss-120b-MLX-8bit"
    ),

    // Kimi
    MLXModel(
      id: "mlx-community/Kimi-VL-A3B-Thinking-4bit",
      name: friendlyName(from: "mlx-community/Kimi-VL-A3B-Thinking-4bit"),
      description:
        "Kimi VL A3B thinking variant (4-bit). Versatile assistant with strong reasoning.",
      downloadURL: "https://huggingface.co/mlx-community/Kimi-VL-A3B-Thinking-4bit"
    ),

    // Llama family
    MLXModel(
      id: "mlx-community/Llama-3.2-1B-Instruct-4bit",
      name: friendlyName(from: "mlx-community/Llama-3.2-1B-Instruct-4bit"),
      description: "Tiny and fast. Great for quick tests, code helpers, and lightweight tasks.",
      downloadURL: "https://huggingface.co/mlx-community/Llama-3.2-1B-Instruct-4bit"
    ),
    MLXModel(
      id: "mlx-community/Llama-3.2-3B-Instruct-4bit",
      name: friendlyName(from: "mlx-community/Llama-3.2-3B-Instruct-4bit"),
      description:
        "Great quality/speed balance. Strong general assistant at a small memory footprint.",
      downloadURL: "https://huggingface.co/mlx-community/Llama-3.2-3B-Instruct-4bit"
    ),
  ]

  fileprivate static func friendlyName(from repoId: String) -> String {
    // Take the last path component and title-case-ish
    let last = repoId.split(separator: "/").last.map(String.init) ?? repoId
    let spaced = last.replacingOccurrences(of: "-", with: " ")
    // Keep common tokens uppercase
    return
      spaced
      .replacingOccurrences(of: "llama", with: "Llama", options: .caseInsensitive)
      .replacingOccurrences(of: "qwen", with: "Qwen", options: .caseInsensitive)
      .replacingOccurrences(of: "gemma", with: "Gemma", options: .caseInsensitive)
      .replacingOccurrences(of: "deepseek", with: "DeepSeek", options: .caseInsensitive)
  }
}

// MARK: - Hugging Face discovery helpers

extension ModelManager {
  fileprivate struct HFModel: Decodable {
    let id: String
    let tags: [String]?
    let siblings: [HFSibling]?
  }

  fileprivate struct HFSibling: Decodable {
    let rfilename: String
  }

  /// Build the HF models API URL
  fileprivate static func makeHFModelsURL(author: String?, search: String, limit: Int) -> URL? {
    var comps = URLComponents()
    comps.scheme = "https"
    comps.host = "huggingface.co"
    comps.path = "/api/models"
    var items: [URLQueryItem] = [
      URLQueryItem(name: "limit", value: String(limit)),
      URLQueryItem(name: "full", value: "1"),
      URLQueryItem(name: "sort", value: "downloads"),
    ]
    if let author, !author.isEmpty { items.append(URLQueryItem(name: "author", value: author)) }
    if !search.isEmpty { items.append(URLQueryItem(name: "search", value: search)) }
    comps.queryItems = items
    return comps.url
  }

  /// Request HF models at URL
  fileprivate static func requestHFModels(at url: URL) async throws -> [HFModel] {
    var request = URLRequest(url: url)
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      return []
    }
    do {
      return try JSONDecoder().decode([HFModel].self, from: data)
    } catch {
      return []
    }
  }

  /// Heuristic to decide if an HF model is likely MLX-compatible
  fileprivate static func isLikelyMLXCompatible(_ model: HFModel) -> Bool {
    let lowerId = model.id.lowercased()
    // Strong signals: org or id contains "mlx"
    if lowerId.contains("mlx") { return true }
    // Tags sometimes include library identifiers
    if let tags = model.tags?.map({ $0.lowercased() }) {
      if tags.contains("mlx") || tags.contains("apple-mlx") || tags.contains("library:mlx") {
        return true
      }
    }
    // File-based heuristic: config + safetensors + some tokenizer asset present
    if let siblings = model.siblings {
      var hasConfig = false
      var hasWeights = false
      var hasTokenizer = false
      for s in siblings {
        let f = s.rfilename.lowercased()
        if f == "config.json" { hasConfig = true }
        if f.hasSuffix(".safetensors") { hasWeights = true }
        if f == "tokenizer.json" || f == "tokenizer.model" || f == "spiece.model"
          || f == "vocab.json" || f == "vocab.txt"
        {
          hasTokenizer = true
        }
      }
      if hasConfig && hasWeights && hasTokenizer { return true }
    }
    return false
  }

  /// Merge new models into availableModels without duplicates; initialize downloadStates
  fileprivate func mergeAvailable(with newModels: [MLXModel]) {
    // Build a case-insensitive set of existing ids across available and suggested
    var existingLower: Set<String> = Set(
      (availableModels + suggestedModels).map { $0.id.lowercased() })
    var appended: [MLXModel] = []
    for m in newModels {
      let key = m.id.lowercased()
      if !existingLower.contains(key) {
        existingLower.insert(key)
        appended.append(m)
      }
    }
    guard !appended.isEmpty else { return }
    availableModels.append(contentsOf: appended)
    for m in appended {
      downloadStates[m.id] = m.isDownloaded ? .completed : .notStarted
    }
  }
}

// MARK: - Local discovery and input parsing helpers

extension ModelManager {
  /// Parse a user-provided text into a Hugging Face repo id ("org/repo") if possible.
  static func parseHuggingFaceRepoId(from input: String) -> String? {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    if let url = URL(string: trimmed), let host = url.host?.lowercased(), host == "huggingface.co" {
      let components = url.pathComponents.filter { $0 != "/" }
      if components.count >= 2 {
        return "\(components[0])/\(components[1])"
      }
      return nil
    }
    // Raw org/repo
    if trimmed.contains("/") {
      let parts = trimmed.split(separator: "/").map(String.init)
      if parts.count >= 2, !parts[0].isEmpty, !parts[1].isEmpty {
        return "\(parts[0])/\(parts[1])"
      }
    }
    return nil
  }

  /// Discover locally downloaded models regardless of SDK allowlist.
  fileprivate static func discoverLocalModels() -> [MLXModel] {
    let fm = FileManager.default
    let root = DirectoryPickerService.shared.effectiveModelsDirectory
    guard
      let orgDirs = try? fm.contentsOfDirectory(
        at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
    else {
      return []
    }

    var models: [MLXModel] = []

    func exists(_ base: URL, _ name: String) -> Bool {
      fm.fileExists(atPath: base.appendingPathComponent(name).path)
    }

    for orgURL in orgDirs {
      var isOrg: ObjCBool = false
      guard fm.fileExists(atPath: orgURL.path, isDirectory: &isOrg), isOrg.boolValue else {
        continue
      }
      guard
        let repos = try? fm.contentsOfDirectory(
          at: orgURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
      else { continue }
      for repoURL in repos {
        var isRepo: ObjCBool = false
        guard fm.fileExists(atPath: repoURL.path, isDirectory: &isRepo), isRepo.boolValue else {
          continue
        }

        // Validate minimal required files (aligned with MLXModel.isDownloaded)
        guard exists(repoURL, "config.json") else { continue }
        let hasTokenizerJSON = exists(repoURL, "tokenizer.json")
        let hasBPE =
          exists(repoURL, "merges.txt")
          && (exists(repoURL, "vocab.json") || exists(repoURL, "vocab.txt"))
        let hasSentencePiece = exists(repoURL, "tokenizer.model") || exists(repoURL, "spiece.model")
        let hasTokenizer = hasTokenizerJSON || hasBPE || hasSentencePiece
        guard hasTokenizer else { continue }
        guard let items = try? fm.contentsOfDirectory(at: repoURL, includingPropertiesForKeys: nil),
          items.contains(where: { $0.pathExtension == "safetensors" })
        else { continue }

        let org = orgURL.lastPathComponent
        let repo = repoURL.lastPathComponent
        let id = "\(org)/\(repo)"
        let model = MLXModel(
          id: id,
          name: friendlyName(from: id),
          description: "Local model (detected)",
          downloadURL: "https://huggingface.co/\(id)"
        )
        models.append(model)
      }
    }

    // De-duplicate by lowercase id
    var seen: Set<String> = []
    var unique: [MLXModel] = []
    for m in models {
      let key = m.id.lowercased()
      if !seen.contains(key) {
        seen.insert(key)
        unique.append(m)
      }
    }
    return unique
  }
}
