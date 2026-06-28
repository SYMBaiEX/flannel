//
//  Item.swift
//  flannel
//
//  Created by SYMBiEX on 6/28/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
