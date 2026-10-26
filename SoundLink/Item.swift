//
//  Item.swift
//  SoundLink
//
//  Created by Chris W on 10/26/26.
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
