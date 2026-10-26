import AppKit
import ScreenCaptureKit
import Vision
import AvatarCore

/// Finds text inside a window: captures just that window (works while it is occluded) and runs
/// Vision OCR. Needs Screen Recording permission; without it lookups return nil.
enum TextLocator {
    /// CG rect of the first recognized occurrence of `query` (case/diacritic-insensitive).
    static func find(_ query: String, windowNumber: Int, frame: Rect) async -> Rect? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let window = content.windows.first(where: { Int($0.windowID) == windowNumber }) else { return nil }
            let config = SCStreamConfiguration()
            config.width = Int(frame.w * 2)
            config.height = Int(frame.h * 2)
            config.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: config)
            return try recognize(query, in: image, frame: frame)
        } catch {
            fputs("Perch: text lookup failed: \(error)\n", stderr)
            return nil
        }
    }

    static func recognize(_ query: String, in image: CGImage, frame: Rect) throws -> Rect? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US", "zh-Hans"]
        try VNImageRequestHandler(cgImage: image).perform([request])
        for observation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first,
                  let range = candidate.string.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]),
                  let box = try candidate.boundingBox(for: range)?.boundingBox else { continue }
            return visionRectToScreen(box.minX, box.minY, box.width, box.height, in: frame)
        }
        return nil
    }
}
