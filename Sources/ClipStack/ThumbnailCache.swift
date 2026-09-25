import AppKit

/// Decoding a full screenshot for every visible row would make scrolling
/// stutter, so thumbnails are downsampled once and kept by clip id.
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache = NSCache<NSNumber, NSImage>()

    private init() {
        cache.countLimit = 300
        cache.totalCostLimit = 32 * 1_048_576
    }

    func thumbnail(for clip: Clip, maxSide: CGFloat = 128) -> NSImage? {
        guard clip.kind == .image, clip.hasBlob else { return nil }
        let key = NSNumber(value: clip.id)
        if let hit = cache.object(forKey: key) { return hit }

        guard let blob = clip.loadBlob(),
              let source = CGImageSourceCreateWithData(blob as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide * 2, // retina
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }

        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width / 2, height: cg.height / 2))
        cache.setObject(image, forKey: key, cost: cg.width * cg.height * 4)
        return image
    }

    // MARK: Custom favorite icons

    private let icons = NSCache<NSNumber, NSImage>()

    func customIcon(for clip: Clip) -> NSImage? {
        guard clip.hasCustomIcon else { return nil }
        let key = NSNumber(value: clip.id)
        if let hit = icons.object(forKey: key) { return hit }
        guard let data = Store.shared.customIcon(for: clip.id),
              let image = NSImage(data: data) else { return nil }
        icons.setObject(image, forKey: key, cost: data.count)
        return image
    }

    func dropCustomIcon(id: Int64) { icons.removeObject(forKey: NSNumber(value: id)) }

    func drop(id: Int64) { cache.removeObject(forKey: NSNumber(value: id)) }
    func dropAll() {
        cache.removeAllObjects()
        icons.removeAllObjects()
    }
}
