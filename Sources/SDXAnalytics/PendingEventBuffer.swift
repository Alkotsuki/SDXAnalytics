//
//  PendingEventBuffer.swift
//  SDXAnalytics
//
//  A bounded FIFO for whatever was recorded before `configure()` ran.
//
//  Internal, and not thread-safe on its own — it only ever exists inside the client's lock.
//
//  Bounded rather than unbounded because the failure mode of an unbounded buffer is the worst one
//  available: an app that never configures (a bad key, a destination that throws) grows this
//  forever and is eventually killed for memory, which reads as a crash bug rather than as the
//  misconfiguration it is. Dropping the oldest and counting the drops turns that into a log line.
//

import Foundation

struct PendingEventBuffer {

    enum Item {
        case event(SDXAnalyticsEvent)
        case purchase(SDXAnalyticsPurchase)
        case screen(name: String, className: String?)
    }

    private(set) var items: [Item] = []
    private(set) var droppedCount = 0

    let limit: Int

    init(limit: Int) {
        self.limit = max(0, limit)
    }

    var isEmpty: Bool { items.isEmpty }
    var count: Int { items.count }

    mutating func append(_ item: Item) {
        guard limit > 0 else {
            droppedCount += 1
            return
        }

        // Drop the oldest rather than refusing the newest. If only some of a session survives, the
        // recent end of it is the useful end — it is closest to whatever the user did last.
        if items.count == limit {
            items.removeFirst()
            droppedCount += 1
        }

        items.append(item)
    }

    /// Hands back everything held and empties the buffer. The drop count survives, because it is
    /// worth logging after the drain.
    mutating func drain() -> [Item] {
        defer { items.removeAll() }
        return items
    }
}
