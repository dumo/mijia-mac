import Testing
import Foundation
@testable import MijiaCore

struct VersionCheckerTests {

    @Test("latestTag 从 GitHub Releases JSON 取出 tag_name")
    func parseTag() throws {
        let json = #"{"url":"x","tag_name":"v1.4.2","name":"release"}"#.data(using: .utf8)!
        #expect(VersionChecker.latestTag(from: json) == "v1.4.2")
    }

    @Test("latestTag 在缺字段 / 非 JSON 时返回 nil")
    func parseTagMissing() {
        #expect(VersionChecker.latestTag(from: "{}".data(using: .utf8)!) == nil)
        #expect(VersionChecker.latestTag(from: "not json".data(using: .utf8)!) == nil)
    }

    @Test("语义化版本比较：去 v 前缀、缺省段补 0")
    func compare() {
        #expect(VersionChecker.compare("v1.2", "1.2.0") == .orderedSame)
        #expect(VersionChecker.compare("1.9.0", "1.10.0") == .orderedAscending)
        #expect(VersionChecker.compare("2.0.0", "1.99.99") == .orderedDescending)
        #expect(VersionChecker.compare("v1.2.3", "v1.2.4") == .orderedAscending)
    }
}
