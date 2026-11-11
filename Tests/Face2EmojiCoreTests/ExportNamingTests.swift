import Foundation
import Testing
import Face2EmojiCore

@Test(arguments: [("IMG_1.HEIC", "IMG_1.jpg"), ("IMG_1.JPG", "IMG_1.JPG"), ("photo.jpeg", "photo.jpeg"),
                  ("a.png", "a.jpg"), ("scan", "scan.jpg"), ("my.trip.heic", "my.trip.jpg")])
func outputName(original: String, expected: String) { #expect(ExportNaming.outputName(forOriginal: original) == expected) }

@Test func suffixesAvoidBatchAndFolderCollisions() throws {
    let folder = try makeTempFolder()
    try Data().write(to: folder.appending(path: "IMG_1.jpg"))
    var taken = Set<String>()
    #expect(ExportNaming.uniqueName("IMG_1.jpg", in: folder, taken: &taken) == "IMG_1 2.jpg")   // file exists
    #expect(ExportNaming.uniqueName("IMG_1.jpg", in: folder, taken: &taken) == "IMG_1 3.jpg")   // batch duplicate
    #expect(ExportNaming.uniqueName("img_1 3.JPG", in: folder, taken: &taken) == "img_1 3 2.JPG") // case-insensitive
    #expect(ExportNaming.uniqueName("other.jpg", in: folder, taken: &taken) == "other.jpg")
}
