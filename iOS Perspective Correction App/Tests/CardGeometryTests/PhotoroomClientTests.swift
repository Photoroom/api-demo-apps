import Foundation
import Testing
@testable import CardGeometry

@Test func maskRequestMatchesDemo() throws {
    let image = Data([0, 1, 2, 255])
    let request = try PhotoroomClient.maskRequest(image: image, apiKey: " test-key ", boundary: "test-boundary")
    #expect(request.url?.absoluteString == "https://sdk.photoroom.com/v1/segment")
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "x-api-key") == "test-key")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "multipart/form-data; boundary=test-boundary")
    let expectedStart = Data("--test-boundary\r\nContent-Disposition: form-data; name=\"image_file\"; filename=\"card.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8)
    let expectedEnd = Data("\r\n--test-boundary\r\nContent-Disposition: form-data; name=\"channels\"\r\n\r\nalpha\r\n--test-boundary--\r\n".utf8)
    #expect(request.httpBody == expectedStart + image + expectedEnd)
}

@Test func rejectsMissingOrInvalidKeyBeforeSending() {
    for key in ["", " \n ", "key\ninjected-header", "key\rheader"] {
        #expect(throws: PhotoroomError.self) { try PhotoroomClient.maskRequest(image: Data(), apiKey: key) }
    }
}

@Test func actionableAPIErrors() {
    #expect(PhotoroomClient.responseError(status: 401).localizedDescription.contains("API key"))
    #expect(PhotoroomClient.responseError(status: 402).localizedDescription.contains("credits"))
    #expect(PhotoroomClient.responseError(status: 429).localizedDescription.contains("Wait"))
    #expect(PhotoroomClient.responseError(status: 503).localizedDescription.contains("503"))
}

@Test func blurRequestsMatchDemo() throws {
    for step in [PhotoroomClient.FinishStep.expand, .blur] {
        let request = try PhotoroomClient.finishRequest(image: Data("image-bytes".utf8), apiKey: " test-key ", step: step, boundary: "finish")
        #expect(request.url?.absoluteString == "https://image-api.photoroom.com/v2/edit")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "test-key")
        let body = String(decoding: request.httpBody!, as: UTF8.self)
        #expect(body.contains("name=\"imageFile\""))
        let names = Set(body.components(separatedBy: "; name=\"").dropFirst().map { String($0.prefix { $0 != "\"" }) })
        let expectedNames: Set<String> = step == .expand
            ? ["imageFile", "referenceBox", "removeBackground", "expand.mode"]
            : ["imageFile", "background.blur.mode", "background.blur.radius", "lighting.mode", "removeBackground", "referenceBox", "export.format"]
        #expect(names == expectedNames) // No additional padding, margin, output size, or positioning parameters.
        let filename = step == .expand ? "perspective-corrected-card.png" : "perspective-expanded-card.png"
        #expect(body.contains("filename=\"\(filename)\""))
        #expect(body.contains("image-bytes"))
        for (name, value) in [("referenceBox", "originalImage"), ("removeBackground", "false")] {
            #expect(body.contains("name=\"\(name)\"\r\n\r\n\(value)\r\n"))
        }
        if step == .expand {
            #expect(body.contains("name=\"expand.mode\"\r\n\r\nai.auto\r\n"))
            #expect(!body.contains("background.blur.mode"))
        } else {
            for (name, value) in [("background.blur.mode", "gaussian"), ("background.blur.radius", "0.012"),
                                  ("lighting.mode", "ai.preserve-hue-and-saturation"), ("export.format", "jpeg")] {
                #expect(body.contains("name=\"\(name)\"\r\n\r\n\(value)\r\n"))
            }
            #expect(!body.contains("expand.mode"))
        }
        #expect(body.hasSuffix("--finish--\r\n"))
    }
}

private final class FinishProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                body.append(contentsOf: buffer.prefix(count))
            }
        }
        let text = String(decoding: body, as: UTF8.self)
        let expanding = text.contains("expand.mode")
        let valid = expanding ? text.contains("original-photo") : text.contains("expanded-photo")
        let response = HTTPURLResponse(url: request.url!, statusCode: valid ? 200 : 400, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((expanding ? "expanded-photo" : "finished-jpeg").utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Test func blurUsesExpandedImageForSecondCall() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [FinishProtocol.self]
    let client = PhotoroomClient(session: URLSession(configuration: configuration))
    let result = try await client.blurredFinish(image: Data("original-photo".utf8), apiKey: "test-key")
    #expect(result == Data("finished-jpeg".utf8))
}
