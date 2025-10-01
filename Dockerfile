FROM python:3.9-slim

# Install system dependencies for Chrome and Selenium
RUN apt-get update && apt-get install -y \
    wget \
    curl \
    gnupg \
    unzip \
    xvfb \
    libnss3 \
    libatk-bridge2.0-0 \
    libdrm2 \
    libxcomposite1 \
    libxdamage1 \
    libxrandr2 \
    libgbm1 \
    libxss1 \
    libasound2 \
    libatspi2.0-0 \
    libgtk-3-0 \
    libgdk-pixbuf2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# Add Google Chrome repository and install Chrome
RUN wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | apt-key add - \
    && echo "deb [arch=amd64] http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google-chrome.list \
    && apt-get update \
    && apt-get install -y google-chrome-stable \
    && rm -rf /var/lib/apt/lists/*

# Install ChromeDriver
RUN CHROME_DRIVER_VERSION=$(curl -sS chromedriver.storage.googleapis.com/LATEST_RELEASE) \
    && wget -O /tmp/chromedriver.zip https://chromedriver.storage.googleapis.com/$CHROME_DRIVER_VERSION/chromedriver_linux64.zip \
    && unzip /tmp/chromedriver.zip chromedriver -d /usr/local/bin/ \
    && chmod +x /usr/local/bin/chromedriver \
    && rm /tmp/chromedriver.zip

# Set working directory
WORKDIR /app

# Copy requirements and install all dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application files
COPY selenium_scraper.py .
COPY selenium_api_server.py .

# Set environment variables for production
ENV CHROME_HEADLESS=true
ENV FLASK_ENV=production
ENV DISPLAY=:99
ENV CHROME_NO_SANDBOX=true

# Create a script to start Xvfb and the app
RUN echo '#!/bin/bash\n\
Xvfb :99 -screen 0 1280x720x16 -nolisten tcp -dpi 96 +extension RANDR &\n\
sleep 2\n\
exec gunicorn --bind 0.0.0.0:${PORT:-10000} selenium_api_server:app' > /app/start.sh \
    && chmod +x /app/start.sh

# Expose port (Render assigns port via $PORT env var)
EXPOSE $PORT

# Run with Xvfb for headless Chrome
CMD ["/app/start.sh"]