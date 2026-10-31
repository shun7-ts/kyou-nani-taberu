#!/usr/bin/env python3
"""Encode a fresh delivery folder from a preserved meal-images source (macOS sips)."""
import argparse
import hashlib
import json
import shutil
import subprocess
from pathlib import Path


def properties(path):
    result = subprocess.run(
        ["sips", "-g", "pixelWidth", "-g", "pixelHeight", "-g", "hasAlpha", str(path)],
        check=True, capture_output=True, text=True,
    )
    values = dict(line.strip().split(": ", 1) for line in result.stdout.splitlines() if ": " in line)
    return int(values["pixelWidth"]), int(values["pixelHeight"]), values["hasAlpha"] == "yes"


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True, help="Preserved original meal-images folder")
    parser.add_argument("--output", type=Path, required=True, help="New, nonexistent output folder")
    parser.add_argument("--max-edge", type=int, default=1280)
    parser.add_argument("--quality", type=int, default=84)
    args = parser.parse_args()
    if args.output.exists() or args.output.with_name(args.output.name + "-report.json").exists():
        parser.error("Output exists; choose a fresh folder. Never repeatedly recompress delivery images.")
    if args.max_edge < 640 or not 1 <= args.quality <= 100:
        parser.error("Use a maximum edge >=640 and JPEG quality 1...100")
    entries = json.loads((args.source / "catalog.json").read_text())
    args.output.mkdir(parents=True)
    records = []
    used = set()
    for entry in entries:
        filename = entry["file"]
        if Path(filename).name != filename or ".." in filename:
            raise ValueError("Unsafe catalog path")
        source = args.source / filename
        width, height, alpha = properties(source)
        convert = not alpha and (source.suffix.lower() == ".png" or max(width, height) > args.max_edge)
        target_name = source.stem + ".jpg" if convert else filename
        if target_name in used:
            raise ValueError("Duplicate delivery filename: " + target_name)
        used.add(target_name)
        target = args.output / target_name
        if convert:
            subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", str(args.quality),
                            "-Z", str(args.max_edge), str(source), "--out", str(target)],
                           check=True, capture_output=True)
        else:
            shutil.copy2(source, target)
        final_width, final_height, final_alpha = properties(target)
        if min(final_width, final_height) <= 300 or (alpha and not final_alpha):
            raise ValueError("Invalid delivery image: " + filename)
        entry["file"] = target_name
        records.append({"recipeKey": entry["recipeKey"], "originalFile": filename,
                        "file": target_name, "originalBytes": source.stat().st_size,
                        "bytes": target.stat().st_size, "originalSHA256": digest(source),
                        "sha256": digest(target), "originalSize": [width, height],
                        "size": [final_width, final_height], "hasAlpha": final_alpha,
                        "transformation": "JPEG quality %d; maximum edge %d; aspect ratio retained" %
                        (args.quality, args.max_edge) if convert else "Unchanged"})
    (args.output / "catalog.json").write_text(json.dumps(entries, ensure_ascii=False, indent=2) + "\n")
    total_before = sum(p.stat().st_size for p in args.source.iterdir() if p.is_file())
    total_after = sum(p.stat().st_size for p in args.output.iterdir() if p.is_file())
    report = {"maxEdge": args.max_edge, "jpegQuality": args.quality,
              "beforeFolderBytes": total_before, "afterFolderBytes": total_after,
              "removedUnusedFiles": sorted(p.name for p in args.source.iterdir()
                                            if p.is_file() and p.name != "catalog.json"
                                            and p.name not in {r["originalFile"] for r in records}),
              "images": records}
    report_path = args.output.with_name(args.output.name + "-report.json")
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"images": len(records), "beforeMiB": round(total_before/2**20, 2),
                      "afterMiB": round(total_after/2**20, 2),
                      "reductionPercent": round((1-total_after/total_before)*100, 1),
                      "report": str(report_path)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
