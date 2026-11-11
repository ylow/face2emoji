# face2emoji — Design

Date: 2026-11-11

Items marked **(decided)** came from the owner. Items marked **(my call)** were
chosen by the designer and not explicitly agreed; the owner may overrule them.

## Intent

A Mac app for covering people's faces in photos with emoji before the photos
are shared. The owner drags a batch of photos out of Apple Photos, the app puts
an emoji over every face it finds, the owner fixes up anything that is wrong,
and exports the whole batch to a folder.

Most photos have one or two faces. The common path is therefore: drop, step
through the batch confirming each photo looks right, export. Editing is the
exception, but when it is needed it must be quick and direct.

## Goals

- **(decided)** Drop many photos at once onto the window, dragged directly from
  Apple Photos.
- **(decided)** Every detected face is covered automatically with a default
  smiley emoji.
- **(decided)** Click an emoji to replace it from a list of face emojis.
- **(decided)** Emojis are easy to move and resize.
- **(decided)** Emojis can be added by hand.
- **(decided)** Batch export of all photos to a chosen folder: full-resolution
  JPEG, original file names, location data stripped.
- **(decided)** Layout: one photo large at a time, with a filmstrip of
  thumbnails down the side.

## Non-goals (my call)

- Videos and the motion part of Live Photos. Only still images.
- Saving a session. Nothing persists between launches; the app is a workbench.
- Writing results back into the Photos library.
- Blur, pixelation, stickers other than emoji, text, or any other editing.
- Recognising who a face belongs to, or remembering an emoji per person.
- Manual rotation of emojis.
- **(decided)** Zoom and pan in the editor. The photo is always shown scaled
  to fit. Keep it simple first.
- **(decided)** Any warning, badge or export prompt for photos that have no
  emoji, and any per-photo "reviewed" tracking. Detection will miss some
  faces; the owner stepping through the batch in the large editor is the
  safeguard.
- Distribution: no App Store, notarisation, or support for older macOS
  versions. It needs to build and run on the owner's Mac (macOS 27, Xcode 27).

## Anti-goals

- **A face that looks covered in the editor but is not covered the same way in
  the exported file.** The editor preview and the export must be produced from
  the same placement data and agree visually.
- **Location data surviving in an exported file.**
- Silently overwriting existing files in the export folder.
- Sending photos anywhere. Everything happens on the machine.

## How it is built (my call)

- Native macOS app in Swift and SwiftUI (dropping to AppKit where SwiftUI's
  drag-and-drop or gesture handling is not good enough).
- Face detection with Apple's Vision framework, on-device.
- The Xcode project is generated with `xcodegen` (installed on the owner's
  machine) from a checked-in `project.yml`, so the project file itself is not
  hand-maintained. Buildable and testable from the command line with
  `xcodebuild`.
- No third-party dependencies.

The repository is empty apart from a README; there is no existing code to fit
in with.

## Behaviour

### Window

One window.

- **Toolbar:** "Add emoji" button; "Default" menu showing the current default
  emoji; position indicator ("3 of 12"); "Export All…" button.
- **Filmstrip** on the left: a vertical scrolling list of thumbnails. Each
  thumbnail shows the photo with its emojis drawn on it. The current photo is
  highlighted.
- **Editor** filling the rest: the current photo scaled to fit, with its
  emojis drawn on top.
- **Empty state:** when there are no photos, the window shows a prompt to drop
  photos on it.

### Adding photos

- Dropping anywhere on the window adds photos to the batch.
  - **(decided)** Drags from Apple Photos must work, including many photos at
    once.
  - **(my call)** Image files dragged from Finder also work.
  - **(my call)** Dropping more photos later appends to the batch.
- Non-image items in a drop are ignored.
- **(my call)** A photo can be removed from the batch from the filmstrip
  (context menu, and Delete when the filmstrip has focus and no emoji is
  selected).
- The original file name of each photo is recorded at drop time for use at
  export. Photos hands over files via a drag promise; the builder must verify
  against a real drag from Photos what name and format arrive, and keep
  whatever name Photos supplies.
- Any temporary copies the app makes of dropped photos are deleted when the
  app quits (not when a photo is removed, because removal can be undone).

### Face detection

- Runs automatically in the background for each photo as it is added. The
  window stays responsive, and photos become viewable as soon as they load.
- A thumbnail shows a progress indicator until its detection has finished.
- Each detected face gets one emoji, the current default emoji.
- **(my call)** Placement: the emoji is centred on the detected face and sized
  larger than the detected face box so that it covers the whole head area
  rather than only eyes-to-chin. A starting factor of about 1.4× the larger
  side of the face box is suggested; the builder should tune this against
  real photos, erring toward too large.
- **(my call)** The emoji is tilted to match the head's roll angle when
  detection reports one.
- Image orientation metadata must be respected so that faces are found in
  photos taken in any orientation and placements land in the right spot.

### Editing emojis

All in the editor, on the current photo.

- **Select:** click an emoji. It shows a selection outline and a resize
  handle. Clicking empty photo area deselects.
- **Replace (decided):** clicking an emoji also opens a small picker next to
  it; choosing an emoji in the picker replaces it and closes the picker.
  Dragging an emoji does not open the picker.
- **Move (decided):** drag the emoji.
- **Resize (decided):** drag the handle; the emoji scales about its centre and
  stays square.
- **Add (decided):** "Add emoji" places a new default emoji in the middle of
  the photo, selected, at a sensible size (**my call:** the median size of the
  photo's existing emojis, or about a fifth of the photo's shorter side if
  there are none).
- **Delete (my call):** Delete or Backspace removes the selected emoji. This
  is how false detections are cleared.
- **Undo / redo (my call):** Cmd-Z / Shift-Cmd-Z cover add, delete, move,
  resize, replace, and removing a photo.
- An emoji may be moved partly off the edge of the photo; it is clipped at
  export.

### The emoji picker and the default (my call)

- The picker offers a fixed, curated grid of face-like emojis: the smiley
  faces, plus animal faces and a few characters (alien, robot, ghost, clown
  and similar). Roughly 40–60. It is not the system emoji keyboard. The exact
  list is left to the builder.
- The "Default" menu in the toolbar offers the same set. The default starts as
  😀 each launch. Changing it affects faces detected and emojis added from
  then on; emojis already placed are not changed.

### Moving through the batch

- Click a thumbnail to show that photo.
- **(my call)** Up/Down arrow keys (and Left/Right) go to the previous/next
  photo.
- Switching photos clears the emoji selection.

### Export

- "Export All…" opens a folder chooser. On confirmation every photo in the
  batch is written to that folder.
- **(decided)** Each output is a JPEG at the original pixel dimensions with
  the emojis drawn in.
- **(decided)** The output name is the original file name, with the extension
  changed to `.jpg` if the source was not a JPEG (for example HEIC).
- **(decided)** Location (GPS) metadata is removed.
- **(my call)** Metadata is written from an allowlist, not copied minus GPS.
  Kept: capture date and time, camera and lens details, exposure settings,
  colour profile. Everything else is dropped, which includes GPS, IPTC/XMP
  place names, captions, titles, keywords, named face regions and Apple maker
  notes. Several of those reveal place or identity, which defeats the purpose.
- **(my call)** Orientation is normalised: pixels are written upright and the
  orientation tag reset, so the file looks the same everywhere.
- **(my call)** The source colour profile is kept (photos from recent iPhones
  are Display P3; they should not be flattened to sRGB).
- **(my call)** JPEG quality about 0.9.
- **(my call)** Name collisions: nothing is ever overwritten. If a name is
  already taken, in the folder or by another photo in the same batch, a
  numeric suffix is added (`IMG_1234 2.jpg`).
- **(my call)** Export is unavailable while any photo is still being loaded or
  scanned for faces.
- A progress indicator is shown during export and it can be cancelled. Files
  already written stay.
- When finished, the app reports how many files were written and offers to
  show the folder in Finder. A photo that fails to export does not stop the
  rest; failures are listed at the end by file name.
- The batch stays loaded after export.

### Emoji rendering

- Emojis are drawn with the system colour emoji font. They must be fully
  opaque where the glyph is, so nothing of the face shows through.
- The same drawing code path produces the editor overlay, the filmstrip
  thumbnail and the export, differing only in scale.
- Known limit: the system emoji font is bitmap-based, so an emoji covering a
  very large face in a full-resolution photo will be upscaled and slightly
  soft. This is accepted.

## Constraints and qualities

- **Placement is stored relative to the image**, not the screen: centre, size
  and rotation in normalised upright-image coordinates. Resizing the window
  never changes a placement.
- **Memory:** a batch may be a hundred or more 12–48 megapixel photos. The app
  holds downsampled images for the editor and filmstrip, and loads a
  full-resolution image only while exporting that photo.
- **Responsiveness:** loading, detection and export all happen off the main
  thread, with bounded parallelism.
- **Privacy:** no network access.

## Testing (my call)

Logic is kept separate from the views so that it can be unit tested:

- Converting a detected face box (in the detector's coordinate system, with a
  given image orientation) to an emoji placement.
- Export: output has the source pixel dimensions; GPS, IPTC and XMP metadata
  are absent; capture date is present; an emoji placed at a known spot changes the pixels
  there and not elsewhere; orientation-tagged input comes out upright.
- File naming: extension replacement and collision suffixes.
- Detection on a fixture image with a known number of faces.

Fixture photos containing faces are needed. The builder should use freely
licensed images or ask the owner for some; none exist in the repo.

Drag-and-drop from Apple Photos and the editing gestures are verified by hand
in the running app.

## Left to the builder

- Code structure, type names and file layout.
- Exact visual styling, sizes, and the contents of the curated emoji list.
- The detection request to use and how its results are tuned into placements.
- How drag promises from Photos are received.
- Limits on parallelism and preview sizes.
