from sqlalchemy import Column, Integer, String, Float, ForeignKey, DateTime, JSON
from sqlalchemy.orm import relationship
from datetime import datetime
from database import Base

class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, nullable=False)
    email = Column(String, unique=True, index=True, nullable=False)
    password_hash = Column(String, nullable=False)
    gender = Column(String, nullable=False)  # "Male" or "Female"
    created_at = Column(DateTime, default=datetime.utcnow)

    measurements = relationship("Measurement", back_populates="user")


class Measurement(Base):
    __tablename__ = "measurements"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    shoulder_cm = Column(Float, nullable=False)
    hip_cm = Column(Float, nullable=False)
    sleeve_cm = Column(Float, nullable=False)
    leg_cm = Column(Float, nullable=False)
    torso_cm = Column(Float, nullable=False)
    recommended_size = Column(String, nullable=False)  # S, M, L, XL
    calibration_method = Column(String, nullable=False) # A4 Paper or User Height
    created_at = Column(DateTime, default=datetime.utcnow)

    user = relationship("User", back_populates="measurements")


class Product(Base):
    __tablename__ = "products"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, nullable=False)
    category = Column(String, nullable=False)  # Shirt, T-Shirt, Kurti, Jeans
    gender = Column(String, nullable=False)    # "Male", "Female", or "Unisex"
    price = Column(Float, nullable=False)
    image_url = Column(String, nullable=False)
    # Example size_chart: {"S": {"shoulder_cm": 40.5}, "M": {"shoulder_cm": 43.0}, "L": {"shoulder_cm": 46.0}}
    size_chart = Column(JSON, nullable=False)