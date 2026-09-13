import SwiftUI
import UIKit

@MainActor
final class EmailExportService {
    static let shared = EmailExportService()

    private init() {}

    func renderToImage(details: MailDetails, bodyText: String, displayScale: CGFloat = 3.0) -> UIImage? {
        let cardView = EmailShareCardView(details: details, bodyText: bodyText)
        let renderer = ImageRenderer(content: cardView)
        renderer.scale = displayScale
        renderer.isOpaque = true
        return renderer.uiImage
    }

    func renderToPDF(details: MailDetails, bodyText: String) -> URL? {
        let cardView = EmailShareCardView(details: details, bodyText: bodyText)
        let renderer = ImageRenderer(content: cardView)

        let tempDirectory = FileManager.default.temporaryDirectory
        let fileName = "Mail-\(details.id).pdf"
        let outputURL = tempDirectory.appendingPathComponent(fileName)

        try? FileManager.default.removeItem(at: outputURL)

        var isSuccess = false

        renderer.render { size, context in
            var box = CGRect(origin: .zero, size: size)
            guard let pdfContext = CGContext(outputURL as CFURL, mediaBox: &box, nil) else {
                return
            }

            pdfContext.beginPDFPage(nil)
            context(pdfContext)
            pdfContext.endPDFPage()
            pdfContext.closePDF()
            isSuccess = true
        }

        return isSuccess ? outputURL : nil
    }
}
