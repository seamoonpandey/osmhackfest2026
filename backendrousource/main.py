from fastapi import FastAPI, Depends, Form, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import HTMLResponse
from sqlalchemy.orm import Session
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker
import shutil, json

# -----------------------------
# FastAPI setup
# -----------------------------
app = FastAPI(title="Pokhara Road Risk Dashboard")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.mount("/uploads", StaticFiles(directory="uploads"), name="uploads")

# -----------------------------
# Database setup
# -----------------------------
DB_URL = "postgresql+psycopg2://postgres:Kiran5000%40@localhost:5432/postgis_36_sample"
engine = create_engine(DB_URL)
SessionLocal = sessionmaker(bind=engine)

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
# Get roads with dynamic risk
# -----------------------------
@app.get("/roads")
def get_roads(db: Session = Depends(get_db)):

    # Fetch roads and join with road_issues to get max severity
    q = text("""
        SELECT
            r.id,
            r.name,
            r.highway,
            r.road_class,
            COALESCE(r.initial_risk, 0) AS initial_risk,
            ST_AsGeoJSON(r.geom) AS geom,
            COALESCE(MAX(ri.severity), 0) AS max_severity
        FROM roads r
        LEFT JOIN road_issues ri ON r.id = ri.road_id
        GROUP BY r.id
    """)

    rows = db.execute(q).fetchall()
    features = []

    for r in rows:
        initial_risk = r.initial_risk or 0
        max_severity = r.max_severity or 0

        # Weighted current risk calculation
        severity_risk = (max_severity / 5) * 100  # normalize to 0-100
        current_risk = 0.7 * initial_risk + 0.3 * severity_risk
        current_risk = min(current_risk, 100)

        # Update current_risk in DB
        db.execute(
            text("UPDATE roads SET current_risk=:risk WHERE id=:id"),
            {"risk": current_risk, "id": r.id}
        )

        try:
            geom_json = json.loads(r.geom)
        except:
            geom_json = None

        features.append({
            "type": "Feature",
            "geometry": geom_json,
            "properties": {
                "id": r.id,
                "name": r.name or 'Unnamed Road',
                "highway": r.highway or 'Unknown',
                "road_class": r.road_class or 'Other',
                "initial_risk": round(initial_risk, 2),
                "risk": round(current_risk, 2),
                "severity": max_severity
            }
        })

    db.commit()
    return {"type": "FeatureCollection", "features": features}


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

    # Insert new issue into road_issues table
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

    db.commit()
    return {"status": "Issue reported successfully"}

# -----------------------------
# Get issues (potholes, etc)
# -----------------------------
@app.get("/issues")
def get_issues(db: Session = Depends(get_db)):
    q = text("""
        SELECT
            id,
            road_id,
            issue_type,
            severity,
            photo_path,
            ST_AsGeoJSON(geom) AS geom
        FROM road_issues
    """)
    rows = db.execute(q).fetchall()
    features = []

    for r in rows:
        try:
            geom_json = json.loads(r.geom) if r.geom else None
        except:
            geom_json = None

        features.append({
            "type": "Feature",
            "geometry": geom_json,
            "properties": {
                "id": r.id,
                "road_id": r.road_id,
                "type": r.issue_type,
                "severity": r.severity,
                "photo": r.photo_path
            }
        })

    return {"type": "FeatureCollection", "features": features}
