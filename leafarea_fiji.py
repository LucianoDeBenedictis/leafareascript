# leafarea_fiji.py
# Fiji/Jython script for batch leaf area analysis.
# Usage via run_leafarea_fiji.sh, or manually:
#   ./fiji --headless --run leafarea_fiji.py \
#     'threshold="auto",trimPx="0",lowSize="0",upperSize="Infinity",lowCirc="0",upCirc="1"'

#@String threshold
#@String trimPx
#@String lowSize
#@String upperSize
#@String lowCirc
#@String upCirc

import os
from ij import IJ
from ij.plugin.filter import ParticleAnalyzer
from ij.measure import ResultsTable, Measurements

# ── Parse parameters ──────────────────────────────────────────────────────────
thresh_arg  = threshold
trim_px     = int(trimPx)
low_size    = float(lowSize)
upper_size  = float("inf") if upperSize == "Infinity" else float(upperSize)
low_circ    = float(lowCirc)
up_circ     = float(upCirc)

# ── Working directory ─────────────────────────────────────────────────────────
dir_path = os.getcwd()

particles_dir = os.path.join(dir_path, "results", "particles")
outlines_dir  = os.path.join(dir_path, "results", "outlines")
for d in [os.path.join(dir_path, "results"), particles_dir, outlines_dir]:
    if not os.path.exists(d):
        os.makedirs(d)

# ── ParticleAnalyzer options ──────────────────────────────────────────────────
# Called directly as a Java object to avoid the headless dialog crash.
# SHOW_OVERLAY_MASKS produces the numbered overlay image on the original.
pa_options = (ParticleAnalyzer.SHOW_OUTLINES |
              ParticleAnalyzer.EXCLUDE_EDGE_PARTICLES |
              ParticleAnalyzer.INCLUDE_HOLES |
              ParticleAnalyzer.CLEAR_WORKSHEET)

pa_measurements = Measurements.AREA | Measurements.CENTROID

# ── Image extensions to process ───────────────────────────────────────────────
img_exts = ('.tif', '.tiff', '.png', '.jpg', '.jpeg', '.bmp')

# ── Batch loop ────────────────────────────────────────────────────────────────
for filename in sorted(os.listdir(dir_path)):
    if not filename.lower().endswith(img_exts):
        continue
    if os.path.isdir(os.path.join(dir_path, filename)):
        continue

    base     = os.path.splitext(filename)[0]
    filepath = os.path.join(dir_path, filename)
    IJ.log("Processing: " + filename)

    # Open image
    imp = IJ.openImage(filepath)

    # Trim canvas symmetrically
    w = imp.getWidth()  - trim_px
    h = imp.getHeight() - trim_px
    IJ.run(imp, "Canvas Size...",
           "width=" + str(w) + " height=" + str(h) + " position=Center")

    # Convert to grayscale
    IJ.run(imp, "8-bit", "")

    # Apply threshold
    if thresh_arg == "auto":
        imp.setAutoThreshold("Default no-reset")
    else:
        IJ.setThreshold(imp, 0, int(thresh_arg))

    # Set measurements: area and centroid
    IJ.run("Set Measurements...", "area centroid display redirect=None decimal=3")

    # Run ParticleAnalyzer directly — bypasses IJ.run() and the headless dialog
    rt = ResultsTable()
    pa = ParticleAnalyzer(pa_options, pa_measurements,
                          rt, low_size, upper_size, low_circ, up_circ)
    pa.analyze(imp)

    # Add Label column identifying the source image (mirrors ImageJ behavior)
    for i in range(rt.size()):
        rt.setValue("Label", i, base)

    # Save per-particle results
    rt.save(os.path.join(particles_dir, base + ".csv"))

    # Save the outlines image produced by ParticleAnalyzer
    outlines_imp = pa.getOutputImage()
    if outlines_imp is not None:
        IJ.saveAs(outlines_imp, "PNG", os.path.join(outlines_dir, base + "_outlines"))
        outlines_imp.close()

    imp.close()

IJ.log("Done. Per-particle CSVs saved to: " + particles_dir)
IJ.log("Outlines images saved to:          " + outlines_dir)
