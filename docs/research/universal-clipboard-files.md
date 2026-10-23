# Files copied on an iPhone: what a Universal Clipboard copy leaves on the Mac

Measured on 2026-10-23 with a probe that polled `NSPasteboard.general` every 0.5 s (macOS 27, an iPhone on the same
Apple ID). The probe is not in the repository: it logged the types at each change without reading anything, read the
file URLs once 5 s later, and then looked at those files every 30 s.

## What was seen

- **Types, before any read.** A photo copied in Photos and a file copied in Files both arrive with `public.file-url`,
  `NSFilenamesPboardType` and `com.apple.is-remote-clipboard` (a photo adds `com.apple.mobileslideshow.asset.localidentifier`,
  a file adds `com.apple.DocumentManager.FINode.File`). No image type is offered for a photo.
- **Where the file is.** Reading the URL gives a file in
  `~/Library/Group Containers/group.com.apple.coreservices.useractivityd/shared-pasteboard/items/<UUID>/<name>`; its
  size can be read (128 KB to 2.1 MB for photos, 884 KB for a PDF) but its bytes cannot: opening it fails with
  "operation not permitted" for an app that is not Apple's, also with security-scoped access, file coordination and the
  pasteboard's image readers (probe, 2026-10-23, five photos). The first read took 0.2 s (the transfer had finished by then); later reads of the same copy took 2 ms.
- **How long it lives.** Only as long as that copy is the current pasteboard item. Every file was there while its copy
  was current and gone within seconds of the pasteboard changing (a photo was missing 5 s after a copy on the Mac, and
  another 8 s after the next iPhone copy replaced it). Three of three files were gone at the next check.

## What it means for Pesto

Pesto keeps only the path of a file clip, never its bytes (`FileClip`), and the watcher reads the file URL on the first
tick that sees a copy. For a remote copy that path is a temporary location that is deleted when the pasteboard moves on,
so a remote file clip kept with *Settings → Privacy → Other devices* on is a dead path almost at once: the card dims
it ("Moved or deleted") and a paste now says so instead of handing the target app the dead path (`FileClip.isGone`).

Options, cheapest first:
1. **Say so** (done): the card dims, and a paste refuses with "Its files were moved or deleted".
2. **Copy the bytes at capture** for a remote file, within `ClipSizePolicy`: the file exists when the watcher reads the
   URL (it did 5 s after the change, and the watcher reads within 60 to 500 ms), so the watcher can read its bytes and
   store the clip as a picture (a photo) or as the file's contents, sealed like any clip. It needs a design decision
   (what a kept non-picture file is, how big it may be, whether a PDF is stored whole) and the existing rule that a
   remote copy is read only after it is kept (`FakePasteboard.contentReads`) still holds, because it is read only when
   `keepsRemoteCopies` is on.
3. **Do not keep a remote file clip at all**, with a one-line reason in the Other devices settings.

Outcome (2026-10-23): 2 was built (`RemoteFileClip`) and then found impossible on a real Mac: the folder is protected from other apps (reading the bytes fails with EPERM, also with security-scoped access, file coordination and the pasteboard's image readers), so a remote photo is not kept either, is counted as left out, and Settings says so (ADR 0004). The recommendation was: 2 for photos (a picture clip is already stored as bytes), 1 for everything else until a kept file
type exists; and say in the Other devices settings that files copied on another device are kept only if they are
pictures.
