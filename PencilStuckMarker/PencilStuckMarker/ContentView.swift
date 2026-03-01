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
    @FocusState private var isCoachInputFocused: Bool
    private let worksheetURL = Bundle.main.url(forResource: "cube_worksheet", withExtension: "pdf")
    @StateObject private var regionManager = RegionStateManager(regions: [
        (id: "ALL", rect: CGRect(x: -10_000, y: -10_000, width: 20_000, height: 20_000)),
    ])

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                let isInterventionUIActive = regionManager.states.values.contains {
                    $0.isCoachPanelVisible || $0.isBubbleExpanded || $0.isInterventionPending
                }

                PDFBackgroundView(url: worksheetURL)
                    .ignoresSafeArea()

                CanvasView(drawing: $drawing, allowsFingerDrawing: !isInterventionUIActive) { strokeBounds, strokeEndPoint in
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
                    let interventionActive = state.interventionMessage != nil
                    let confirmedActive = interventionActive && state.isInterventionConfirmed
                    let pendingActive = state.isInterventionPending && !state.isInterventionConfirmed
                    let anchor = state.interventionAnchor ?? state.lastStrokePoint ?? CGPoint(x: proxy.size.width * 0.5, y: proxy.size.height * 0.35)
                    let bubbleX = min(max(anchor.x, 110), proxy.size.width - 110)
                    let panelLift: CGFloat = state.isCoachPanelVisible ? 148 : (state.isBubbleExpanded ? 94 : 70)
                    let bubbleY = min(max(anchor.y - panelLift, 54), proxy.size.height - 40)
                    let boxXBase = bubbleX + (state.isCoachPanelVisible ? (state.coachOffset.width + coachDragTranslation.width) : 0)
                    let boxYBase = bubbleY + (state.isCoachPanelVisible ? (state.coachOffset.height + coachDragTranslation.height) : 0)
                    let boxX = min(max(boxXBase, state.isCoachPanelVisible ? 158 : 110), proxy.size.width - (state.isCoachPanelVisible ? 158 : 110))
                    let boxY = min(max(boxYBase, 86), proxy.size.height - 60)

                    if pendingActive || confirmedActive {
                        Circle()
                            .stroke(Color.gray.opacity(0.55), lineWidth: 1.6)
                            .frame(width: 42, height: 42)
                            .position(anchor)
                            .transition(.opacity)
                    }

                    if let message = state.interventionMessage {
                        VStack(alignment: .leading, spacing: 8) {
                            if !state.isCoachPanelVisible {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("💭 \(message)")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text("Need a hint?")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation(.spring(duration: 0.25)) {
                                        regionManager.toggleBubble(regionId: state.regionId)
                                    }
                                }
                            }

                            if state.isCoachPanelVisible {
                                HStack {
                                    Spacer()
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            regionManager.closeCoachPanel(regionId: state.regionId)
                                        }
                                        isCoachInputFocused = false
                                        coachDragTranslation = .zero
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.caption2.weight(.bold))
                                            .foregroundStyle(.secondary)
                                            .padding(6)
                                            .background(Color.white.opacity(0.75))
                                            .clipShape(Circle())
                                    }
                                    .buttonStyle(.plain)
                                }

                                ScrollView {
                                    VStack(alignment: .leading, spacing: 8) {
                                        ForEach(state.coachMessages) { coachMessage in
                                            if coachMessage.speaker == .coach {
                                                Text("Coach: \(coachMessage.text)")
                                                    .font(.caption)
                                                    .foregroundStyle(Color.black)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                            } else {
                                                Text("You: \(coachMessage.text)")
                                                    .font(.caption)
                                                    .foregroundStyle(Color.black.opacity(0.82))
                                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                            }
                                        }
                                    }
                                }
                                .frame(maxHeight: 84)

                                HStack(spacing: 8) {
                                    TextField("One short line…", text: Binding(
                                        get: { state.coachInput },
                                        set: { regionManager.updateCoachInput(regionId: state.regionId, text: $0) }
                                    ))
                                    .focused($isCoachInputFocused)
                                    .font(.subheadline)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(Color.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))

                                    Button(state.isCoachLoading ? "..." : "Send") {
                                        isCoachInputFocused = false
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
                            } else if state.isBubbleExpanded {
                                HStack(spacing: 8) {
                                    Button(state.isInterventionConfirmed ? "Talk with coach" : "Talk with coach") {
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

                                if state.isInterventionConfirmed {
                                    Button {
                                        showVoicePlannedAlert = true
                                    } label: {
                                        Label("Voice mode (planned)", systemImage: "mic.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    Text("Checking... opening coach when ready")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(width: state.isCoachPanelVisible ? 300 : nil)
                        .background(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.gray.opacity(0.55), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .zIndex(1)
                        .position(x: boxX, y: boxY)
                        .simultaneousGesture(
                            DragGesture(minimumDistance: 3)
                                .onChanged { value in
                                    guard state.isCoachPanelVisible else { return }
                                    coachDragTranslation = value.translation
                                }
                                .onEnded { value in
                                    guard state.isCoachPanelVisible else { return }
                                    regionManager.moveCoachPanel(regionId: state.regionId, delta: value.translation)
                                    coachDragTranslation = .zero
                                }
                        )
                        .animation(.easeInOut(duration: 0.22), value: state.isCoachPanelVisible)
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
}

#Preview {
    ContentView()
}
