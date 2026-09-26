import Flutter
import UIKit
import XCTest
@testable import Runner

class RunnerTests: XCTestCase {

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
