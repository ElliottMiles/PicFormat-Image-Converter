//
//  WebPEncoder.swift
//  Good_Image_Converter
//
//  iOS has no first-party WebP encoder — ImageIO can only *decode* WebP.
//  Producing WebP output requires linking libwebp, which isn't something
//  that can be pulled in without network access to resolve a Swift
//  Package. This file is the single seam where that support plugs in.
//
//  TO ENABLE WEBP OUTPUT:
//  1. In Xcode: File > Add Package Dependencies…
//     URL: https://github.com/SDWebImage/libwebp
//     (a maintained, dependency-free SPM mirror of Google's libwebp C
//     library — no networking or telemetry, pure local codec)
//  2. Add the "libwebp" product to the Good_Image_Converter target.
//  3. Add `import libwebp` below and replace the body of `encode(...)`
//     with a call to WebPEncodeRGBA / WebPEncodeLosslessRGBA, e.g.:
//
//       var outputBuffer: UnsafeMutablePointer<UInt8>?
//       let size = WebPEncodeRGBA(rgbaBytes, width, height, stride,
//                                  quality, &outputBuffer)
//       guard size > 0, let outputBuffer else { return nil }
//       defer { WebPFree(outputBuffer) }
//       return Data(bytes: outputBuffer, count: size)
//
//  4. Flip `isAvailable` to `true`.
//
//  Once that's done, WebP will automatically appear as an output option —
//  FormatCapabilityService reads `isAvailable` from here, nothing else
//  needs to change.
//

import CoreGraphics
import Foundation

enum WebPEncoder {
    /// Flip to `true` once libwebp is linked (see instructions above).
    nonisolated static let isAvailable = false

    /// Encodes `image` to WebP. `quality` is 0...1, where 1.0 requests a
    /// lossless encode and anything lower requests lossy encoding at that
    /// quality factor.
    nonisolated static func encode(_ image: CGImage, quality: CGFloat) -> Data? {
        // Not linked in this build — see the instructions above.
        nil
    }
}
