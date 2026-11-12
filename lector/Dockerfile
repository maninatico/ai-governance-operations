# Lector local de comprobantes: texto del PDF, QR de ARCA, OCR y detección de texto oculto.
# Corre en la PC, sin salida a internet. Fase 8.4 del proyecto Gobernanza de IA en Operaciones.
FROM python:3.13-slim
RUN apt-get update && apt-get install -y --no-install-recommends tesseract-ocr tesseract-ocr-spa libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY lector.py .
USER nobody
EXPOSE 8000
CMD ["uvicorn", "lector:app", "--host", "0.0.0.0", "--port", "8000"]
