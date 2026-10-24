import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ResidentPhoto {
    /// Decode a bounded thumbnail and re-encode only its pixels. Original EXIF/GPS is never copied.
    public static func thumbnail(_ data: Data) throws -> Data {
        guard data.count <= 20_000_000, let source = CGImageSourceCreateWithData(data as CFData, nil) else { throw RelayError.invalid("Choose an image smaller than 20 MB.") }
        for size in [256, 128] {
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: size,
                kCGImageSourceShouldCacheImmediately: true]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw RelayError.invalid("This image could not be opened. Choose another photo.") }
            for quality in [0.75, 0.5, 0.25] {
                let output = NSMutableData()
                guard let writer = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { throw RelayError.invalid("Could not prepare the profile photo.") }
                CGImageDestinationAddImage(writer, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
                if CGImageDestinationFinalize(writer), output.length <= 24_000 { return output as Data }
            }
        }
        throw RelayError.invalid("This photo is too detailed. Choose a smaller image.")
    }
}
