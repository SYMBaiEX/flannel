//
//  LocalProviderAutoDiscoveryScheduleTests.swift
//  flannelTests
//
//  Created by OpenAI Codex on 7/3/26.
//

import Foundation
import Testing
@testable import flannel

struct LocalProviderAutoDiscoveryScheduleTests {
    @Test("Auto discovery refreshes immediately when no refresh has started")
    func refreshesImmediatelyWithoutPriorRefresh() {
        let schedule = LocalProviderAutoDiscoverySchedule(refreshInterval: 120)

        #expect(schedule.shouldRefresh(
            now: Date(timeIntervalSince1970: 1_800_000_000),
            lastRefreshStartedAt: nil,
            isDiscovering: false,
            targetCount: 2
        ))
    }

    @Test("Auto discovery waits for the refresh interval")
    func waitsForRefreshInterval() {
        let schedule = LocalProviderAutoDiscoverySchedule(refreshInterval: 120)
        let lastRefresh = Date(timeIntervalSince1970: 1_800_000_000)

        #expect(schedule.shouldRefresh(
            now: lastRefresh.addingTimeInterval(119),
            lastRefreshStartedAt: lastRefresh,
            isDiscovering: false,
            targetCount: 2
        ) == false)

        #expect(schedule.shouldRefresh(
            now: lastRefresh.addingTimeInterval(120),
            lastRefreshStartedAt: lastRefresh,
            isDiscovering: false,
            targetCount: 2
        ))
    }

    @Test("Auto discovery skips while a discovery pass is already running")
    func skipsWhileDiscovering() {
        let schedule = LocalProviderAutoDiscoverySchedule(refreshInterval: 120)

        #expect(schedule.shouldRefresh(
            now: Date(timeIntervalSince1970: 1_800_000_500),
            lastRefreshStartedAt: Date(timeIntervalSince1970: 1_800_000_000),
            isDiscovering: true,
            targetCount: 2
        ) == false)
    }

    @Test("Auto discovery skips when no local targets are available")
    func skipsWithoutTargets() {
        let schedule = LocalProviderAutoDiscoverySchedule(refreshInterval: 120)

        #expect(schedule.shouldRefresh(
            now: Date(timeIntervalSince1970: 1_800_000_500),
            lastRefreshStartedAt: nil,
            isDiscovering: false,
            targetCount: 0
        ) == false)
    }
}
