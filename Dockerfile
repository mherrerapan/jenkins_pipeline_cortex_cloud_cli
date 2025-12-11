FROM python:3.7-slim
WORKDIR /app

# Copy only the requirements file first to leverage build cache
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the rest of the application source code
COPY . .

CMD ["python", "app.py"]