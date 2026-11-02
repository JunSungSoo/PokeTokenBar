import XCTest
@testable import PokeTokenBar

final class DriveReleaseSourceTests:XCTestCase {
    func testVersionIsReadFromRealZipNamesWithoutComparingDatesOrRounds() {
        for name in ["PokeTokenBar-3.0.1.zip","PokeTokenBar-3.0.1-261102(3).zip","PokeTokenBar-3.0.1-arm64-20261102-update.zip"]{
            XCTAssertEqual(DriveReleaseSource.version(filename:name),"3.0.1")
        }
        XCTAssertEqual(DriveReleaseSource.version(filename:"PokeTokenBar-2.5.6-261103(99).zip"),"2.5.6")
        for name in ["PokeTokenBar-3.0.zip","PokeTokenBar-3.0.1-beta.zip","PokeTokenBar-3.0.1-261102(3).zip.exe","https://evil.test/PokeTokenBar-3.0.1.zip","Other-3.0.1.zip","PokeTokenBar-999999999999999999.0.1.zip"]{XCTAssertNil(DriveReleaseSource.version(filename:name),name)}
    }
    func testPublicDriveTitleParsingRejectsLoginAndMalformedMetadata() {
        XCTAssertEqual(DriveReleaseSource.release(html:"<html><title>PokeTokenBar-3.0.1-261102&#40;4&#41;.zip - Google Drive</title></html>"),.init(tag:"3.0.1",url:DriveReleaseSource.shareURL.absoluteString))
        for title in ["Sign in - Google Accounts","PokeTokenBar-3.0.1.zip - Other","PokeTokenBar-3.0.1-beta.zip - Google Drive","PokeTokenBar-3.0.1.zip.exe - Google Drive"]{XCTAssertNil(DriveReleaseSource.release(html:"<title>\(title)</title>"))}
        XCTAssertNil(DriveReleaseSource.release(html:"<div>No title</div>"))
    }
    @MainActor func testLiveDriveProbeWhenExplicitlyEnabled()async throws {
        guard ProcessInfo.processInfo.environment["PTB_DRIVE_LIVE_PROBE"]=="1" else{throw XCTSkip("Opt-in network check")}
        let fetched=await DriveReleaseSource.fetch()
        let release=try XCTUnwrap(fetched)
        XCTAssertNotNil(UpdateChecker.normalizedReleaseVersion(release.tag))
        XCTAssertEqual(release.url,DriveReleaseSource.shareURL.absoluteString)
    }
}
