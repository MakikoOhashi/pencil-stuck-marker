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

    init(regions: [(id: String, rect: CGRect)]) {
        states = Dictionary(
            uniqueKeysWithValues: regions.map { ($0.id, RegionState(regionId: $0.id, rect: $0.rect)) }
        )
    }

    // MARK: - Single entry point for stroke events

    func updateRegionState(regionId: String, strokeBounds: CGRect) {
        guard var state = states[regionId],
              state.rect.intersects(strokeBounds) else { return }
        state.lastStrokeAt = Date()
        state.elapsedSeconds = 0
        state.isInterventionPending = false   // reset on new activity
        states[regionId] = state
    }

    // MARK: - Timer tick (1 s)

    func onTimerTick(now: Date) {
        for regionId in states.keys {
            if let last = states[regionId]?.lastStrokeAt {
                states[regionId]?.elapsedSeconds = Int(now.timeIntervalSince(last))
            }
            checkAndTrigger(regionId: regionId)
        }
    }

    // MARK: - Stuck detection (pure, testable)

    func detectStuckCandidate(_ state: RegionState) -> Bool {
        guard state.lastStrokeAt != nil else { return false }
        return state.elapsedSeconds >= 10
    }

    // MARK: - Single trigger call site

    private func checkAndTrigger(regionId: String) {
        guard let state = states[regionId],
              detectStuckCandidate(state),
              !state.isInterventionPending else { return }
        states[regionId]?.isInterventionPending = true
        triggerInterventionCandidate(regionId: regionId, state: state)
    }

    private func triggerInterventionCandidate(regionId: String, state: RegionState) {
        // Capture frame on MainActor before hopping to InterventionService actor
        let framePngBase64 = FrameCapture.captureBase64() ?? ""
        Task {
            await InterventionService.shared.analyze(
                regionId: regionId,
                state: state,
                framePngBase64: framePngBase64
            )
        }
    }
}
