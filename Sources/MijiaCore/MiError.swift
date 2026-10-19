import Foundation

public enum MiError: Error, LocalizedError, Equatable {
    case invalidBase64(String)
    case gzipInvalid
    case invalidResponse(String)
    case http(status: Int, body: String)
    /// 登录流程错误（passport / longPolling 返回非 0 code）
    case login(code: Int, desc: String)
    /// 业务接口错误（api.mijia.tech 返回非 0 code）
    case api(code: Int, message: String)
    case notLoggedIn
    case timeout
    case deviceNotFound(String)
    case multipleDevices(String)
    case unsupportedProp(String)
    case propNotReadable(String)
    case propNotWritable(String)
    case valueOutOfRange(String)

    public var errorDescription: String? {
        switch self {
        case .invalidBase64(let what):
            return "Base64 解码失败: \(what)"
        case .gzipInvalid:
            return "Gzip 数据非法或解压失败"
        case .invalidResponse(let what):
            return "响应无法解析: \(what)"
        case .http(let status, let body):
            return "HTTP \(status): \(body.prefix(200))"
        case .login(let code, let desc):
            return "登录失败 [\(code)]: \(desc)"
        case .api(let code, let message):
            return "接口错误 [\(code)]: \(message)"
        case .notLoggedIn:
            return "尚未登录，请先扫码登录"
        case .timeout:
            return "等待扫码超时（120 秒），请重试"
        case .deviceNotFound(let name):
            return "未找到设备: \(name)"
        case .multipleDevices(let name):
            return "匹配到多个设备: \(name)"
        case .unsupportedProp(let name):
            return "不支持的属性: \(name)"
        case .propNotReadable(let name):
            return "属性不可读: \(name)"
        case .propNotWritable(let name):
            return "属性不可写: \(name)"
        case .valueOutOfRange(let detail):
            return "值超出范围: \(detail)"
        }
    }
}
