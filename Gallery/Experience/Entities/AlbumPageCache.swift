import RealityKit
import UIKit

@MainActor
struct AlbumPageMaterials {
    let left: UnlitMaterial
    let right: UnlitMaterial
}

/// Keeps only the current spread and its immediate neighbors. Requests may
/// download progressively, but texture work is paused while a sheet is moving.
@MainActor
final class AlbumPageCache {
    private final class Entry {
        let page: PhotoPage
        var images: [UIImage?]
        var materials: AlbumPageMaterials?
        var finished = false
        var unavailable = false
        var dirty = true
        var request: Task<Void, Never>?
        var render: Task<Void, Never>?
        var waiters: [UUID: CheckedContinuation<AlbumPageMaterials?, Never>] = [:]

        init(page: PhotoPage) {
            self.page = page
            images = Array(repeating: nil, count: page.photos.count)
        }

        func resumeWaiters(_ materials: AlbumPageMaterials?) {
            let pending = Array(waiters.values)
            waiters.removeAll()
            for waiter in pending { waiter.resume(returning: materials) }
        }

        func cancel() {
            request?.cancel()
            render?.cancel()
            resumeWaiters(nil)
        }
    }

    var onUpdate: ((Int) -> Void)?
    private var entries: [Int: Entry] = [:]
    private var pages: [PhotoPage] = []
    private var title = ""
    private var animationActive = false
    private let thumbnails = PhotoThumbnailCache()

    func configure(title: String, pages: [PhotoPage]) {
        clear()
        self.title = title
        self.pages = pages
    }

    func clear() {
        for entry in entries.values { entry.cancel() }
        entries.removeAll()
        pages = []
        animationActive = false
        thumbnails.stopAllCaching()
    }

    func keepWindow(around index: Int) {
        let wanted = Set([index - 1, index, index + 1].filter { $0 > 0 && $0 <= pages.count })
        for key in Array(entries.keys) where !wanted.contains(key) {
            entries.removeValue(forKey: key)?.cancel()
        }
        // Start the requested spread before its neighbors.
        for key in [index, index + 1, index - 1] where wanted.contains(key) {
            if entries[key] == nil { start(key) }
        }
    }

    func materials(at index: Int) -> AlbumPageMaterials? { entries[index]?.materials }
    func hasUnavailablePhotos(at index: Int) -> Bool { entries[index]?.unavailable ?? false }

    func setAnimationActive(_ active: Bool) {
        animationActive = active
        if !active {
            for (index, entry) in entries where entry.dirty { scheduleRender(entry, at: index) }
        }
    }

    func retry(_ index: Int) {
        entries.removeValue(forKey: index)?.cancel()
        if index > 0 && index <= pages.count { start(index) }
    }

    func preparedMaterials(at index: Int) async -> AlbumPageMaterials? {
        guard !Task.isCancelled, let entry = entries[index] else { return nil }
        if let materials = entry.materials { return materials }
        if entry.finished && entry.unavailable && !entry.dirty { return nil }
        let token = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(returning: nil)
                    return
                }
                entry.waiters[token] = continuation
            }
        } onCancel: {
            Task { @MainActor in entry.waiters.removeValue(forKey: token)?.resume(returning: nil) }
        }
    }

    private func start(_ index: Int) {
        let entry = Entry(page: pages[index - 1])
        entries[index] = entry
        entry.request = Task { [weak self, weak entry] in
            guard let self, let entry else { return }
            async let first = self.fetch(entry, index: index, slot: 0)
            async let second = self.fetch(entry, index: index, slot: 1)
            let results = await (first, second)
            guard !Task.isCancelled, self.entries[index] === entry else { return }
            entry.finished = true
            entry.unavailable = results.0 == nil || (entry.images.count > 1 && results.1 == nil)
            entry.request = nil
            entry.dirty = true
            self.scheduleRender(entry, at: index)
            self.onUpdate?(index)
        }
    }

    private func fetch(_ entry: Entry, index: Int, slot: Int) async -> UIImage? {
        guard entry.page.photos.indices.contains(slot) else { return nil }
        return await thumbnails.thumbnail(for: entry.page.photos[slot].id,
                                           targetSize: GalleryConfig.albumPhotoTargetSize) { [weak self, weak entry] image in
            guard let self, let entry, self.entries[index] === entry else { return }
            entry.images[slot] = image
            entry.dirty = true
            // Don't rasterize an empty spread after every individual callback.
            if entry.images.allSatisfy({ $0 != nil }) { self.scheduleRender(entry, at: index) }
        }
    }

    private func scheduleRender(_ entry: Entry, at index: Int) {
        guard !animationActive, entry.dirty, entry.render == nil,
              entry.finished || entry.images.allSatisfy({ $0 != nil }) else { return }
        entry.render = Task { [weak self, weak entry] in
            // Coalesce opportunistic callbacks and both photos into one upload.
            do { try await Task.sleep(for: .milliseconds(60)) } catch { return }
            guard let self, let entry, self.entries[index] === entry else { return }
            entry.render = nil
            guard !self.animationActive, !Task.isCancelled else { return }
            entry.dirty = false
            do {
                let left = PhotoPageRenderer.leafImage(title: self.title, page: entry.page,
                                                      slot: 0, images: entry.images, loading: false)
                let right = PhotoPageRenderer.leafImage(title: self.title, page: entry.page,
                                                       slot: 1, images: entry.images, loading: false)
                let materials = AlbumPageMaterials(left: try Self.material(for: left),
                                                   right: try Self.material(for: right))
                entry.materials = materials
                entry.resumeWaiters(materials)
            } catch {
                entry.unavailable = true
                entry.resumeWaiters(nil)
                print("Could not prepare album page: \(error)")
            }
            self.onUpdate?(index)
        }
    }

    private static func material(for image: UIImage) throws -> UnlitMaterial {
        guard let cgImage = image.cgImage else { return UnlitMaterial(color: .white) }
        let texture = try TextureResource(image: cgImage, options: .init(semantic: .color))
        var material = UnlitMaterial()
        material.color = .init(tint: .white, texture: .init(texture))
        material.faceCulling = .back
        return material
    }
}
