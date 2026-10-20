#!/usr/bin/env swift

import AppKit
import Foundation

private let width = 402
private let height = 874
private let ignoredTopRows = 48
/// Mask luminance at or above this value (white = ignore) skips grading.
private let maskIgnoreLuminance = 240.0
private let inkLuminance = 200.0

private struct Options {
    let target: URL
    let actual: URL
    let diff: URL
    let mask: URL?
    let threshold: Double
}

private struct Scores {
    let composite: Double
    let position: Double
    let size: Double
    let color: Double
    let fontStyle: Double
    let edgeF1: Double
    let appearanceSimilarity: Double
}

private enum ParityError: Error, CustomStringConvertible {
    case usage
    case unreadableImage(URL)
    case unexpectedDimensions(URL, width: Int, height: Int, expectation: String)
    case cannotCreateBitmap
    case cannotWriteDiff(URL)

    var description: String {
        switch self {
        case .usage:
            return "usage: VisualParity.swift --target target.png --actual actual.png --diff diff.png [--mask mask.png] [--threshold 0.90]"
        case let .unreadableImage(url):
            return "could not read image: \(url.path)"
        case let .unexpectedDimensions(url, actualWidth, actualHeight, expectation):
            return "expected \(expectation), found \(actualWidth)x\(actualHeight): \(url.path)"
        case .cannotCreateBitmap:
            return "could not create bitmap"
        case let .cannotWriteDiff(url):
            return "could not write diff: \(url.path)"
        }
    }
}

private func parseOptions() throws -> Options {
    var values: [String: String] = [:]
    var index = 1
    while index + 1 < CommandLine.arguments.count {
        values[CommandLine.arguments[index]] = CommandLine.arguments[index + 1]
        index += 2
    }

    guard
        let target = values["--target"],
        let actual = values["--actual"],
        let diff = values["--diff"]
    else {
        throw ParityError.usage
    }

    return Options(
        target: URL(fileURLWithPath: target),
        actual: URL(fileURLWithPath: actual),
        diff: URL(fileURLWithPath: diff),
        mask: values["--mask"].map(URL.init(fileURLWithPath:)),
        threshold: Double(values["--threshold"] ?? "0.90") ?? 0.90
    )
}

private func strictRGBA(
    from url: URL,
    allowedPixelScales: ClosedRange<Int>
) throws -> [UInt8] {
    guard
        let image = NSImage(contentsOf: url),
        let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else {
        throw ParityError.unreadableImage(url)
    }
    guard
        source.width.isMultiple(of: width),
        source.height.isMultiple(of: height)
    else {
        throw ParityError.unexpectedDimensions(
            url,
            width: source.width,
            height: source.height,
            expectation: "\(width)x\(height) at an allowed uniform pixel scale"
        )
    }

    let horizontalScale = source.width / width
    let verticalScale = source.height / height
    guard
        horizontalScale == verticalScale,
        allowedPixelScales.contains(horizontalScale)
    else {
        throw ParityError.unexpectedDimensions(
            url,
            width: source.width,
            height: source.height,
            expectation: "\(width)x\(height) at a uniform \(allowedPixelScales) pixel scale"
        )
    }

    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let colorSpace = CGColorSpaceCreateDeviceRGB()

    let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
        guard let context = CGContext(
            data: bytes.baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return false
        }

        context.interpolationQuality = .high
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }

    guard rendered else {
        throw ParityError.cannotCreateBitmap
    }
    return pixels
}

private func luminance(_ pixels: [UInt8], x: Int, y: Int) -> Double {
    let offset = (y * width + x) * 4
    return 0.2126 * Double(pixels[offset])
        + 0.7152 * Double(pixels[offset + 1])
        + 0.0722 * Double(pixels[offset + 2])
}

private func gradient(_ pixels: [UInt8], x: Int, y: Int) -> Double {
    guard x > 0, x < width - 1, y > 0, y < height - 1 else {
        return 0
    }
    let horizontal = luminance(pixels, x: x + 1, y: y) - luminance(pixels, x: x - 1, y: y)
    let vertical = luminance(pixels, x: x, y: y + 1) - luminance(pixels, x: x, y: y - 1)
    return hypot(horizontal, vertical)
}

private func isIgnored(_ mask: [UInt8]?, x: Int, y: Int) -> Bool {
    if y < ignoredTopRows {
        return true
    }
    guard let mask else {
        return false
    }
    // White = ignore (Apple Maps surface). Black = graded chrome and pins.
    return luminance(mask, x: x, y: y) >= maskIgnoreLuminance
}

private func hasEdge(
    _ edgeMap: [Bool],
    nearX x: Int,
    y: Int,
    radius: Int = 2
) -> Bool {
    for candidateY in max(ignoredTopRows, y - radius)...min(height - 1, y + radius) {
        for candidateX in max(0, x - radius)...min(width - 1, x + radius) {
            if edgeMap[candidateY * width + candidateX] {
                return true
            }
        }
    }
    return false
}

private func profileDistance(_ left: [Double], _ right: [Double]) -> Double {
    var total = 0.0
    for index in 0..<left.count {
        total += abs(left[index] - right[index])
    }
    return min(1, total / 2)
}

private func writeDiff(
    target: [UInt8],
    actual: [UInt8],
    mask: [UInt8]?,
    to url: URL
) throws {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: width * 4,
        bitsPerPixel: 32
    ) else {
        throw ParityError.cannotCreateBitmap
    }

    guard let destination = bitmap.bitmapData else {
        throw ParityError.cannotCreateBitmap
    }
    for y in 0..<height {
        for x in 0..<width {
            let pixel = y * width + x
            let offset = pixel * 4
            if isIgnored(mask, x: x, y: y) {
                destination[offset] = 210
                destination[offset + 1] = 210
                destination[offset + 2] = 210
                destination[offset + 3] = 255
                continue
            }
            let difference = (
                abs(Int(target[offset]) - Int(actual[offset]))
                    + abs(Int(target[offset + 1]) - Int(actual[offset + 1]))
                    + abs(Int(target[offset + 2]) - Int(actual[offset + 2]))
            ) / 3

            destination[offset] = UInt8(clamping: difference * 3)
            destination[offset + 1] = UInt8(clamping: 30 + difference / 3)
            destination[offset + 2] = UInt8(clamping: 255 - min(220, difference * 2))
            destination[offset + 3] = 255
        }
    }

    guard
        let data = bitmap.representation(using: .png, properties: [:]),
        (try? data.write(to: url)) != nil
    else {
        throw ParityError.cannotWriteDiff(url)
    }
}

private func score(target: [UInt8], actual: [UInt8], mask: [UInt8]?) -> Scores {
    let edgeThreshold = 18.0
    var targetEdges = [Bool](repeating: false, count: width * height)
    var actualEdges = [Bool](repeating: false, count: width * height)
    var targetRows = [Double](repeating: 0, count: height)
    var actualRows = [Double](repeating: 0, count: height)
    var targetCols = [Double](repeating: 0, count: width)
    var actualCols = [Double](repeating: 0, count: width)
    var targetBins = [Double](repeating: 0, count: 8)
    var actualBins = [Double](repeating: 0, count: 8)

    for y in 0..<height {
        for x in 0..<width {
            if isIgnored(mask, x: x, y: y) {
                continue
            }
            let index = y * width + x
            targetEdges[index] = gradient(target, x: x, y: y) >= edgeThreshold
            actualEdges[index] = gradient(actual, x: x, y: y) >= edgeThreshold
        }
    }

    var targetEdgeCount = 0
    var actualEdgeCount = 0
    var matchedTargetEdges = 0
    var matchedActualEdges = 0
    var totalDifference = 0.0
    var comparedPixelCount = 0
    var targetInk = 0.0
    var actualInk = 0.0

    for y in 0..<height {
        for x in 0..<width {
            if isIgnored(mask, x: x, y: y) {
                continue
            }
            let pixel = y * width + x
            let offset = pixel * 4

            if targetEdges[pixel] {
                targetEdgeCount += 1
                if hasEdge(actualEdges, nearX: x, y: y) {
                    matchedTargetEdges += 1
                }
            }
            if actualEdges[pixel] {
                actualEdgeCount += 1
                if hasEdge(targetEdges, nearX: x, y: y) {
                    matchedActualEdges += 1
                }
            }

            let difference = (
                abs(Double(target[offset]) - Double(actual[offset]))
                    + abs(Double(target[offset + 1]) - Double(actual[offset + 1]))
                    + abs(Double(target[offset + 2]) - Double(actual[offset + 2]))
            ) / (3.0 * 255.0)

            totalDifference += difference
            comparedPixelCount += 1

            let targetInkPixel = luminance(target, x: x, y: y) < inkLuminance
            let actualInkPixel = luminance(actual, x: x, y: y) < inkLuminance
            if targetInkPixel {
                targetRows[y] += 1
                targetCols[x] += 1
                targetInk += 1
                let bin = min(7, Int(gradient(target, x: x, y: y) / 32))
                targetBins[bin] += 1
            }
            if actualInkPixel {
                actualRows[y] += 1
                actualCols[x] += 1
                actualInk += 1
                let bin = min(7, Int(gradient(actual, x: x, y: y) / 32))
                actualBins[bin] += 1
            }
        }
    }

    if targetInk > 0 {
        for index in 0..<height { targetRows[index] /= targetInk }
        for index in 0..<width { targetCols[index] /= targetInk }
        for index in 0..<8 { targetBins[index] /= targetInk }
    }
    if actualInk > 0 {
        for index in 0..<height { actualRows[index] /= actualInk }
        for index in 0..<width { actualCols[index] /= actualInk }
        for index in 0..<8 { actualBins[index] /= actualInk }
    }

    let recall = targetEdgeCount == 0 ? 1 : Double(matchedTargetEdges) / Double(targetEdgeCount)
    let precision = actualEdgeCount == 0 ? 1 : Double(matchedActualEdges) / Double(actualEdgeCount)
    let edgeF1 = recall + precision == 0 ? 0 : 2 * recall * precision / (recall + precision)
    let appearanceSimilarity = comparedPixelCount == 0
        ? 1
        : 1 - totalDifference / Double(comparedPixelCount)
    let position = edgeF1
    let size = 1 - (
        profileDistance(targetRows, actualRows) + profileDistance(targetCols, actualCols)
    ) / 2
    let color = appearanceSimilarity
    let fontStyle = 1 - profileDistance(targetBins, actualBins)
    let gradedComposite = (position + size + color + fontStyle) / 4
    let legacyComposite = 0.35 * edgeF1 + 0.65 * appearanceSimilarity
    let composite = mask == nil ? legacyComposite : gradedComposite

    return Scores(
        composite: composite,
        position: position,
        size: size,
        color: color,
        fontStyle: fontStyle,
        edgeF1: edgeF1,
        appearanceSimilarity: appearanceSimilarity
    )
}

do {
    let options = try parseOptions()
    let target = try strictRGBA(from: options.target, allowedPixelScales: 1...1)
    let actual = try strictRGBA(from: options.actual, allowedPixelScales: 1...4)
    let mask = try options.mask.map { try strictRGBA(from: $0, allowedPixelScales: 1...1) }
    let result = score(target: target, actual: actual, mask: mask)
    try writeDiff(target: target, actual: actual, mask: mask, to: options.diff)

    let payload: [String: Any] = [
        "target": options.target.path,
        "actual": options.actual.path,
        "diff": options.diff.path,
        "mask": options.mask?.path ?? "",
        "composite": result.composite,
        "position": result.position,
        "size": result.size,
        "color": result.color,
        "fontStyle": result.fontStyle,
        "edgeF1": result.edgeF1,
        "appearanceSimilarity": result.appearanceSimilarity,
        "threshold": options.threshold,
        "passed": result.composite >= options.threshold
    ]
    let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: data, as: UTF8.self))
    exit(result.composite >= options.threshold ? 0 : 1)
} catch {
    fputs("\(error)\n", stderr)
    exit(2)
}
