import Foundation
import ImageIO
import UniformTypeIdentifiers

enum Thumbnail {
    /// JPEG data for a grid tile: longest side `maxPixel`, EXIF orientation applied.
    /// 200 px is a 100 pt tile at 2x. nil if the file is not a decodable image.
    static func data(from file: URL, maxPixel: Int = 200) -> Data? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        let output = NSMutableData()
        guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}
