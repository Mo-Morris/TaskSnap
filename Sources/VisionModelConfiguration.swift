import AppKit
import Foundation

struct VisionModelConfiguration: Codable, Equatable, Sendable {
    var endpoint: String
    var apiKey: String
    var model: String

    var trimmedEndpoint: String {
        endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedModel: String {
        model.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isComplete: Bool {
        !trimmedEndpoint.isEmpty && !trimmedAPIKey.isEmpty && !trimmedModel.isEmpty
    }
}

enum VisionModelError: LocalizedError {
    case incompleteConfiguration
    case invalidEndpoint
    case invalidResponse
    case requestFailed(Int, String)
    case emptySummary

    var errorDescription: String? {
        switch self {
        case .incompleteConfiguration:
            "请填写接口地址、API Key 和模型名。"
        case .invalidEndpoint:
            "接口地址无效。"
        case .invalidResponse:
            "模型返回格式无法识别。"
        case let .requestFailed(statusCode, message):
            "模型测试失败（HTTP \(statusCode)）：\(message)"
        case .emptySummary:
            "模型没有返回有效内容。"
        }
    }
}

protocol VisionSummarizing: Sendable {
    func summarize(imageData: Data, configuration: VisionModelConfiguration) async throws -> String
    func validate(configuration: VisionModelConfiguration) async throws
}

struct OpenAICompatibleVisionClient: VisionSummarizing {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func summarize(imageData: Data, configuration: VisionModelConfiguration) async throws -> String {
        try await requestSummary(
            imageData: imageData,
            configuration: configuration,
            prompt: """
            你是一个截图待办整理助手。用户提供的每张截图都代表一个需要稍后处理的待做事项，请不要把它当作普通图片描述，而要从「用户接下来要做什么」的角度提炼任务。

            请观察截图里的文字、界面、错误状态、聊天内容、设计稿或上下文，生成：
            1. 主标题：简洁明确，像待办事项标题，优先使用动词开头，不超过 14 个中文字符。
            2. 副标题：补充截图背景和任务线索，说明为什么要做、要处理哪个对象或当前卡在哪里，不超过 36 个中文字符。

            如果截图信息不足，也要基于可见内容给出合理待办方向，不要只说「查看截图」或「处理任务」。
            只按下面两行格式输出，不要添加编号、解释、Markdown 或多余内容：
            主标题：...
            副标题：...
            """
        )
    }

    func validate(configuration: VisionModelConfiguration) async throws {
        _ = try await requestSummary(
            imageData: Self.validationPNG,
            configuration: configuration,
            prompt: "这是模型连通性测试。请只回复 OK。"
        )
    }

    private func requestSummary(imageData: Data, configuration: VisionModelConfiguration, prompt: String) async throws -> String {
        guard configuration.isComplete else {
            debugLog("Configuration is incomplete.")
            throw VisionModelError.incompleteConfiguration
        }

        let requestURL = try chatCompletionsURL(from: configuration.trimmedEndpoint)
        debugLog("""
        Preparing request
        endpoint: \(configuration.trimmedEndpoint)
        resolvedURL: \(requestURL.absoluteString)
        model: \(configuration.trimmedModel)
        apiKey: \(redactedAPIKey(configuration.trimmedAPIKey))
        imageBytes: \(imageData.count)
        prompt: \(prompt)
        """)

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("Bearer \(configuration.trimmedAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let chatRequest = ChatRequest(
            model: configuration.trimmedModel,
            messages: [
                ChatMessage(role: "user", content: [
                    .text(prompt),
                    .imageURL(ImageURL(url: "data:image/png;base64,\(imageData.base64EncodedString())"))
                ])
            ],
            maxTokens: 120
        )
        request.httpBody = try JSONEncoder().encode(chatRequest)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            debugLog("Invalid response type: \(type(of: response))")
            throw VisionModelError.invalidResponse
        }

        debugLog("""
        Received response
        status: \(httpResponse.statusCode)
        url: \(httpResponse.url?.absoluteString ?? "nil")
        body: \(responsePreview(from: data))
        """)

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data).error.message)
                ?? String(data: data, encoding: .utf8)
                ?? "未知错误"
            debugLog("Request failed with HTTP \(httpResponse.statusCode): \(message)")
            throw VisionModelError.requestFailed(httpResponse.statusCode, message)
        }

        let decoded: ChatResponse
        do {
            decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        } catch {
            debugLog("Failed to decode response: \(error)")
            throw error
        }

        let summary = decoded.choices.first?.message.content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""

        guard !summary.isEmpty else {
            debugLog("Response decoded, but summary content is empty.")
            throw VisionModelError.emptySummary
        }

        debugLog("Summary received: \(summary)")
        return summary
    }

    private func chatCompletionsURL(from endpoint: String) throws -> URL {
        guard var components = URLComponents(string: endpoint) else {
            throw VisionModelError.invalidEndpoint
        }

        if components.path.hasSuffix("/chat/completions") {
            guard let url = components.url else { throw VisionModelError.invalidEndpoint }
            return url
        }

        let trimmedPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if trimmedPath.isEmpty {
            components.path = "/v1/chat/completions"
        } else if trimmedPath.hasSuffix("/v1") || trimmedPath == "v1" {
            components.path = "/\(trimmedPath)/chat/completions"
        } else {
            components.path = "/\(trimmedPath)/v1/chat/completions"
        }

        guard let url = components.url else {
            throw VisionModelError.invalidEndpoint
        }

        return url
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        print("[TaskSnap][Vision] \(message)")
        #endif
    }

    private func redactedAPIKey(_ apiKey: String) -> String {
        guard apiKey.count > 8 else {
            return "\(String(repeating: "*", count: apiKey.count)) (\(apiKey.count) chars)"
        }

        return "\(apiKey.prefix(4))...\(apiKey.suffix(4)) (\(apiKey.count) chars)"
    }

    private func responsePreview(from data: Data) -> String {
        guard let text = String(data: data, encoding: .utf8) else {
            return "<\(data.count) bytes, non-utf8>"
        }

        let limit = 2_000
        if text.count <= limit {
            return text
        }

        return "\(text.prefix(limit))... <truncated, \(text.count) chars total>"
    }

    private static let validationPNG = makeValidationPNG()

    private static func makeValidationPNG() -> Data {
        let size = 16
        let samplesPerPixel = 4
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: size,
            pixelsHigh: size,
            bitsPerSample: 8,
            samplesPerPixel: samplesPerPixel,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: size * samplesPerPixel,
            bitsPerPixel: 8 * samplesPerPixel
        )!

        guard let bitmapData = bitmap.bitmapData else {
            return Data()
        }

        for y in 0..<size {
            for x in 0..<size {
                let offset = (y * size + x) * samplesPerPixel
                bitmapData[offset] = 255
                bitmapData[offset + 1] = 255
                bitmapData[offset + 2] = 255
                bitmapData[offset + 3] = 255
            }
        }

        return bitmap.representation(using: .png, properties: [:]) ?? Data()
    }
}

private struct ChatRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let maxTokens: Int

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case maxTokens = "max_tokens"
    }
}

private struct ChatMessage: Encodable {
    let role: String
    let content: [MessageContent]
}

private enum MessageContent: Encodable {
    case text(String)
    case imageURL(ImageURL)

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .text(text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case let .imageURL(imageURL):
            try container.encode("image_url", forKey: .type)
            try container.encode(imageURL, forKey: .imageURL)
        }
    }
}

private struct ImageURL: Encodable {
    let url: String
}

private struct ChatResponse: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let message: ResponseMessage
    }

    struct ResponseMessage: Decodable {
        let content: String
    }
}

private struct ErrorResponse: Decodable {
    let error: APIError

    struct APIError: Decodable {
        let message: String
    }
}
