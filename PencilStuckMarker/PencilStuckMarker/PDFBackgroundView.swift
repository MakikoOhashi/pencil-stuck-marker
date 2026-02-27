//
//  PDFBackgroundView.swift
//  PencilStuckMarker
//

import SwiftUI
import PDFKit
import UIKit

struct PDFBackgroundView: UIViewRepresentable {
    let url: URL?

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .white
        view.isUserInteractionEnabled = false
        if let url {
            view.document = PDFDocument(url: url)
        }
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        guard let url else { return }
        if uiView.document == nil {
            uiView.document = PDFDocument(url: url)
        }
    }
}
