FROM ubuntu:22.04

WORKDIR /app

# 1. Install Python 3
RUN apt-get update && \
    apt-get install -y --no-install-recommends python3 python3-pip && \
    rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# FIX FOR CORTEX SCANNER BUG:
# The scanner crashes because it expects a "status.d" directory.
# We create it and link the real status file to it so the scanner works.
# ---------------------------------------------------------------------------
RUN mkdir -p /var/lib/dpkg/status.d && \
    ln -s /var/lib/dpkg/status /var/lib/dpkg/status.d/status

# 2. Install Dependencies
COPY requirements.txt .
RUN pip3 install --no-cache-dir -r requirements.txt

# 3. Copy Application
COPY . .

CMD ["python3", "app.py"]