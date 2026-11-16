import Foundation
import SwiftData
import CoreLocation
import ImageIO
import UniformTypeIdentifiers
import AVFoundation
import UIKit

/// A photo or video from a trip, kept with the camp it was taken at.
/// The file lives in Documents/Memories (backed up with the phone); the model holds its name.
@Model
final class Memory {
    var id: UUID = UUID()
    var addedAt: Date = Date.now
    /// When it was taken (from the photo's own metadata when it has it).
    var takenAt: Date = Date.now
    var isVideo: Bool = false
    var fileName: String = ""
    var siteID: String?
    var siteName: String?
    var lat: Double?
    var lon: Double?
    /// What they were doing: one of PackActivity's raw values.
    var activity: String?
    var note: String = ""
    var trip: Trip?

    init(fileName: String, isVideo: Bool, takenAt: Date, coordinate: CLLocationCoordinate2D?) {
        self.fileName = fileName
        self.isVideo = isVideo
        self.takenAt = takenAt
        lat = coordinate?.latitude
        lon = coordinate?.longitude
    }

    var url: URL { MemoryFiles.directory.appending(path: fileName) }
    var coordinate: CLLocationCoordinate2D? {
        guard let lat, let lon else { return nil }
        return .init(latitude: lat, longitude: lon)
    }
}

/// Saving and reading memory files, and the metadata inside them.
enum MemoryFiles {
    static let directory: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appending(path: "Memories", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Saves a photo as a JPEG no larger than 2560 px on its long side (plenty for a 1080p recap),
    /// keeping when and where it was taken.
    static func savePhoto(_ data: Data) throws -> (fileName: String, takenAt: Date?, coordinate: CLLocationCoordinate2D?) {
        let meta = metadata(data)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true,
                  kCGImageSourceThumbnailMaxPixelSize: 2560,
              ] as CFDictionary),
              let jpeg = UIImage(cgImage: image).jpegData(compressionQuality: 0.85) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let name = "\(UUID().uuidString).jpg"
        try jpeg.write(to: directory.appending(path: name), options: .atomic)
        return (name, meta.date, meta.coordinate)
    }

    /// Moves a picked or recorded movie into the folder.
    static func saveVideo(from url: URL) async throws -> (fileName: String, takenAt: Date?, coordinate: CLLocationCoordinate2D?) {
        let name = "\(UUID().uuidString).\(url.pathExtension.isEmpty ? "mov" : url.pathExtension.lowercased())"
        let dest = directory.appending(path: name)
        try FileManager.default.copyItem(at: url, to: dest)
        let asset = AVURLAsset(url: dest)
        let date = try? await asset.load(.creationDate)?.load(.dateValue)
        var coordinate: CLLocationCoordinate2D?
        if let items = try? await asset.load(.metadata),
           let loc = AVMetadataItem.metadataItems(from: items, filteredByIdentifier: .quickTimeMetadataLocationISO6709).first,
           let iso = try? await loc.load(.stringValue) {
            coordinate = parseISO6709(iso)
        }
        return (name, date, coordinate)
    }

    static func delete(_ m: Memory) {
        try? FileManager.default.removeItem(at: m.url)
        try? FileManager.default.removeItem(at: thumbnailURL(m))
    }

    // MARK: Thumbnails

    static func thumbnailURL(_ m: Memory) -> URL { directory.appending(path: "thumb-\(m.id.uuidString).jpg") }

    /// A square-ish thumbnail, cached next to the file.
    static func thumbnail(_ m: Memory) async -> UIImage? {
        let cached = thumbnailURL(m)
        if let img = UIImage(contentsOfFile: cached.path()) { return img }
        let url = m.url
        let isVideo = m.isVideo
        let image: UIImage? = await Task.detached(priority: .utility) {
            if isVideo {
                let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
                gen.appliesPreferredTrackTransform = true
                gen.maximumSize = CGSize(width: 480, height: 480)
                guard let cg = try? await gen.image(at: .init(seconds: 0.5, preferredTimescale: 600)).image else { return nil }
                return UIImage(cgImage: cg)
            }
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                      kCGImageSourceThumbnailMaxPixelSize: 480,
                  ] as CFDictionary) else { return nil }
            return UIImage(cgImage: cg)
        }.value
        if let data = image?.jpegData(compressionQuality: 0.8) { try? data.write(to: cached) }
        return image
    }

    // MARK: Metadata

    private static func metadata(_ data: Data) -> (date: Date?, coordinate: CLLocationCoordinate2D?) {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return (nil, nil) }
        var date: Date?
        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
           let raw = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy:MM:dd HH:mm:ss"
            date = f.date(from: raw)
        }
        var coordinate: CLLocationCoordinate2D?
        if let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any],
           var lat = gps[kCGImagePropertyGPSLatitude] as? Double, var lon = gps[kCGImagePropertyGPSLongitude] as? Double {
            if (gps[kCGImagePropertyGPSLatitudeRef] as? String) == "S" { lat = -lat }
            if (gps[kCGImagePropertyGPSLongitudeRef] as? String) == "W" { lon = -lon }
            coordinate = .init(latitude: lat, longitude: lon)
        }
        return (date, coordinate)
    }

    /// "+38.5733-109.5498+1234.5/" → coordinate.
    private static func parseISO6709(_ s: String) -> CLLocationCoordinate2D? {
        let scanner = Scanner(string: s)
        guard let lat = scanner.scanDouble(), let lon = scanner.scanDouble() else { return nil }
        return .init(latitude: lat, longitude: lon)
    }
}

extension Trip {
    /// The stop a memory belongs to: nearest camp within 30 miles of where it was taken, else the
    /// camp for the day it was taken, else nil (the trip in general).
    func stop(for m: Memory) -> TripStop? {
        let stops = orderedStops
        if let c = m.coordinate,
           let near = stops.min(by: { TripPlanner.miles($0.coordinate, c) < TripPlanner.miles($1.coordinate, c) }),
           TripPlanner.miles(near.coordinate, c) <= 30 {
            return near
        }
        guard let start = startDate else { return nil }
        let day = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: start),
                                                  to: Calendar.current.startOfDay(for: m.takenAt)).day ?? -1
        var night = 0
        for s in stops {
            if day >= night && day <= night + max(s.nights, 0) { return s }
            night += max(s.nights, 0)
        }
        return nil
    }
}
