import CoreGraphics
import Foundation
import Testing
import Face2EmojiCore

@Test func uprightSizeAppliesOrientation() throws {
    let rotated = try TestImages.reencode(TestImages.fixture("one-face.jpg"), exifOrientation: 6)
    #expect(try ImageLoader.uprightPixelSize(of: rotated) == CGSize(width: 1280, height: 1600))
    let img = try ImageLoader.loadUpright(rotated, maxPixelSize: nil)
    #expect(img.width == 1280 && img.height == 1600)
}

@Test func downsamplesToMaxPixelSize() throws {
    let img = try ImageLoader.loadUpright(TestImages.fixture("one-face.jpg"), maxPixelSize: 320)
    #expect(max(img.width, img.height) == 320)
}

@Test func rejectsNonImage() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).jpg")
    try Data("not an image".utf8).write(to: url)
    #expect(throws: ImageLoader.NotAnImage.self) { try ImageLoader.loadUpright(url, maxPixelSize: 320) }
    #expect(throws: ImageLoader.NotAnImage.self) { try ImageLoader.uprightPixelSize(of: url) }
}
