import Foundation
import Vision
import ImageIO

/// This worker owns the image bytes only for recognition. No files, logging, analytics or network requests.
enum ReceiptOCR {
    static func recognize(data: Data) async throws -> [String] {
        guard data.count <= 25 * 1024 * 1024 else { throw ReceiptError.tooLarge }
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return try autoreleasepool {
                guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 3000
                      ] as CFDictionary) else { throw ReceiptError.invalidImage }
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.recognitionLanguages = ["ja-JP", "en-US"]
                request.usesLanguageCorrection = true
                try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
                try Task.checkCancellation()
                let observations = (request.results ?? []).sorted { $0.boundingBox.midY > $1.boundingBox.midY }
                var groups: [[VNRecognizedTextObservation]] = []
                for observation in observations {
                    if let index = groups.indices.last, let anchor = groups[index].first,
                       abs(anchor.boundingBox.midY - observation.boundingBox.midY) < min(anchor.boundingBox.height, observation.boundingBox.height) * 0.5 {
                        groups[index].append(observation)
                    } else { groups.append([observation]) }
                }
                let lines = groups.map { group in
                    group.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
                        .compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
                }.filter { !$0.isEmpty }
                guard !lines.isEmpty else { throw ReceiptError.noText }
                return lines
            }
        }
        return try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
    }
}
