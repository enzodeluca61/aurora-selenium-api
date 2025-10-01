FROM python:3.9-bullseye

# Install system dependencies
RUN apt-get update && apt-get install -y \
    wget curl gnupg2 unzip xvfb \
    fonts-liberation libasound2 libatk-bridge2.0-0 \
    libatk1.0-0 libatspi2.0-0 libdrm2 libgtk-3-0 \
    libnspr4 libnss3 libxcomposite1 libxdamage1 \
    libxfixes3 libxrandr2 libxss1 libxtst6 \
    lsb-release && rm -rf /var/lib/apt/lists/*

# Install Chrome
RUN wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /usr/share/keyrings/googlechrome-linux-keyring.gpg && \
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/googlechrome-linux-keyring.gpg] http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google-chrome.list && \
    apt-get update && apt-get install -y google-chrome-stable && \
    rm -rf /var/lib/apt/lists/*

# Install ChromeDriver
RUN wget -O /tmp/chromedriver.zip "https://storage.googleapis.com/chrome-for-testing-public/131.0.6778.87/linux64/chromedriver-linux64.zip" && \
    unzip /tmp/chromedriver.zip -d /tmp/ && \
    mv /tmp/chromedriver-linux64/chromedriver /usr/local/bin/ && \
    chmod +x /usr/local/bin/chromedriver && \
    rm -rf /tmp/chromedriver.zip /tmp/chromedriver-linux64

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY selenium_scraper.py selenium_api_server.py ./

ENV CHROME_HEADLESS=true
ENV FLASK_ENV=production
ENV DISPLAY=:99
ENV CHROME_NO_SANDBOX=true

RUN echo '#!/bin/bash\nXvfb :99 -screen 0 1280x720x16 -nolisten tcp -dpi 96 +extension RANDR &\nsleep 2\nexec gunicorn --bind 0.0.0.0:${PORT:-10000} selenium_api_server:app' > /app/start.sh && chmod +x /app/start.sh

EXPOSE $PORT
CMD ["/app/start.sh"]