import Testing
import MijiaCore

/// 固化「批量返回乱序」这个坑：`/miotspec/prop/get` 的返回顺序与请求顺序无关，
/// 只能按返回项自带的 did/siid/piid 归位。按下标配对会让每台设备显示别人的状态。
@Suite struct PropResponsesTests {

    /// 真机探针（2026-10-20）抓到的一次批量返回：请求顺序与返回顺序完全不同。
    /// 这里保留真实 did 与真实 value，siid/piid 统一取 2.1（本次请求就是读开关）。
    private func realShuffledResults() -> [JSONValue] {
        // 请求顺序（下标即请求序）:
        // 0:100000001  1:100000002  2:100000003  3:miwifi…  4:100000004
        // 5:100000005  6:100000006  7:100000007  8:100000008  9:100000009  10:100000010
        // 返回顺序（实测，已乱序）:
        // 100000007, 100000008, 100000009, 100000001, 100000002,
        // miwifi…(code=-704010000), 100000003, 100000005, 100000006, 100000004, 100000010
        func item(did: String, code: Int, value: JSONValue?) -> JSONValue {
            var object: [String: JSONValue] = [
                "did": .string(did),
                "siid": .int(2),
                "piid": .int(1),
                "code": .int(code),
            ]
            if let value { object["value"] = value }
            return .object(object)
        }
        return [
            item(did: "100000007", code: 0, value: .bool(false)),
            item(did: "100000008", code: 0, value: .bool(false)),
            item(did: "100000009", code: 0, value: .bool(false)),
            item(did: "100000001", code: 0, value: .bool(true)),
            item(did: "100000002", code: 0, value: .bool(false)),
            item(did: "miwifi.example-0000", code: -704010000, value: nil),
            item(did: "100000003", code: 0, value: .bool(false)),
            item(did: "100000005", code: 0, value: .bool(true)),
            item(did: "100000006", code: 0, value: .bool(true)),
            item(did: "100000004", code: 0, value: .bool(true)),
            item(did: "100000010", code: 0, value: .bool(true)),
        ]
    }

    @Test func 乱序返回也能各自归位() {
        let values = PropResponses.values(from: realShuffledResults())

        func bool(_ did: String) -> Bool? {
            values[PropResponses.Key(did: did, siid: 2, piid: 1)]?.boolValue
        }

        // 关键是 100000001：它在返回里排第 4 位，若按下标就会被读成 false（别人的值）
        #expect(bool("100000001") == true)
        #expect(bool("100000005") == true)
        #expect(bool("100000006") == true)
        #expect(bool("100000004") == true)
        #expect(bool("100000010") == true)
        #expect(bool("100000007") == false)
        #expect(bool("100000008") == false)
        #expect(bool("100000009") == false)
        #expect(bool("100000002") == false)
        #expect(bool("100000003") == false)
    }

    @Test func 按下标配对会得到错误结果() {
        // 反例：证明「按下标」确实会错，锁住这个回归点
        let results = realShuffledResults()
        let requestedDids = ["100000001", "100000002", "100000003", "miwifi.example-0000",
                             "100000004", "100000005", "100000006", "100000007",
                             "100000008", "100000009", "100000010"]
        var byIndex: [String: Bool] = [:]
        for (index, result) in results.enumerated() where index < requestedDids.count {
            guard let object = result.objectValue,
                  object["code"]?.intValue == 0,
                  let value = object["value"]?.boolValue else { continue }
            byIndex[requestedDids[index]] = value
        }
        // 下标配对把「微波炉 false」错配给了空气净化器
        #expect(byIndex["100000001"] == false)
        // 真值其实是 true
        #expect(PropResponses.values(from: results)[PropResponses.Key(did: "100000001", siid: 2, piid: 1)]?.boolValue == true)
    }

    @Test func 非零code的条目被丢弃() {
        let values = PropResponses.values(from: realShuffledResults())
        #expect(values[PropResponses.Key(did: "miwifi.example-0000", siid: 2, piid: 1)] == nil)
    }

    @Test func 缺字段的条目被丢弃而不污染结果() {
        let results: [JSONValue] = [
            .object(["siid": .int(2), "piid": .int(1), "code": .int(0), "value": .bool(true)]), // 无 did
            .object(["did": .string("A"), "piid": .int(1), "code": .int(0), "value": .bool(true)]), // 无 siid
            .object(["did": .string("A"), "siid": .int(2), "code": .int(0), "value": .bool(true)]), // 无 piid
            .object(["did": .string("A"), "siid": .int(2), "piid": .int(1), "code": .int(0)]), // 无 value
        ]
        #expect(PropResponses.values(from: results).isEmpty)
    }

    @Test func 同一设备多个属性能区分() {
        let results: [JSONValue] = [
            .object(["did": .string("S"), "siid": .int(3), "piid": .int(7),
                     "code": .int(0), "value": .double(26.5)]),
            .object(["did": .string("S"), "siid": .int(3), "piid": .int(8),
                     "code": .int(0), "value": .int(55)]),
        ]
        let values = PropResponses.values(from: results)
        #expect(values[PropResponses.Key(did: "S", siid: 3, piid: 7)]?.doubleValue == 26.5)
        #expect(values[PropResponses.Key(did: "S", siid: 3, piid: 8)]?.intValue == 55)
    }

    @Test func 空返回不崩溃() {
        #expect(PropResponses.values(from: []).isEmpty)
    }
}
