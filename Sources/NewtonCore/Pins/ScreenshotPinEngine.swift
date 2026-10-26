// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Lucas Despot

import Foundation
import CoreGraphics

public struct PinnedItem: Identifiable, Sendable, Equatable {
    public let id: UUID
    public var title: String
    public var imagePath: String?
    public var timestamp: Date
    public var opacity: Double
    public var width: CGFloat
    public var height: CGFloat

    public init(
        id: UUID = UUID(),
        title: String,
        imagePath: String? = nil,
        timestamp: Date = Date(),
        opacity: Double = 1.0,
        width: CGFloat = 360,
        height: CGFloat = 240
    ) {
        self.id = id
        self.title = title
        self.imagePath = imagePath
        self.timestamp = timestamp
        self.opacity = opacity
        self.width = width
        self.height = height
    }
}

public final class ScreenshotPinEngine: @unchecked Sendable {
    public static let shared = ScreenshotPinEngine()

    private let lock = NSLock()
    private var _pins: [PinnedItem] = []

    public var pins: [PinnedItem] {
        lock.lock()
        defer { lock.unlock() }
        return _pins
    }

    public init() {}

    public func addPin(title: String, imagePath: String? = nil, width: CGFloat = 360, height: CGFloat = 240) -> PinnedItem {
        lock.lock()
        defer { lock.unlock() }
        let item = PinnedItem(title: title, imagePath: imagePath, width: width, height: height)
        _pins.append(item)
        return item
    }

    public func removePin(id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        _pins.removeAll { $0.id == id }
    }

    public func setOpacity(id: UUID, opacity: Double) {
        lock.lock()
        defer { lock.unlock() }
        if let idx = _pins.firstIndex(where: { $0.id == id }) {
            _pins[idx].opacity = max(0.1, min(1.0, opacity))
        }
    }

    public static func calculateAspectRatioFit(width: CGFloat, height: CGFloat, maxDimension: CGFloat = 500) -> CGSize {
        guard width > 0, height > 0 else {
            return CGSize(width: 320, height: 200)
        }
        let ratio = min(maxDimension / width, maxDimension / height)
        let fitRatio = min(1.0, ratio)
        return CGSize(width: max(120, width * fitRatio), height: max(80, height * fitRatio))
    }
}
