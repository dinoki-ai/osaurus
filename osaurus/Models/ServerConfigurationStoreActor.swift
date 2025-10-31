import Foundation

actor ServerConfigurationStoreActor {
  static let shared = ServerConfigurationStoreActor()

  func load() async -> ServerConfiguration? {
    let url = await configurationFileURL()
    if !FileManager.default.fileExists(atPath: url.path) { return nil }
    do {
      let data = try Data(contentsOf: url)
      let decoder = JSONDecoder()
      return try decoder.decode(ServerConfiguration.self, from: data)
    } catch {
      print("[Osaurus] Failed to load ServerConfiguration (actor): \(error)")
      return nil
    }
  }

  func save(_ configuration: ServerConfiguration) async {
    let url = await configurationFileURL()
    do {
      try ensureDirectoryExists(url.deletingLastPathComponent())
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(configuration)
      try data.write(to: url, options: [.atomic])
    } catch {
      print("[Osaurus] Failed to save ServerConfiguration (actor): \(error)")
    }
  }

  // MARK: - Helpers
  private func configurationFileURL() async -> URL {
    if let override = await MainActor.run(body: { ServerConfigurationStore.overrideDirectory }) {
      return override.appendingPathComponent("ServerConfiguration.json")
    }
    let fm = FileManager.default
    let supportDir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    let bundleId = Bundle.main.bundleIdentifier ?? "osaurus"
    return supportDir.appendingPathComponent(bundleId, isDirectory: true)
      .appendingPathComponent("ServerConfiguration.json")
  }

  private func ensureDirectoryExists(_ url: URL) throws {
    var isDir: ObjCBool = false
    if !FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
  }
}
