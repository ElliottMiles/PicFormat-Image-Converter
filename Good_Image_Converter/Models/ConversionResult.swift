//
//  ConversionResult.swift
//  Good_Image_Converter
//

import UIKit

struct ConversionResult: Identifiable {
    let id = UUID()
    let sourceID: UUID
    let filename: String
    let data: Data
    let format: ImageFormat
    let thumbnail: UIImage

    var byteCount: Int { data.count }

    var formattedByteCount: String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }
}

enum ConversionError: LocalizedError {
    case encodingFailed(name: String, format: ImageFormat)
    case formatUnavailable(ImageFormat)

    var errorDescription: String? {
        switch self {
        case .encodingFailed(let name, let format):
            return "\"\(name)\" couldn't be converted to \(format.displayName)."
        case .formatUnavailable(let format):
            return "\(format.displayName) isn't available on this device."
        }
    }
}
