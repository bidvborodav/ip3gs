# Task 4: Downsampled thumbnails (optional — see judgement calls)

**Files:** create `Sources/ip3gs/Thumbnail.swift`, `Tests/ip3gsTests/ThumbnailTests.swift`;
modify `PhotoLibrary.swift` (one line) and `PhotoLibraryTests.swift` (fixture bytes).

- [x] **Step 1: Implement.**

```swift
import AppKit
import ImageIO
import UniformTypeIdentifiers

enum Thumbnail {
    /// JPEG data for a grid tile: longest side `maxPixel`, EXIF orientation applied.
    /// 200 px = a 100 pt tile at 2x. nil if the file is not a decodable image.
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
```

- [x] **Step 2: Use it** in `PhotoLibrary.refresh()`: replace `try? Data(contentsOf: $0)` with
  `Thumbnail.data(from: $0)`. The fake bridge in `PhotoLibraryTests` must now write a real JPEG
  (generate a 400x300 one with `NSBitmapImageRep`/`CGContext` in a test helper) instead of
  `Data([0x01])`.

- [x] **Step 3: Test.** Generate a 1000x500 JPEG into a temp file; `Thumbnail.data(from:)` returns
  data that decodes (`CGImageSourceCreateWithData`) to an image whose longer side is `<= 200` and
  whose aspect ratio is ~2:1; a text file returns nil.
- [x] **Step 4: Run the full unit suite**, then commit `feat: downsample grid thumbnails to 200 px`.

Back to the [milestone 2 plan](README.md).
