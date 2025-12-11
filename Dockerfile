FROM amazonlinux:2023

WORKDIR /app

# 1. Install Python 3 & Pip using dnf (The RPM package manager)
RUN dnf install -y python3 python3-pip && \
    dnf clean all

# 2. Install App Dependencies
COPY requirements.txt .
RUN pip3 install --no-cache-dir -r requirements.txt

# 3. Copy Application
COPY . .

# 4. Run
CMD ["python3", "app.py"]