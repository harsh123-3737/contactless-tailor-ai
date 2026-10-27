# Use official Python lightweight image
FROM python:3.11-slim

# Install system graphics dependencies for MediaPipe
RUN apt-get update && apt-get install -y \
    libgl1 \
    libglib2.0-0 \
    libgles2 \
    libegl1 \
    && rm -rf /var/lib/apt/lists/*

# Set the working directory
WORKDIR /app

# Copy and install Python packages
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy your backend code
COPY . .


# Start the FastAPI server using Render's dynamic PORT
CMD uvicorn main:app --host 0.0.0.0 --port $PORT