import Foundation

public struct ReleaseInfo: Equatable, Sendable {
  let version: String
  let tagName: String
  let dmgURL: URL?
  let htmlURL: URL
}

struct UpdateChecker: Sendable {

  private let currentVersion: String
  private let fetch: @Sendable (URL) async throws -> Data

  private static let latestReleaseURL =
    URL(string: "https://api.github.com/repos/istefox/CleanKey/releases/latest")!

  init(
    currentVersion: String,
    fetch: @escaping @Sendable (URL) async throws -> Data = { url in
      var request = URLRequest(url: url)
      request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
      request.setValue("CleanKey/macOS", forHTTPHeaderField: "User-Agent")
      let (data, response) = try await URLSession.shared.data(for: request)
      guard let http = response as? HTTPURLResponse else {
        throw URLError(.badServerResponse)
      }
      guard http.statusCode == 200 else {
        throw URLError(
          .badServerResponse,
          userInfo: [NSLocalizedDescriptionKey: "GitHub API returned HTTP \(http.statusCode)"]
        )
      }
      return data
    }
  ) {
    self.currentVersion = currentVersion
    self.fetch = fetch
  }

  func checkForUpdate() async throws -> ReleaseInfo? {
    let data = try await fetch(Self.latestReleaseURL)

    struct GitHubRelease: Decodable {
      let tag_name: String
      let html_url: String
      let assets: [Asset]
      struct Asset: Decodable {
        let name: String
        let browser_download_url: String
      }
    }

    let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
    guard Self.isRemoteNewer(remoteTag: release.tag_name, localVersion: currentVersion) else {
      return nil
    }

    let dmgAsset = release.assets.first(where: { $0.name.hasSuffix(".dmg") })
    let dmgURL = dmgAsset.flatMap { URL(string: $0.browser_download_url) }
    let htmlURL =
      URL(string: release.html_url)
      ?? URL(string: "https://github.com/istefox/CleanKey/releases")!
    let version =
      release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name

    return ReleaseInfo(version: version, tagName: release.tag_name, dmgURL: dmgURL, htmlURL: htmlURL)
  }

  /// Returns true when remoteTag represents a version newer than localVersion.
  /// Strips a leading "v", then compares dot-separated numeric components.
  /// Any non-numeric component causes the function to return false (no spurious updates).
  static func isRemoteNewer(remoteTag: String, localVersion: String) -> Bool {
    let remoteStr = remoteTag.hasPrefix("v") ? String(remoteTag.dropFirst()) : remoteTag
    let remoteParts = remoteStr.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
    let localParts = localVersion.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }

    guard remoteParts.allSatisfy({ $0 != nil }), localParts.allSatisfy({ $0 != nil }) else {
      return false
    }

    let remoteNums = remoteParts.compactMap { $0 }
    let localNums = localParts.compactMap { $0 }
    let count = max(remoteNums.count, localNums.count)

    for i in 0..<count {
      let r = i < remoteNums.count ? remoteNums[i] : 0
      let l = i < localNums.count ? localNums[i] : 0
      if r > l { return true }
      if r < l { return false }
    }
    return false
  }
}
