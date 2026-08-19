//
//  CompressionQuality.swift
//  Good_Image_Converter
//

import Foundation

/// User-facing compression tiers. Only meaningful for formats where
/// `ImageFormat.supportsVariableQuality` is true; lossless formats always
/// behave as `.lossless` regardless of the selected tier.
enum CompressionQuality: String, CaseIterable, Identifiable {
    case lossless
    case high
    case balanced
    case maximumCompression

    nonisolated var id: String { rawValue }

    nonisolated var displayName: String {
        switch self {
        case .lossless: return "Lossless"
        case .high: return "High Quality"
        case .balanced: return "Balanced"
        case .maximumCompression: return "Maximum Compression"
        }
    }

    nonisolated var subtitle: String {
        switch self {
        case .lossless: return "No quality loss, largest files"
        case .high: return "Minimal quality loss"
        case .balanced: return "Good tradeoff between size and quality"
        case .maximumCompression: return "Smallest files, more visible quality loss"
        }
    }

    /// Value passed to `kCGImageDestinationLossyCompressionQuality` (0...1).
    nonisolated var encoderQuality: CGFloat {
        switch self {
        case .lossless: return 1.0
        case .high: return 0.85
        case .balanced: return 0.65
        case .maximumCompression: return 0.35
        }
    }

    nonisolated var systemImageName: String {
        switch self {
        case .lossless: return "checkmark.seal"
        case .high: return "star"
        case .balanced: return "scalemass"
        case .maximumCompression: return "arrow.down.circle"
        }
    }
}
