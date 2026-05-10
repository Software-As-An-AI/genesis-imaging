import Foundation
import Observation
import ImagingCore

@MainActor
@Observable
public final class HistoryViewModel {
    public var entries: [HistoryEntry] = []
    private let store: HistoryStore

    public init(store: HistoryStore = .shared) {
        self.store = store
        reload()
    }

    public func reload() {
        entries = store.list()
    }

    public func clear() {
        store.clear()
        reload()
    }
}
