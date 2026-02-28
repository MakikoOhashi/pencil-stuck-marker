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
    private let pendingMessage = "Looks like you paused here."
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
        state.isInterventionConfirmed = false
        state.interventionMessage = nil
        state.interventionStyle = nil
        state.interventionAnchor = nil
        state.bubbleExpiresAt = nil
        state.isBubbleExpanded = false
        state.interventionLevel = 0
        state.isCoachPanelVisible = false
        state.coachOffset = .zero
        state.coachInput = ""
        state.coachLine = nil
        state.coachMessages = []
        state.isCoachLoading = false
        states[regionId] = state
    }

    // MARK: - Timer tick (1 s)

    func onTimerTick(now: Date) {
        for regionId in states.keys {
            if let last = states[regionId]?.lastStrokeAt {
                states[regionId]?.elapsedSeconds = Int(now.timeIntervalSince(last))
            }
            if let expiresAt = states[regionId]?.bubbleExpiresAt,
               now >= expiresAt,
               states[regionId]?.isCoachPanelVisible != true {
                states[regionId]?.interventionMessage = nil
                states[regionId]?.interventionStyle = nil
                states[regionId]?.interventionAnchor = nil
                states[regionId]?.isInterventionPending = false
                states[regionId]?.isInterventionConfirmed = false
                states[regionId]?.bubbleExpiresAt = nil
                states[regionId]?.isBubbleExpanded = false
                states[regionId]?.interventionLevel = 0
                states[regionId]?.isCoachPanelVisible = false
                states[regionId]?.coachOffset = .zero
                states[regionId]?.coachInput = ""
                states[regionId]?.coachLine = nil
                states[regionId]?.coachMessages = []
                states[regionId]?.isCoachLoading = false
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
        states[regionId]?.isInterventionConfirmed = false
        states[regionId]?.interventionMessage = pendingMessage
        states[regionId]?.interventionAnchor = state.lastStrokePoint ?? CGPoint(x: state.rect.midX, y: state.rect.midY)
        states[regionId]?.bubbleExpiresAt = Date().addingTimeInterval(6)
        states[regionId]?.isBubbleExpanded = false
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
                guard let response,
                      response.target.regionId == regionId else {
                    self.clearPendingIntervention(regionId: regionId, cooldownSeconds: 10)
                    return
                }
                if response.intervene {
                    self.states[regionId]?.isInterventionConfirmed = true
                    self.states[regionId]?.interventionStyle = response.style
                    self.states[regionId]?.interventionMessage = self.messageTemplates.randomElement() ?? response.message
                    self.states[regionId]?.interventionAnchor = state.lastStrokePoint ?? CGPoint(x: state.rect.midX, y: state.rect.midY)
                    self.states[regionId]?.bubbleExpiresAt = Date().addingTimeInterval(12)
                    self.states[regionId]?.isBubbleExpanded = false
                    self.states[regionId]?.interventionLevel = 1
                    self.states[regionId]?.cooldownUntil = Date().addingTimeInterval(TimeInterval(response.cooldownSeconds))
                    self.states[regionId]?.coachOffset = .zero
                    self.states[regionId]?.coachLine = nil
                    self.states[regionId]?.coachMessages = []
                } else {
                    self.clearPendingIntervention(regionId: regionId, cooldownSeconds: response.cooldownSeconds)
                }
            }
        }
    }

    private func clearPendingIntervention(regionId: String, cooldownSeconds: Int) {
        states[regionId]?.isInterventionConfirmed = false
        states[regionId]?.interventionMessage = nil
        states[regionId]?.interventionStyle = nil
        states[regionId]?.interventionAnchor = nil
        states[regionId]?.bubbleExpiresAt = nil
        states[regionId]?.isBubbleExpanded = false
        states[regionId]?.interventionLevel = 0
        states[regionId]?.isCoachPanelVisible = false
        states[regionId]?.coachInput = ""
        states[regionId]?.coachLine = nil
        states[regionId]?.coachMessages = []
        states[regionId]?.isCoachLoading = false
        states[regionId]?.cooldownUntil = Date().addingTimeInterval(TimeInterval(cooldownSeconds))
    }

    // MARK: - Bubble interactions

    func toggleBubble(regionId: String) {
        guard states[regionId]?.interventionMessage != nil else { return }
        states[regionId]?.isBubbleExpanded.toggle()
        states[regionId]?.bubbleExpiresAt = Date().addingTimeInterval(12)
    }

    func openCoachPanel(regionId: String) {
        for key in states.keys {
            states[key]?.isCoachPanelVisible = (key == regionId)
        }
        states[regionId]?.isBubbleExpanded = true
        states[regionId]?.bubbleExpiresAt = Date().addingTimeInterval(180)
        if states[regionId]?.coachLine == nil {
            let starter = "Try reading it out loud once."
            states[regionId]?.coachLine = starter
            states[regionId]?.coachMessages = [
                CoachMessage(speaker: .coach, text: starter)
            ]
        }
    }

    func toggleCoachPanel(regionId: String) {
        if states[regionId]?.isCoachPanelVisible == true {
            closeCoachPanel(regionId: regionId)
        } else {
            openCoachPanel(regionId: regionId)
        }
    }

    func closeCoachPanel(regionId: String) {
        states[regionId]?.isCoachPanelVisible = false
        states[regionId]?.bubbleExpiresAt = Date().addingTimeInterval(12)
    }

    func moveCoachPanel(regionId: String, delta: CGSize) {
        let current = states[regionId]?.coachOffset ?? .zero
        states[regionId]?.coachOffset = CGSize(
            width: current.width + delta.width,
            height: current.height + delta.height
        )
    }

    func updateCoachInput(regionId: String, text: String) {
        states[regionId]?.coachInput = text
    }

    func sendCoachMessage(regionId: String) {
        guard var state = states[regionId], !state.isCoachLoading else { return }
        let trimmed = state.coachInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        state.isCoachLoading = true
        states[regionId] = state
        Task {
            let response = await InterventionService.shared.coach(regionId: regionId, state: state, userText: trimmed)
            await MainActor.run {
                self.states[regionId]?.isCoachLoading = false
                self.states[regionId]?.coachInput = ""
                self.states[regionId]?.coachMessages.append(
                    CoachMessage(speaker: .user, text: trimmed)
                )
                if let response {
                    self.states[regionId]?.coachLine = response.nextAction
                    self.states[regionId]?.coachMessages.append(
                        CoachMessage(speaker: .coach, text: response.nextAction)
                    )
                } else {
                    let fallback = "Try saying the goal in your own words."
                    self.states[regionId]?.coachLine = fallback
                    self.states[regionId]?.coachMessages.append(
                        CoachMessage(speaker: .coach, text: fallback)
                    )
                }
                self.states[regionId]?.bubbleExpiresAt = Date().addingTimeInterval(180)
            }
        }
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
        states[regionId]?.isInterventionPending = false
        states[regionId]?.isInterventionConfirmed = false
        states[regionId]?.bubbleExpiresAt = nil
        states[regionId]?.isBubbleExpanded = false
        states[regionId]?.interventionLevel = 0
        states[regionId]?.isCoachPanelVisible = false
        states[regionId]?.coachOffset = .zero
        states[regionId]?.coachInput = ""
        states[regionId]?.coachLine = nil
        states[regionId]?.coachMessages = []
        states[regionId]?.isCoachLoading = false
        states[regionId]?.cooldownUntil = Date().addingTimeInterval(30)
    }
}
