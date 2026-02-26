//
//  InterventionService.swift
//  PencilStuckMarker
//
//  Sends stuck-candidate data to the Python service and receives an intervention command.
//  API contract matches README §"API Contract (Swift ↔ Python)".
//

import Foundation
import CoreGraphics

actor InterventionService {

    static let shared = InterventionService()

    private let endpoint = URL(string: "http://localhost:8000/analyze")!

    func analyze(regionId: String, state: RegionState, framePngBase64: String) async -> AnalyzeResponse? {
        let anchor = CGPoint(x: state.rect.midX, y: state.rect.midY)
        let payload = AnalyzeRequest(
            regionId: regionId,
            stallSeconds: Double(state.elapsedSeconds),
            oscillationCount: state.oscillationCount,
            anchor: .init(x: anchor.x, y: anchor.y),
            regionRect: .init(x: state.rect.minX, y: state.rect.minY,
                              w: state.rect.width, h: state.rect.height),
            framePngBase64: framePngBase64
        )

        guard let body = try? JSONEncoder().encode(payload) else { return nil }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(AnalyzeResponse.self, from: data)
            print("[Intervention] intervene=\(response.intervene) style=\(response.style) msg=\(response.message)")
            return response
        } catch {
            print("[Intervention] /analyze failed: \(error)")
            return nil
        }
    }
}

// MARK: - Request — matches README API contract

private struct AnalyzeRequest: Encodable, Sendable {
    let regionId: String
    let stallSeconds: Double
    let oscillationCount: Int
    let anchor: XY
    let regionRect: Rect
    let framePngBase64: String

    enum CodingKeys: String, CodingKey {
        case regionId = "region_id"
        case stallSeconds = "stall_seconds"
        case oscillationCount = "oscillation_count"
        case anchor
        case regionRect = "region_rect"
        case framePngBase64 = "frame_png_base64"
    }

    struct XY: Encodable, Sendable { let x, y: CGFloat }
    struct Rect: Encodable, Sendable { let x, y, w, h: CGFloat }
}

// MARK: - Response — matches README API contract

struct AnalyzeResponse: Decodable, Sendable {
    let intervene: Bool
    let style: String
    let message: String
    let target: Target
    let cooldownSeconds: Int

    enum CodingKeys: String, CodingKey {
        case intervene, style, message, target
        case cooldownSeconds = "cooldown_seconds"
    }

    struct Target: Decodable, Sendable {
        let regionId: String
        enum CodingKeys: String, CodingKey { case regionId = "region_id" }
    }
}
