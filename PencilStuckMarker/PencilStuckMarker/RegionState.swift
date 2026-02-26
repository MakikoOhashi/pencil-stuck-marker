//
//  RegionState.swift
//  PencilStuckMarker
//

import CoreGraphics
import Foundation

struct RegionState {
    let regionId: String
    let rect: CGRect

    var lastStrokeAt: Date? = nil
    var elapsedSeconds: Int = 0
    var oscillationCount: Int = 0    // write/erase cycles — tracked in future step
    var isInterventionPending: Bool = false
    var interventionMessage: String? = nil
    var interventionStyle: String? = nil
    var bubbleExpiresAt: Date? = nil
    var cooldownUntil: Date? = nil
}
