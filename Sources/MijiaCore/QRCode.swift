import Foundation
import CoreImage
import CoreGraphics
import ImageIO

/// 用 CoreImage 原生生成二维码矩阵（无任何第三方依赖）。
/// 返回 `[[Bool]]`，`true` = 深色模块；行序为**从上到下**（已做方向校正）。
public enum QRCode {

    /// ⚠️ 不能对 CIImage 做非整数倍缩放：双线性插值会把模块边界糊掉，
    /// 结果就是「看起来像二维码但扫不出来」。CIQRCodeGenerator 输出的
    /// extent 本身就是 模块数×模块数，直接按原始尺寸渲染即可。
    public static func matrix(_ string: String) -> [[Bool]]? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(string.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let image = filter.outputImage else { return nil }

        let bounds = image.extent
        let w = Int(bounds.width.rounded())
        let h = Int(bounds.height.rounded())
        guard w > 0, h > 0 else { return nil }

        var buffer = [UInt8](repeating: 255, count: w * h)
        let context = CIContext()
        context.render(image,
                       toBitmap: &buffer,
                       rowBytes: w,
                       bounds: bounds,
                       format: .L8,
                       colorSpace: CGColorSpaceCreateDeviceGray())

        var m: [[Bool]] = (0..<h).map { y in
            (0..<w).map { x in buffer[y * w + x] < 128 }
        }
        m = correctOrientation(m)
        return m
    }

    /// 终端 ASCII 渲染。每个模块占 2 列以修正字符宽高比，四周留 4 模块 quiet zone
    /// （二维码规范要求，不留扫不出来）。
    public static func ascii(_ string: String) -> String? {
        guard let m = matrix(string), let w = m.first?.count else { return nil }
        let blank = String(repeating: "  ", count: w + 8)
        var lines: [String] = Array(repeating: blank, count: 4)
        for row in m {
            var line = String(repeating: "  ", count: 4)
            for cell in row {
                line += cell ? "██" : "  "
            }
            line += String(repeating: "  ", count: 4)
            lines.append(line)
        }
        lines.append(contentsOf: Array(repeating: blank, count: 4))
        return lines.joined(separator: "\n")
    }

    /// 生成 PNG（用于直接展示给用户扫，比终端 ASCII 可靠得多）
    public static func pngData(_ string: String,
                               modulePixels: Int = 8,
                               quiet: Int = 4) -> Data? {
        guard let m = matrix(string), let w = m.first?.count else { return nil }
        let side = (w + quiet * 2) * modulePixels
        var buffer = [UInt8](repeating: 255, count: side * side)

        for y in 0..<w {
            for x in 0..<w where m[y][x] {
                for dy in 0..<modulePixels {
                    for dx in 0..<modulePixels {
                        let py = (y + quiet) * modulePixels + dy
                        let px = (x + quiet) * modulePixels + dx
                        buffer[py * side + px] = 0
                    }
                }
            }
        }

        guard let provider = CGDataProvider(data: Data(buffer) as CFData) else { return nil }
        guard let cg = CGImage(width: side, height: side,
                               bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: side,
                               space: CGColorSpaceCreateDeviceGray(),
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                               provider: provider, decode: nil,
                               shouldInterpolate: false, intent: .defaultIntent) else { return nil }

        let output = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(output as CFMutableData,
                                                          "public.png" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, cg, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return output as Data
    }

    // MARK: - 方向校正

    /// CoreImage 渲染到 bitmap 的行序在不同路径下可能是自下而上的。
    /// 二维码左上/右上/左下是定位图案（finder），右下角一定是数据区——
    /// 用这一点判断是否需要上下翻转。
    private static func correctOrientation(_ m: [[Bool]]) -> [[Bool]] {
        guard m.count >= 7, let w = m.first?.count, w >= 7 else { return m }
        if isFinderPattern(m, row: m.count - 7, col: w - 7) {
            return m.reversed()
        }
        return m
    }

    /// 严格匹配 7x7 finder：外圈实心、次圈空心、中心 3x3 实心
    private static func isFinderPattern(_ m: [[Bool]], row: Int, col: Int) -> Bool {
        for i in 0..<7 {
            for j in 0..<7 {
                let expected: Bool
                if i == 0 || i == 6 || j == 0 || j == 6 {
                    expected = true
                } else if (2...4).contains(i) && (2...4).contains(j) {
                    expected = true
                } else {
                    expected = false
                }
                if m[row + i][col + j] != expected { return false }
            }
        }
        return true
    }
}
