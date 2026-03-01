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

    private let endpoint = URL(string: "http://127.0.0.1:8000/analyze")!
    private let coachEndpoint = URL(string: "http://127.0.0.1:8000/coach")!

    func analyze(regionId: String, requestId: UUID, state: RegionState, framePngBase64: String) async -> AnalyzeResponse? {
        let anchor = state.lastStrokePoint ?? CGPoint(x: state.rect.midX, y: state.rect.midY)
        let payload = AnalyzeRequest(
            requestId: requestId.uuidString,
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
        request.timeoutInterval = 8.0
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

    func coach(regionId: String, state: RegionState, userText: String) async -> CoachResponse? {
        let anchor = state.lastStrokePoint ?? CGPoint(x: state.rect.midX, y: state.rect.midY)
        let payload = CoachRequest(
            regionId: regionId,
            stallSeconds: Double(state.elapsedSeconds),
            oscillationCount: state.oscillationCount,
            anchor: .init(x: anchor.x, y: anchor.y),
            userText: userText,
            previousCoachLine: state.coachLine
        )

        guard let body = try? JSONEncoder().encode(payload) else { return nil }

        var request = URLRequest(url: coachEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 6.0
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            return try JSONDecoder().decode(CoachResponse.self, from: data)
        } catch {
            print("[Coach] /coach failed: \(error)")
            return nil
        }
    }
}

// MARK: - Request — matches README API contract

nonisolated private struct AnalyzeRequest: Encodable, Sendable {
    let requestId: String
    let regionId: String
    let stallSeconds: Double
    let oscillationCount: Int
    let anchor: XY
    let regionRect: Rect
    let framePngBase64: String

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case regionId = "region_id"
        case stallSeconds = "stall_seconds"
        case oscillationCount = "oscillation_count"
        case anchor
        case regionRect = "region_rect"
        case framePngBase64 = "frame_png_base64"
    }

    nonisolated struct XY: Encodable, Sendable { let x, y: CGFloat }
    nonisolated struct Rect: Encodable, Sendable { let x, y, w, h: CGFloat }
}

nonisolated private struct CoachRequest: Encodable, Sendable {
    let regionId: String
    let stallSeconds: Double
    let oscillationCount: Int
    let anchor: AnalyzeRequest.XY
    let userText: String
    let previousCoachLine: String?

    enum CodingKeys: String, CodingKey {
        case regionId = "region_id"
        case stallSeconds = "stall_seconds"
        case oscillationCount = "oscillation_count"
        case anchor
        case userText = "user_text"
        case previousCoachLine = "previous_coach_line"
    }
}

// MARK: - Response — matches README API contract

nonisolated struct AnalyzeResponse: Decodable, Sendable {
    let requestId: String
    let intervene: Bool
    let style: String
    let message: String
    let target: Target
    let cooldownSeconds: Int

    enum CodingKeys: String, CodingKey {
        case requestId = "request_id"
        case intervene, style, message, target
        case cooldownSeconds = "cooldown_seconds"
    }

    nonisolated struct Target: Decodable, Sendable {
        let regionId: String
        enum CodingKeys: String, CodingKey { case regionId = "region_id" }
    }
}

nonisolated struct CoachResponse: Decodable, Sendable {
    let summary: String
    let question: String
    let nextAction: String

    enum CodingKeys: String, CodingKey {
        case summary, question
        case nextAction = "next_action"
    }
}
