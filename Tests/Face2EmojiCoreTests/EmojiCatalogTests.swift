import Testing
import Face2EmojiCore

@Test func catalogIsWellFormed() {
    #expect(EmojiCatalog.all.first == "😀")
    #expect((40...60).contains(EmojiCatalog.all.count))
    #expect(Set(EmojiCatalog.all).count == EmojiCatalog.all.count)
    #expect(EmojiCatalog.all.allSatisfy { $0.count == 1 })
}
