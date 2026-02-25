//
//  CanvasView.swift
//  PencilStuckMarker
//

import SwiftUI
import PencilKit

struct CanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    var onStrokeAdded: (CGRect) -> Void

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
        var onStrokeAdded: (CGRect) -> Void
        var previousCount = 0

        init(onStrokeAdded: @escaping (CGRect) -> Void) {
            self.onStrokeAdded = onStrokeAdded
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            let strokes = canvasView.drawing.strokes
            if strokes.count > previousCount, let last = strokes.last {
                onStrokeAdded(last.renderBounds)
            }
            previousCount = strokes.count
        }
    }
}
