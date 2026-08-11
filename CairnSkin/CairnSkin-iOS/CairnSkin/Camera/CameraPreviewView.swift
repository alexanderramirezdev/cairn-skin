//
//  CameraPreviewView.swift
//  CairnSkin
//
//  WHAT THIS FILE IS:
//  A small bridge that displays AVFoundation's live camera feed inside
//  SwiftUI. Same "UIViewRepresentable" bridge pattern as CameraPicker,
//  just wrapping a raw preview layer instead of a whole picker screen.
//

import SwiftUI
import AVFoundation

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    /// Mirrors the live preview for the front camera, matching the photo
    /// output's mirroring so what the user sees and what gets saved agree.
    /// Without it, moving left appears to move right and lining up against
    /// the ghost overlay becomes guesswork.
    var isMirrored: Bool = false

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        if isMirrored, let connection = view.videoPreviewLayer.connection,
           connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {}

    // A tiny custom UIView whose backing layer IS the preview layer.
    // Overriding `layerClass` is the standard way to do this in UIKit.
    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
