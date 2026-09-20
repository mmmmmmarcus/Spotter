#!/usr/bin/env python3
"""Build the World Clock template asset from Natural Earth's 110m land GeoJSON."""
import json
import pathlib
import sys

source = json.loads(pathlib.Path(sys.argv[1]).read_text())
paths = []
for feature in source["features"]:
    geometry = feature["geometry"]
    polygons = [geometry["coordinates"]] if geometry["type"] == "Polygon" else geometry["coordinates"]
    for polygon in polygons:
        for ring in polygon:
            paths.append("M" + "L".join(f"{(x + 180) * 2:.2f},{(90 - y) * 2:.2f}" for x, y in ring) + "Z")
output = pathlib.Path(__file__).resolve().parents[1] / "Spotter/Assets.xcassets/WorldClockLand.imageset"
output.mkdir(parents=True, exist_ok=True)
output.joinpath("land.svg").write_text(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 720 360" width="720" height="360">'
    '<path fill="black" fill-rule="evenodd" d="' + "".join(paths) + '"/></svg>\n'
)
output.joinpath("Contents.json").write_text(json.dumps({
    "images": [{"filename": "land.svg", "idiom": "universal"}],
    "info": {"author": "xcode", "version": 1},
    "properties": {"preserves-vector-representation": True, "template-rendering-intent": "template"}
}, indent=2) + "\n")
