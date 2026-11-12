import Face2EmojiCore
import SwiftUI

/// Every emoji of `EmojiCatalog.all` in a grid, 8 to a row, each in a 32 pt cell. Clicking one
/// calls `onPick` with it.
struct EmojiPickerView: View {
    private let onPick: (String) -> Void

    private static let cellSide: CGFloat = 32
    private static let columns = Array(repeating: GridItem(.fixed(cellSide), spacing: 0), count: 8)

    init(onPick: @escaping (String) -> Void) {
        self.onPick = onPick
    }

    var body: some View {
        LazyVGrid(columns: Self.columns, spacing: 0) {
            ForEach(EmojiCatalog.all, id: \.self) { emoji in
                Button { onPick(emoji) } label: {
                    Text(emoji)
                        .font(.system(size: 24))
                        .frame(width: Self.cellSide, height: Self.cellSide)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
    }
}
