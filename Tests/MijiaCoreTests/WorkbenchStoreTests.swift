import Testing
import Foundation
@testable import MijiaCore

@Suite("工作台布局持久化")
struct WorkbenchStoreTests {

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mijia-wb-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("空目录返回 nil（区分「没配过」与「配了空」）")
    func emptyIsNil() throws {
        let dir = try tempDir()
        let store = WorkbenchStore(directory: dir)
        #expect(store.keys(for: "did-1") == nil)
    }

    @Test("首次取用会写入默认值并持久化")
    func defaultingPersists() throws {
        let dir = try tempDir()
        var store = WorkbenchStore(directory: dir)
        let first = store.keys(for: "did-1", defaultingTo: ["group:2"])
        #expect(first == ["group:2"])

        let reread = WorkbenchStore(directory: dir)
        #expect(reread.keys(for: "did-1") == ["group:2"])
    }

    @Test("默认值为空时不写盘，仍返回 nil")
    func emptyDefaultNotPersisted() throws {
        let dir = try tempDir()
        var store = WorkbenchStore(directory: dir)
        #expect(store.keys(for: "did-1", defaultingTo: []).isEmpty)
        #expect(WorkbenchStore(directory: dir).keys(for: "did-1") == nil)
    }

    @Test("增删与去重")
    func addRemove() throws {
        let dir = try tempDir()
        var store = WorkbenchStore(directory: dir)

        let added = store.add("group:2", to: "did-1")
        let duplicated = store.add("group:2", to: "did-1")
        store.add("on", to: "did-1")
        let afterAdd = store.keys(for: "did-1")

        let removed = store.remove("group:2", from: "did-1")
        let removedAgain = store.remove("group:2", from: "did-1")
        let afterRemove = store.keys(for: "did-1")

        #expect(added)
        #expect(!duplicated)
        #expect(afterAdd == ["group:2", "on"])
        #expect(removed)
        #expect(!removedAgain)
        #expect(afterRemove == ["on"])
    }

    @Test("拖拽排序")
    func move() throws {
        let dir = try tempDir()
        var store = WorkbenchStore(directory: dir)
        store.setKeys(["a", "b", "c", "d"], for: "did-1")

        store.move(did: "did-1", fromOffsets: IndexSet(integer: 3), toOffset: 1)
        let forward = store.keys(for: "did-1")

        store.move(did: "did-1", fromOffsets: IndexSet(integer: 0), toOffset: 4)
        let backward = store.keys(for: "did-1")

        #expect(forward == ["a", "d", "b", "c"])
        #expect(backward == ["d", "b", "c", "a"])
    }

    @Test("排序索引越界不崩且不改变内容")
    func moveOutOfRange() throws {
        let dir = try tempDir()
        var store = WorkbenchStore(directory: dir)
        store.setKeys(["a", "b"], for: "did-1")

        store.move(did: "did-1", fromOffsets: IndexSet(integer: 99), toOffset: 99)
        let unchanged = store.keys(for: "did-1")

        store.move(did: "did-x", fromOffsets: IndexSet(integer: 0), toOffset: 0)
        let unknown = store.keys(for: "did-x")

        #expect(unchanged == ["a", "b"])
        #expect(unknown == nil)
    }

    @Test("多设备互不干扰，且改动立刻落盘")
    func isolation() throws {
        let dir = try tempDir()
        var store = WorkbenchStore(directory: dir)
        store.setKeys(["x"], for: "did-1")
        store.setKeys(["y", "z"], for: "did-2")

        let reread = WorkbenchStore(directory: dir)
        let one = reread.keys(for: "did-1")
        let two = reread.keys(for: "did-2")
        let hasZ = reread.contains("z", in: "did-2")
        let lacksZ = reread.contains("z", in: "did-1")

        #expect(one == ["x"])
        #expect(two == ["y", "z"])
        #expect(hasZ)
        #expect(!lacksZ)
    }

    @Test("removeAll 只影响指定设备")
    func removeAll() throws {
        let dir = try tempDir()
        var store = WorkbenchStore(directory: dir)
        store.setKeys(["x"], for: "did-1")
        store.setKeys(["y"], for: "did-2")
        store.removeAll(for: "did-1")

        let reread = WorkbenchStore(directory: dir)
        #expect(reread.keys(for: "did-1") == nil)
        #expect(reread.keys(for: "did-2") == ["y"])
    }

    @Test("写入是原子的：目录下不留 .tmp 残留，且能被重新读回")
    func atomicWrite() throws {
        let dir = try tempDir()
        var store = WorkbenchStore(directory: dir)
        store.setKeys(["a", "b", "c"], for: "did-1")

        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(files == ["workbench.json"])
        #expect(WorkbenchStore(directory: dir).keys(for: "did-1") == ["a", "b", "c"])
    }

    @Test("文件损坏时退化为空表而不抛错")
    func corruptedFile() throws {
        let dir = try tempDir()
        try Data("not json".utf8).write(to: dir.appendingPathComponent("workbench.json"))
        let store = WorkbenchStore(directory: dir)
        #expect(store.keys(for: "did-1") == nil)
    }
}
