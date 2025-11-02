//
//  ModelCacheInspectorView.swift
//  osaurus
//
//  Popover UI to inspect and manage cached MLX models.
//

import SwiftUI

struct ModelCacheInspectorView: View {
  @Environment(\.theme) private var theme
  @State private var items: [CacheItem] = []
  @State private var isClearingAll = false

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Loaded Models")
          .font(.system(size: 13, weight: .semibold))
          .foregroundColor(theme.primaryText)
        Spacer()
        Button(action: { Task { await refresh() } }) {
          Image(systemName: "arrow.clockwise")
            .font(.system(size: 12, weight: .semibold))
        }
        .buttonStyle(PlainButtonStyle())
        .help("Refresh")
      }

      if items.isEmpty {
        Text("No models currently cached.")
          .font(.system(size: 12))
          .foregroundColor(theme.secondaryText)
          .padding(.vertical, 8)
      } else {
        VStack(spacing: 8) {
          ForEach(items, id: \.id) { item in
            HStack(alignment: .center, spacing: 8) {
              VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                  Text(item.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(theme.primaryText)
                }
                Text(formatBytes(item.bytes))
                  .font(.system(size: 11, design: .monospaced))
                  .foregroundColor(theme.secondaryText)
              }
              Spacer()
              Button(role: .destructive) {
                Task { @MainActor in
                  ModelManager.shared.deleteModel(item.model)
                  await refresh()
                }
              } label: {
                Text("Delete")
                  .font(.system(size: 12, weight: .semibold))
              }
            }
            .padding(8)
            .background(
              RoundedRectangle(cornerRadius: 8)
                .fill(theme.cardBackground)
                .overlay(
                  RoundedRectangle(cornerRadius: 8)
                    .stroke(theme.cardBorder, lineWidth: 1)
                )
            )
          }
        }
      }

      Divider()

      HStack {
        Button(role: .destructive) {
          Task {
            isClearingAll = true
            await clearAll()
            await refresh()
            isClearingAll = false
          }
        } label: {
          HStack(spacing: 6) {
            Image(systemName: "trash")
            Text("Clear All")
          }
        }
        .buttonStyle(.bordered)
        .tint(theme.errorColor)

        Spacer()
      }
    }
    .onAppear {
      Task { await refresh() }
    }
  }

  private func refresh() async {
    let models = ModelManager.discoverLocalModels()
    let computed: [CacheItem] = models.map { m in
      let bytes = directoryAllocatedSize(at: m.localDirectory) ?? 0
      return CacheItem(id: m.id, name: m.name, bytes: bytes, model: m)
    }.sorted { lhs, rhs in
      lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
    await MainActor.run { items = computed }
  }

  private func formatBytes(_ bytes: Int64) -> String {
    if bytes <= 0 { return "~0 MB" }
    let kb = Double(bytes) / 1024.0
    let mb = kb / 1024.0
    let gb = mb / 1024.0
    if gb >= 1.0 { return String(format: "%.2f GB", gb) }
    return String(format: "%.1f MB", mb)
  }

  private func directoryAllocatedSize(at url: URL) -> Int64? {
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

  private func clearAll() async {
    await MainActor.run {
      let models = ModelManager.discoverLocalModels()
      for m in models { ModelManager.shared.deleteModel(m) }
    }
  }
}

private struct CacheItem: Identifiable {
  let id: String
  let name: String
  let bytes: Int64
  let model: MLXModel
}
