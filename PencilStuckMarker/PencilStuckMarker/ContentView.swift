//
//  ContentView.swift
//  PencilStuckMarker
//

import SwiftUI
import PencilKit
import Combine

struct ContentView: View {
    @State private var drawing = PKDrawing()
    @StateObject private var regionManager = RegionStateManager(regions: [
        (id: "A", rect: CGRect(x: 40, y: 120, width: 440, height: 260)),
        (id: "B", rect: CGRect(x: 40, y: 440, width: 440, height: 260)),
    ])

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .topLeading) {
            CanvasView(drawing: $drawing) { strokeBounds in
                for regionId in regionManager.states.keys {
                    regionManager.updateRegionState(regionId: regionId, strokeBounds: strokeBounds)
                }
            }
            .ignoresSafeArea()

            ForEach(
                regionManager.states.values.sorted(by: { $0.regionId < $1.regionId }),
                id: \.regionId
            ) { state in
                let stuck = regionManager.detectStuckCandidate(state)

                ZStack(alignment: .topTrailing) {
                    Rectangle()
                        .strokeBorder(
                            stuck ? Color.yellow : Color.gray.opacity(0.5),
                            lineWidth: 2
                        )
                        .background(stuck ? Color.yellow.opacity(0.15) : Color.clear)

                    Text(state.lastStrokeAt == nil ? "--" : "\(state.elapsedSeconds)s")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(6)
                }
                .frame(width: state.rect.width, height: state.rect.height)
                .position(x: state.rect.midX, y: state.rect.midY)
            }
        }
        .onReceive(timer) { now in
            regionManager.onTimerTick(now: now)
        }
    }
}

#Preview {
    ContentView()
}
