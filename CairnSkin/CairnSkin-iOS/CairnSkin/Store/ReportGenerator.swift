//
//  ReportGenerator.swift
//  CairnSkin
//
//  WHAT THIS FILE IS:
//  Builds a PDF summary of one tracking area: every photo with its date,
//  note, and change value, plus a disclaimer.
//
//  WHY THE DISCLAIMER IS IN THE DOCUMENT, NOT JUST THE APP:
//  A PDF outlives the screen that made it. It gets emailed, printed, and
//  handed to people who never saw the app or its context. Whatever
//  framing this file carries is the only framing a reader gets, so the
//  disclaimer appears on the first page and again in the footer of every
//  page — it can't be scrolled past or cropped out.
//
//  WHY THERE'S NO "EMAIL THIS" BUTTON:
//  The app writes a file and hands it to the user; what happens next is
//  their decision. Building a send path would make the app a channel for
//  transmitting health-adjacent photos, which is a materially different
//  privacy posture than "everything stays on your device unless you
//  choose otherwise."
//

import UIKit
import PDFKit
import Vision

// nonisolated for the same reason as FeatureExtractor: PDF rendering is
// run from Task.detached so a large export doesn't freeze the UI, and it
// touches only values handed to it plus read-only disk access.
nonisolated enum ReportGenerator {

    // US Letter at 72 dpi.
    private static let pageWidth: CGFloat = 612
    private static let pageHeight: CGFloat = 792
    private static let margin: CGFloat = 48

    private static let disclaimer = "Cairn Skin is a personal wellness journal. It does not diagnose, screen for, or assess any medical condition. This document is a record of photographs the user took and any notes they added, nothing more. Photographs are affected by lighting, camera angle, and distance, so apparent differences between them may not reflect a real change. Always consult a qualified healthcare provider about any health concern."

    /// Writes a PDF to a temporary file and returns its URL.
    ///
    /// Takes the entries array and the archive rather than the store.
    /// The store is main-actor isolated (it owns UI state), so reaching
    /// into it from the background task that calls this would be a
    /// concurrency violation. The caller gathers `entries` on the main
    /// actor and passes the plain array down; PhotoArchive is safe to use
    /// from anywhere.
    static func generate(
        area: TrackingArea,
        entries: [TrackingEntry],
        archive: PhotoArchive
    ) throws -> URL {
        let baselinePrint = entries.first.flatMap { archive.featurePrint(for: $0) }

        let format = UIGraphicsPDFRendererFormat()
        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight),
            format: format
        )

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CairnSkin-\(safeFileName(area.name)).pdf")

        try renderer.writePDF(to: url) { context in
            context.beginPage()
            var y = margin

            y = drawHeader(area: area, entryCount: entries.count, at: y)
            y = drawDisclaimerBox(at: y)

            for (index, entry) in entries.enumerated() {
                // autoreleasepool releases each decoded image as soon as
                // it's drawn. Without it, exporting an area with 100 photos
                // holds every decoded image in memory until the whole loop
                // finishes, which is a memory spike large enough to get the
                // app killed on older devices.
                autoreleasepool {
                    // Start a new page when the next block wouldn't fit.
                    if y + 170 > pageHeight - margin - 40 {
                        drawFooter(context: context)
                        context.beginPage()
                        y = margin
                    }
                    y = drawEntry(
                        entry,
                        index: index,
                        baselinePrint: baselinePrint,
                        archive: archive,
                        at: y
                    )
                }
            }
            drawFooter(context: context)
        }

        return url
    }

    // MARK: - Drawing helpers

    private static func drawHeader(area: TrackingArea, entryCount: Int, at y: CGFloat) -> CGFloat {
        var y = y
        let title = "Cairn Skin — Photo Log"
        title.draw(at: CGPoint(x: margin, y: y), withAttributes: [
            .font: UIFont.boldSystemFont(ofSize: 22),
            .foregroundColor: UIColor.black
        ])
        y += 30

        let subtitle = "\(area.name)  ·  \(area.category.rawValue)  ·  \(entryCount) photo\(entryCount == 1 ? "" : "s")"
        subtitle.draw(at: CGPoint(x: margin, y: y), withAttributes: [
            .font: UIFont.systemFont(ofSize: 12),
            .foregroundColor: UIColor.darkGray
        ])
        y += 18

        let generated = "Generated \(Date().formatted(date: .long, time: .shortened))"
        generated.draw(at: CGPoint(x: margin, y: y), withAttributes: [
            .font: UIFont.systemFont(ofSize: 10),
            .foregroundColor: UIColor.gray
        ])
        return y + 24
    }

    private static func drawDisclaimerBox(at y: CGFloat) -> CGFloat {
        let boxWidth = pageWidth - margin * 2
        let textRect = CGRect(x: margin + 10, y: y + 10, width: boxWidth - 20, height: 90)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2

        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 9),
            .foregroundColor: UIColor.darkGray,
            .paragraphStyle: paragraph
        ]
        let height = (disclaimer as NSString).boundingRect(
            with: CGSize(width: textRect.width, height: .greatestFiniteMagnitude),
            options: .usesLineFragmentOrigin,
            attributes: attributes,
            context: nil
        ).height

        let box = CGRect(x: margin, y: y, width: boxWidth, height: height + 20)
        let path = UIBezierPath(roundedRect: box, cornerRadius: 6)
        UIColor(white: 0.95, alpha: 1).setFill()
        path.fill()

        disclaimer.draw(with: CGRect(x: textRect.minX, y: textRect.minY, width: textRect.width, height: height),
                        options: .usesLineFragmentOrigin,
                        attributes: attributes,
                        context: nil)

        return y + height + 36
    }

    private static func drawEntry(
        _ entry: TrackingEntry,
        index: Int,
        baselinePrint: VNFeaturePrintObservation?,
        archive: PhotoArchive,
        at y: CGFloat
    ) -> CGFloat {
        let thumbSize: CGFloat = 130

        // Downsampled, not full-resolution. Drawing a dozen multi-megapixel
        // JPEGs into a PDF is slow and memory-hungry, and the result is a
        // 130pt square either way. printImage() uses 800px — enough for a
        // clean print, a fraction of the cost of the original.
        if let image = archive.printImage(for: entry) {
            let rect = CGRect(x: margin, y: y, width: thumbSize, height: thumbSize)
            let path = UIBezierPath(roundedRect: rect, cornerRadius: 6)
            path.addClip()
            image.draw(in: aspectFillRect(for: image, in: rect))
            // Reset the clip for subsequent drawing.
            UIGraphicsGetCurrentContext()?.resetClip()
        }

        let textX = margin + thumbSize + 16
        let textWidth = pageWidth - textX - margin
        var textY = y + 4

        let dateLabel = index == 0
            ? "Baseline · \(entry.date.formatted(date: .abbreviated, time: .shortened))"
            : entry.date.formatted(date: .abbreviated, time: .shortened)
        dateLabel.draw(at: CGPoint(x: textX, y: textY), withAttributes: [
            .font: UIFont.boldSystemFont(ofSize: 13),
            .foregroundColor: UIColor.black
        ])
        textY += 20

        // NO SIMILARITY FIGURE.
        //
        // This is the version most likely to end up in front of a
        // clinician, which makes it the worst place for a number that
        // looks like a measurement and isn't. The Vision distance is
        // dominated by lighting and background rather than by the subject,
        // and printing it on a document someone brings to an appointment
        // gives it an authority it can't support.
        //
        // The photographs, dates, and notes are the record. They're also
        // what's actually useful in that room.
        //
        // The one exception is kept below: "not comparable" is a strong,
        // reliable signal (an unrelated object scores far outside the range
        // of any same-subject pair), and flagging a photo that doesn't
        // belong is worth doing.
        if let baselinePrint,
           let print = archive.featurePrint(for: entry),
           index > 0 {
            let distance = (try? FeatureExtractor.distance(between: baselinePrint, and: print)) ?? 0
            if !FeatureExtractor.isComparable(distance: distance) {
                "May not show the same area as the baseline".draw(
                    at: CGPoint(x: textX, y: textY),
                    withAttributes: [
                        .font: UIFont.systemFont(ofSize: 11),
                        .foregroundColor: UIColor.darkGray
                    ]
                )
                textY += 18
            }
        }

        if !entry.note.isEmpty {
            let noteRect = CGRect(x: textX, y: textY, width: textWidth, height: thumbSize - (textY - y) - 4)
            entry.note.draw(with: noteRect, options: .usesLineFragmentOrigin, attributes: [
                .font: UIFont.italicSystemFont(ofSize: 11),
                .foregroundColor: UIColor.darkGray
            ], context: nil)
        }

        return y + thumbSize + 20
    }

    private static func drawFooter(context: UIGraphicsPDFRendererContext) {
        let text = "Not a medical measurement. Cairn Skin does not diagnose or assess any condition."
        let rect = CGRect(x: margin, y: pageHeight - margin + 6,
                          width: pageWidth - margin * 2, height: 14)
        text.draw(with: rect, options: .usesLineFragmentOrigin, attributes: [
            .font: UIFont.systemFont(ofSize: 8),
            .foregroundColor: UIColor.gray
        ], context: nil)
    }

    /// Scales an image to fill a rect while preserving aspect ratio.
    private static func aspectFillRect(for image: UIImage, in rect: CGRect) -> CGRect {
        let imageAspect = image.size.width / image.size.height
        let rectAspect = rect.width / rect.height
        var drawRect = rect
        if imageAspect > rectAspect {
            let width = rect.height * imageAspect
            drawRect = CGRect(x: rect.midX - width/2, y: rect.minY, width: width, height: rect.height)
        } else {
            let height = rect.width / imageAspect
            drawRect = CGRect(x: rect.minX, y: rect.midY - height/2, width: rect.width, height: height)
        }
        return drawRect
    }

    private static func safeFileName(_ name: String) -> String {
        name.components(separatedBy: CharacterSet.alphanumerics.inverted).joined(separator: "-")
    }
}
