//
//  RegionStateManager.swift
//  PencilStuckMarker
//

import Foundation
import CoreGraphics
import Combine

@MainActor
final class RegionStateManager: ObservableObject {

    @Published private(set) var states: [String: RegionState]
    private let messageTemplates = [
        "Looks like you paused here a bit.",
        "You might be rewriting and erasing repeatedly.",
        "Want to take another look at this area?",
        "Want to think it through out loud?",
    ]

    init(regions: [(id: String, rect: CGRect)]) {
        states = Dictionary(
            uniqueKeysWithValues: regions.map { ($0.id, RegionState(regionId: $0.id, rect: $0.rect)) }
        )
    }

    // MARK: - Single entry point for stroke events

    func updateRegionState(regionId: String, strokeBounds: CGRect, strokeEndPoint: CGPoint) {
        guard var state = states[regionId],
              state.rect.intersects(strokeBounds) else { return }
        state.lastStrokeAt = Date()
        state.lastStrokePoint = strokeEndPoint
        state.elapsedSeconds = 0
        state.isInterventionPending = false   // reset on new activity
        state.interventionMessage = nil
        state.interventionStyle = nil
        state.interventionAnchor = nil
        state.bubbleExpiresAt = nil
        state.isBubbleExpanded = false
        state.interventionLevel = 0
        states[regionId] = state
    }

    // MARK: - Timer tick (1 s)

    func onTimerTick(now: Date) {
        for regionId in states.keys {
            if let last = states[regionId]?.lastStrokeAt {
                states[regionId]?.elapsedSeconds = Int(now.timeIntervalSince(last))
            }
            if let expiresAt = states[regionId]?.bubbleExpiresAt, now >= expiresAt {
                states[regionId]?.interventionMessage = nil
                states[regionId]?.interventionStyle = nil
                states[regionId]?.interventionAnchor = nil
                states[regionId]?.bubbleExpiresAt = nil
                states[regionId]?.isBubbleExpanded = false
                states[regionId]?.interventionLevel = 0
            }
            checkAndTrigger(regionId: regionId, now: now)
        }
    }

    // MARK: - Stuck detection (pure, testable)

    func detectStuckCandidate(_ state: RegionState) -> Bool {
        guard state.lastStrokeAt != nil else { return false }
        return state.elapsedSeconds >= 10
    }

    // MARK: - Single trigger call site

    private func checkAndTrigger(regionId: String, now: Date) {
        guard let state = states[regionId],
              detectStuckCandidate(state),
              !state.isInterventionPending else { return }
        if let cooldownUntil = state.cooldownUntil, now < cooldownUntil { return }
        states[regionId]?.isInterventionPending = true
        triggerInterventionCandidate(regionId: regionId, state: state)
    }

    private func triggerInterventionCandidate(regionId: String, state: RegionState) {
        // Capture frame on MainActor before hopping to InterventionService actor
        let framePngBase64 = FrameCapture.captureBase64() ?? ""
        Task {
            let response = await InterventionService.shared.analyze(
                regionId: regionId,
                state: state,
                framePngBase64: framePngBase64
            )
            await MainActor.run {
                self.states[regionId]?.isInterventionPending = false
                guard let response, response.intervene,
                      response.target.regionId == regionId else { return }
                self.states[regionId]?.interventionStyle = response.style
                self.states[regionId]?.interventionMessage = self.messageTemplates.randomElement() ?? response.message
                self.states[regionId]?.interventionAnchor = state.lastStrokePoint ?? CGPoint(x: state.rect.midX, y: state.rect.midY)
                self.states[regionId]?.bubbleExpiresAt = Date().addingTimeInterval(12)
                self.states[regionId]?.isBubbleExpanded = false
                self.states[regionId]?.interventionLevel = 1
                self.states[regionId]?.cooldownUntil = Date().addingTimeInterval(TimeInterval(response.cooldownSeconds))
            }
        }
    }

    // MARK: - Bubble interactions

    func toggleBubble(regionId: String) {
        guard states[regionId]?.interventionMessage != nil else { return }
        states[regionId]?.isBubbleExpanded.toggle()
        states[regionId]?.bubbleExpiresAt = Date().addingTimeInterval(12)
    }

    func requestMoreHint(regionId: String) {
        guard states[regionId]?.interventionMessage != nil else { return }
        states[regionId]?.interventionStyle = "level2"
        states[regionId]?.interventionLevel = 2
        states[regionId]?.isBubbleExpanded = false
        states[regionId]?.bubbleExpiresAt = Date().addingTimeInterval(10)
    }

    func dismissIntervention(regionId: String) {
        states[regionId]?.interventionMessage = nil
        states[regionId]?.interventionStyle = nil
        states[regionId]?.interventionAnchor = nil
        states[regionId]?.bubbleExpiresAt = nil
        states[regionId]?.isBubbleExpanded = false
        states[regionId]?.interventionLevel = 0
        states[regionId]?.cooldownUntil = Date().addingTimeInterval(30)
    }
}
