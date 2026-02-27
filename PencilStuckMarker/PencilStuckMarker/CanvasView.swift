//
//  CanvasView.swift
//  PencilStuckMarker
//

import SwiftUI
import PencilKit

struct CanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    var onStrokeAdded: (CGRect, CGPoint) -> Void

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawing = drawing
        canvas.delegate = context.coordinator
        canvas.tool = PKInkingTool(.pen, color: .black, width: 3)
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .clear
        return canvas
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        // State 更新ごとに最新クロージャを Coordinator に渡す
        context.coordinator.onStrokeAdded = onStrokeAdded
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onStrokeAdded: onStrokeAdded)
    }

    class Coordinator: NSObject, PKCanvasViewDelegate {
        var onStrokeAdded: (CGRect, CGPoint) -> Void
        var previousCount = 0

        init(onStrokeAdded: @escaping (CGRect, CGPoint) -> Void) {
            self.onStrokeAdded = onStrokeAdded
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            let strokes = canvasView.drawing.strokes
            if strokes.count > previousCount, let last = strokes.last {
                let fallback = CGPoint(x: last.renderBounds.midX, y: last.renderBounds.midY)
                let endPoint: CGPoint
                if last.path.count > 0 {
                    endPoint = last.path[last.path.count - 1].location
                } else {
                    endPoint = fallback
                }
                onStrokeAdded(last.renderBounds, endPoint)
            }
            previousCount = strokes.count
        }
    }
}
