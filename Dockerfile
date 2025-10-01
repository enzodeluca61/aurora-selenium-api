FROM python:3.9-slim

# Install minimal dependencies for Flask app only
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy requirements and install only Flask dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir flask flask-cors gunicorn supabase

# Copy application files
COPY selenium_scraper.py .
COPY selenium_api_server.py .

# Set environment variables (no Chrome needed for fallback mode)
ENV CHROME_HEADLESS=true
ENV FLASK_ENV=production

# Expose port (Render assigns port via $PORT env var)
EXPOSE $PORT

# Run simple gunicorn without Chrome dependencies
CMD ["sh", "-c", "gunicorn --bind 0.0.0.0:${PORT:-10000} selenium_api_server:app"]