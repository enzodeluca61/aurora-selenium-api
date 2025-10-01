FROM python:3.9-bullseye

# Install system dependencies for Chrome and Selenium
RUN apt-get update && apt-get install -y \
    wget \
    curl \
    gnupg2 \
    unzip \
    xvfb \
    fonts-liberation \
    libasound2 \
    libatk-bridge2.0-0 \
    libatk1.0-0 \
    libatspi2.0-0 \
    libdrm2 \
    libgtk-3-0 \
    libnspr4 \
    libnss3 \
    libxcomposite1 \
    libxdamage1 \
    libxfixes3 \
    libxrandr2 \
    libxss1 \
    libxtst6 \
    lsb-release \
    && rm -rf /var/lib/apt/lists/*

# Add Google Chrome repository and install Chrome (updated method)
RUN wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /usr/share/keyrings/googlechrome-linux-keyring.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/googlechrome-linux-keyring.gpg] http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google-chrome.list \
    && apt-get update \
    && apt-get install -y google-chrome-stable \
    && rm -rf /var/lib/apt/lists/*

# Install ChromeDriver using new Chrome for Testing API
RUN CHROME_VERSION=$(google-chrome --version | cut -d ' ' -f3) \
    && echo "Chrome version: $CHROME_VERSION" \
    && CHROMEDRIVER_URL=$(curl -s "https://googlechromelabs.github.io/chrome-for-testing/known-good-versions-with-downloads.json" | \
       python3 -c "
import sys, json
data = json.load(sys.stdin)
chrome_version = '$CHROME_VERSION'
for version in data['versions']:
    if version['version'] == chrome_version:
        for download in version['downloads'].get('chromedriver', []):
            if download['platform'] == 'linux64':
                print(download['url'])
                sys.exit(0)
# Fallback to latest stable
for version in reversed(data['versions']):
    for download in version['downloads'].get('chromedriver', []):
        if download['platform'] == 'linux64':
            print(download['url'])
            sys.exit(0)
") \
    && echo "ChromeDriver URL: $CHROMEDRIVER_URL" \
    && wget -O /tmp/chromedriver.zip "$CHROMEDRIVER_URL" \
    && unzip /tmp/chromedriver.zip -d /tmp/ \
    && mv /tmp/chromedriver-linux64/chromedriver /usr/local/bin/ \
    && chmod +x /usr/local/bin/chromedriver \
    && rm -rf /tmp/chromedriver.zip /tmp/chromedriver-linux64

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