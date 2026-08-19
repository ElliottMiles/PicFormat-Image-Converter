//
//  FormatCapabilityService.swift
//  Good_Image_Converter
//
//  Determines, at runtime, which output formats this specific device and
//  OS build can actually encode. Never hardcode format availability by
//  device model — HEIC/HEIF/AVIF hardware support varies across chips and
//  OS versions, so we ask ImageIO what it can currently produce.
//

import ImageIO
import UniformTypeIdentifiers

enum FormatCapabilityService {

    /// All formats this device can currently encode to, in the order
    /// they should be presented to the user.
    nonisolated static var availableFormats: [ImageFormat] {
        ImageFormat.allCases.filter(isAvailable)
    }

    nonisolated static func isAvailable(_ format: ImageFormat) -> Bool {
        switch format {
        case .svg:
            // Our SVG output wraps the raster image ourselves; no ImageIO
            // encoder needed, so it's always available.
            return true
        case .webp:
            return WebPEncoder.isAvailable
        default:
            return writableTypeIdentifiers.contains(format.utType.identifier as CFString)
        }
    }

    /// ImageIO's live list of destination types it can currently write.
    /// This is exactly the API Apple recommends for detecting hardware-
    /// dependent encoders like HEIC, rather than branching on device model.
    nonisolated private static let writableTypeIdentifiers: [CFString] = {
        (CGImageDestinationCopyTypeIdentifiers() as? [CFString]) ?? []
    }()
}
