//
//  ShareSheet.swift
//  CairnSkin
//
//  WHAT THIS FILE IS:
//  A SwiftUI wrapper around the iOS share sheet (UIActivityViewController),
//  used to hand the generated PDF to the user.
//
//  Note what this does and doesn't do: it opens the system share sheet
//  and hands over a file. The app never sends anything itself — no mail
//  is composed, no upload happens, no destination is chosen for the user.
//  Whether the PDF gets saved to Files, AirDropped, or emailed is
//  entirely the user's decision, which keeps the app out of the business
//  of transmitting health-adjacent photos.
//

import SwiftUI
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// SwiftUI's .sheet(item:) requires Identifiable. URL isn't by default,
// so this small conformance lets a generated file URL drive sheet
// presentation directly — when it's non-nil, the share sheet appears.
extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
