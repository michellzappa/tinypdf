import Foundation
import AppKit
import PDFKit
import TinyKit
import UniformTypeIdentifiers
import Vision

@Observable
final class AppState: FileState {
    init() {
        super.init(
            bookmarkKey: "lastFolderBookmarkPDF",
            defaultExtension: "pdf",
            supportedExtensions: ["pdf"]
        )
    }

    // Disable auto-save — writing text back to .pdf would corrupt it
    override var shouldAutoSave: Bool { false }

    // Extract text from PDF instead of reading as UTF-8
    override func readFileContent(from url: URL) -> String {
        guard url.pathExtension.lowercased() == "pdf" else {
            return super.readFileContent(from: url)
        }
        guard let document = PDFDocument(url: url) else {
            return "<!-- Error: Could not open PDF -->"
        }
        if document.isEncrypted && !document.unlock(withPassword: "") {
            return "<!-- This PDF is encrypted and cannot be read -->"
        }
        return extractText(from: document)
    }

    private func extractText(from document: PDFDocument) -> String {
        let pageCount = document.pageCount
        guard pageCount > 0 else {
            return "<!-- This PDF contains no pages -->"
        }
        var sections: [String] = []
        for i in 0..<pageCount {
            guard let page = document.page(at: i) else { continue }
            let header = "# Page \(i + 1)"
            let text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !text.isEmpty {
                sections.append("\(header)\n\n\(text)")
            } else if let ocrText = ocrPage(page), !ocrText.isEmpty {
                sections.append("\(header)\n\n*OCR:*\n\n\(ocrText)")
            } else {
                sections.append("\(header)\n\n*(No text content on this page)*")
            }
        }
        return sections.joined(separator: "\n\n---\n\n")
    }

    /// OCR a single PDF page using Vision framework.
    private func ocrPage(_ page: PDFPage) -> String? {
        // Render page to CGImage at 2x for better recognition
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0
        let width = Int(bounds.width * scale)
        let height = Int(bounds.height * scale)
        guard width > 0, height > 0 else { return nil }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.setFillColor(.white)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.scaleBy(x: scale, y: scale)

        NSGraphicsContext.saveGraphicsState()
        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.current = nsCtx
        page.draw(with: .mediaBox, to: ctx)
        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = ctx.makeImage() else { return nil }

        // Run VNRecognizeTextRequest synchronously
        var recognized: [String] = []
        let request = VNRecognizeTextRequest { request, _ in
            guard let observations = request.results as? [VNRecognizedTextObservation] else { return }
            for observation in observations {
                if let candidate = observation.topCandidates(1).first {
                    recognized.append(candidate.string)
                }
            }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])

        return recognized.isEmpty ? nil : recognized.joined(separator: "\n")
    }

    /// The PDF document for the currently selected file (used by preview pane).
    var currentPDFDocument: PDFDocument? {
        guard let url = selectedFile else { return nil }
        return PDFDocument(url: url)
    }

    /// Page count for display.
    var pageCount: Int {
        guard let url = selectedFile else { return 0 }
        return PDFDocument(url: url)?.pageCount ?? 0
    }

    /// Export extracted text to a markdown file.
    func exportAsMarkdown() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        let baseName = selectedFile?.deletingPathExtension().lastPathComponent ?? "Untitled"
        panel.nameFieldStringValue = "\(baseName).md"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }
}
