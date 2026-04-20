#!/bin/bash
# run_leafarea_fiji.sh
# Version for Linux/Mac using Fiji instead of ImageJ.
# Run from the directory containing your images.

SCRIPT_DIR="$(dirname "$0")"
MACRO_PATH="$SCRIPT_DIR/leafarea_fiji.py"
CONFIG_FILE="$SCRIPT_DIR/leafarea.cfg"

# ── Find ImageJ ──────────────────────────────────────────────────────────────

IJ_DIR=""

if [[ -f "$CONFIG_FILE" ]]; then
    IJ_DIR=$(cat "$CONFIG_FILE")
    if [[ ! -f "$IJ_DIR/fiji" ]]; then
        echo "Saved Fiji path no longer valid: $IJ_DIR"
        IJ_DIR=""
    fi
fi

if [[ -z "$IJ_DIR" ]]; then
    echo "Fiji not found. Please enter the full path to your Fiji folder."
    echo "(e.g. /home/user/Fiji)"
    echo ""
    read -p "Fiji folder path: " IJ_DIR
    IJ_DIR="${IJ_DIR%/}"  # strip trailing slash
    if [[ ! -f "$IJ_DIR/fiji" ]]; then
        echo "Error: Fiji executable not found in $IJ_DIR"
        exit 1
    fi
    echo "$IJ_DIR" > "$CONFIG_FILE"
    echo "Saved to $CONFIG_FILE"
    echo ""
fi

FIJI_EXE="$IJ_DIR/fiji"

# ── Defaults ─────────────────────────────────────────────────────────────────
DEF_THRESHOLD="auto"
DEF_TRIMPX="0"
DEF_LOWSIZE="0"
DEF_UPPERSIZE="Infinity"
DEF_LOWCIRC="0"
DEF_UPCIRC="1"

echo "=== Fiji Leaf Area Analyzer ==="
echo "(Press Enter to accept the default shown in brackets)"
echo ""

read -p "Threshold ('auto' or 0-255)            [$DEF_THRESHOLD]:   " threshold
read -p "Trim (pixels from width/height total)  [$DEF_TRIMPX]:      " trimPx
read -p "Min particle size (px)                 [$DEF_LOWSIZE]:     " lowSize
read -p "Max particle size (px)                 [$DEF_UPPERSIZE]: " upperSize
read -p "Min circularity (0-1)                  [$DEF_LOWCIRC]:     " lowCirc
read -p "Max circularity (0-1)                  [$DEF_UPCIRC]:      " upCirc

echo ""
echo "--- Scale conversion ---"
echo "Provide DPI for automatic conversion, or leave blank to enter paper size manually."
read -p "DPI (leave blank to use paper size): " dpi

if [[ -z "$dpi" ]]; then
    echo "Enter paper dimensions in mm (e.g. A4 = 210 x 297):"
    read -p "Paper width  (mm): " paper_w_mm
    read -p "Paper height (mm): " paper_h_mm
fi

# ── Apply defaults for empty fields ─────────────────────────────────────────
threshold="${threshold:-$DEF_THRESHOLD}"
trimPx="${trimPx:-$DEF_TRIMPX}"
lowSize="${lowSize:-$DEF_LOWSIZE}"
upperSize="${upperSize:-$DEF_UPPERSIZE}"
lowCirc="${lowCirc:-$DEF_LOWCIRC}"
upCirc="${upCirc:-$DEF_UPCIRC}"

# ── Validate threshold ───────────────────────────────────────────────────────
if [[ "$threshold" != "auto" && ! "$threshold" =~ ^[0-9]+$ ]]; then
    echo "Error: threshold must be 'auto' or a number between 0 and 255."
    exit 1
fi
if [[ "$threshold" =~ ^[0-9]+$ && ( "$threshold" -lt 0 || "$threshold" -gt 255 ) ]]; then
    echo "Error: manual threshold must be between 0 and 255."
    exit 1
fi

# ── Run ImageJ ───────────────────────────────────────────────────────────────
ARGS='threshold="'"${threshold}"'",trimPx="'"${trimPx}"'",lowSize="'"${lowSize}"'",upperSize="'"${upperSize}"'",lowCirc="'"${lowCirc}"'",upCirc="'"${upCirc}"'"'

echo ""
echo "Running Fiji on: $(pwd)"
echo "Arguments: $ARGS"
echo ""

"$FIJI_EXE" --headless --run "$MACRO_PATH" "$ARGS"

# ── Summarize per-particle CSVs and write summary ───────────────────────────
echo ""
echo "Summarizing results and converting to mm²..."

RESULTS_DIR="$(pwd)/results"
IMAGE_DIR="$(pwd)"

TMP_PY=$(mktemp /tmp/leafarea_XXXXXX.py)

cat > "$TMP_PY" << PYEOF
import csv, os, glob
from pathlib import Path

results_dir   = "$RESULTS_DIR"
particles_dir = os.path.join(results_dir, "particles")
image_dir     = "$IMAGE_DIR"
use_dpi       = "$dpi"
paper_w_mm    = float("$paper_w_mm") if not use_dpi and "$paper_w_mm" else 0
paper_h_mm    = float("$paper_h_mm") if not use_dpi and "$paper_h_mm" else 0

if use_dpi:
    dpi = float(use_dpi)
    px_to_mm2_global = (25.4 / dpi) ** 2
    print(f"DPI={dpi} -> 1 px = {px_to_mm2_global:.8f} mm2")
else:
    px_to_mm2_global = None

img_extensions = [".tif", ".tiff", ".png", ".jpg", ".jpeg", ".bmp",
                  ".TIF", ".TIFF", ".PNG", ".JPG", ".JPEG", ".BMP"]

summary_rows = [["File", "Area_mm2"]]
csv_files = sorted(glob.glob(os.path.join(particles_dir, "*.csv")))

for csvpath in csv_files:
    base = Path(csvpath).stem

    if px_to_mm2_global is not None:
        px_to_mm2 = px_to_mm2_global
    else:
        imgfile = None
        for ext in img_extensions:
            candidate = os.path.join(image_dir, base + ext)
            if os.path.isfile(candidate):
                imgfile = candidate
                break
        if imgfile is None:
            print(f"Warning: no image found for {base}, skipping.")
            continue
        from PIL import Image
        img = Image.open(imgfile)
        px_to_mm2 = (paper_w_mm * paper_h_mm) / (img.width * img.height)
        print(f"{base}: {img.width}x{img.height} px -> 1 px = {px_to_mm2:.8f} mm2")

    with open(csvpath, newline="") as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    total_area_px = 0.0
    for row in rows:
        try:
            total_area_px += float(row["Area"].strip())
        except (ValueError, KeyError):
            continue
    if "Label" not in rows[0]:
        raise KeyError(f"No Label column found in {os.path.basename(csvpath)}")
    label = rows[0]["Label"].strip()

    area_mm2 = total_area_px * px_to_mm2
    summary_rows.append([label, f"{area_mm2:.6f}"])
    print(f"  {base}: total {total_area_px:.0f} px -> {area_mm2:.6f} mm2")

outfile = os.path.join(results_dir, "summary.csv")
with open(outfile, "w", newline="") as f:
    csv.writer(f).writerows(summary_rows)

print(f"Summary saved to: {outfile}")
PYEOF

python3 "$TMP_PY"
rm "$TMP_PY"

echo ""
echo "Done."
