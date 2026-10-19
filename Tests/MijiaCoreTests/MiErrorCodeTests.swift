import Testing
import Foundation
@testable import MijiaCore

@Suite("米家错误码")
struct MiErrorCodeTests {

    @Test("设备离线码 -704042011 能翻成人话")
    func offline() {
        #expect(MiErrorCode.message(for: -704042011) == "设备离线")
        #expect(MiErrorCode.describe(-704042011) == "设备离线（-704042011）")
    }

    @Test("未知码保留原始数值，不吞掉信息")
    func unknownCode() {
        #expect(MiErrorCode.message(for: 123456) == nil)
        #expect(MiErrorCode.describe(123456) == "错误码 123456")
    }
}
