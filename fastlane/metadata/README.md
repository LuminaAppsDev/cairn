# Store listing metadata (`fastlane/metadata/`)

F-Droid imports the listing for `com.luminaapps.cairn` straight from this
directory (the same layout Google Play's `fastlane supply` uses), so the text
and graphics live with the app instead of in the
[fdroiddata recipe](../../fdroid/com.luminaapps.cairn.yml). Reference:
[All About Descriptions, Graphics and Screenshots](https://f-droid.org/en/docs/All_About_Descriptions_Graphics_and_Screenshots/).

## Layout

```
fastlane/metadata/android/
  <locale>/                     # en-US, de-DE  (BCP-47 dirs)
    title.txt                   # listing title  — "Cairn: Health Aggregator"
    short_description.txt        # one line, ≤ 80 chars
    full_description.txt         # long description (plain text / limited HTML)
    changelogs/
      <versionCode>.txt          # per-build notes; filename = the integer versionCode
    images/
      featureGraphic.png         # 1024×500 banner (generated, see below)
      phoneScreenshots/          # 1.png, 2.png, …  (you capture these)
```

`<locale>` dirs are `en-US` and `de-DE`. The launcher *icon* is **not** placed
here — F-Droid extracts it from the built APK, so there is one source of truth
for it (`assets/icon/`).

## What is in place vs. what you provide

| Asset | State |
| --- | --- |
| `title` / `short_description` / `full_description` (en + de) | ✅ committed |
| `changelogs/3.txt` (the 0.1.2 build, versionCode 3) | ✅ committed |
| `images/featureGraphic.png` (en + de) | ✅ generated — `python3 tool/generate_feature_graphic.py` |
| `images/phoneScreenshots/*.png` | ✅ committed — six per locale (en + de) |

## Screenshots — how to add them

F-Droid needs real screenshots of the app; they can only be captured from a
running build (the physical device is the reliable path — the emulator's DNS is
flaky here).

1. Run a release build and reach the screens worth showing (Home overview, the
   Sleep deep-dive, a per-category chart, Settings/connect).
2. Capture each screen as **PNG or JPG** (PNG preferred). Any phone resolution
   is fine; portrait, no device frame, no rounded-corner overlay.
3. Drop them into `android/<locale>/images/phoneScreenshots/` named so they sort
   in display order: `1.png`, `2.png`, `3.png`, … (lexical sort — zero-pad past
   9). Aim for **2–8**; the first is the headline.
4. For German screenshots, run the app with the device set to German and save
   them under `de-DE/`. If a locale has no screenshots, F-Droid falls back to
   `en-US`, so the `en-US` set is the minimum.

After adding them, nothing else is needed — F-Droid re-imports on its next build
of the tag.
