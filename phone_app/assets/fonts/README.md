# Archivo

Three static weights used by the Aphasia SOX theme: Regular 400 for speech,
SemiBold 600 for captions and metadata, ExtraBold 800 for anything that names
a thing.

Bundled rather than fetched. The app renders before its first sync, so it has
to theme correctly on a phone with no network — `google_fonts` would leave the
first launch in a fallback face.

## Provenance

Upstream ships Archivo only as a variable font, so these are instanced from it
rather than downloaded:

```bash
curl -L -o "Archivo-VF.ttf" \
  "https://github.com/google/fonts/raw/main/ofl/archivo/Archivo%5Bwdth,wght%5D.ttf"

python - <<'PY'
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer
for weight, label in [(400, "Regular"), (600, "SemiBold"), (800, "ExtraBold")]:
    font = instancer.instantiateVariableFont(
        TTFont("Archivo-VF.ttf"), {"wght": weight, "wdth": 100}
    )
    font.save(f"Archivo-{label}.ttf")
PY
```

`wdth` is pinned to 100 — the design uses only the normal width.

## Licence

SIL Open Font License 1.1, in `OFL.txt`. It travels with the fonts; keep it
here.
