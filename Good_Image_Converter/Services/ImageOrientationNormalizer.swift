//
//  ImageOrientationNormalizer.swift
//  Good_Image_Converter
//
//  Bakes EXIF orientation into pixel data so every output format — even
//  ones that don't understand an orientation tag (BMP, some SVG viewers,
//  etc.) — comes out right-side up.
//
//  Deliberately implemented with a raw CGContext instead of
//  UIGraphicsImageRenderer: UIGraphicsImageRenderer defaults to the
//  *screen's* scale factor (2x/3x) unless a format with scale = 1 is
//  passed in explicitly, which silently multiplies output resolution
//  and can bloat "lossless" files by 4-9x. CGContext has no such
//  implicit scale, so the output always matches the source's true
//  pixel dimensions.
//

import CoreGraphics
import ImageIO

enum ImageOrientationNormalizer {

    /// Returns a new CGImage with `orientation` baked into the pixels.
    /// If `orientation` is already `.up`, the original image is returned
    /// unchanged (no redundant redraw / recompression).
    nonisolated static func normalize(_ image: CGImage, orientation: CGImagePropertyOrientation) -> CGImage {
        guard orientation != .up else { return image }

        let srcW = CGFloat(image.width)
        let srcH = CGFloat(image.height)
        let swapsDimensions: Bool
        switch orientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            swapsDimensions = true
        default:
            swapsDimensions = false
        }
        let canvasW = swapsDimensions ? srcH : srcW
        let canvasH = swapsDimensions ? srcW : srcH

        let hasAlpha = image.alphaInfo != .none && image.alphaInfo != .noneSkipFirst && image.alphaInfo != .noneSkipLast
        let bitmapInfo: UInt32 = hasAlpha
            ? CGImageAlphaInfo.premultipliedLast.rawValue
            : CGImageAlphaInfo.noneSkipLast.rawValue

        guard let context = CGContext(
            data: nil,
            width: Int(canvasW),
            height: Int(canvasH),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ) else {
            return image
        }

        context.concatenate(transform(for: orientation, canvasWidth: canvasW, canvasHeight: canvasH))
        context.draw(image, in: CGRect(x: 0, y: 0, width: srcW, height: srcH))

        return context.makeImage() ?? image
    }

    nonisolated private static func transform(for orientation: CGImagePropertyOrientation, canvasWidth: CGFloat, canvasHeight: CGFloat) -> CGAffineTransform {
        var transform = CGAffineTransform.identity

        switch orientation {
        case .down, .downMirrored:
            transform = transform.translatedBy(x: canvasWidth, y: canvasHeight).rotated(by: .pi)
        case .left, .leftMirrored:
            transform = transform.translatedBy(x: canvasWidth, y: 0).rotated(by: .pi / 2)
        case .right, .rightMirrored:
            transform = transform.translatedBy(x: 0, y: canvasHeight).rotated(by: -.pi / 2)
        case .up, .upMirrored:
            break
        }

        switch orientation {
        case .upMirrored, .downMirrored:
            transform = transform.translatedBy(x: canvasWidth, y: 0).scaledBy(x: -1, y: 1)
        case .leftMirrored, .rightMirrored:
            transform = transform.translatedBy(x: canvasHeight, y: 0).scaledBy(x: -1, y: 1)
        default:
            break
        }

        return transform
    }
}
