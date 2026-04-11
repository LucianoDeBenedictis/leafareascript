// leafarea.ijm
// Usage (from terminal):
//   imagej -b leafarea.ijm \
//     "threshold=auto,trimPx=10,lowSize=50,upperSize=500,lowCirc=0.5,upCirc=1.0"
//
// threshold: "auto" uses Default auto-threshold, or a number 0-255 for manual
// All other arguments are passed as a single comma-separated string of key=value pairs.
// Measurements are in pixels (no scale set).

args = getArgument();

// ── Parse key=value pairs ──────────────────────────────────────────────────
function getParam(args, key) {
    pairs = split(args, ",");
    for (k = 0; k < pairs.length; k++) {
        kv = split(pairs[k], "=");
        if (kv[0] == key) return kv[1];
    }
    exit("Missing argument: " + key);
}

threshArg = getParam(args, "threshold");
trimPx    = parseInt(getParam(args, "trimPx"));
lowSize   = parseFloat(getParam(args, "lowSize"));
upperSize = parseFloat(getParam(args, "upperSize"));
lowCirc   = parseFloat(getParam(args, "lowCirc"));
upCirc    = parseFloat(getParam(args, "upCirc"));

// ── Working directory = directory where the macro is launched from ─────────
dir = getDirectory("current");
if (!endsWith(dir, "/")) dir = dir + "/";

particlesDir = dir + "results/particles/";
threshDir    = dir + "results/thresholded/";
if (!File.exists(dir + "results/"))  File.makeDirectory(dir + "results/");
if (!File.exists(particlesDir))      File.makeDirectory(particlesDir);
if (!File.exists(threshDir))         File.makeDirectory(threshDir);

// ── Batch loop ─────────────────────────────────────────────────────────────
list = getFileList(dir);

for (i = 0; i < list.length; i++) {

    name = list[i];

    // Skip sub-directories and non-image files
    if (File.isDirectory(dir + name)) continue;
    lower = toLowerCase(name);
    if (!endsWith(lower, ".tif")  && !endsWith(lower, ".tiff") &&
        !endsWith(lower, ".png")  && !endsWith(lower, ".jpg")  &&
        !endsWith(lower, ".jpeg") && !endsWith(lower, ".bmp")) continue;

    open(dir + name);
    baseName = replace(name, "\\.[^.]+$", "");   // strip extension

    // Trim canvas symmetrically
    width  = getWidth()  - trimPx;
    height = getHeight() - trimPx;
    run("Canvas Size...", "width=" + width +
        " height=" + height + " position=Center");

    run("8-bit");

    // Apply threshold: auto or manual
    if (threshArg == "auto") {
        setAutoThreshold("Default no-reset");
    } else {
        setThreshold(0, parseInt(threshArg), "raw");
    }

    // Measure area, centroid; include holes; exclude edge particles
    run("Set Measurements...", "area centroid display redirect=None decimal=3");
    run("Analyze Particles...",
        "size=" + lowSize + "-" + upperSize +
        " circularity=" + lowCirc + "-" + upCirc +
        " show=Outlines display exclude clear include");

    // Results window is active after Analyze Particles — save directly
    saveAs("Results", particlesDir + baseName + ".csv");

    // Save the outline mask image produced by Analyze Particles
    saveAs("PNG", threshDir + baseName + "_overlay.png");

    close("*");
}

print("Done. Per-particle CSVs saved to: " + particlesDir);
print("Outline images saved to:          " + threshDir);
