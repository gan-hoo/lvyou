// Prints the text Vision recognises in a screenshot, top to bottom.
// Usage: swift scripts/ocr.swift shot.png
import AppKit
import Vision

let url = URL(fileURLWithPath: CommandLine.arguments[1])
guard let image = NSImage(contentsOf: url) else { print("cannot open \(url.path)"); exit(1) }
var rect = CGRect(origin: .zero, size: image.size)
guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { exit(1) }

let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.recognitionLanguages = ["zh-Hans", "en-US"]
request.usesLanguageCorrection = false
try VNImageRequestHandler(cgImage: cg).perform([request])

let lines = (request.results ?? [])
    .compactMap { obs -> (CGFloat, CGFloat, String)? in
        guard let text = obs.topCandidates(1).first?.string else { return nil }
        return (1 - obs.boundingBox.midY, obs.boundingBox.minX, text)
    }
    .sorted { abs($0.0 - $1.0) < 0.012 ? $0.1 < $1.1 : $0.0 < $1.0 }

var row: [String] = []
var lastY: CGFloat = -1
for (y, _, text) in lines {
    if lastY >= 0 && abs(y - lastY) >= 0.012 {
        print(row.joined(separator: "  |  "))
        row = []
    }
    row.append(text)
    lastY = y
}
if !row.isEmpty { print(row.joined(separator: "  |  ")) }
