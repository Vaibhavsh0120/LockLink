import Flutter
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

  func testWidgetRejectsAmbiguousAddressesAndMalformedStatus() throws {
    let key = String(repeating: "a", count: 64)
    for address in ["http://0172.16.0.1", "http://192.168.01.111", "http://10.1.2.3:0",
                    "http://10.1.2.3:65536", "http://8.8.8.8", "http://gate.local/unlock"] {
      XCTAssertThrowsError(try GateWidgetConfiguration(address: address, signingKey: key).validate())
    }
    try GateWidgetConfiguration(address: "http://192.168.0.111:8080", signingKey: key).validate()
    let statuses: [[String: Any]] = [["online": true], ["online": "true", "state": "locked"],
      ["online": true, "state": "unknown"], ["online": true, "state": "unlocking"],
      ["online": true, "state": "locked", "mode": "relay"],
      ["online": true, "state": "locked", "mode": "relay", "armed": "true"],
      ["online": true, "state": "locked", "mode": 12],
      ["online": 1, "state": "locked"]]
    for status in statuses {
      XCTAssertThrowsError(try GateWidgetStatus.modeForStatus(status))
    }
    XCTAssertEqual(try GateWidgetStatus.modeForStatus(["online": true, "state": "locked"]), "led")
    XCTAssertEqual(try GateWidgetStatus.modeForStatus(
      ["online": true, "state": "locked", "mode": "relay", "armed": true]), "relay")
  }

  func testResignedWidgetGroupRequiresOSAccessAndRejectsAmbiguity() {
    let base = "group.com.locklink.locklink"
    let resigned = base + ".ABCDE12345"
    XCTAssertEqual(GateWidgetStore.resolveGroup(metadataGroups: [resigned],
      profileData: nil, isAccessible: { $0 == resigned }), resigned)
    XCTAssertNil(GateWidgetStore.resolveGroup(metadataGroups: [resigned],
      profileData: nil, isAccessible: { _ in false }))
    XCTAssertNil(GateWidgetStore.resolveGroup(metadataGroups: ["group.other.app"],
      profileData: nil, isAccessible: { $0 != base }))
    XCTAssertNil(GateWidgetStore.resolveGroup(metadataGroups: [resigned, base + ".OTHER12345"],
      profileData: nil, isAccessible: { $0 != base }))
    XCTAssertEqual(GateWidgetStore.resolveGroup(metadataGroups: [],
      profileData: nil, isAccessible: { $0 == base }), base)
  }

  func testResignedWidgetGroupCanUseProfileWithoutAltStoreMetadata() throws {
    let resigned = "group.com.locklink.locklink.ABCDE12345"
    let plist = try PropertyListSerialization.data(fromPropertyList: [
      "Entitlements": ["com.apple.security.application-groups": [resigned]]
    ], format: .xml, options: 0)
    // A mobileprovision contains an XML plist inside a CMS envelope. The parser
    // discovers names only; the OS access check remains the authority.
    let profile = Data([0x30, 0x82, 0xFF]) + plist + Data([0x00, 0xFF])
    XCTAssertEqual(GateWidgetStore.resolveGroup(metadataGroups: [],
      profileData: profile, isAccessible: { $0 == resigned }), resigned)
    XCTAssertNil(GateWidgetStore.resolveGroup(metadataGroups: [],
      profileData: Data("invalid".utf8), isAccessible: { _ in false }))
  }

}
