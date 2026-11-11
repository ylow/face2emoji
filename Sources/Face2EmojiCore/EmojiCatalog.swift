/// The fixed, curated emoji the picker offers: face-like emoji only.
public enum EmojiCatalog {
    /// The default emoji at every launch.
    public static let defaultEmoji = "😀"

    /// Smiley faces, then animal faces, then characters; the first entry is `defaultEmoji`.
    /// Every entry is opaque over nearly all of the middle of its square, where a detected
    /// face sits. Popular emoji with see-through gaps there (🤯 🐰 🐔 🦄 👺) are left out.
    /// All date from Emoji 13.0 or earlier, so macOS 15 has them.
    public static let all: [String] = [
        defaultEmoji, "😃", "😄", "😁", "😆", "😅", "😂", "🤣", "🙂", "🙃",
        "😉", "😊", "😇", "🥰", "😍", "🤩", "😘", "😋", "😜", "🤪",
        "🤓", "😎", "🥸", "🤠", "🥳", "😏", "🙄", "😴", "😱", "😡",
        "🥶",
        "🐶", "🐱", "🐭", "🐹", "🦊", "🐻", "🐼", "🐨", "🐯", "🦁",
        "🐮", "🐷", "🐸", "🐵",
        "👽", "🤖", "👻", "🤡", "💀", "🎃", "👹", "🌝", "🌞",
    ]
}
