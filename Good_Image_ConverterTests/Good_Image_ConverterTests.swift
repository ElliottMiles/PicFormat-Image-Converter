//
//  Good_Image_ConverterTests.swift
//  Good_Image_ConverterTests
//

import Testing
import Foundation
import CoreGraphics
import ImageIO
@testable import Good_Image_Converter

// MARK: - ImageOrientationNormalizer

@Suite("ImageOrientationNormalizer")
struct ImageOrientationNormalizerTests {

    private struct Pixel: Equatable, CustomStringConvertible {
        let r, g, b, a: UInt8
        var description: String { "(\(r),\(g),\(b),\(a))" }
    }

    private static let red = Pixel(r: 255, g: 0, b: 0, a: 255)
    private static let green = Pixel(r: 0, g: 255, b: 0, a: 255)
    private static let blue = Pixel(r: 0, g: 0, b: 255, a: 255)
    private static let yellow = Pixel(r: 255, g: 255, b: 0, a: 255)
    private static let gray = Pixel(r: 128, g: 128, b: 128, a: 255)

    // Deliberately non-square (4x2) so a bug that fails to swap
    // width/height for the transposing orientations (left/leftMirrored/
    // right/rightMirrored) is caught by a dimension mismatch, not just a
    // pixel mismatch. Each corner gets a distinct color — a solid-color
    // image can't distinguish a correct transform from a
    // transposed/mirrored one.
    private static let sourceWidth = 4
    private static let sourceHeight = 2

    private struct Case {
        let orientation: CGImagePropertyOrientation
        let expectedWidth: Int
        let expectedHeight: Int
        let topLeft: Pixel
        let topRight: Pixel
        let bottomLeft: Pixel
        let bottomRight: Pixel
    }

    // Ground truth derived from Apple's documented per-value semantics
    // (CGImagePropertyOrientation: "0th row is at <side>, 0th column is
    // at <side>") applied to the corner colors below, independent of
    // this file's own implementation under test.
    private static let cases: [Case] = [
        Case(orientation: .up, expectedWidth: sourceWidth, expectedHeight: sourceHeight,
             topLeft: red, topRight: green, bottomLeft: blue, bottomRight: yellow),
        Case(orientation: .upMirrored, expectedWidth: sourceWidth, expectedHeight: sourceHeight,
             topLeft: green, topRight: red, bottomLeft: yellow, bottomRight: blue),
        Case(orientation: .down, expectedWidth: sourceWidth, expectedHeight: sourceHeight,
             topLeft: yellow, topRight: blue, bottomLeft: green, bottomRight: red),
        Case(orientation: .downMirrored, expectedWidth: sourceWidth, expectedHeight: sourceHeight,
             topLeft: blue, topRight: yellow, bottomLeft: red, bottomRight: green),
        Case(orientation: .leftMirrored, expectedWidth: sourceHeight, expectedHeight: sourceWidth,
             topLeft: red, topRight: blue, bottomLeft: green, bottomRight: yellow),
        Case(orientation: .right, expectedWidth: sourceHeight, expectedHeight: sourceWidth,
             topLeft: blue, topRight: red, bottomLeft: yellow, bottomRight: green),
        Case(orientation: .rightMirrored, expectedWidth: sourceHeight, expectedHeight: sourceWidth,
             topLeft: yellow, topRight: green, bottomLeft: blue, bottomRight: red),
        Case(orientation: .left, expectedWidth: sourceHeight, expectedHeight: sourceWidth,
             topLeft: green, topRight: yellow, bottomLeft: red, bottomRight: blue),
    ]

    private static func makeAsymmetricImage() -> CGImage {
        let width = sourceWidth
        let height = sourceHeight
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!

        let buffer = context.data!.assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = context.bytesPerRow
        for y in 0..<height {
            for x in 0..<width {
                let pixel: Pixel
                switch (x, y) {
                case (0, 0): pixel = red
                case (width - 1, 0): pixel = green
                case (0, height - 1): pixel = blue
                case (width - 1, height - 1): pixel = yellow
                default: pixel = gray
                }
                let offset = y * bytesPerRow + x * 4
                buffer[offset] = pixel.r
                buffer[offset + 1] = pixel.g
                buffer[offset + 2] = pixel.b
                buffer[offset + 3] = pixel.a
            }
        }

        return context.makeImage()!
    }

    private static func pixel(of image: CGImage, x: Int, y: Int) -> Pixel {
        let data = image.dataProvider!.data! as Data
        let bytesPerRow = image.bytesPerRow
        let bytesPerPixel = image.bitsPerPixel / 8
        let offset = y * bytesPerRow + x * bytesPerPixel
        return Pixel(r: data[offset], g: data[offset + 1], b: data[offset + 2], a: data[offset + 3])
    }

    @Test func normalizeProducesCorrectPixelsForEveryOrientation() {
        let source = Self.makeAsymmetricImage()

        for testCase in Self.cases {
            let result = ImageOrientationNormalizer.normalize(source, orientation: testCase.orientation)

            #expect(result.width == testCase.expectedWidth, "\(testCase.orientation) width")
            #expect(result.height == testCase.expectedHeight, "\(testCase.orientation) height")

            #expect(Self.pixel(of: result, x: 0, y: 0) == testCase.topLeft,
                     "\(testCase.orientation) top-left")
            #expect(Self.pixel(of: result, x: result.width - 1, y: 0) == testCase.topRight,
                     "\(testCase.orientation) top-right")
            #expect(Self.pixel(of: result, x: 0, y: result.height - 1) == testCase.bottomLeft,
                     "\(testCase.orientation) bottom-left")
            #expect(Self.pixel(of: result, x: result.width - 1, y: result.height - 1) == testCase.bottomRight,
                     "\(testCase.orientation) bottom-right")
        }
    }

    @Test func normalizeSkipsRedrawWhenAlreadyUpright() {
        let source = Self.makeAsymmetricImage()
        let result = ImageOrientationNormalizer.normalize(source, orientation: .up)
        #expect(result === source)
    }
}

// MARK: - FileExportService

@Suite("FileExportService.sanitize")
struct FileExportServiceSanitizeTests {

    @Test(arguments: ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"])
    func replacesEachForbiddenCharacterWithDash(character: String) {
        let name = "a\(character)b"
        #expect(FileExportService.sanitize(name) == "a-b")
    }

    @Test func emptyInputFallsBackToDefaultName() {
        #expect(FileExportService.sanitize("") == "Converted Image")
    }

    @Test func whitespaceOnlyInputFallsBackToDefaultName() {
        #expect(FileExportService.sanitize("   ") == "Converted Image")
    }

    @Test func alreadyCleanNameIsUnchanged() {
        #expect(FileExportService.sanitize("My Photo 2024") == "My Photo 2024")
    }

    @Test func trimsSurroundingWhitespace() {
        #expect(FileExportService.sanitize("  vacation  ") == "vacation")
    }
}

@Suite("FileExportService.filenames")
struct FileExportServiceFilenamesTests {

    @Test func singleImageHasNoNumericSuffix() {
        let names = FileExportService.filenames(baseName: "vacation", count: 1, extension: "jpg")
        #expect(names == ["vacation.jpg"])
    }

    @Test func multiImageNumbersSequentiallyFromOne() {
        let names = FileExportService.filenames(baseName: "vacation", count: 3, extension: "png")
        #expect(names == ["vacation-1.png", "vacation-2.png", "vacation-3.png"])
    }

    @Test func singleImageSanitizesBaseName() {
        let names = FileExportService.filenames(baseName: "my/trip", count: 1, extension: "jpg")
        #expect(names == ["my-trip.jpg"])
    }

    @Test func multiImageSanitizesBaseName() {
        let names = FileExportService.filenames(baseName: "my:trip", count: 2, extension: "png")
        #expect(names == ["my-trip-1.png", "my-trip-2.png"])
    }
}
