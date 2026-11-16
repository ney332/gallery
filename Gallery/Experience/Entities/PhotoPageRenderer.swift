import UIKit

@MainActor
enum PhotoPageRenderer {
    /// One photo per face. An odd final photo leaves the other face as plain paper.
    static func leafImage(title: String, page: PhotoPage, slot: Int, images: [UIImage?], loading: Bool) -> UIImage {
        let layoutSize = CGSize(width: 600, height: 780)
        let pixelScale = (GalleryConfig.albumPageTextureWidth / 2) / layoutSize.width
        let size = CGSize(width: layoutSize.width * pixelScale, height: layoutSize.height * pixelScale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            context.cgContext.scaleBy(x: pixelScale, y: pixelScale)
            context.cgContext.interpolationQuality = .high
            UIColor(red: 0.97, green: 0.95, blue: 0.9, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: layoutSize))
            guard page.photos.indices.contains(slot) else { return }
            drawText(title, rect: CGRect(x: 30, y: 25, width: 540, height: 48), size: 24)
            let rect = CGRect(x: 40, y: 92, width: 520, height: 610)
            UIColor.white.setFill()
            context.fill(rect.insetBy(dx: -8, dy: -8))
            if images.indices.contains(slot), let image = images[slot], image.size.width > 0, image.size.height > 0 {
                let scale = min(rect.width / image.size.width, rect.height / image.size.height)
                let fitted = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                image.draw(in: CGRect(x: rect.midX - fitted.width / 2, y: rect.midY - fitted.height / 2,
                                      width: fitted.width, height: fitted.height))
            } else {
                let text = loading ? String(localized: "album.loading") : String(localized: "album.photo.unavailable")
                drawText(text, rect: CGRect(x: 60, y: rect.midY - 40, width: 480, height: 100), size: 24)
            }
            drawText("\((page.number - 1) * 2 + slot + 1)",
                     rect: CGRect(x: 240, y: 729, width: 120, height: 30), size: 20)
        }
    }

    private static func drawText(_ text: String, rect: CGRect, size: CGFloat) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        (text as NSString).draw(in: rect, withAttributes: [
            .font: UIFont.systemFont(ofSize: size), .foregroundColor: UIColor.darkGray, .paragraphStyle: paragraph
        ])
    }
}
