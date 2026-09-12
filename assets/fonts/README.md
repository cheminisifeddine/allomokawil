# Cairo — the app's brand face

These two files are real static TrueType instances of the Cairo variable font,
version **3.130**, by Mohamed Gaber / Accademia di Belle Arti di Urbino, under the
SIL Open Font License 1.1 (`OFL.txt` sits next to them). They are what
`pubspec.yaml` declares as family `Cairo`, and Cairo is the typeface named in
every `fontFamily` in `lib/src/core/theme/app_theme.dart` and `ui.dart`.

## Why this file exists

On 11 Sep the two `.ttf` files here were committed as GitHub `404: Not Found`
HTML pages (magic `0a0a0a0a`, `<!DOCTYPE html>`), 267 KB each. Flutter therefore
rejected them and every string in the app — Android, iOS and web — silently fell
back to a system face. The web bundle logged it on every load:

    Failed to load font Cairo at assets/assets/fonts/Cairo-Regular.ttf
    ... Verify that ... contains a valid font

Do not hand-edit these files, and do not "download" them with a tool that can
write an HTTP error page into the file. Check the magic bytes before committing
any font: a real sfnt starts `00 01 00 00` (TrueType) or `4F 54 54 4F` ("OTTO",
CFF outlines). `file` prints "HTML document" for the old broken ones.

## Provenance

* Source: `google/fonts` → `ofl/cairo/Cairo[slnt,wght].ttf` (variable; axes
  `wght` 200–1000 default 400, `slnt` -11–11 default 0). The copy used here is
  pinned at upstream commit `d2528f6d1f43e7d9d0d2e1794afe2ad6fd7d56ba`
  ("Cairo: Version 3.130", 2023-03-08) — the newest commit touching that file.
* Raw URL:
  `https://raw.githubusercontent.com/google/fonts/d2528f6d1f43e7d9d0d2e1794afe2ad6fd7d56ba/ofl/cairo/Cairo%5Bslnt%2Cwght%5D.ttf`
* Instanced to static 400 and 700 with the `slnt` axis pinned at 0, so Flutter
  gets two plain faces and no variable-font machinery:

      uv pip install fonttools brotli
      python -m fontTools.varLib.instancer "Cairo[slnt,wght].ttf" \
          wght=400 slnt=0 --update-name-table -o Cairo-Regular.ttf
      python -m fontTools.varLib.instancer "Cairo[slnt,wght].ttf" \
          wght=700 slnt=0 --update-name-table -o Cairo-Bold.ttf

* Verified after instancing: `usWeightClass` 400 / 700, `fsType` 0
  (installable / embeddable), 1956 glyphs of which 1951 carry real outlines, and
  the full Arabic block present (`ء آ أ ؤ إ ئ ا ب ت ث … ي ة ى`) plus the
  Arabic-Indic digits `٠`–`٩` and the GSUB shaping features `init medi fina rlig`
  that Arabic joining needs.
* The two other download routes named in the backlog are dead ends: gstatic's
  legacy `/l/font?kit=` URL and the `fonts.google.com/download` zip both return
  non-sfnt payloads.

Only the two `.ttf` files are bundled into the app (`pubspec.yaml` declares them
under `fonts:`, not under `assets:`), so this README and the OFL text ship in the
repo without adding a byte to the binary.
