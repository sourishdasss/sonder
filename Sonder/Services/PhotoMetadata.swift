import CoreLocation
import Foundation
import ImageIO
import UIKit

/// Reads location and capture date from a photo's EXIF data, entirely on-device.
/// Only the resolved coordinate, place name and date are ever uploaded; raw EXIF is discarded
/// when the image is re-encoded.
enum PhotoMetadata {
    struct Info: Equatable {
        var coordinate: CLLocationCoordinate2D?
        var takenAt: Date?

        static func == (lhs: Info, rhs: Info) -> Bool {
            lhs.takenAt == rhs.takenAt
                && lhs.coordinate?.latitude == rhs.coordinate?.latitude
                && lhs.coordinate?.longitude == rhs.coordinate?.longitude
        }
    }

    static func read(from imageData: Data) -> Info {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return Info()
        }
        return Info(coordinate: coordinate(in: properties), takenAt: captureDate(in: properties))
    }

    static func coordinate(in properties: [String: Any]) -> CLLocationCoordinate2D? {
        guard let gps = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any],
              let latitude = (gps[kCGImagePropertyGPSLatitude as String] as? NSNumber)?.doubleValue,
              let longitude = (gps[kCGImagePropertyGPSLongitude as String] as? NSNumber)?.doubleValue else {
            return nil
        }
        let latitudeRef = (gps[kCGImagePropertyGPSLatitudeRef as String] as? String)?.uppercased()
        let longitudeRef = (gps[kCGImagePropertyGPSLongitudeRef as String] as? String)?.uppercased()
        let coordinate = CLLocationCoordinate2D(
            latitude: latitudeRef == "S" ? -abs(latitude) : latitude,
            longitude: longitudeRef == "W" ? -abs(longitude) : longitude
        )
        guard CLLocationCoordinate2DIsValid(coordinate),
              !(coordinate.latitude == 0 && coordinate.longitude == 0) else { return nil }
        return coordinate
    }

    static func captureDate(in properties: [String: Any]) -> Date? {
        guard let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any],
              let raw = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: raw)
    }

    /// Downscales and re-encodes a photo as JPEG for upload (also strips its metadata).
    static func preparedJPEG(from imageData: Data, maxDimension: CGFloat = 1600, quality: CGFloat = 0.8) -> Data? {
        guard let image = UIImage(data: imageData) else { return nil }
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxDimension ? maxDimension / longest : 1
        let target = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        guard target.width > 0, target.height > 0 else { return nil }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return rendered.jpegData(compressionQuality: quality)
    }
}
