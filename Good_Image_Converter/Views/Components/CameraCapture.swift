//
//  CameraCapture.swift
//  Good_Image_Converter
//

import SwiftUI

struct CameraCapture: UIViewControllerRepresentable {
    let onCaptured: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCaptured: onCaptured)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCaptured: (UIImage?) -> Void

        init(onCaptured: @escaping (UIImage?) -> Void) {
            self.onCaptured = onCaptured
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            let image = info[.originalImage] as? UIImage
            onCaptured(image)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCaptured(nil)
        }
    }
}
