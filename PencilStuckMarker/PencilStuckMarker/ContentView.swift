//
//  ContentView.swift
//  PencilStuckMarker
//

import SwiftUI
import PencilKit
import Combine

struct ContentView: View {
    @State private var drawing = PKDrawing()
    @State private var lastStrokeAt: [Int: Date] = [:]
    @State private var elapsed: [Int: Int] = [:]

    let boxes: [CGRect] = [
        CGRect(x: 40, y: 120, width: 440, height: 260),
        CGRect(x: 40, y: 440, width: 440, height: 260),
    ]

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .topLeading) {
            CanvasView(drawing: $drawing) { strokeRect in
                for (i, box) in boxes.enumerated() {
                    if box.intersects(strokeRect) {
                        lastStrokeAt[i] = Date()
                    }
                }
            }
            .ignoresSafeArea()

            ForEach(0..<boxes.count, id: \.self) { i in
                let secs = elapsed[i, default: 0]
                let stuck = lastStrokeAt[i] != nil && secs >= 10

                ZStack(alignment: .topTrailing) {
                    Rectangle()
                        .strokeBorder(
                            stuck ? Color.yellow : Color.gray.opacity(0.5),
                            lineWidth: 2
                        )
                        .background(stuck ? Color.yellow.opacity(0.15) : Color.clear)

                    Text(lastStrokeAt[i] == nil ? "--" : "\(secs)s")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(6)
                }
                .frame(width: boxes[i].width, height: boxes[i].height)
                .position(x: boxes[i].midX, y: boxes[i].midY)
            }
        }
        .onReceive(timer) { now in
            for i in 0..<boxes.count {
                if let last = lastStrokeAt[i] {
                    elapsed[i] = Int(now.timeIntervalSince(last))
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
