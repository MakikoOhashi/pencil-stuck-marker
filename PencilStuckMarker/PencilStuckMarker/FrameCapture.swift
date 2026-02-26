//
//  FrameCapture.swift
//  PencilStuckMarker
//
//  Captures the current key window as a base64-encoded PNG.
//  Called once per stuck candidate — NOT per frame.
//
//  Day 2: switch to region-cropped snapshot for lower payload / better Vision Agent focus.
//

import UIKit

enum FrameCapture {

    /// Renders the key window into a UIImage, scales it down, returns base64 PNG.
    /// Max dimension: 768 px (keeps payload < ~500 KB for Vision Agent).
    @MainActor
    static func captureBase64() -> String? {
        guard let window = keyWindow() else {
            print("[FrameCapture] no key window found")
            return nil
        }

        // Render window layer (captures PDF + PencilKit drawing in one pass)
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let full = renderer.image { ctx in
            window.layer.render(in: ctx.cgContext)
        }

        let scaled = full.scaledToMaxDimension(768)
        guard let pngData = scaled.pngData() else {
            print("[FrameCapture] PNG encoding failed")
            return nil
        }

        print("[FrameCapture] captured \(Int(scaled.size.width))x\(Int(scaled.size.height)) px, \(pngData.count / 1024) KB")
        return pngData.base64EncodedString()
    }

    private static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .windows
            .first { $0.isKeyWindow }
    }
}

private extension UIImage {
    func scaledToMaxDimension(_ maxDim: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDim else { return self }
        let scale = maxDim / longest
        let newSize = CGSize(width: (size.width * scale).rounded(),
                             height: (size.height * scale).rounded())
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
