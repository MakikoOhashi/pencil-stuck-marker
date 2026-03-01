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
    private var watchdogTasks: [String: Task<Void, Never>] = [:]
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
        let minStrokeSize: CGFloat = 2.0
        if strokeBounds.width < minStrokeSize && strokeBounds.height < minStrokeSize {
            // Ignore tiny tap-like artifacts so text-field taps do not reset intervention UI.
            return
        }
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
        state.shouldAutoOpenCoach = false
        state.phase = .idle
        state.activeRequestId = nil
        state.isCoachPanelVisible = false
        state.coachOffset = .zero
        state.coachInput = ""
        state.coachLine = nil
        state.coachMessages = []
        state.isCoachLoading = false
        states[regionId] = state
        cancelWatchdog(for: regionId)
    }

    // MARK: - Timer tick (1 s)

    func onTimerTick(now: Date) {
        for regionId in states.keys {
            if let last = states[regionId]?.lastStrokeAt {
                states[regionId]?.elapsedSeconds = Int(now.timeIntervalSince(last))
            }
            if let expiresAt = states[regionId]?.bubbleExpiresAt,
               now >= expiresAt,
               states[regionId]?.isCoachPanelVisible != true,
               states[regionId]?.isInterventionPending != true,
               states[regionId]?.isBubbleExpanded != true {
                states[regionId]?.interventionMessage = nil
                states[regionId]?.interventionStyle = nil
                states[regionId]?.interventionAnchor = nil
                states[regionId]?.isInterventionPending = false
                states[regionId]?.isInterventionConfirmed = false
                states[regionId]?.bubbleExpiresAt = nil
                states[regionId]?.isBubbleExpanded = false
                states[regionId]?.interventionLevel = 0
                states[regionId]?.shouldAutoOpenCoach = false
                states[regionId]?.phase = .idle
                states[regionId]?.activeRequestId = nil
                states[regionId]?.isCoachPanelVisible = false
                states[regionId]?.coachOffset = .zero
                states[regionId]?.coachInput = ""
                states[regionId]?.coachLine = nil
                states[regionId]?.coachMessages = []
                states[regionId]?.isCoachLoading = false
                cancelWatchdog(for: regionId)
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
        if state.phase == .bubbleExpanded || state.phase == .coachOpen { return }
        // Do not retrigger while an intervention is already visible.
        if state.interventionMessage != nil || state.isCoachPanelVisible { return }
        if let cooldownUntil = state.cooldownUntil, now < cooldownUntil { return }
        let requestId = UUID()
        states[regionId]?.isInterventionPending = true
        states[regionId]?.isInterventionConfirmed = false
        states[regionId]?.interventionMessage = pendingMessage
        states[regionId]?.interventionAnchor = state.lastStrokePoint ?? CGPoint(x: state.rect.midX, y: state.rect.midY)
        states[regionId]?.bubbleExpiresAt = Date().addingTimeInterval(6)
        states[regionId]?.isBubbleExpanded = false
        states[regionId]?.shouldAutoOpenCoach = false
        states[regionId]?.phase = .pending
        states[regionId]?.activeRequestId = requestId
        triggerInterventionCandidate(regionId: regionId, state: state, requestId: requestId)
    }

    private func triggerInterventionCandidate(regionId: String, state: RegionState, requestId: UUID) {
        // Capture frame on MainActor before hopping to InterventionService actor
        let framePngBase64 = FrameCapture.captureBase64() ?? ""
        cancelWatchdog(for: regionId)
        watchdogTasks[regionId] = Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            await MainActor.run {
                guard self.states[regionId]?.activeRequestId == requestId,
                      self.states[regionId]?.isInterventionPending == true else { return }
                let wasExpanded = self.states[regionId]?.isBubbleExpanded == true
                let wasCoachVisible = self.states[regionId]?.isCoachPanelVisible == true
                self.states[regionId]?.isInterventionPending = false
                self.states[regionId]?.isInterventionConfirmed = true
                self.states[regionId]?.interventionStyle = "watchdog"
                self.states[regionId]?.interventionMessage = self.messageTemplates.first ?? "Looks like you paused here a bit."
                self.states[regionId]?.bubbleExpiresAt = Date().addingTimeInterval(12)
                self.states[regionId]?.isBubbleExpanded = wasExpanded || wasCoachVisible
                self.states[regionId]?.interventionLevel = 0
                self.states[regionId]?.cooldownUntil = Date().addingTimeInterval(30)
                self.states[regionId]?.phase = wasCoachVisible ? .coachOpen : ((wasExpanded || self.states[regionId]?.shouldAutoOpenCoach == true) ? .bubbleExpanded : .idle)
                self.states[regionId]?.activeRequestId = nil
                if self.states[regionId]?.shouldAutoOpenCoach == true {
                    self.states[regionId]?.shouldAutoOpenCoach = false
                    self.openCoachPanelUnlocked(regionId: regionId)
                }
                self.cancelWatchdog(for: regionId)
            }
        }
        Task {
            let response = await InterventionService.shared.analyze(
                regionId: regionId,
                requestId: requestId,
                state: state,
                framePngBase64: framePngBase64
            )
            await MainActor.run {
                guard self.states[regionId]?.activeRequestId == requestId else { return }
                if let responseRequestId = response?.requestId,
                   UUID(uuidString: responseRequestId) != requestId {
                    return
                }
                self.cancelWatchdog(for: regionId)
                self.states[regionId]?.isInterventionPending = false
                guard let response,
                      response.target.regionId == regionId else {
                    // Network/API failure fallback: keep UX responsive with local confirm.
                    self.states[regionId]?.isInterventionConfirmed = true
                    self.states[regionId]?.interventionStyle = "fallback"
                    self.states[regionId]?.interventionMessage = self.messageTemplates.first ?? "Need a quick hint?"
                    self.states[regionId]?.bubbleExpiresAt = Date().addingTimeInterval(12)
                    self.states[regionId]?.isBubbleExpanded = false
                    self.states[regionId]?.interventionLevel = 0
                    self.states[regionId]?.cooldownUntil = Date().addingTimeInterval(30)
                    self.states[regionId]?.phase = .idle
                    self.states[regionId]?.activeRequestId = nil
                    return
                }
                if response.intervene {
                    let shouldAutoOpen = self.states[regionId]?.shouldAutoOpenCoach == true
                    let wasExpanded = self.states[regionId]?.isBubbleExpanded == true
                    let wasCoachVisible = self.states[regionId]?.isCoachPanelVisible == true
                    self.states[regionId]?.isInterventionConfirmed = true
                    if !wasExpanded && !wasCoachVisible {
                        self.states[regionId]?.interventionStyle = response.style
                        self.states[regionId]?.interventionMessage = self.messageTemplates.randomElement() ?? response.message
                        self.states[regionId]?.interventionAnchor = state.lastStrokePoint ?? CGPoint(x: state.rect.midX, y: state.rect.midY)
                    }
                    self.states[regionId]?.bubbleExpiresAt = Date().addingTimeInterval(12)
                    self.states[regionId]?.isBubbleExpanded = wasExpanded || wasCoachVisible || shouldAutoOpen
                    self.states[regionId]?.interventionLevel = 1
                    self.states[regionId]?.cooldownUntil = Date().addingTimeInterval(TimeInterval(response.cooldownSeconds))
                    if !wasCoachVisible {
                        self.states[regionId]?.coachOffset = .zero
                        self.states[regionId]?.coachLine = nil
                        self.states[regionId]?.coachMessages = []
                    }
                    self.states[regionId]?.shouldAutoOpenCoach = false
                    if shouldAutoOpen {
                        self.openCoachPanelUnlocked(regionId: regionId)
                    } else {
                        self.states[regionId]?.phase = wasCoachVisible ? .coachOpen : (self.states[regionId]?.isBubbleExpanded == true ? .bubbleExpanded : .idle)
                    }
                    self.states[regionId]?.activeRequestId = nil
                } else {
                    // Negative verification should not close or rewrite an already-open UI.
                    let isUserInteracting =
                        self.states[regionId]?.phase == .bubbleExpanded ||
                        self.states[regionId]?.phase == .coachOpen ||
                        self.states[regionId]?.isBubbleExpanded == true ||
                        self.states[regionId]?.isCoachPanelVisible == true
                    if !isUserInteracting {
                        self.states[regionId]?.isInterventionConfirmed = false
                        self.states[regionId]?.interventionMessage = nil
                        self.states[regionId]?.interventionStyle = nil
                        self.states[regionId]?.interventionAnchor = nil
                        self.states[regionId]?.bubbleExpiresAt = nil
                        self.states[regionId]?.isBubbleExpanded = false
                        self.states[regionId]?.interventionLevel = 0
                        self.states[regionId]?.shouldAutoOpenCoach = false
                        self.states[regionId]?.isCoachPanelVisible = false
                        self.states[regionId]?.coachInput = ""
                        self.states[regionId]?.coachLine = nil
                        self.states[regionId]?.coachMessages = []
                        self.states[regionId]?.isCoachLoading = false
                        self.states[regionId]?.phase = .idle
                    }
                    self.states[regionId]?.cooldownUntil = Date().addingTimeInterval(TimeInterval(response.cooldownSeconds))
                    self.states[regionId]?.activeRequestId = nil
                }
            }
        }
    }

    private func cancelWatchdog(for regionId: String) {
        watchdogTasks[regionId]?.cancel()
        watchdogTasks[regionId] = nil
    }

    // MARK: - Bubble interactions

    func toggleBubble(regionId: String) {
        guard states[regionId]?.interventionMessage != nil else { return }
        states[regionId]?.isBubbleExpanded.toggle()
        states[regionId]?.bubbleExpiresAt = Date().addingTimeInterval(states[regionId]?.isBubbleExpanded == true ? 180 : 12)
        if states[regionId]?.isCoachPanelVisible == true {
            states[regionId]?.phase = .coachOpen
        } else if states[regionId]?.isBubbleExpanded == true {
            states[regionId]?.phase = .bubbleExpanded
        } else {
            states[regionId]?.phase = states[regionId]?.isInterventionPending == true ? .pending : .idle
        }
    }

    private func openCoachPanelUnlocked(regionId: String) {
        for key in states.keys {
            states[key]?.isCoachPanelVisible = (key == regionId)
            if key != regionId, states[key]?.phase == .coachOpen {
                states[key]?.phase = states[key]?.isBubbleExpanded == true ? .bubbleExpanded : .idle
            }
        }
        states[regionId]?.isBubbleExpanded = true
        states[regionId]?.bubbleExpiresAt = Date().addingTimeInterval(180)
        states[regionId]?.phase = .coachOpen
        if states[regionId]?.coachLine == nil {
            let starter = "Try reading it out loud once."
            states[regionId]?.coachLine = starter
            states[regionId]?.coachMessages = [
                CoachMessage(speaker: .coach, text: starter)
            ]
        }
    }

    func openCoachPanel(regionId: String) {
        guard states[regionId]?.isInterventionConfirmed == true else { return }
        openCoachPanelUnlocked(regionId: regionId)
    }

    func toggleCoachPanel(regionId: String) {
        if states[regionId]?.isCoachPanelVisible == true {
            closeCoachPanel(regionId: regionId)
        } else {
            // Open immediately and stop in-flight pending transition from overriding user intent.
            states[regionId]?.shouldAutoOpenCoach = false
            states[regionId]?.isInterventionPending = false
            states[regionId]?.activeRequestId = nil
            cancelWatchdog(for: regionId)
            openCoachPanelUnlocked(regionId: regionId)
        }
    }

    func closeCoachPanel(regionId: String) {
        states[regionId]?.isCoachPanelVisible = false
        states[regionId]?.bubbleExpiresAt = Date().addingTimeInterval(12)
        states[regionId]?.phase = states[regionId]?.isBubbleExpanded == true ? .bubbleExpanded : (states[regionId]?.isInterventionPending == true ? .pending : .idle)
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

        if isResolvedMessage(trimmed) {
            let closingLine = "Great! Keep going with the problem."
            states[regionId]?.coachInput = ""
            states[regionId]?.coachMessages.append(
                CoachMessage(speaker: .user, text: trimmed)
            )
            states[regionId]?.coachLine = closingLine
            states[regionId]?.coachMessages.append(
                CoachMessage(speaker: .coach, text: closingLine)
            )
            states[regionId]?.bubbleExpiresAt = Date().addingTimeInterval(2)

            Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await MainActor.run {
                    self.dismissIntervention(regionId: regionId)
                }
            }
            return
        }

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

    private func isResolvedMessage(_ text: String) -> Bool {
        let t = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = t.replacingOccurrences(of: #"[^a-z0-9\s]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = [
            "i understood", "understood", "got it", "i got it",
            "i understand", "makes sense", "solved", "all good",
            "わかった", "分かった", "理解した", "ok", "okay"
        ]
        return tokens.contains { normalized.contains($0) || t.contains($0) }
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
        states[regionId]?.shouldAutoOpenCoach = false
        states[regionId]?.phase = .idle
        states[regionId]?.activeRequestId = nil
        states[regionId]?.isCoachPanelVisible = false
        states[regionId]?.coachOffset = .zero
        states[regionId]?.coachInput = ""
        states[regionId]?.coachLine = nil
        states[regionId]?.coachMessages = []
        states[regionId]?.isCoachLoading = false
        states[regionId]?.cooldownUntil = Date().addingTimeInterval(30)
        cancelWatchdog(for: regionId)
    }
}
