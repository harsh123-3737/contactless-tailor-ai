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
from mediapipe.tasks import python
from mediapipe.tasks.python import vision
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi import FastAPI, File, UploadFile, Form
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import DateTime, Integer, String, create_engine, func, select
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column, sessionmaker


DATABASE_URL = f"sqlite:///{(Path(__file__).resolve().parent / 'analytics.db').as_posix()}"
engine = create_engine(
    DATABASE_URL,
    connect_args={"check_same_thread": False},
)
SessionLocal = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


class AnalyticsBase(DeclarativeBase):
    pass


class ScanRecord(AnalyticsBase):
    __tablename__ = "scan_records"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    customer_name: Mapped[str] = mapped_column(String(120), nullable=False)
    recommended_size: Mapped[str] = mapped_column(String(12), nullable=False, index=True)
    fit_preference: Mapped[str] = mapped_column(String(40), nullable=False, index=True)
    timestamp: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=lambda: datetime.now(timezone.utc), index=True
    )


AnalyticsBase.metadata.create_all(bind=engine)


class ScanCreate(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)

    customer_name: str = Field(min_length=1, max_length=120)
    recommended_size: str = Field(min_length=1, max_length=12)
    fit_preference: str = Field(min_length=1, max_length=40)
    timestamp: Optional[datetime] = None

def get_size_recommendation(measurements: dict) -> dict:
    """
    Analyzes raw biometric measurements and outputs a standard clothing size.
    (Using Shoulder Width as the primary anchor for this prototype).
    """
    shoulder_cm = measurements.get("shoulder_width", {}).get("cm", 42.0)
    
    # Simple rule-based sizing algorithm
    if shoulder_cm < 40.0:
        size = "S"
        fit_type = "Slim Fit"
    elif 40.0 <= shoulder_cm < 44.0:
        size = "M"
        fit_type = "Regular Fit"
    elif 44.0 <= shoulder_cm < 48.0:
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

# ---> ADD THIS ENTIRE BLOCK <---
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:5173","https://contactless-tailor-ai.vercel.app/"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
# -------------------------------


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
            pixel_height = calculate_distance(nose, mid_ankle) * 1.08
            ppc = pixel_height / height_cm

        # 4. Draw pose skeleton
        for pt in pts.values():
            cv2.circle(img_body, pt, 4, (0, 0, 255), -1)
        for start, end in POSE_CONNECTIONS:
            if start in pts and end in pts:
                cv2.line(img_body, pts[start], pts[end], (0, 255, 0), 2)

        def to_units(px):
            val_cm = px / ppc
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
