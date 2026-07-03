//
//  LocalProviderAutoDiscoverySchedule.swift
//  flannel
//
//  Created by OpenAI Codex on 7/3/26.
//

import Foundation

nonisolated struct LocalProviderAutoDiscoverySchedule: Hashable, Sendable {
    static let defaultRefreshInterval: TimeInterval = 120
    static let defaultRefreshIntervalNanoseconds: UInt64 = 120_000_000_000

    var refreshInterval: TimeInterval = Self.defaultRefreshInterval

    func shouldRefresh(
        now: Date,
        lastRefreshStartedAt: Date?,
        isDiscovering: Bool,
        targetCount: Int
    ) -> Bool {
        guard targetCount > 0,
              !isDiscovering else {
            return false
        }

        guard let lastRefreshStartedAt else {
            return true
        }

        return now.timeIntervalSince(lastRefreshStartedAt) >= refreshInterval
    }
}
