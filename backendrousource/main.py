from fastapi import FastAPI, Depends, Form, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import HTMLResponse
from sqlalchemy.orm import Session
from sqlalchemy import text
from db import SessionLocal
import shutil, json
from shapely import wkt

# -----------------------------
# FastAPI setup
# -----------------------------
app = FastAPI(title="Pokhara Road Risk Dashboard")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"]
)

app.mount("/uploads", StaticFiles(directory="uploads"), name="uploads")

# -----------------------------
# Dependency
# -----------------------------
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

# -----------------------------
# Home page
# -----------------------------
@app.get("/", response_class=HTMLResponse)
def home():
    return open("dashboard.html", encoding="utf-8").read()

# -----------------------------
# Get roads with risk
# -----------------------------
@app.get("/roads")
def get_roads(db: Session = Depends(get_db)):
    try:
        q = text("""
            SELECT
                id,
                name,
                highway,
                road_class,
                COALESCE(initial_risk,0) AS initial_risk,
                COALESCE(current_risk, initial_risk) AS current_risk,
                ST_AsText(geom) AS wkt
            FROM roads
        """)
        rows = db.execute(q).fetchall()
        features = []

        for r in rows:
            initial_risk = r.initial_risk or 0
            current_risk = r.current_risk or initial_risk

            # Convert WKT to GeoJSON
            try:
                geom_obj = wkt.loads(r.wkt)
                geom_json = json.loads(json.dumps(geom_obj.__geo_interface__))
            except:
                geom_json = None

            features.append({
                "type": "Feature",
                "geometry": geom_json,
                "properties": {
                    "id": r.id,
                    "name": r.name or "Unnamed Road",
                    "highway": r.highway or "Unknown",
                    "road_class": r.road_class or "Other",
                    "initial_risk": round(initial_risk, 2),
                    "risk": round(current_risk, 2)
                }
            })

        return {"type": "FeatureCollection", "features": features}

    except Exception as e:
        import traceback
        print(f"Database error (likely missing PostGIS), failing over to mock data: {e}")
        # Mock Response for testing without PostGIS
        return {
            "type": "FeatureCollection",
            "features": [
                {
                    "type": "Feature",
                    "geometry": {
                        "type": "LineString",
                        "coordinates": [
                            [85.3240, 27.7120], [85.3241, 27.7130], [85.3242, 27.7140],
                            [85.3243, 27.7150], [85.3243, 27.7160], [85.3242, 27.7170],
                            [85.3241, 27.7180], [85.3238, 27.7195]
                        ]
                    },
                    "properties": {
                        "id": 101, "name": "Durbar Marg (Backend Mock)", "highway": "primary",
                        "road_class": "Primary", "initial_risk": 50, "risk": 80.5
                    }
                },
                {
                    "type": "Feature",
                    "geometry": {
                        "type": "LineString",
                        "coordinates": [
                           [85.3200, 27.7185], [85.3197, 27.7200], [85.3190, 27.7215],
                           [85.3180, 27.7230], [85.3175, 27.7235]
                        ]
                    },
                    "properties": {
                        "id": 102, "name": "Lazimpat (Backend Mock)", "highway": "secondary",
                        "road_class": "Secondary", "initial_risk": 30, "risk": 45.0
                    }
                }
            ]
        }

import os

# -----------------------------
# Ensure uploads directory exists
# -----------------------------
os.makedirs("uploads", exist_ok=True)

# -----------------------------
# InMemory Store for fallback (with File Persistence)
# -----------------------------
MOCK_DATA_FILE = "mock_data.json"

def load_mock_data():
    if os.path.exists(MOCK_DATA_FILE):
        try:
            with open(MOCK_DATA_FILE, "r") as f:
                return json.load(f)
        except:
            return []
    return []

def save_mock_data(data):
    try:
        with open(MOCK_DATA_FILE, "w") as f:
            json.dump(data, f)
    except Exception as e:
        print(f"Failed to save mock data: {e}")

MOCK_ISSUES_STORE = load_mock_data()

# -----------------------------
# Get formatted issues (potholes, etc)
# -----------------------------
@app.get("/issues")
def get_issues(db: Session = Depends(get_db)):
    try:
        # Fetch individual issues
        result = db.execute(text("""
            SELECT 
                ri.id, 
                ri.road_id, 
                ri.issue_type, 
                ri.severity, 
                ri.photo_path,
                ST_AsText(ri.geom) as wkt
            FROM road_issues ri
        """)).fetchall()

        features = []
        for row in result:
            try:
                # Parse WKT to GeoJSON geometry
                geom_obj = wkt.loads(row.wkt)
                geom_json = json.loads(json.dumps(geom_obj.__geo_interface__))
            except:
                geom_json = None
            
            features.append({
                "type": "Feature",
                "geometry": geom_json,
                "properties": {
                    "id": row.id,
                    "road_id": row.road_id,
                    "type": row.issue_type,
                    "severity": row.severity,
                    "photo": row.photo_path
                }
            })

        return {"type": "FeatureCollection", "features": features}

    except Exception as e:
        print(f"Database error (likely missing PostGIS), serving from In-Memory Store: {e}")
        return {
            "type": "FeatureCollection",
            "features": MOCK_ISSUES_STORE
        }

# -----------------------------
# Report issue
# -----------------------------
@app.post("/report")
def report_issue(
    road_id: int = Form(...),
    issue_type: str = Form(...),
    severity: int = Form(...),
    lat: float = Form(...),
    lon: float = Form(...),
    photo: UploadFile = File(None),
    db: Session = Depends(get_db)
):
    photo_path = None
    if photo:
        photo_path = f"uploads/{photo.filename}"
        with open(photo_path, "wb") as f:
            shutil.copyfileobj(photo.file, f)

    try:
        db.execute(text("""
            INSERT INTO road_issues
            (road_id, issue_type, severity, geom, photo_path)
            VALUES
            (:road_id, :issue_type, :severity,
             ST_SetSRID(ST_Point(:lon, :lat), 4326),
             :photo)
        """), {
            "road_id": road_id,
            "issue_type": issue_type,
            "severity": severity,
            "lat": lat,
            "lon": lon,
            "photo": photo_path
        })

        # Recalculate current_risk for this road
        db.execute(text("""
            UPDATE roads r
            SET current_risk = LEAST(
                0.7*r.initial_risk + 0.3*COALESCE(max_sev,0)/5*100,
                100
            )
            FROM (
                SELECT MAX(severity) AS max_sev
                FROM road_issues
                WHERE road_id = :road_id
            ) AS sub
            WHERE r.id = :road_id
        """), {"road_id": road_id})

        db.commit()
    except Exception as e:
         print(f"Database error (running in mock mode): {e}")
         
         # Fallback: Save to In-Memory Store
         import time
         new_id = int(time.time())
         MOCK_ISSUES_STORE.append({
            "type": "Feature",
            "geometry": {
                "type": "Point",
                "coordinates": [lon, lat]
            },
            "properties": {
                "id": new_id,
                "road_id": road_id,
                "type": issue_type,
                "severity": severity,
                "photo": photo_path
            }
         })
         save_mock_data(MOCK_ISSUES_STORE)
         print(f"MOCK MOCK: Saved report {new_id} to memory. Total issues: {len(MOCK_ISSUES_STORE)}")

    return {"status": "Issue reported successfully"}
