//
//  flannelTests.swift
//  flannelTests
//
//  Created by SYMBiEX on 6/28/26.
//

import Foundation
import Testing
@testable import flannel

struct flannelTests {

    @Test("Item preserves the timestamp it is initialized with")
    func itemPreservesProvidedTimestamp() {
        let timestamp = Date(timeIntervalSince1970: 1_719_632_400)
        let item = Item(timestamp: timestamp)

        #expect(item.timestamp == timestamp)
    }
}
