import XCTest
@testable import ImagingCore

final class HistoryStoreTests: XCTestCase {
    private var tempFileURL: URL!

    override func setUp() {
        super.setUp()
        tempFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("history-test-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempFileURL)
        super.tearDown()
    }

    private func makeEntry(
        timestamp: Date = Date(),
        input: String = "/tmp/in.png",
        output: String = "/tmp/out.png",
        durationMs: Int = 1234
    ) -> HistoryEntry {
        HistoryEntry(
            timestamp: timestamp,
            inputPath: input,
            outputPath: output,
            modelName: "realesrgan-x4plus",
            scale: 4,
            inputBytes: 100_000,
            outputBytes: 1_600_000,
            durationMs: durationMs,
            engineName: "ncnn"
        )
    }

    func testAppendAndList() throws {
        let store = HistoryStore(fileURL: tempFileURL)
        let entry = makeEntry()
        store.append(entry)
        let list = store.list()
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list.first?.id, entry.id)
        XCTAssertEqual(list.first?.modelName, "realesrgan-x4plus")
    }

    func testNewestFirst() {
        let store = HistoryStore(fileURL: tempFileURL)
        let now = Date()
        let older = makeEntry(timestamp: now.addingTimeInterval(-3600), input: "/tmp/older.png")
        let newer = makeEntry(timestamp: now, input: "/tmp/newer.png")
        store.append(older)
        store.append(newer)
        let list = store.list()
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(list.first?.inputPath, "/tmp/newer.png", "newest entry should be first")
        XCTAssertEqual(list.last?.inputPath, "/tmp/older.png")
    }

    func testMaxEntriesPruning() {
        let store = HistoryStore(fileURL: tempFileURL, maxEntries: 50)
        let base = Date(timeIntervalSinceReferenceDate: 100_000)
        for i in 0..<60 {
            // Each entry one second apart so ordering is deterministic.
            store.append(makeEntry(timestamp: base.addingTimeInterval(Double(i)),
                                   input: "/tmp/in-\(i).png"))
        }
        let list = store.list()
        XCTAssertEqual(list.count, 50, "store should cap at maxEntries=50")
        // Newest-first: first item must be the i=59 entry.
        XCTAssertEqual(list.first?.inputPath, "/tmp/in-59.png")
        // Oldest kept must be i=10 (60 inserted, 50 retained → drop i=0..9).
        XCTAssertEqual(list.last?.inputPath, "/tmp/in-10.png")
    }

    func testClear() {
        let store = HistoryStore(fileURL: tempFileURL)
        store.append(makeEntry())
        store.append(makeEntry(input: "/tmp/in2.png"))
        XCTAssertEqual(store.list().count, 2)
        store.clear()
        XCTAssertEqual(store.list().count, 0)
    }

    func testRoundtripPersistence() {
        let entry = makeEntry(input: "/tmp/persist.png")
        do {
            let store1 = HistoryStore(fileURL: tempFileURL)
            store1.append(entry)
        }
        let store2 = HistoryStore(fileURL: tempFileURL)
        let list = store2.list()
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list.first?.id, entry.id)
        XCTAssertEqual(list.first?.inputPath, "/tmp/persist.png")
        XCTAssertEqual(list.first?.engineName, "ncnn")
    }

    func testEmptyListWhenNoFile() {
        let store = HistoryStore(fileURL: tempFileURL)
        XCTAssertEqual(store.list().count, 0, "non-existent file should yield empty list, not crash")
    }
}
