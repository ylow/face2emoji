import Foundation

/// File names for exported photos.
public enum ExportNaming {
    /// "IMG_1.HEIC" → "IMG_1.jpg"; "a.JPG", "a.jpeg", "a.jpg" unchanged; "scan" → "scan.jpg".
    public static func outputName(forOriginal name: String) -> String {
        let (stem, ext) = split(name)
        if let ext, ["jpg", "jpeg"].contains(ext.lowercased()) { return name }
        return stem + ".jpg"
    }

    /// Returns `name`, or "stem 2.ext", "stem 3.ext"… — the first candidate that is neither in
    /// `taken` (compared case-insensitively) nor an existing file in `folder`. Inserts the result into `taken`.
    public static func uniqueName(_ name: String, in folder: URL, taken: inout Set<String>) -> String {
        let (stem, ext) = split(name)
        let takenLowercased = Set(taken.map { $0.lowercased() })
        var candidate = name
        var number = 1
        while takenLowercased.contains(candidate.lowercased()) || exists(candidate, in: folder) {
            number += 1
            candidate = "\(stem) \(number)" + (ext.map { ".\($0)" } ?? "")
        }
        taken.insert(candidate)
        return candidate
    }

    /// The name before its extension, and the extension without its dot, if there is one.
    private static func split(_ name: String) -> (stem: String, ext: String?) {
        let path = name as NSString
        return path.pathExtension.isEmpty ? (name, nil) : (path.deletingPathExtension, path.pathExtension)
    }

    /// Whether anything, even a broken symbolic link, has `name` in `folder`.
    private static func exists(_ name: String, in folder: URL) -> Bool {
        // attributesOfItem does not follow a final symbolic link, unlike fileExists(atPath:).
        (try? FileManager.default.attributesOfItem(atPath: folder.appending(path: name).path)) != nil
    }
}
