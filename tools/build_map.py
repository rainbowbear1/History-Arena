"""Builds assets/maps/kazakhstan.svg from Natural Earth data (public domain) and converts
latitude/longitude to the 0-1 map coordinates used by `map` questions.

Usage (Natural Earth v5.1.2, 1:50m GeoJSON files downloaded separately):
    python tools/build_map.py <ne_50m_admin_0_countries.geojson> <ne_50m_lakes.geojson>
    python tools/build_map.py --point <lat> <lon>     # prints "x y" for a map question

The projection is equirectangular, scaled by cos(48°) so Kazakhstan keeps its familiar shape,
and the view is fixed (VIEW below) so coordinates stay valid if the SVG is rebuilt.
"""
import json
import math
import sys

WIDTH, HEIGHT = 2048, 1024
LAT0 = 48.0
# View in degrees: west, east, south, north (2:1 after the cos(LAT0) scaling).
VIEW = (40.75, 93.05, 39.0, 56.5)
OUT_SVG = "assets/maps/kazakhstan.svg"

COLORS = {
    "background": "#9cc0d6",
    "neighbour": "#d8caa9",
    "neighbour_line": "#b5a37f",
    "kazakhstan": "#f1c76f",
    "kazakhstan_line": "#7a4e1d",
    "water": "#8fb7d1",
    "water_line": "#5f8fae",
}


def _scale():
    return math.cos(math.radians(LAT0))


def project(lat, lon):
    """Returns (x, y) in 0-1 map units (0,0 = top-left)."""
    west, east, south, north = VIEW
    k = _scale()
    x = (lon - west) * k / ((east - west) * k)
    y = (north - lat) / (north - south)
    return x, y


def _check_aspect():
    west, east, south, north = VIEW
    ratio = (east - west) * _scale() / (north - south)
    assert abs(ratio - 2.0) < 0.02, "VIEW must be 2:1 after scaling, got %.3f" % ratio


def _rings(geometry):
    if geometry["type"] == "Polygon":
        return geometry["coordinates"]
    if geometry["type"] == "MultiPolygon":
        return [ring for polygon in geometry["coordinates"] for ring in polygon]
    return []


def _path(rings):
    parts = []
    for ring in rings:
        points = []
        for lon, lat in ring:
            x, y = project(lat, lon)
            points.append("%.1f,%.1f" % (x * WIDTH, y * HEIGHT))
        parts.append("M" + " L".join(points) + " Z")
    return " ".join(parts)


def _in_view(rings):
    west, east, south, north = VIEW
    for ring in rings:
        for lon, lat in ring:
            if west - 5 <= lon <= east + 5 and south - 5 <= lat <= north + 5:
                return True
    return False


def build(countries_path, lakes_path):
    _check_aspect()
    with open(countries_path, encoding="utf-8") as f:
        countries = json.load(f)["features"]
    with open(lakes_path, encoding="utf-8") as f:
        lakes = json.load(f)["features"]

    shapes = []
    kazakhstan = None
    for feature in countries:
        rings = _rings(feature["geometry"])
        if feature["properties"].get("ADMIN") == "Kazakhstan":
            kazakhstan = rings
        elif _in_view(rings):
            shapes.append('<path d="%s" fill="%s" stroke="%s" stroke-width="2" fill-rule="evenodd"/>'
                          % (_path(rings), COLORS["neighbour"], COLORS["neighbour_line"]))
    if kazakhstan is None:
        raise SystemExit("Kazakhstan not found in " + countries_path)

    shapes.append('<path d="%s" fill="%s" stroke="%s" stroke-width="5" fill-rule="evenodd"/>'
                  % (_path(kazakhstan), COLORS["kazakhstan"], COLORS["kazakhstan_line"]))

    for feature in lakes:
        rings = _rings(feature["geometry"])
        if _in_view(rings):
            shapes.append('<path d="%s" fill="%s" stroke="%s" stroke-width="2" fill-rule="evenodd"/>'
                          % (_path(rings), COLORS["water"], COLORS["water_line"]))

    svg = ['<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">'
           % (WIDTH, HEIGHT, WIDTH, HEIGHT),
           '<!-- Made with Natural Earth (public domain), v5.1.2, 1:50m. Built by tools/build_map.py -->',
           '<rect width="100%%" height="100%%" fill="%s"/>' % COLORS["background"]]
    svg += shapes
    svg.append("</svg>")
    with open(OUT_SVG, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(svg) + "\n")
    print("wrote", OUT_SVG)


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "--point":
        x, y = project(float(sys.argv[2]), float(sys.argv[3]))
        print("%.3f %.3f" % (x, y))
    elif len(sys.argv) == 3:
        build(sys.argv[1], sys.argv[2])
    else:
        print(__doc__)
        sys.exit(1)
