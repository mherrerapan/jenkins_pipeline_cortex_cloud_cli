FROM ubuntu:22.04

WORKDIR /app

# 1. Install Python 3 & Pip (minimal flags to keep size down)
# --no-install-recommends: Skips heavy extras (like documentation/optional libs)
RUN apt-get update && \
    apt-get install -y --no-install-recommends python3 python3-pip && \
    rm -rf /var/lib/apt/lists/*

# 2. Install App Dependencies
COPY requirements.txt .
RUN pip3 install --no-cache-dir -r requirements.txt

# 3. Copy Application
COPY . .

# 4. Run
CMD ["python3", "app.py"]