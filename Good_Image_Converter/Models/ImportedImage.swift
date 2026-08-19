//
//  ImportedImage.swift
//  Good_Image_Converter
//
//  A source image that has been pulled in from Photos, Files, or the
//  Camera and decoded, ready to feed into the conversion pipeline.
//

import UIKit
import ImageIO

struct ImportedImage: Identifiable, Equatable {
    let id = UUID()
    /// Name to base the output filename on (without extension).
    let baseFilename: String
    let cgImage: CGImage
    let orientation: CGImagePropertyOrientation
    let originalByteCount: Int
    let thumbnail: UIImage

    static func == (lhs: ImportedImage, rhs: ImportedImage) -> Bool {
        lhs.id == rhs.id
    }

    /// The image's pixel dimensions as they will appear once orientation
    /// is applied (i.e. what the user actually sees), not raw storage order.
    var displaySize: CGSize {
        switch orientation {
        case .left, .right, .leftMirrored, .rightMirrored:
            return CGSize(width: cgImage.height, height: cgImage.width)
        default:
            return CGSize(width: cgImage.width, height: cgImage.height)
        }
    }
}

enum ImportError: LocalizedError {
    case unreadableFile(name: String)
    case unsupportedData
    case cameraUnavailable

    var errorDescription: String? {
        switch self {
        case .unreadableFile(let name):
            return "\"\(name)\" couldn't be read as an image."
        case .unsupportedData:
            return "That file isn't a supported image type."
        case .cameraUnavailable:
            return "The camera isn't available on this device."
        }
    }
}
