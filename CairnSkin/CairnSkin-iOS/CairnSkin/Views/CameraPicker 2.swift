//
//  CameraPicker.swift
//  CairnSkin
//
//  WHAT THIS FILE IS:
//  SwiftUI doesn't have a built-in camera view, so this wraps Apple's
//  older UIKit camera controller (UIImagePickerController) so it can be
//  used from SwiftUI. This kind of wrapper is called a
//  "UIViewControllerRepresentable" — it's a well-known, standard bridge
//  pattern, not a hack. You'll see this exact shape any time a SwiftUI
//  app needs a UIKit-only capability.
//

import SwiftUI
import UIKit

struct CameraPicker: UIViewControllerRepresentable {

    // A "binding" — a two-way connection back to whatever screen
    // presented this picker, similar to @bind in Blazor. When we set
    // capturedImage inside this file, the presenting view sees it too.
    @Binding var capturedImage: UIImage?
    @Environment(\.dismiss) private var dismiss

    // Required by UIViewControllerRepresentable: build the actual
    // UIKit screen.
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        // Use the camera when it exists (real devices); fall back to the
        // photo library when it doesn't (the iOS Simulator has no camera,
        // and would crash if we demanded one). This means the app "just
        // works" in both places with no code changes.
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera)
            ? .camera
            : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    // Required by the protocol, but we don't need to update anything
    // after creation, so this is empty.
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    // A "Coordinator" is the standard way to receive UIKit delegate
    // callbacks (like "user took a photo") and translate them back into
    // SwiftUI state. Think of it as an adapter/event-handler object.
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        // Called when the user takes a photo and taps "Use Photo".
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.capturedImage = image
            }
            parent.dismiss()
        }

        // Called when the user taps "Cancel".
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
