//
//  ContentView.swift
//  PencilStuckMarker
//

import SwiftUI
import PencilKit
import Combine

struct ContentView: View {
    @State private var drawing = PKDrawing()
    @State private var showVoicePlannedAlert = false
    @StateObject private var regionManager = RegionStateManager(regions: [
        (id: "ALL", rect: CGRect(x: -10_000, y: -10_000, width: 20_000, height: 20_000)),
    ])

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                CanvasView(drawing: $drawing) { strokeBounds, strokeEndPoint in
                    for regionId in regionManager.states.keys {
                        regionManager.updateRegionState(
                            regionId: regionId,
                            strokeBounds: strokeBounds,
                            strokeEndPoint: strokeEndPoint
                        )
                    }
                }
                .ignoresSafeArea()

                ForEach(Array(regionManager.states.values), id: \.regionId) { state in
                    let stuck = regionManager.detectStuckCandidate(state)
                    let interventionActive = state.interventionMessage != nil
                    let level2Active = state.interventionLevel >= 2 || state.interventionStyle == "level2"
                    let anchor = state.interventionAnchor ?? state.lastStrokePoint ?? CGPoint(x: proxy.size.width * 0.5, y: proxy.size.height * 0.35)
                    let bubbleX = min(max(anchor.x, 110), proxy.size.width - 110)
                    let bubbleY = min(max(anchor.y - (state.isBubbleExpanded ? 94 : 70), 54), proxy.size.height - 40)

                    if stuck || interventionActive {
                        Circle()
                            .fill(level2Active ? Color.orange.opacity(0.24) : Color.yellow.opacity(0.2))
                            .frame(width: level2Active ? 230 : 170, height: level2Active ? 230 : 170)
                            .blur(radius: level2Active ? 12 : 16)
                            .position(anchor)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }

                    if level2Active {
                        Image(systemName: "arrowtriangle.down.fill")
                            .foregroundStyle(Color.orange)
                            .font(.title3)
                            .position(x: anchor.x, y: max(16, anchor.y - 78))
                            .transition(.opacity.combined(with: .scale))
                    }

                    if let message = state.interventionMessage {
                        VStack(alignment: .leading, spacing: 8) {
                            Button {
                                withAnimation(.spring(duration: 0.25)) {
                                    regionManager.toggleBubble(regionId: state.regionId)
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("💭 \(message)")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text("Need a hint?")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)

                            if state.isBubbleExpanded {
                                HStack(spacing: 8) {
                                    Button("More hint") {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            regionManager.requestMoreHint(regionId: state.regionId)
                                        }
                                    }
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(Color.orange.opacity(0.2))
                                    .clipShape(Capsule())

                                    Button("I'm okay for now") {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            regionManager.dismissIntervention(regionId: state.regionId)
                                        }
                                    }
                                    .font(.caption2)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(Color.gray.opacity(0.18))
                                    .clipShape(Capsule())
                                }

                                Button {
                                    showVoicePlannedAlert = true
                                } label: {
                                    Label("Voice mode (planned)", systemImage: "mic.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(level2Active ? Color.orange.opacity(0.85) : Color.yellow.opacity(0.8), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .position(x: bubbleX, y: bubbleY)
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    }
                }
            }
        }
        .onReceive(timer) { now in
            regionManager.onTimerTick(now: now)
        }
        .alert("Voice mode is planned for a future update.", isPresented: $showVoicePlannedAlert) {
            Button("OK", role: .cancel) {}
        }
    }
}

#Preview {
    ContentView()
}
