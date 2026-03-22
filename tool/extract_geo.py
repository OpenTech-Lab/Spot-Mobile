"""
Converts Natural Earth Shapefiles → assets/geo/places.db (SQLite).

Run once from the project root:
    python3 tool/extract_geo.py

Sources:
  assets/data/ne_10m_populated_places_simple/  (7,342 cities)
  assets/data/ne_110m_admin_0_countries/        (177 country polygons — not stored,
                                                  country name is taken from adm0name
                                                  in the populated places file)
Output:
  assets/geo/places.db  — SQLite with a single `cities` table:
    id       INTEGER PRIMARY KEY
    name     TEXT     display name (UTF-8, e.g. "Tōkyō")
    country  TEXT     country name (e.g. "Japan")
    lat      REAL
    lon      REAL
"""

import os
import sqlite3
import shapefile  # pip install pyshp

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHP  = os.path.join(ROOT, 'assets', 'data',
                    'ne_10m_populated_places_simple',
                    'ne_10m_populated_places_simple.shp')
OUT  = os.path.join(ROOT, 'assets', 'geo', 'places.db')

os.makedirs(os.path.dirname(OUT), exist_ok=True)
if os.path.exists(OUT):
    os.remove(OUT)

conn = sqlite3.connect(OUT)
cur  = conn.cursor()

cur.execute('''
CREATE TABLE cities (
    id      INTEGER PRIMARY KEY,
    name    TEXT    NOT NULL,
    country TEXT    NOT NULL,
    lat     REAL    NOT NULL,
    lon     REAL    NOT NULL
)
''')

sf     = shapefile.Reader(SHP)
fnames = [f[0] for f in sf.fields[1:]]

# Resolve column indices once
i_name    = fnames.index('name')
i_country = fnames.index('adm0name')
i_lat     = fnames.index('latitude')
i_lon     = fnames.index('longitude')

rows = []
for rec in sf.records():
    name    = str(rec[i_name]).strip()
    country = str(rec[i_country]).strip()
    try:
        lat = float(rec[i_lat])
        lon = float(rec[i_lon])
    except (TypeError, ValueError):
        continue
    if name and country:
        rows.append((name, country, lat, lon))

cur.executemany(
    'INSERT INTO cities (name, country, lat, lon) VALUES (?, ?, ?, ?)',
    rows,
)

# Bounding-box indexes speed up the lat/lon pre-filter in Flutter
cur.execute('CREATE INDEX idx_lat ON cities(lat)')
cur.execute('CREATE INDEX idx_lon ON cities(lon)')

conn.commit()
conn.close()

size_kb = os.path.getsize(OUT) / 1024
print(f'OK — {len(rows):,} cities → {OUT}  ({size_kb:.0f} KB)')
