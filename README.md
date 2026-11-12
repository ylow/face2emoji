# face2emoji

Face2Emoji is a Mac app that covers the faces in your photos with emoji. Drop photos on its window from
Apple Photos or Finder: it finds the faces and puts an emoji on each, which you can then move, resize, replace,
add or delete. Export All… writes every photo as a full-size JPEG into a folder you choose, with the emoji drawn
in and location and other identifying metadata left out, and never overwrites a file already there.

## Build and run

You need macOS 15 or later, Xcode 27 (Swift 6.4) and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`). From the repository root:

```sh
xcodegen generate
xcodebuild -project Face2Emoji.xcodeproj -scheme Face2Emoji -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/Face2Emoji.app
```

The app lands in `build/Build/Products/Debug/Face2Emoji.app`. With `-configuration Release` instead, it lands in
`build/Build/Products/Release/Face2Emoji.app`.

Debug builds read the environment variable `FACE2EMOJI_DEBUG_LOAD` at launch: a colon-separated list of image
paths, which are added as if they had been dropped on the window. Release builds do not read it. For example:

```sh
FACE2EMOJI_DEBUG_LOAD="$PWD/Tests/Face2EmojiCoreTests/Fixtures/one-face.jpg:$PWD/Tests/Face2EmojiCoreTests/Fixtures/three-faces.jpg" \
  build/Build/Products/Debug/Face2Emoji.app/Contents/MacOS/Face2Emoji
```

## Tests

```sh
swift test
```

This runs the tests of `Face2EmojiCore`, the Swift package that holds the app's logic. The app's windows and
views have no automated tests; the checks below cover what needs a person at the Mac.

## Manual checks

These need a real screen, a real Apple Photos library and Finder, so they cannot be automated here.

1. **Dragging from Apple Photos.** Drag in a single photo. Then drag in 20 or more photos at once, including a
   HEIC, a portrait-orientation shot and a Live Photo. Every photo appears in the filmstrip, in the order
   dragged, upright, with an emoji on each face.
2. **Dragging from Finder.** Drag in a single image file, then several at once. Files that are not images are
   ignored.
3. **Export names.** Export the Photos batch to a new folder. The file names match the names Photos gave, with
   HEIC files ending in `.jpg`. Exporting again into the same folder adds `… 2.jpg` files and leaves the first
   ones untouched.
4. **No location.** For an exported file, neither Finder's Get Info nor Preview's Inspector (Tools ▸ Show
   Inspector) shows a location.
5. **Keys after clicks.** After clicking in the editor, in the filmstrip and on the toolbar, the arrow keys still
   change photo and Delete still deletes the selected emoji, or the photo when no emoji is selected.
6. **Picker.** Escape closes the emoji picker.
7. **Undo.** Edit ▸ Undo and Edit ▸ Redo show the action names (Change Emoji, Add Emoji, Delete Emoji, Remove
   Photo), and Cmd-Z and Shift-Cmd-Z work.
8. **Dragged emoji are exported where they were dragged.** Drag a photo's emoji somewhere else, export, and open
   the exported file: the emoji is at the dragged position.
9. **Export All… button.** It is drawn as the prominent (accent-coloured) button while the window is active, and
   is disabled while there are no photos or while photos are still loading or being scanned for faces.
10. **During and after an export.** While the progress sheet or the result alert is up, the arrow keys and
    Delete leave the photos alone, and Edit ▸ Undo is unavailable. Escape cancels a running export. On the result
    alert, Return presses OK, and Show in Finder opens the export folder.
11. **Dropping while the folder panel is open.** Click Export All… and, with the folder panel still open, drag a
    photo onto the window behind it. Either the drop is refused, or the photo is added and choosing a folder
    then exports nothing (Export All… works again once the photo has loaded). Nothing is exported while a photo
    is still being scanned for faces.
