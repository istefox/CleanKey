import XCTest

@testable import CleanKey

final class UpdateCheckerTests: XCTestCase {

  // MARK: - isRemoteNewer

  func testNewerPatch() {
    XCTAssertTrue(UpdateChecker.isRemoteNewer(remoteTag: "v1.0.1", localVersion: "1.0.0"))
  }

  func testNewerMinor() {
    XCTAssertTrue(UpdateChecker.isRemoteNewer(remoteTag: "v1.1.0", localVersion: "1.0.9"))
  }

  func testNewerMajor() {
    XCTAssertTrue(UpdateChecker.isRemoteNewer(remoteTag: "v2.0.0", localVersion: "1.9.9"))
  }

  func testMultiDigitComponent() {
    // 1.10.0 > 1.9.0 (not lexicographic)
    XCTAssertTrue(UpdateChecker.isRemoteNewer(remoteTag: "v1.10.0", localVersion: "1.9.0"))
  }

  func testSameVersion() {
    XCTAssertFalse(UpdateChecker.isRemoteNewer(remoteTag: "v1.0.0", localVersion: "1.0.0"))
  }

  func testOlderVersion() {
    XCTAssertFalse(UpdateChecker.isRemoteNewer(remoteTag: "v0.9.0", localVersion: "1.0.0"))
  }

  func testVPrefixStripped() {
    XCTAssertTrue(UpdateChecker.isRemoteNewer(remoteTag: "v1.0.1", localVersion: "1.0.0"))
    XCTAssertFalse(UpdateChecker.isRemoteNewer(remoteTag: "1.0.0", localVersion: "1.0.0"))
  }

  func testNonNumericComponentReturnsFalse() {
    XCTAssertFalse(UpdateChecker.isRemoteNewer(remoteTag: "v1.0.alpha", localVersion: "1.0.0"))
  }

  func testMalformedTagReturnsFalse() {
    XCTAssertFalse(UpdateChecker.isRemoteNewer(remoteTag: "latest", localVersion: "1.0.0"))
  }

  // MARK: - checkForUpdate with injected fetch

  func testCheckForUpdateReturnsReleaseInfoWhenNewer() async throws {
    let json = """
      {
        "tag_name": "v9.9.9",
        "html_url": "https://github.com/istefox/CleanKey/releases/tag/v9.9.9",
        "assets": [
          {
            "name": "CleanKey-9.9.9.dmg",
            "browser_download_url": "https://github.com/istefox/CleanKey/releases/download/v9.9.9/CleanKey-9.9.9.dmg"
          }
        ]
      }
      """.data(using: .utf8)!

    let checker = UpdateChecker(currentVersion: "1.0.0") { _ in json }
    let info = try await checker.checkForUpdate()

    XCTAssertNotNil(info)
    XCTAssertEqual(info?.version, "9.9.9")
    XCTAssertEqual(info?.tagName, "v9.9.9")
    XCTAssertEqual(info?.dmgURL?.lastPathComponent, "CleanKey-9.9.9.dmg")
  }

  func testCheckForUpdateReturnsNilWhenNotNewer() async throws {
    let json = """
      {
        "tag_name": "v1.0.0",
        "html_url": "https://github.com/istefox/CleanKey/releases/tag/v1.0.0",
        "assets": []
      }
      """.data(using: .utf8)!

    let checker = UpdateChecker(currentVersion: "1.0.0") { _ in json }
    let info = try await checker.checkForUpdate()

    XCTAssertNil(info)
  }

  func testCheckForUpdateNilDmgWhenNoAsset() async throws {
    let json = """
      {
        "tag_name": "v2.0.0",
        "html_url": "https://github.com/istefox/CleanKey/releases/tag/v2.0.0",
        "assets": []
      }
      """.data(using: .utf8)!

    let checker = UpdateChecker(currentVersion: "1.0.0") { _ in json }
    let info = try await checker.checkForUpdate()

    XCTAssertNotNil(info)
    XCTAssertNil(info?.dmgURL)
  }

  func testCheckForUpdatePropagatesNetworkError() async {
    let checker = UpdateChecker(currentVersion: "1.0.0") { _ in
      throw URLError(.notConnectedToInternet)
    }
    do {
      _ = try await checker.checkForUpdate()
      XCTFail("Expected error to be thrown")
    } catch {
      XCTAssertTrue(error is URLError)
    }
  }
}
