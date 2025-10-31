//
//  LocalMLXModels.swift
//  osaurus
//
//  Read-only helper to discover local MLX models on disk.
//

import Foundation

enum LocalMLXModels {
  static func getAvailableModels() -> [String] {
    return scanDiskForModels().map { $0.name }
  }

  static func modelId(forName name: String) -> String? {
    let pairs = scanDiskForModels()
    if let match = pairs.first(where: { $0.name == name }) { return match.id }
    if let match = pairs.first(where: { pair in
      let repo = pair.id.split(separator: "/").last.map(String.init)?.lowercased()
      return repo == name.lowercased()
    }) {
      return match.id
    }
    if let match = pairs.first(where: { $0.id.lowercased() == name.lowercased() }) {
      return match.id
    }
    return nil
  }

  private static func scanDiskForModels() -> [(name: String, id: String)] {
    let fm = FileManager.default
    let root = effectiveModelsDirectoryUnsafe()
    guard
      let topLevel = try? fm.contentsOfDirectory(
        at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
    else {
      return []
    }
    var results: [(String, String)] = []

    func exists(_ name: String, at repoURL: URL) -> Bool {
      fm.fileExists(atPath: repoURL.appendingPathComponent(name).path)
    }

    func validateAndAppend(org: String, repo: String, repoURL: URL) {
      guard exists("config.json", at: repoURL) else { return }
      let hasTokenizerJSON = exists("tokenizer.json", at: repoURL)
      let hasBPE =
        exists("merges.txt", at: repoURL)
        && (exists("vocab.json", at: repoURL) || exists("vocab.txt", at: repoURL))
      let hasSentencePiece =
        exists("tokenizer.model", at: repoURL) || exists("spiece.model", at: repoURL)
      let hasTokenizerAssets = hasTokenizerJSON || hasBPE || hasSentencePiece
      guard hasTokenizerAssets else { return }
      guard let items = try? fm.contentsOfDirectory(at: repoURL, includingPropertiesForKeys: nil),
        items.contains(where: { $0.pathExtension == "safetensors" })
      else { return }
      let id = "\(org)/\(repo)"
      let name = repo.lowercased()
      results.append((name, id))
    }

    for orgURL in topLevel {
      var isOrgDir: ObjCBool = false
      guard fm.fileExists(atPath: orgURL.path, isDirectory: &isOrgDir), isOrgDir.boolValue else {
        continue
      }
      guard
        let repos = try? fm.contentsOfDirectory(
          at: orgURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
      else { continue }
      for repoURL in repos {
        var isRepoDir: ObjCBool = false
        guard fm.fileExists(atPath: repoURL.path, isDirectory: &isRepoDir), isRepoDir.boolValue
        else {
          continue
        }
        validateAndAppend(
          org: orgURL.lastPathComponent, repo: repoURL.lastPathComponent, repoURL: repoURL)
      }
    }

    var seen: Set<String> = []
    var unique: [(String, String)] = []
    for (name, id) in results {
      if !seen.contains(id) {
        seen.insert(id)
        unique.append((name, id))
      }
    }
    return unique
  }

  // MARK: - Utilities

  static func localDirectory(forModelId id: String) -> URL? {
    let parts = id.split(separator: "/").map(String.init)
    let base = effectiveModelsDirectoryUnsafe()
    let url: URL = parts.reduce(base) { partial, component in
      partial.appendingPathComponent(component, isDirectory: true)
    }
    let fm = FileManager.default
    let hasConfig = fm.fileExists(atPath: url.appendingPathComponent("config.json").path)
    if let items = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil),
      hasConfig && items.contains(where: { $0.pathExtension == "safetensors" })
    {
      return url
    }
    return nil
  }

  static func weightsSizeBytes(forModelId id: String) -> Int64 {
    guard let dir = localDirectory(forModelId: id) else { return 0 }
    let fm = FileManager.default
    guard
      let enumerator = fm.enumerator(
        at: dir, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey])
    else {
      return 0
    }
    var total: Int64 = 0
    for case let fileURL as URL in enumerator {
      if fileURL.pathExtension.lowercased() == "safetensors" {
        if let attrs = try? fm.attributesOfItem(atPath: fileURL.path),
          let size = attrs[.size] as? NSNumber
        {
          total += size.int64Value
        }
      }
    }
    return total
  }

  // Resolve effective models directory without touching main-actor singletons.
  // Mirrors DirectoryPickerService.effectiveModelsDirectory fallback order.
  private static func effectiveModelsDirectoryUnsafe() -> URL {
    let fm = FileManager.default
    // 1) OSU_MODELS_DIR env
    if let override = ProcessInfo.processInfo.environment["OSU_MODELS_DIR"], !override.isEmpty {
      let expanded = (override as NSString).expandingTildeInPath
      return URL(fileURLWithPath: expanded, isDirectory: true)
    }

    // 2) Try security-scoped bookmark if present
    let bookmarkKey = "ModelDirectoryBookmark"
    if let bookmarkData = UserDefaults.standard.data(forKey: bookmarkKey) {
      do {
        var isStale = false
        let url = try URL(
          resolvingBookmarkData: bookmarkData,
          options: .withSecurityScope,
          relativeTo: nil,
          bookmarkDataIsStale: &isStale)
        if !isStale { return url }
      } catch {
        // Ignore and fall back to defaults
      }
    }

    // 3) Existing old default at ~/Documents/MLXModels (if present)
    let homeURL = fm.homeDirectoryForCurrentUser
    let newDefault = homeURL.appendingPathComponent("MLXModels")
    let documentsPath = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
    let oldDefault = documentsPath.appendingPathComponent("MLXModels")
    if fm.fileExists(atPath: newDefault.path) { return newDefault }
    if fm.fileExists(atPath: oldDefault.path) { return oldDefault }
    return newDefault
  }
}
