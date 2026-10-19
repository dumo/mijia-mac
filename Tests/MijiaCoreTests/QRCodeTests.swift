import Testing
import Foundation
import CoreImage
import CoreGraphics
@testable import MijiaCore

@Suite("二维码生成")
struct QRCodeTests {

    /// 把矩阵还原成 CGImage（第一行 = 图像顶部），交给 CIDetector 解码。
    /// 这是**方向正确性的唯一可靠判据**——CoreImage 渲染到 bitmap 的行序
    /// 可能是自下而上的，一旦搞反二维码就扫不出来。
    private func image(from matrix: [[Bool]], scale: Int = 8, quiet: Int = 4) -> CGImage? {
        guard let w = matrix.first?.count, matrix.count == w else { return nil }
        let side = (w + quiet * 2) * scale
        var buffer = [UInt8](repeating: 255, count: side * side)

        for y in 0..<w {
            for x in 0..<w {
                guard matrix[y][x] else { continue }
                for dy in 0..<scale {
                    for dx in 0..<scale {
                        let py = (y + quiet) * scale + dy
                        let px = (x + quiet) * scale + dx
                        buffer[py * side + px] = 0
                    }
                }
            }
        }

        let data = Data(buffer)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(width: side,
                       height: side,
                       bitsPerComponent: 8,
                       bitsPerPixel: 8,
                       bytesPerRow: side,
                       space: CGColorSpaceCreateDeviceGray(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider,
                       decode: nil,
                       shouldInterpolate: false,
                       intent: .defaultIntent)
    }

    @Test("生成的二维码矩阵能被系统解码器识别（验证行序未翻转）")
    func matrixIsDecodable() throws {
        let payload = "https://account.xiaomi.com/longPolling/loginUrl?_qrsize=240&sid=mijia"
        let matrix = try #require(QRCode.matrix(payload))
        let image = try #require(image(from: matrix))

        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                  options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])!
        let features = detector.features(in: CIImage(cgImage: image))
        let messages = features.compactMap { ($0 as? CIQRCodeFeature)?.messageString }
        #expect(messages == [payload])
    }

    @Test("中文/长 URL 也能被识别")
    func matrixHandlesLongPayload() throws {
        let payload = String(repeating: "米家", count: 30) + "-tail"
        let matrix = try #require(QRCode.matrix(payload))
        let image = try #require(image(from: matrix))
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                  options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])!
        let messages = detector.features(in: CIImage(cgImage: image))
            .compactMap { ($0 as? CIQRCodeFeature)?.messageString }
        #expect(messages.contains(payload))
    }

    @Test("ASCII 渲染带 4 模块 quiet zone 且行数正确")
    func asciiLayout() throws {
        let matrix = try #require(QRCode.matrix("test"))
        let ascii = try #require(QRCode.ascii("test"))
        let lines = ascii.split(separator: "\n", omittingEmptySubsequences: false)
        // 4 行上边距 + 矩阵 + 4 行下边距
        #expect(lines.count == matrix.count + 8)
        #expect(lines[0].allSatisfy { $0 == " " })
    }
}
