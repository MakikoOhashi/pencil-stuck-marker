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
    @State private var coachDragTranslation: CGSize = .zero
    private let worksheetURL = Bundle.main.url(forResource: "cube_worksheet", withExtension: "pdf")
    @StateObject private var regionManager = RegionStateManager(regions: [
        (id: "ALL", rect: CGRect(x: -10_000, y: -10_000, width: 20_000, height: 20_000)),
    ])

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                PDFBackgroundView(url: worksheetURL)
                    .ignoresSafeArea()

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
                    let panelLift: CGFloat = state.isCoachPanelVisible ? 148 : (state.isBubbleExpanded ? 94 : 70)
                    let bubbleY = min(max(anchor.y - panelLift, 54), proxy.size.height - 40)
                    let coachXBase = bubbleX + state.coachOffset.width + coachDragTranslation.width
                    let coachYBase = bubbleY + 8 + state.coachOffset.height + coachDragTranslation.height
                    let coachX = min(max(coachXBase, 158), proxy.size.width - 158)
                    let coachY = min(max(coachYBase, 86), proxy.size.height - 86)

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

                    if let message = state.interventionMessage, !state.isCoachPanelVisible {
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
                                    Button(state.isCoachPanelVisible ? "Close coach" : "Talk with coach") {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            regionManager.toggleCoachPanel(regionId: state.regionId)
                                        }
                                    }
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(Color.orange.opacity(0.2))
                                    .clipShape(Capsule())

                                    Button("I'm okay") {
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

                    if state.isCoachPanelVisible {
                        Color.clear
                            .contentShape(Rectangle())
                            .ignoresSafeArea()
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    regionManager.closeCoachPanel(regionId: state.regionId)
                                }
                                coachDragTranslation = .zero
                            }

                        coachOverlay(for: state)
                            .position(x: coachX, y: coachY)
                            .gesture(
                                DragGesture(minimumDistance: 3)
                                    .onChanged { value in
                                        coachDragTranslation = value.translation
                                    }
                                    .onEnded { value in
                                        regionManager.moveCoachPanel(regionId: state.regionId, delta: value.translation)
                                        coachDragTranslation = .zero
                                    }
                            )
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
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

    @ViewBuilder
    private func coachOverlay(for state: RegionState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(state.coachMessages) { message in
                        if message.speaker == .coach {
                            Text("Coach: \(message.text)")
                                .font(.caption)
                                .foregroundStyle(Color.black)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            Text("You: \(message.text)")
                                .font(.caption)
                                .foregroundStyle(Color.black.opacity(0.82))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                }
            }
            .frame(maxHeight: 120)

            HStack(spacing: 8) {
                TextField("One short line…", text: Binding(
                    get: { state.coachInput },
                    set: { regionManager.updateCoachInput(regionId: state.regionId, text: $0) }
                ))
                .font(.subheadline)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                Button(state.isCoachLoading ? "..." : "Send") {
                    regionManager.sendCoachMessage(regionId: state.regionId)
                }
                .disabled(state.isCoachLoading || state.coachInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.orange)
                .clipShape(Capsule())
            }
        }
        .padding(14)
        .frame(width: 300)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.40)))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    ContentView()
}
