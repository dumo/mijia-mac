import Foundation

/// `/miotspec/prop/get`（及 `/miotspec/prop/set`）批量返回的**归位**解析。
///
/// ⚠️ 真机探针实测（2026-10-20，17 台设备）：服务端**不保证返回顺序与请求一致**。
/// 一次 11 条的批量请求里有 10 条乱序，例如请求顺序 `[A,B,C,…]` 被返回成
/// `[G,H,I,A,…]`。因此**绝不能**按下标把结果配回请求项——早期版本正是这么写的，
/// 后果是每台设备的开关显示的都是别人的状态。
///
/// 返回项自带 `did` / `siid` / `piid`，形如
/// `{"did":"100000001","siid":2,"piid":1,"code":0,"value":true}`，只能据此归位。
public enum PropResponses: Sendable {

    /// 属性坐标：设备 + 服务 + 属性。
    public struct Key: Hashable, Sendable {
        public let did: String
        public let siid: Int
        public let piid: Int

        public init(did: String, siid: Int, piid: Int) {
            self.did = did
            self.siid = siid
            self.piid = piid
        }

        public init(did: String, prop: DevProp) {
            self.init(did: did, siid: prop.siid, piid: prop.piid)
        }
    }

    /// 把批量返回按属性坐标归位，只保留成功（`code == 0`）且带 `value` 的条目。
    ///
    /// 缺少 `did` / `siid` / `piid` 的条目一律丢弃：宁可少显示一个开关，
    /// 也绝不能把值错配到别的设备上。
    public static func values(from results: [JSONValue]) -> [Key: JSONValue] {
        var output: [Key: JSONValue] = [:]
        for result in results {
            guard let object = result.objectValue,
                  object["code"]?.intValue == 0,
                  let value = object["value"],
                  let did = object["did"]?.stringValue,
                  let siid = object["siid"]?.intValue,
                  let piid = object["piid"]?.intValue else { continue }
            output[Key(did: did, siid: siid, piid: piid)] = value
        }
        return output
    }
}
