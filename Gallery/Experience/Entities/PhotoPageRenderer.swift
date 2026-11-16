import UIKit

@MainActor
enum PhotoPageRenderer {
    static func image(title: String, page: PhotoPage, images: [UIImage?], loading: Bool) -> UIImage {
        let layoutSize = CGSize(width: 1200, height: 950)
        let pixelScale = GalleryConfig.albumPageTextureWidth / layoutSize.width
        let size = CGSize(width: GalleryConfig.albumPageTextureWidth, height: layoutSize.height * pixelScale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            context.cgContext.scaleBy(x: pixelScale, y: pixelScale)
            context.cgContext.interpolationQuality = .high
            UIColor(red: 0.97, green: 0.95, blue: 0.9, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: layoutSize))
            drawText(title, rect: CGRect(x: 45, y: 28, width: 1110, height: 52), size: 30)
            for (index, _) in page.photos.enumerated() {
                let rect = CGRect(x: 48 + CGFloat(index) * 576, y: 115, width: 528, height: 725)
                UIColor.white.setFill()
                context.fill(rect.insetBy(dx: -10, dy: -10))
                if images.indices.contains(index), let image = images[index], image.size.width > 0, image.size.height > 0 {
                    let scale = min(rect.width / image.size.width, rect.height / image.size.height)
                    let fitted = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                    image.draw(in: CGRect(x: rect.midX - fitted.width / 2, y: rect.midY - fitted.height / 2,
                                          width: fitted.width, height: fitted.height))
                } else {
                    let text = loading ? String(localized: "album.loading") : String(localized: "album.photo.unavailable")
                    drawText(text, rect: CGRect(x: rect.minX + 20, y: rect.midY - 40, width: rect.width - 40, height: 100), size: 28)
                }
            }
            drawText("\(page.number)", rect: CGRect(x: 540, y: 885, width: 120, height: 40), size: 25)
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
