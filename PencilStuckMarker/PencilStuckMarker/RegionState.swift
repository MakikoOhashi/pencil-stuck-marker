//
//  RegionState.swift
//  PencilStuckMarker
//

import CoreGraphics
import Foundation

enum InterventionPhase {
    case idle
    case pending
    case bubbleExpanded
    case coachOpen
}

enum CoachSpeaker: Equatable {
    case user
    case coach
}

struct CoachMessage: Identifiable {
    let id = UUID()
    let speaker: CoachSpeaker
    let text: String
}

struct RegionState {
    let regionId: String
    let rect: CGRect

    var lastStrokeAt: Date? = nil
    var lastStrokePoint: CGPoint? = nil
    var elapsedSeconds: Int = 0
    var oscillationCount: Int = 0    // write/erase cycles — tracked in future step
    var isInterventionPending: Bool = false
    var isInterventionConfirmed: Bool = false
    var interventionMessage: String? = nil
    var interventionStyle: String? = nil
    var interventionAnchor: CGPoint? = nil
    var bubbleExpiresAt: Date? = nil
    var cooldownUntil: Date? = nil
    var isBubbleExpanded: Bool = false
    var interventionLevel: Int = 0
    var shouldAutoOpenCoach: Bool = false
    var phase: InterventionPhase = .idle
    var activeRequestId: UUID? = nil
    var isCoachPanelVisible: Bool = false
    var coachOffset: CGSize = .zero
    var coachInput: String = ""
    var coachLine: String? = nil
    var coachMessages: [CoachMessage] = []
    var isCoachLoading: Bool = false
}
