#!/usr/bin/env python3
"""
OpenStreetMap (OSM) Offline Road Network Downloader for IDR Navigation Engine.

Downloads road centerlines, elevated flyover decks, tunnels, and lanes
using the public Overpass API and formats them into clean offline GeoJSON
ready for the Flutter `OsmMapLoader` and `MapSnapper`.

Usage:
  python scripts/download_osm_roads.py --preset mumbai_pune_expressway
  python scripts/download_osm_roads.py --preset delhi_meerut_expressway
  python scripts/download_osm_roads.py --bbox 18.50,73.80,18.55,73.88 --output assets/maps/pune_roads.geojson
"""

import argparse
import json
import os
import sys
import urllib.parse
import urllib.request

ROAD_LEVELS = {
    "highways": {
        "description": "Expressways & National Highways (motorway, trunk, links)",
        "filter": "motorway|trunk|motorway_link|trunk_link",
    },
    "arterials": {
        "description": "Highways + Major State Arterials (adds primary, secondary)",
        "filter": "motorway|trunk|primary|secondary|motorway_link|trunk_link|primary_link|secondary_link",
    },
    "all": {
        "description": "Complete Road Grid including Minor Roads (tertiary, residential, service, living_street)",
        "filter": "motorway|trunk|primary|secondary|tertiary|residential|service|unclassified|living_street|motorway_link|trunk_link|primary_link|secondary_link|tertiary_link",
    },
}

# Popular Indian Highway & Urban Flyover Benchmark Presets
PRESETS = {
    "maharashtra_highways": {
        "description": "Maharashtra Expressway Network (Mumbai-Pune Expressway, Atal Setu MTHL, NH-48, Panvel & Pune)",
        "bbox": (18.600, 72.850, 19.200, 73.950),  # (south, west, north, east)
        "default_level": "highways",
    },
    "mumbai_pune_expressway": {
        "description": "Mumbai-Pune Expressway (NH-48 Bhor Ghat with Khandala tunnels & multi-tier viaducts)",
        "bbox": (18.700, 73.250, 18.820, 73.480),
        "default_level": "highways",
    },
    "pune_urban_full": {
        "description": "Pune City Urban Grid (Shivajinagar, FC Road, Kothrud, Deccan - Arterial & Minor Roads)",
        "bbox": (18.500, 73.810, 18.540, 73.865),
        "default_level": "all",
    },
    "mumbai_bkc_urban": {
        "description": "Mumbai BKC & Western Express (Bandra Kurla Complex with flyovers & minor grid)",
        "bbox": (19.050, 72.850, 19.080, 72.890),
        "default_level": "all",
    },
    "maharashtra_samruddhi": {
        "description": "Maharashtra Samruddhi Mahamarg (Igatpuri - Nashik Expressway Section with Twin Tunnels)",
        "bbox": (19.600, 73.500, 19.950, 74.050),
        "default_level": "highways",
    },
    "delhi_meerut_expressway": {
        "description": "Delhi-Meerut Expressway (14-lane high-speed corridor with elevated flyovers)",
        "bbox": (28.620, 77.280, 28.700, 77.420),
        "default_level": "highways",
    },
    "bengaluru_electronic_city": {
        "description": "Bengaluru Electronic City Elevated Highway (Tier 2 Flyover deck over Hosur Road)",
        "bbox": (12.830, 77.640, 12.920, 77.690),
        "default_level": "highways",
    },
    "atal_tunnel_rohtang": {
        "description": "Atal Tunnel Rohtang (9.02 km GNSS-denied Himalayan highway tunnel)",
        "bbox": (32.340, 77.120, 32.440, 77.180),
        "default_level": "highways",
    },
}

OVERPASS_SERVERS = [
    "https://overpass-api.de/api/interpreter",
    "https://lz4.overpass-api.de/api/interpreter",
    "https://z.overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
]


def build_overpass_query(south: float, west: float, north: float, east: float, road_filter: str) -> str:
    """Builds an optimized Overpass QL query extracting drivable roads with geometry."""
    return f"""
    [out:json][timeout:90];
    (
      way["highway"~"{road_filter}"]({south},{west},{north},{east});
    );
    out body geom;
    """


def download_osm_data(query: str) -> dict:
    """Executes the Overpass QL query across mirrors."""
    headers = {
        "User-Agent": "IDR-DeadReckoning-SIH2026/1.0 (contact@idr-hackathon.org)",
        "Accept": "application/json, text/javascript, */*; q=0.01",
    }

    for server in OVERPASS_SERVERS:
        print(f"[*] Querying Overpass server: {server}...", flush=True)
        try:
            url = f"{server}?data=" + urllib.parse.quote(query)
            req = urllib.request.Request(
                url,
                headers=headers,
            )
            with urllib.request.urlopen(req, timeout=90) as response:
                if response.status == 200:
                    raw_text = response.read().decode("utf-8")
                    return json.loads(raw_text)
        except Exception as e:
            print(f"[!] Server {server} failed: {e}. Trying next mirror...", flush=True)

    raise RuntimeError("All Overpass API servers failed or timed out.")




def overpass_to_geojson(overpass_json: dict) -> dict:
    """Converts raw Overpass JSON elements with inline geometry into standard GeoJSON."""
    elements = overpass_json.get("elements", [])
    features = []

    for el in elements:
        if el.get("type") != "way":
            continue

        geom_nodes = el.get("geometry", [])
        if len(geom_nodes) < 2:
            continue

        coords = [[pt["lon"], pt["lat"], 0.0] for pt in geom_nodes]
        tags = el.get("tags", {})

        feature = {
            "type": "Feature",
            "id": el.get("id"),
            "properties": {
                "name": tags.get("name") or tags.get("ref") or tags.get("highway") or "Road",
                "ref": tags.get("ref", ""),
                "highway": tags.get("highway", "road"),
                "bridge": tags.get("bridge", "no"),
                "tunnel": tags.get("tunnel", "no"),
                "layer": tags.get("layer", "0"),
                "lanes": tags.get("lanes", "2"),
                "maxspeed": tags.get("maxspeed", "60"),
                "oneway": tags.get("oneway", "no"),
            },
            "geometry": {
                "type": "LineString",
                "coordinates": coords,
            },
        }
        features.append(feature)

    return {
        "type": "FeatureCollection",
        "generator": "IDR OpenStreetMap Extractor",
        "features": features,
    }


def main():
    parser = argparse.ArgumentParser(description="Download offline OSM road network for IDR engine.")
    parser.add_argument("--preset", choices=list(PRESETS.keys()), help="Preset Indian highway benchmark area")
    parser.add_argument("--bbox", help="Custom bounding box: south,west,north,east (e.g. 18.5,73.8,18.6,73.9)")
    parser.add_argument(
        "--level",
        choices=list(ROAD_LEVELS.keys()),
        default=None,
        help="Road classification level: 'highways' (motorway/trunk), 'arterials' (+primary/secondary), 'all' (adds minor/residential/service). Default: preset default or 'highways'.",
    )
    parser.add_argument("--output", help="Output .geojson file path")

    args = parser.parse_args()

    preset_info = None
    if args.preset:
        preset_info = PRESETS[args.preset]
        south, west, north, east = preset_info["bbox"]
        default_out = f"assets/maps/{args.preset}.geojson"
        print(f"[*] Selected Preset: {args.preset} - {preset_info['description']}")
    elif args.bbox:
        parts = [float(p.strip()) for p in args.bbox.split(",")]
        if len(parts) != 4:
            sys.exit("Error: --bbox must have 4 comma-separated values: south,west,north,east")
        south, west, north, east = parts
        default_out = "assets/maps/custom_osm_roads.geojson"
    else:
        print("[!] No preset or bbox provided. Defaulting to 'mumbai_pune_expressway'.")
        preset_info = PRESETS["mumbai_pune_expressway"]
        south, west, north, east = preset_info["bbox"]
        default_out = "assets/maps/mumbai_pune_expressway.geojson"

    level_key = args.level or (preset_info.get("default_level", "highways") if preset_info else "highways")
    road_filter = ROAD_LEVELS[level_key]["filter"]
    print(f"[*] Road Filter Level: '{level_key}' ({ROAD_LEVELS[level_key]['description']})", flush=True)

    lat_span = abs(north - south)
    lon_span = abs(east - west)
    if level_key == "all" and (lat_span > 0.25 or lon_span > 0.25):
        print("[!] NOTICE: Querying 'all' minor roads over a large regional box (>25km) may take longer or hit server memory limits.", flush=True)
        print("    Recommendation: Use '--level arterials' for regional networks, or a tighter bbox for full minor street grids.", flush=True)

    out_file = args.output or default_out
    os.makedirs(os.path.dirname(out_file), exist_ok=True)

    print(f"[*] Bounding Box: South={south}, West={west}, North={north}, East={east}")
    query = build_overpass_query(south, west, north, east, road_filter)

    try:
        raw_data = download_osm_data(query)
        geojson = overpass_to_geojson(raw_data)
        num_roads = len(geojson["features"])

        with open(out_file, "w", encoding="utf-8") as f:
            json.dump(geojson, f, indent=2)

        print(f"[OK] Successfully downloaded {num_roads} road segments!", flush=True)
        print(f"[OK] Saved offline road network to: {out_file}", flush=True)
        print("\nNext step: Load into Flutter using:", flush=True)
        print(f"  final branches = await OsmMapLoader.loadFromAsset('{out_file}');", flush=True)
        print("  final snapper = MapSnapper(branches: branches);", flush=True)


    except Exception as e:
        sys.exit(f"Error during OSM download: {e}")


if __name__ == "__main__":
    main()
