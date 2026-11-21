from database import SessionLocal, engine, Base
import models

# Ensure tables exist
Base.metadata.create_all(bind=engine)

def seed_products():
    db = SessionLocal()

    # Check if products already exist to avoid duplicates
    if db.query(models.Product).count() > 0:
        print("Products already exist in database!")
        db.close()
        return

    sample_products = [
        # --- MEN'S CLOTHING (5 Items) ---
        models.Product(
            name="Classic Cotton Slim Fit Shirt",
            category="Shirt",
            gender="Male",
            price=899.0,
            image_url="https://images.unsplash.com/photo-1596755094514-f87e34085b2c?w=500",
            size_chart={
                "S": {"shoulder_cm": 40.5, "torso_cm": 60.0, "sleeve_cm": 60.0},
                "M": {"shoulder_cm": 43.0, "torso_cm": 62.5, "sleeve_cm": 62.0},
                "L": {"shoulder_cm": 45.5, "torso_cm": 65.0, "sleeve_cm": 64.0},
                "XL": {"shoulder_cm": 48.0, "torso_cm": 67.5, "sleeve_cm": 66.0},
            }
        ),
        models.Product(
            name="Solid Round Neck T-Shirt",
            category="T-Shirt",
            gender="Male",
            price=499.0,
            image_url="https://images.unsplash.com/photo-1521572163474-6864f9cf17ab?w=500",
            size_chart={
                "S": {"shoulder_cm": 40.0, "torso_cm": 58.0, "sleeve_cm": 20.0},
                "M": {"shoulder_cm": 42.5, "torso_cm": 60.5, "sleeve_cm": 21.5},
                "L": {"shoulder_cm": 45.0, "torso_cm": 63.0, "sleeve_cm": 23.0},
                "XL": {"shoulder_cm": 47.5, "torso_cm": 65.5, "sleeve_cm": 24.5},
            }
        ),
        models.Product(
            name="Urban Denim Jacket",
            category="Jacket",
            gender="Male",
            price=1899.0,
            image_url="https://images.unsplash.com/photo-1576995853123-5a10305d93c0?w=500",
            size_chart={
                "S": {"shoulder_cm": 41.5, "torso_cm": 61.0, "sleeve_cm": 61.0},
                "M": {"shoulder_cm": 44.0, "torso_cm": 63.5, "sleeve_cm": 63.0},
                "L": {"shoulder_cm": 46.5, "torso_cm": 66.0, "sleeve_cm": 65.0},
                "XL": {"shoulder_cm": 49.0, "torso_cm": 68.5, "sleeve_cm": 67.0},
            }
        ),
        models.Product(
            name="Casual Checked Flannel Shirt",
            category="Shirt",
            gender="Male",
            price=1199.0,
            image_url="https://images.unsplash.com/photo-1589310243389-96a5483213a8?w=500",
            size_chart={
                "S": {"shoulder_cm": 41.0, "torso_cm": 60.5, "sleeve_cm": 60.5},
                "M": {"shoulder_cm": 43.5, "torso_cm": 63.0, "sleeve_cm": 62.5},
                "L": {"shoulder_cm": 46.0, "torso_cm": 65.5, "sleeve_cm": 64.5},
                "XL": {"shoulder_cm": 48.5, "torso_cm": 68.0, "sleeve_cm": 66.5},
            }
        ),
        models.Product(
            name="Polo Collar Regular T-Shirt",
            category="T-Shirt",
            gender="Male",
            price=699.0,
            image_url="https://images.unsplash.com/photo-1586363104862-3a5e2ab60d99?w=500",
            size_chart={
                "S": {"shoulder_cm": 40.5, "torso_cm": 59.0, "sleeve_cm": 21.0},
                "M": {"shoulder_cm": 43.0, "torso_cm": 61.5, "sleeve_cm": 22.0},
                "L": {"shoulder_cm": 45.5, "torso_cm": 64.0, "sleeve_cm": 23.5},
                "XL": {"shoulder_cm": 48.0, "torso_cm": 66.5, "sleeve_cm": 25.0},
            }
        ),

        # --- WOMEN'S CLOTHING (5 Items) ---
        models.Product(
            name="Floral Printed Cotton Kurti",
            category="Kurti",
            gender="Female",
            price=799.0,
            image_url="https://images.unsplash.com/photo-1583391733956-6c78276477e2?w=500",
            size_chart={
                "S": {"shoulder_cm": 35.5, "torso_cm": 55.0, "sleeve_cm": 43.0},
                "M": {"shoulder_cm": 37.5, "torso_cm": 57.0, "sleeve_cm": 44.5},
                "L": {"shoulder_cm": 39.5, "torso_cm": 59.0, "sleeve_cm": 46.0},
                "XL": {"shoulder_cm": 41.5, "torso_cm": 61.0, "sleeve_cm": 47.5},
            }
        ),
        models.Product(
            name="Casual Oversized Graphic Tee",
            category="T-Shirt",
            gender="Female",
            price=549.0,
            image_url="https://images.unsplash.com/photo-1503342217505-b0a15ec3261c?w=500",
            size_chart={
                "S": {"shoulder_cm": 36.5, "torso_cm": 54.0, "sleeve_cm": 18.5},
                "M": {"shoulder_cm": 38.5, "torso_cm": 56.0, "sleeve_cm": 19.5},
                "L": {"shoulder_cm": 40.5, "torso_cm": 58.0, "sleeve_cm": 20.5},
                "XL": {"shoulder_cm": 42.5, "torso_cm": 60.0, "sleeve_cm": 21.5},
            }
        ),
        models.Product(
            name="Formal Solid Button-Down Shirt",
            category="Shirt",
            gender="Female",
            price=999.0,
            image_url="https://images.unsplash.com/photo-1598554747436-c9293d6a588f?w=500",
            size_chart={
                "S": {"shoulder_cm": 36.0, "torso_cm": 56.0, "sleeve_cm": 56.0},
                "M": {"shoulder_cm": 38.0, "torso_cm": 58.0, "sleeve_cm": 57.5},
                "L": {"shoulder_cm": 40.0, "torso_cm": 60.0, "sleeve_cm": 59.0},
                "XL": {"shoulder_cm": 42.0, "torso_cm": 62.0, "sleeve_cm": 60.5},
            }
        ),
        models.Product(
            name="Summer A-Line Midi Dress",
            category="Dress",
            gender="Female",
            price=1499.0,
            image_url="https://images.unsplash.com/photo-1572804013309-59a88b7e92f1?w=500",
            size_chart={
                "S": {"shoulder_cm": 35.0, "torso_cm": 54.0, "sleeve_cm": 20.0},
                "M": {"shoulder_cm": 37.0, "torso_cm": 56.0, "sleeve_cm": 21.0},
                "L": {"shoulder_cm": 39.0, "torso_cm": 58.0, "sleeve_cm": 22.0},
                "XL": {"shoulder_cm": 41.0, "torso_cm": 60.0, "sleeve_cm": 23.0},
            }
        ),
        models.Product(
            name="Cropped Classic Denim Jacket",
            category="Jacket",
            gender="Female",
            price=1699.0,
            image_url="https://images.unsplash.com/photo-1544441893-675973e31985?w=500",
            size_chart={
                "S": {"shoulder_cm": 36.5, "torso_cm": 48.0, "sleeve_cm": 57.0},
                "M": {"shoulder_cm": 38.5, "torso_cm": 50.0, "sleeve_cm": 58.5},
                "L": {"shoulder_cm": 40.5, "torso_cm": 52.0, "sleeve_cm": 60.0},
                "XL": {"shoulder_cm": 42.5, "torso_cm": 54.0, "sleeve_cm": 61.5},
            }
        ),
    ]

    db.add_all(sample_products)
    db.commit()
    db.close()
    print("Successfully inserted 10 sample products (5 Men, 5 Women)!")

if __name__ == "__main__":
    seed_products()