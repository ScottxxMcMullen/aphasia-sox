# Launcher icon pass — instructions for Claude Code

**Independent of every other pass.** Nothing here touches Dart.

**Goal:** ship mark B as the launcher icon, replacing the default Flutter icon, with a proper
adaptive icon on Android 8+ and a legacy fallback below that.

**The assets are already exported.** They are in this repo at
`docs/design-handoff/icon/android/`, generated from the SVG masters in
`docs/design-handoff/icon/master/`. Do not re-render them from the design file or run a generator
package — copy them.

**No new package.** `flutter_launcher_icons` would regenerate from a single PNG and produce a
different safe-zone crop than the one the design specifies. The files are pre-cut; a plain copy
is both fewer moving parts and the more faithful result.

---

## 1. Copy the bitmaps

```
docs/design-handoff/icon/android/mipmap-<d>/ic_launcher.png             →  android/app/src/main/res/mipmap-<d>/ic_launcher.png
docs/design-handoff/icon/android/mipmap-<d>/ic_launcher_round.png       →  android/app/src/main/res/mipmap-<d>/ic_launcher_round.png
docs/design-handoff/icon/android/mipmap-<d>/ic_launcher_foreground.png  →  android/app/src/main/res/mipmap-<d>/ic_launcher_foreground.png
```

for `<d>` in `mdpi hdpi xhdpi xxhdpi xxxhdpi`. Overwrite the Flutter defaults. Delete nothing
else in `res/`.

Sizes, for reference — check a couple after copying:

| Density | `ic_launcher` / `_round` | `ic_launcher_foreground` |
| --- | --- | --- |
| mdpi | 48 | 108 |
| hdpi | 72 | 162 |
| xhdpi | 96 | 216 |
| xxhdpi | 144 | 324 |
| xxxhdpi | 192 | 432 |

`play-store-512.png` is for the Play Console listing only — it does not go in `res/`.

## 2. The adaptive icon

Two new files. `android/app/src/main/res/values/ic_launcher_background.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#201E1D</color>
</resources>
```

`android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml` — and an identical
`ic_launcher_round.xml` beside it:

```xml
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/ic_launcher_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
```

The background is the flat ink color rather than an image: the launcher parallaxes background
against foreground, and a flat ground means that motion never reveals an edge. The ink is the
same `#201E1D` as `SoxTokens.ink` — if the theme's ink ever changes, this hex changes with it.

## 3. Manifest

`android/app/src/main/AndroidManifest.xml` should already point at `@mipmap/ic_launcher`. Confirm
it, add the round reference if it is absent, and set the label:

```xml
<application
    android:label="Aphasia SOX"
    android:icon="@mipmap/ic_launcher"
    android:roundIcon="@mipmap/ic_launcher_round"
```

`android:label` is what sits under the icon in the launcher. "Aphasia SOX" replaces "aphasia_app".
This is the one place the app gets renamed — the in-app title bar is the home layout pass.

## 4. Geometry, if you ever need to re-cut

The foreground is drawn on the 108dp adaptive grid at 432px (4×). The glyph is 192px tall — 48dp
of the 108dp grid — and centred at (216, 216). Its furthest ink sits 29.4dp from centre against
the 33dp safe radius, so it clears the safe circle with room to spare: a launcher may crop to a
circle, a squircle, or a rounded square, and the mark survives all three untouched. The
legacy square art fills its frame with the glyph at 65% of the canvas height, because legacy
icons are not cropped and should not float in a large empty ground.

The masters are plain SVG; re-rendering at any size is a matter of changing the `width`/`height`
attributes.

---

## Definition of done

1. Uninstall the app, then install fresh — the launcher shows mark B, not the Flutter logo.
2. The label under the icon reads "Aphasia SOX".
3. Long-press and drag the icon: the red bars and the stem stay fully inside the crop at every
   launcher shape, and the parallax never exposes a background edge.
4. Check the icon in the app switcher and in Settings → Apps, which use different sizes.
5. On an Android 7 device or emulator (below adaptive-icon support), the legacy square still
   renders correctly.
