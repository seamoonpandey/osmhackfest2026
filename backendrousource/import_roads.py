import json
import psycopg2
from psycopg2.extras import execute_values

# -----------------------------
# 1️⃣ Database configuration
# -----------------------------
DB_NAME = "osmapp"
DB_USER = "moon"
DB_PASS = ""
DB_HOST = "localhost"
DB_PORT = "5432"

GEOJSON_PATH = r"export.geojson"

# -----------------------------
# 2️⃣ Connect to PostGIS
# -----------------------------
conn = psycopg2.connect(
    dbname=DB_NAME, user=DB_USER, password=DB_PASS, host=DB_HOST, port=DB_PORT
)
cur = conn.cursor()

# Enable PostGIS extension
cur.execute("CREATE EXTENSION IF NOT EXISTS postgis;")

# -----------------------------
# 3️⃣ Create tables if not exist
# -----------------------------
cur.execute("""
CREATE TABLE IF NOT EXISTS roads (
    id SERIAL PRIMARY KEY,
    name TEXT,
    highway TEXT,
    road_class TEXT,
    geom GEOMETRY(MULTILINESTRING, 4326),
    initial_risk FLOAT,
    current_risk FLOAT DEFAULT 0
);
""")

cur.execute("""
CREATE TABLE IF NOT EXISTS road_issues (
    id SERIAL PRIMARY KEY,
    road_id BIGINT REFERENCES roads(id),
    issue_type TEXT,
    severity INT,
    geom GEOMETRY(Point, 4326),
    photo_path TEXT,
    created_at TIMESTAMP DEFAULT now()
);
""")

conn.commit()
print("✅ Tables ready.")

# -----------------------------
# 4️⃣ Load GeoJSON
# -----------------------------
with open(GEOJSON_PATH, "r", encoding="utf-8") as f:
    data = json.load(f)

features = data["features"]

# -----------------------------
# 5️⃣ Prepare roads for insertion
# -----------------------------
rows_to_insert = []

for feat in features:
    props = feat.get("properties", {})
    geom = feat.get("geometry")

    if not geom or geom.get("type") not in ["LineString", "MultiLineString"]:
        continue

    highway = (props.get("highway") or "").lower()

    # Assign road_class + initial_risk
    if highway == "trunk":
        road_class = "Trunk"
        initial_risk = 80
    elif highway == "primary":
        road_class = "Primary"
        initial_risk = 70
    elif highway == "secondary":
        road_class = "Secondary"
        initial_risk = 55
    elif highway == "tertiary":
        road_class = "Tertiary"
        initial_risk = 40
    elif highway == "residential":
        road_class = "Residential"
        initial_risk = 25
    elif highway in ["unclassified", "track", "footway"]:
        road_class = "Unclassified/Track/Footway"
        initial_risk = 15
    else:
        road_class = "Other"
        initial_risk = 0

    # Convert geometry to WKT
    geom_wkt = None
    if geom["type"] == "LineString":
        coords = ", ".join(f"{c[0]} {c[1]}" for c in geom["coordinates"])
        geom_wkt = f"LINESTRING({coords})"
    elif geom["type"] == "MultiLineString":
        lines = []
        for line in geom["coordinates"]:
            coords = ", ".join(f"{c[0]} {c[1]}" for c in line)
            lines.append(f"({coords})")
        geom_wkt = f"MULTILINESTRING({', '.join(lines)})"

    rows_to_insert.append((props.get("name"), highway, road_class, geom_wkt, initial_risk))

# -----------------------------
# 6️⃣ Insert roads into PostGIS
# -----------------------------
sql = """
INSERT INTO roads (name, highway, road_class, geom, initial_risk)
VALUES %s
ON CONFLICT DO NOTHING
"""
execute_values(
    cur,
    sql,
    [(name, highway, road_class, f"SRID=4326;{geom}", risk) for name, highway, road_class, geom, risk in rows_to_insert],
    template="(%s, %s, %s, ST_GeomFromText(%s), %s)"
)

conn.commit()
print(f"✅ Inserted {len(rows_to_insert)} roads.")

# -----------------------------
# 7️⃣ Compute current_risk based on road_issues
# -----------------------------
cur.execute("""
UPDATE roads r
SET current_risk = LEAST(
    0.7 * r.initial_risk + 0.3 * COALESCE(max_sev.max_sev, 0) / 5 * 100,
    100
)
FROM (
    SELECT road_id, MAX(severity) AS max_sev
    FROM road_issues
    GROUP BY road_id
) AS max_sev
WHERE r.id = max_sev.road_id;
""")

# For roads with no issues, current_risk = initial_risk
cur.execute("""
UPDATE roads
SET current_risk = initial_risk
WHERE current_risk IS NULL OR current_risk = 0;
""")

conn.commit()
cur.close()
conn.close()
print("✅ current_risk calculated for all roads.")
print("🎉 Database ready for FastAPI dashboard!")
