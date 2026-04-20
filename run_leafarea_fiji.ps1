# run_leafarea_fiji.ps1
# Run from the directory containing your images:
#   cd C:\path\to\images
#   & "C:\path\to\scripts\run_leafarea_fiji.ps1"

$ScriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$ScriptPath = Join-Path $ScriptDir "leafarea_fiji.py"
$ConfigFile = Join-Path $ScriptDir "leafarea.cfg"

# ── Find Fiji ─────────────────────────────────────────────────────────────────
$FijiDir = ""

if (Test-Path $ConfigFile) {
    $FijiDir = (Get-Content $ConfigFile -Raw).Trim()
    if (-not (Test-Path (Join-Path $FijiDir "fiji-windows-x64.exe"))) {
        Write-Host "Saved Fiji path no longer valid: $FijiDir"
        $FijiDir = ""
    }
}

if (-not $FijiDir) {
    Write-Host "Fiji not found. Please enter the full path to your Fiji folder."
    Write-Host "(e.g. C:\Users\me\Fiji)"
    Write-Host ""
    $FijiDir = (Read-Host "Fiji folder path").Trim().TrimEnd('\')
    if (-not (Test-Path (Join-Path $FijiDir "fiji-windows-x64.exe"))) {
        Write-Error "fiji-windows-x64.exe not found in $FijiDir"
        exit 1
    }
    $FijiDir | Set-Content $ConfigFile
    Write-Host "Path saved to $ConfigFile"
    Write-Host ""
}

$FijiExe = Join-Path $FijiDir "fiji-windows-x64.exe"
if (-not (Test-Path $FijiExe)) {
    Write-Error "fiji-windows-x64.exe not found in $FijiDir"
    exit 1
}

# ── Defaults ─────────────────────────────────────────────────────────────────
$Defaults = @{
    threshold = "auto"
    trimPx    = "0"
    lowSize   = "0"
    upperSize = "Infinity"
    lowCirc   = "0"
    upCirc    = "1"
}

# ── Prompts ───────────────────────────────────────────────────────────────────
Write-Host "=== Fiji Leaf Area Analyzer ==="
Write-Host "(Press Enter to accept the default shown in brackets)"
Write-Host ""

function Prompt-Default($msg, $default) {
    $val = Read-Host "$msg [$default]"
    if ($val -eq "") { return $default } else { return $val }
}

$threshold = Prompt-Default "Threshold ('auto' or 0-255)          " $Defaults.threshold
$trimPx    = Prompt-Default "Trim (pixels from width/height total)" $Defaults.trimPx
$lowSize   = Prompt-Default "Min particle size (px)               " $Defaults.lowSize
$upperSize = Prompt-Default "Max particle size (px)               " $Defaults.upperSize
$lowCirc   = Prompt-Default "Min circularity (0-1)                " $Defaults.lowCirc
$upCirc    = Prompt-Default "Max circularity (0-1)                " $Defaults.upCirc

# ── Validate threshold ────────────────────────────────────────────────────────
if ($threshold -ne "auto") {
    if ($threshold -notmatch '^\d+$' -or [int]$threshold -lt 0 -or [int]$threshold -gt 255) {
        Write-Error "Threshold must be 'auto' or a number between 0 and 255."
        exit 1
    }
}

# ── Scale conversion ──────────────────────────────────────────────────────────
Write-Host ""
Write-Host "--- Scale conversion ---"
Write-Host "Provide DPI for automatic conversion, or leave blank to enter paper size manually."

$dpi    = (Read-Host "DPI (leave blank to use paper size)").Trim()
$PaperW = ""
$PaperH = ""

if (-not $dpi) {
    Write-Host "Enter paper dimensions in mm (e.g. A4 = 210 x 297):"
    $PaperW = Read-Host "Paper width  (mm)"
    $PaperH = Read-Host "Paper height (mm)"
}

# ── Run Fiji ──────────────────────────────────────────────────────────────────
# --run with #@String parameters requires each value double-quoted
$FijiArgs = "threshold='$threshold',trimPx='$trimPx',lowSize='$lowSize',upperSize='$upperSize',lowCirc='$lowCirc',upCirc='$upCirc'"

Write-Host ""
Write-Host "Running Fiji on: $(Get-Location)"
Write-Host "Arguments: $FijiArgs"
Write-Host ""

Start-Process -Wait -NoNewWindow -FilePath $FijiExe -ArgumentList "--headless --run `"$ScriptPath`" `"$FijiArgs`""

# ── Summarize per-particle CSVs and write summary ─────────────────────────────
Write-Host ""
Write-Host "Summarizing results and converting to mm2..."

$ResultsDir   = Join-Path (Get-Location) "results"
$ParticlesDir = Join-Path $ResultsDir "particles"
$ImageDir     = (Get-Location).Path

$TempPy = Join-Path $env:TEMP "leafarea_summary.py"

@"
import csv, os, glob
from pathlib import Path

results_dir   = r'$ResultsDir'
particles_dir = r'$ParticlesDir'
image_dir     = r'$ImageDir'
use_dpi       = '$dpi'
paper_w_mm    = float('$PaperW') if not use_dpi and '$PaperW' else 0
paper_h_mm    = float('$PaperH') if not use_dpi and '$PaperH' else 0

if use_dpi:
    dpi = float(use_dpi)
    px_to_mm2_global = (25.4 / dpi) ** 2
    print(f'DPI={dpi} -> 1 px = {px_to_mm2_global:.8f} mm2')
else:
    px_to_mm2_global = None

img_extensions = ['.tif', '.tiff', '.png', '.jpg', '.jpeg', '.bmp',
                  '.TIF', '.TIFF', '.PNG', '.JPG', '.JPEG', '.BMP']

summary_rows = [['File', 'Area_mm2']]
csv_files = sorted(glob.glob(os.path.join(particles_dir, '*.csv')))

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
            print(f'Warning: no image found for {base}, skipping.')
            continue
        from PIL import Image
        img = Image.open(imgfile)
        px_to_mm2 = (paper_w_mm * paper_h_mm) / (img.width * img.height)
        print(f'{base}: {img.width}x{img.height} px -> 1 px = {px_to_mm2:.8f} mm2')

    with open(csvpath, newline='') as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    total_area_px = 0.0
    for row in rows:
        try:
            total_area_px += float(row['Area'].strip())
        except (ValueError, KeyError):
            continue
    if 'Label' not in rows[0]:
        raise KeyError(f'No Label column found in {os.path.basename(csvpath)}')
    label = rows[0]['Label'].strip()

    area_mm2 = total_area_px * px_to_mm2
    summary_rows.append([label, f'{area_mm2:.6f}'])
    print(f'  {base}: total {total_area_px:.0f} px -> {area_mm2:.6f} mm2')

outfile = os.path.join(results_dir, 'summary.csv')
with open(outfile, 'w', newline='') as f:
    csv.writer(f).writerows(summary_rows)

print(f'Summary saved to: {outfile}')
"@ | Set-Content $TempPy -Encoding UTF8

python $TempPy
Remove-Item $TempPy

Write-Host ""
Write-Host "Done."
