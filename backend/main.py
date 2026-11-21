from typing import Optional
from datetime import datetime, time, timedelta, timezone
from pathlib import Path
import trimesh
import os
import cv2
import numpy as np
import mediapipe as mp
import math
import uuid
import bcrypt  # <-- NEW: Password hashing mate
from mediapipe.tasks import python
from mediapipe.tasks.python import vision
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse
from fastapi import FastAPI, File, UploadFile, Form, Depends, HTTPException  # <-- NEW: Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import DateTime, Integer, String, func, select
from sqlalchemy.orm import Mapped, Session, mapped_column

# <-- NEW: database.py ane models.py mathi import karo
from database import engine, SessionLocal, Base, get_db
import models


# Tamaro junu ScanRecord table (Base par shift karyu etle badha tables ek j jagya e rahe)
class ScanRecord(Base):
    __tablename__ = "scan_records"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    customer_name: Mapped[str] = mapped_column(String(120), nullable=False)
    recommended_size: Mapped[str] = mapped_column(String(12), nullable=False, index=True)
    fit_preference: Mapped[str] = mapped_column(String(40), nullable=False, index=True)
    timestamp: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=lambda: datetime.now(timezone.utc), index=True
    )


# Badha tables (scan_records, users, measurements, products) auto-create thase
Base.metadata.create_all(bind=engine)


class ScanCreate(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)

    customer_name: str = Field(min_length=1, max_length=120)
    recommended_size: str = Field(min_length=1, max_length=12)
    fit_preference: str = Field(min_length=1, max_length=40)
    timestamp: Optional[datetime] = None


# --- NEW: Register & Login Schemas ---
class UserRegister(BaseModel):
    name: str
    email: str
    password: str
    gender: str  # "Male" or "Female"

class UserLogin(BaseModel):
    email: str
    password: str

def get_size_recommendation(measurements: dict) -> dict:
    """
    Analyzes raw biometric measurements and outputs a standard clothing size.
    (Using Shoulder Width as the primary anchor for this prototype).
    """
    shoulder_cm = measurements.get("shoulder_width", {}).get("cm", 42.0)
    
    # Simple rule-based sizing algorithm
    if shoulder_cm < 41.5:
        size = "S"
        fit_type = "Slim Fit"
    elif 41.5 <= shoulder_cm < 44.5:
        size = "M"
        fit_type = "Regular Fit"
    elif 44.5 <= shoulder_cm < 48.0:
        size = "L"
        fit_type = "Relaxed Fit"
    else:
        size = "XL"
        fit_type = "Relaxed Fit"
        
    return {
        "recommended_size": size,
        "fit_type": fit_type,
        "fit_notes": {
            "shoulder": f"Shoulder span ({shoulder_cm}cm) aligns perfectly with Size {size}.",
            "sleeves": "Standard sleeve length; minor tailoring may be required depending on brand."
        }
    }

app = FastAPI(title="AI Tailor Backend")


@app.get("/health")
def health_check():
    """Lightweight endpoint for external keep-alive pings (cron-job.org).
    Does not touch the database or MediaPipe, so it stays fast.
    """
    return {"status": "ok"}

# ---> ADD THIS ENTIRE BLOCK <---
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000","https://contactless-tailor-ai.vercel.app"],
    # Vercel generates a NEW random subdomain for every deployment
    # (e.g. contactless-tailor-jdup7p7l9-...vercel.app), so exact origins
    # keep breaking. This regex allows any *.vercel.app origin instead.
    allow_origin_regex=r"https://[a-z0-9-]+\.vercel\.app",
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
# -------------------------------
@app.post("/register")
def register_user(user: UserRegister, db: Session = Depends(get_db)):
    existing_user = db.query(models.User).filter(models.User.email == user.email).first()
    if existing_user:
        raise HTTPException(status_code=400, detail="Email already registered")

    hashed_pw = bcrypt.hashpw(user.password.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')

    new_user = models.User(
        name=user.name,
        email=user.email,
        password_hash=hashed_pw,
        gender=user.gender
    )
    db.add(new_user)
    db.commit()
    db.refresh(new_user)

    return {
        "message": "User registered successfully",
        "user_id": new_user.id,
        "name": new_user.name,
        "gender": new_user.gender
    }


@app.post("/login")
def login_user(user: UserLogin, db: Session = Depends(get_db)):
    db_user = db.query(models.User).filter(models.User.email == user.email).first()
    if not db_user:
        raise HTTPException(status_code=400, detail="Invalid email or password")

    if not bcrypt.checkpw(user.password.encode('utf-8'), db_user.password_hash.encode('utf-8')):
        raise HTTPException(status_code=400, detail="Invalid email or password")

    return {
        "message": "Login successful",
        "user_id": db_user.id,
        "name": db_user.name,
        "email": db_user.email,
        "gender": db_user.gender
    }

# ==========================================
# 3. SAVE & GET MEASUREMENTS (Scan History)
# ==========================================

class MeasurementCreate(BaseModel):
    user_id: int
    shoulder_cm: float
    hip_cm: float
    sleeve_cm: float
    leg_cm: float
    torso_cm: float
    recommended_size: str
    calibration_method: str  # "A4 Paper" or "User Height"


@app.post("/measurements")
def save_measurement(data: MeasurementCreate, db: Session = Depends(get_db)):
    user = db.query(models.User).filter(models.User.id == data.user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    new_m = models.Measurement(
        user_id=data.user_id,
        shoulder_cm=data.shoulder_cm,
        hip_cm=data.hip_cm,
        sleeve_cm=data.sleeve_cm,
        leg_cm=data.leg_cm,
        torso_cm=data.torso_cm,
        recommended_size=data.recommended_size,
        calibration_method=data.calibration_method
    )
    db.add(new_m)

    # Analytics Dashboard (Vercel) mate ScanRecord ma auto-save
    new_scan_log = ScanRecord(
        customer_name=user.name,
        recommended_size=data.recommended_size or "M",
        fit_preference="Regular Fit",
    )
    db.add(new_scan_log)

    db.commit()
    db.refresh(new_m)
    return {"message": "Measurement saved successfully", "measurement_id": new_m.id}


@app.get("/measurements/{user_id}")
def get_user_measurements(user_id: int, db: Session = Depends(get_db)):
    history = (
        db.query(models.Measurement)
        .filter(models.Measurement.user_id == user_id)
        .order_by(models.Measurement.created_at.desc())
        .all()
    )
    return {"user_id": user_id, "total_scans": len(history), "history": history}


# ==========================================
# 4. AI-FIT PRODUCTS API (Gender + Best Fit)
# ==========================================

def find_best_fit(user_shoulder_cm: float, size_chart: dict):
    best_size = None
    min_diff = float("inf")

    for size_label, dims in size_chart.items():
        garment_shoulder = dims.get("shoulder_cm", 0)
        diff = abs(user_shoulder_cm - garment_shoulder)
        if diff < min_diff:
            min_diff = diff
            best_size = size_label

    # Realistic match % (0 cm diff = 99%, 1 cm diff = ~95%)
    match_percent = max(70, min(99, round(99 - (min_diff * 4))))
    return best_size, match_percent


@app.get("/products/{user_id}")
def get_ai_fit_products(user_id: int, db: Session = Depends(get_db)):
    user = db.query(models.User).filter(models.User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    # User nu latest saved measurement fetch karo
    latest_scan = (
        db.query(models.Measurement)
        .filter(models.Measurement.user_id == user_id)
        .order_by(models.Measurement.created_at.desc())
        .first()
    )

    # User na gender mujab products filter karo
    products = (
        db.query(models.Product)
        .filter(models.Product.gender.in_([user.gender, "Unisex"]))
        .all()
    )

    result = []
    for p in products:
        if latest_scan:
            best_size, match_pct = find_best_fit(latest_scan.shoulder_cm, p.size_chart)
            fit_badge = f"Best Fit: {best_size} ({match_pct}% Match)"
        else:
            best_size = None
            match_pct = None
            fit_badge = "Scan body for AI Fit"

        result.append({
            "id": p.id,
            "name": p.name,
            "category": p.category,
            "gender": p.gender,
            "price": p.price,
            "image_url": p.image_url,
            "available_sizes": list(p.size_chart.keys()),
            "size_chart": p.size_chart,
            "ai_recommended_size": best_size,
            "match_percentage": match_pct,
            "fit_badge": fit_badge
        })

    return {
        "user_name": user.name,
        "gender": user.gender,
        "has_scan": latest_scan is not None,
        "products": result
    }

@app.post("/api/scans", status_code=201)
def create_scan(scan: ScanCreate):
    """Persist one completed mobile scan for merchant analytics."""
    scan_timestamp = scan.timestamp or datetime.now(timezone.utc)
    if scan_timestamp.tzinfo is None:
        scan_timestamp = scan_timestamp.replace(tzinfo=timezone.utc)

    with SessionLocal() as session:
        record = ScanRecord(
            customer_name=scan.customer_name,
            recommended_size=scan.recommended_size.upper(),
            fit_preference=scan.fit_preference,
            timestamp=scan_timestamp.astimezone(timezone.utc),
        )
        session.add(record)
        session.commit()
        session.refresh(record)
        return {
            "id": record.id,
            "customer_name": record.customer_name,
            "recommended_size": record.recommended_size,
            "fit_preference": record.fit_preference,
            "timestamp": record.timestamp,
        }

@app.get("/api/scans")
def get_analytics_scans(db: Session = Depends(get_db)):
    # Nava measurements table mathi latest scans fetch karo (User sathe join kari ne)
    records = (
        db.query(models.Measurement, models.User)
        .join(models.User, models.Measurement.user_id == models.User.id)
        .order_by(models.Measurement.id.desc())
        .all()
    )

    scans = []
    for m, u in records:
        scans.append({
            "id": m.id,
            "customer_name": u.name,
            "gender": u.gender,
            "recommended_size": m.recommended_size or "M",
            "fit_preference": "Regular Fit",
            "shoulder_cm": m.shoulder_cm,
            "hip_cm": m.hip_cm,
            "sleeve_cm": m.sleeve_cm,
            "leg_cm": m.leg_cm,
            "torso_cm": m.torso_cm,
            "created_at": m.created_at.isoformat() if m.created_at else "",
        })

    return scans

@app.get("/api/dashboard/stats")
def get_dashboard_stats():
    """Return aggregate scan counts in UTC, including zero-count days."""
    now_utc = datetime.now(timezone.utc)
    today_start = datetime.combine(now_utc.date(), time.min).replace(tzinfo=timezone.utc)
    chart_start = today_start - timedelta(days=6)
    # SQLite stores timezone-aware datetimes without an offset; query in UTC-naive form.
    today_start_db = today_start.replace(tzinfo=None)
    chart_start_db = chart_start.replace(tzinfo=None)

    with SessionLocal() as session:
        total_scans = session.scalar(select(func.count(ScanRecord.id))) or 0
        total_scans_today = session.scalar(
            select(func.count(ScanRecord.id)).where(ScanRecord.timestamp >= today_start_db)
        ) or 0

        size_rows = session.execute(
            select(ScanRecord.recommended_size, func.count(ScanRecord.id))
            .group_by(ScanRecord.recommended_size)
            .order_by(ScanRecord.recommended_size)
        ).all()
        fit_rows = session.execute(
            select(ScanRecord.fit_preference, func.count(ScanRecord.id))
            .group_by(ScanRecord.fit_preference)
            .order_by(ScanRecord.fit_preference)
        ).all()
        daily_rows = session.execute(
            select(func.date(ScanRecord.timestamp), func.count(ScanRecord.id))
            .where(ScanRecord.timestamp >= chart_start_db)
            .group_by(func.date(ScanRecord.timestamp))
        ).all()
        popular_size = session.execute(
            select(ScanRecord.recommended_size, func.count(ScanRecord.id))
            .group_by(ScanRecord.recommended_size)
            .order_by(func.count(ScanRecord.id).desc(), ScanRecord.recommended_size.asc())
            .limit(1)
        ).first()

    daily_counts = {str(day): count for day, count in daily_rows}
    scans_over_last_7_days = [
        {"date": (chart_start.date() + timedelta(days=offset)).isoformat(),
         "scans": daily_counts.get((chart_start.date() + timedelta(days=offset)).isoformat(), 0)}
        for offset in range(7)
    ]

    return {
        "total_scans": total_scans,
        "total_scans_today": total_scans_today,
        "most_popular_size": popular_size[0] if popular_size else None,
        "size_distribution": [{"name": size, "value": count} for size, count in size_rows],
        "fit_preferences": [{"name": fit, "value": count} for fit, count in fit_rows],
        "scans_over_last_7_days": scans_over_last_7_days,
    }

UPLOAD_DIR = "uploads"
os.makedirs(UPLOAD_DIR, exist_ok=True)

MODEL_PATH = "pose_landmarker.task"
base_options = python.BaseOptions(model_asset_path=MODEL_PATH)
options = vision.PoseLandmarkerOptions(base_options=base_options, output_segmentation_masks=False)
detector = vision.PoseLandmarker.create_from_options(options)

POSE_CONNECTIONS = [
    (0, 1), (1, 2), (2, 3), (3, 7), (0, 4), (4, 5), (5, 6), (6, 8), (9, 10),
    (11, 12), (11, 13), (13, 15), (15, 17), (15, 19), (15, 21), (17, 19),
    (12, 14), (14, 16), (16, 18), (16, 20), (16, 22), (18, 20),
    (11, 23), (12, 24), (23, 24), (23, 25), (25, 27), (27, 29), (27, 31), 
    (29, 31), (24, 26), (26, 28), (28, 30), (28, 32), (30, 32)
]


def calculate_distance(p1, p2):
    return math.hypot(p2[0] - p1[0], p2[1] - p1[1])

def find_a4_paper(img):
    """Detects A4 paper using edge detection and quadrilateral approximation
    to prevent merging with white/light clothing.
    """
    h_img, w_img, _ = img.shape
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    blurred = cv2.GaussianBlur(gray, (5, 5), 0)
    edged = cv2.Canny(blurred, 50, 150)

    # Dilate edges slightly to close small gaps
    kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (3, 3))
    dilated = cv2.dilate(edged, kernel, iterations=1)

    contours, _ = cv2.findContours(dilated, cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE)
    if not contours:
        return None, None

    # Sort contours by area descending
    contours = sorted(contours, key=cv2.contourArea, reverse=True)[:15]

    for c in contours:
        peri = cv2.arcLength(c, True)
        approx = cv2.approxPolyDP(c, 0.02 * peri, True)

        # A4 paper must have 4 corners
        if len(approx) == 4 and cv2.contourArea(c) > 20000:
            x, y, w, h = cv2.boundingRect(approx)
            aspect_ratio = max(w, h) / float(min(w, h))

            # A4 aspect ratio is ~1.414 (tolerance 1.15 to 1.65)
            center_x = x + (w / 2)
            is_centered = (w_img * 0.25) < center_x < (w_img * 0.75)

            if 1.15 < aspect_ratio < 1.65 and is_centered:
                paper_width_px = min(w, h)
                
                # Debug draw
                debug_img = img.copy()
                cv2.drawContours(debug_img, [approx], -1, (0, 255, 0), 3)
                cv2.imwrite(os.path.join(UPLOAD_DIR, "debug_paper_detection.jpg"), debug_img)

                return paper_width_px, approx

    return None, None
def generate_3d_mannequin(measurements: dict, output_path: str):
    """
    Generates a solid 3D humanoid mesh using geometric blocks 
    scaled precisely to the user's biometric tailoring metrics, 
    and exports it as a .glb file.
    """
    shoulder_w = measurements["shoulder_width"]["cm"] / 100.0  # meters
    torso_l = measurements["torso_length"]["cm"] / 100.0
    leg_l = measurements["leg_length"]["cm"] / 100.0
    hip_w = measurements["hip_width"]["cm"] / 100.0
    sleeve_l = measurements["sleeve_length"]["cm"] / 100.0

    with open(output_path, "w") as f:
        f.write("# Contactless AI Solid 3D Mannequin\n")
        
        v_idx = 1
        
        def add_box(cx, cy, cz, w, h, d):
            nonlocal v_idx
            verts = [
                (cx-w/2, cy-h/2, cz-d/2), (cx+w/2, cy-h/2, cz-d/2),
                (cx+w/2, cy+h/2, cz-d/2), (cx-w/2, cy+h/2, cz-d/2),
                (cx-w/2, cy-h/2, cz+d/2), (cx+w/2, cy-h/2, cz+d/2),
                (cx+w/2, cy+h/2, cz+d/2), (cx-w/2, cy+h/2, cz+d/2)
            ]
            for v in verts:
                f.write(f"v {v[0]:.4f} {v[1]:.4f} {v[2]:.4f}\n")
            
            faces = [
                (1,2,3), (1,3,4), (5,8,7), (5,7,6), # Front & Back
                (1,5,6), (1,6,2), (4,3,7), (4,7,8), # Bottom & Top
                (1,4,8), (1,8,5), (2,6,7), (2,7,3)  # Sides
            ]
            for face in faces:
                f.write(f"f {face[0]+v_idx-1} {face[1]+v_idx-1} {face[2]+v_idx-1}\n")
            v_idx += 8

        depth = 0.15 
        add_box(0, torso_l/2, 0, shoulder_w, torso_l, depth) # Torso
        add_box(0, torso_l + 0.15, 0, 0.18, 0.22, 0.18) # Head
        add_box(-shoulder_w/2 - 0.08, torso_l - sleeve_l/2, 0, 0.10, sleeve_l, 0.10) # Left Arm
        add_box(shoulder_w/2 + 0.08, torso_l - sleeve_l/2, 0, 0.10, sleeve_l, 0.10) # Right Arm
        add_box(-hip_w/4, -leg_l/2, 0, 0.12, leg_l, 0.12) # Left Leg
        add_box(hip_w/4, -leg_l/2, 0, 0.12, leg_l, 0.12) # Right Leg

    # Convert the saved .obj to a .glb with a solid color
  
@app.post("/upload")
async def upload_two_step(
    body_image: UploadFile = File(...),
    calib_image: Optional[UploadFile] = File(None),
    height_cm: Optional[float] = Form(None)
):
    try:
        body_path = os.path.join(UPLOAD_DIR, "body_" + body_image.filename)
        with open(body_path, "wb") as buffer:
            buffer.write(await body_image.read())

        img_body = cv2.imread(body_path)
        h, w, _ = img_body.shape
        ppc = 0.0
        calibration_method = ""

        # 1. Process calibration image if provided
        if calib_image:
            calib_path = os.path.join(UPLOAD_DIR, "calib_" + calib_image.filename)
            with open(calib_path, "wb") as buffer:
                buffer.write(await calib_image.read())
            
            img_calib = cv2.imread(calib_path)
            paper_width_px, paper_contour = find_a4_paper(img_calib)
            
            if paper_width_px:
                ppc = paper_width_px / 21.0
                calibration_method = "A4 Paper (Step 1)"
                cv2.drawContours(img_calib, [paper_contour], -1, (255, 0, 0), 3)
                cv2.imwrite(os.path.join(UPLOAD_DIR, "annotated_calib_" + calib_image.filename), img_calib)
            os.remove(calib_path)

        # 2. Extract pose landmarks from body image
        mp_image = mp.Image.create_from_file(body_path)
        detection_result = detector.detect(mp_image)

        if not detection_result.pose_landmarks:
            if os.path.exists(body_path):
                os.remove(body_path)
            return JSONResponse(content={"error": "No human body detected in body image."}, status_code=400)

        landmarks = detection_result.pose_landmarks[0]
        pts = {idx: (int(l.x * w), int(l.y * h)) for idx, l in enumerate(landmarks)}

        # 3. Fallback to height calibration if A4 detection failed or was absent
        if ppc == 0.0:
            if height_cm is None:
                if os.path.exists(body_path):
                    os.remove(body_path)
                return JSONResponse(content={"error": "A4_FAILED_NEED_HEIGHT"}, status_code=400)
            
            calibration_method = "User Height"
            nose = pts[0]
            mid_ankle = ((pts[27][0] + pts[28][0]) / 2, (pts[27][1] + pts[28][1]) / 2)
            pixel_height = calculate_distance(nose, mid_ankle) * 1.25
            ppc = pixel_height / height_cm

        # 4. Draw pose skeleton
        for pt in pts.values():
            cv2.circle(img_body, pt, 4, (0, 0, 255), -1)
        for start, end in POSE_CONNECTIONS:
            if start in pts and end in pts:
                cv2.line(img_body, pts[start], pts[end], (0, 255, 0), 2)

        calib_multiplier = 1.18 if calibration_method == "A4 Paper (Step 1)" else 1.0

        def to_units(px):
            # Ahiya calibration multiplier (1.18) add karyo che
            val_cm = (px / ppc) * calib_multiplier 
            return {"cm": round(val_cm, 1), "in": round(val_cm / 2.54, 1)}

       # Base pixel distances (Raw Skeleton)
        raw_shoulder_px = calculate_distance(pts[11], pts[12])
        raw_hip_px = calculate_distance(pts[23], pts[24])
        raw_l_sleeve_px = calculate_distance(pts[11], pts[13]) + calculate_distance(pts[13], pts[15])
        raw_r_sleeve_px = calculate_distance(pts[12], pts[14]) + calculate_distance(pts[14], pts[16])
        raw_l_leg_px = calculate_distance(pts[23], pts[25]) + calculate_distance(pts[25], pts[27])
        raw_r_leg_px = calculate_distance(pts[24], pts[26]) + calculate_distance(pts[26], pts[28])
        
        mid_shoulder = ((pts[11][0] + pts[12][0]) / 2, (pts[11][1] + pts[12][1]) / 2)
        mid_hip = ((pts[23][0] + pts[24][0]) / 2, (pts[23][1] + pts[24][1]) / 2)
        raw_torso_px = calculate_distance(mid_shoulder, mid_hip)

        # Apply Biometric Tailoring Multipliers
        measurements = {
            "shoulder_width": to_units(raw_shoulder_px * 1.30),
            "hip_width": to_units(raw_hip_px * 1.20),
            "sleeve_length": to_units(((raw_l_sleeve_px + raw_r_sleeve_px) / 2) * 1.15),
            "leg_length": to_units(((raw_l_leg_px + raw_r_leg_px) / 2) * 1.20),
            "torso_length": to_units(raw_torso_px * 1.10),
            "calibration_ppc": round(ppc, 2)
        }

        annotated_filename = f"annotated_body_{body_image.filename}"
        cv2.imwrite(os.path.join(UPLOAD_DIR, annotated_filename), img_body)
        os.remove(body_path)

        # ---> 3D GENERATION TRIGGER <---
        scan_id = str(uuid.uuid4())
        obj_path = os.path.join(UPLOAD_DIR, f"{scan_id}_model.obj")
        generate_3d_mannequin(measurements, obj_path)

        # 1. Run the measurements through the new sizing algorithm
        sizing_data = get_size_recommendation(measurements)

        # 2. Return the updated JSON to Flutter
        return JSONResponse(
            content={
                "message": "Metrics generated",
                "filename": annotated_filename,
                "calibration_method": calibration_method,
                "measurements": measurements,
                "sizing": sizing_data,     # <--- ADDED SIZING DATA HERE
                "scan_id": scan_id 
            },
            status_code=200
        )

    except Exception as e:
        return JSONResponse(content={"error": str(e)}, status_code=500)
    
# ---> NEW GET ENDPOINT FOR 3D MODEL <---
# Replace your current @app.get endpoint with this:
@app.get("/model-3d/{scan_id}.obj")
async def get_3d_model(scan_id: str):
    obj_path = os.path.join(UPLOAD_DIR, f"{scan_id}_model.obj")
    if os.path.exists(obj_path):
        return FileResponse(obj_path, media_type="text/plain", filename="avatar.obj")
    return {"error": "Model not found"}
