"""Lector local de comprobantes (Fase 8.4). Corre en la PC, sin salida a internet.
Recibe un PDF del lote y devuelve: texto del PDF, QR de ARCA decodificado, OCR (si hace falta)
y la detección de texto oculto (defensa 2 de la Fase 6). Nada de esto usa IA externa."""
import base64, io, json, re, unicodedata
from pathlib import Path
from urllib.parse import urlparse, parse_qs

import cv2
import numpy as np
import pdfplumber
import pytesseract
from fastapi import FastAPI, HTTPException

BASE = Path("/datos")              # lote de prueba montado en solo lectura
app = FastAPI(title="Lector local de comprobantes", version="1.0")

def normalizar(t):
    t = unicodedata.normalize("NFKD", t.lower())
    return "".join(c for c in t if not unicodedata.combining(c))

def palabras(t):
    return [w for w in re.findall(r"[a-z0-9]{4,}", normalizar(t))]

def variantes(imagen_bgr):
    g = cv2.cvtColor(imagen_bgr, cv2.COLOR_BGR2GRAY)
    yield g
    yield cv2.threshold(g, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)[1]
    yield cv2.GaussianBlur(g, (3, 3), 0)
    yield cv2.resize(g, None, fx=0.5, fy=0.5, interpolation=cv2.INTER_AREA)
    yield cv2.resize(g, None, fx=1.5, fy=1.5, interpolation=cv2.INTER_CUBIC)
    yield cv2.adaptiveThreshold(g, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY, 31, 10)

def leer_qr(pagina):
    """Prueba varias resoluciones y filtros: un escaneado con ruido a veces solo se lee así."""
    det = cv2.QRCodeDetector()
    for dpi in (150, 200, 300):
        img = np.array(pagina.to_image(resolution=dpi).original.convert("RGB"))[:, :, ::-1]
        for im in variantes(img):
            datos, _, _ = det.detectAndDecode(im)
            if datos:
                return datos
    return None

def interpretar_qr(url):
    """QR de ARCA: https://www.afip.gob.ar/fe/qr/?p=<JSON en base64>"""
    try:
        u = urlparse(url)
        if "afip.gob.ar" not in u.netloc and "arca.gob.ar" not in u.netloc:
            return None, "El QR no apunta a ARCA"
        p = parse_qs(u.query).get("p", [""])[0]
        p += "=" * (-len(p) % 4)
        return json.loads(base64.b64decode(p).decode("utf-8")), None
    except Exception as e:
        return None, f"QR ilegible: {e}"

def es_casi_blanco(color):
    if color is None:
        return False
    if isinstance(color, (int, float)):
        return color >= 0.95
    c = list(color)
    if len(c) == 1:
        return c[0] >= 0.95
    if len(c) == 3:
        return min(c) >= 0.95
    if len(c) == 4:                # CMYK: blanco = sin tinta
        return max(c) <= 0.05
    return False

@app.get("/salud")
def salud():
    return {"estado": "ok", "tesseract": str(pytesseract.get_tesseract_version())}

@app.get("/leer")
def leer(archivo: str):
    ruta = (BASE / archivo).resolve()
    if BASE.resolve() not in ruta.parents or ruta.suffix.lower() != ".pdf" or not ruta.exists():
        raise HTTPException(400, "Archivo inválido o inexistente")

    texto, ocr, motivos_ocultos, fragmentos = [], [], [], []
    qr_url = None
    with pdfplumber.open(ruta) as pdf:
        for pag in pdf.pages:
            texto.append(pag.extract_text() or "")
            # Revisión letra por letra: color del fondo, tamaño diminuto, fuera de la página
            raros = [ch for ch in pag.chars
                     if es_casi_blanco(ch.get("non_stroking_color")) or ch.get("size", 10) < 5
                     or ch["x0"] < 0 or ch["top"] < 0 or ch["x1"] > pag.width or ch["bottom"] > pag.height]
            if len(raros) >= 5:
                motivos_ocultos.append(f"{len(raros)} caracteres invisibles (color del fondo, letra diminuta o fuera de la página)")
                fragmentos.append("".join(c["text"] for c in raros)[:300])
            # Imagen de la página: QR y OCR (lo que ve una persona)
            img = np.array(pag.to_image(resolution=200).original.convert("RGB"))[:, :, ::-1]
            qr_url = qr_url or leer_qr(pag)
            ocr.append(pytesseract.image_to_string(img, lang="spa"))
        n_pag = len(pdf.pages)

    texto_capa, texto_ocr = "\n".join(texto).strip(), "\n".join(ocr).strip()
    escaneado = len(texto_capa) < 20

    # Comparar lo que hay en el archivo con lo que se ve: palabras del texto que el OCR no encuentra
    if not escaneado:
        vistas = set(palabras(texto_ocr))
        faltan = [w for w in palabras(texto_capa) if w not in vistas]
        proporcion = len(faltan) / max(1, len(palabras(texto_capa)))
        if len(faltan) >= 8 and proporcion > 0.15:
            motivos_ocultos.append(f"{len(faltan)} palabras del archivo no se ven en la página")
            fragmentos.append(" ".join(faltan[:40]))

    qr_datos, qr_error = (interpretar_qr(qr_url) if qr_url else (None, None))
    return {
        "archivo": archivo,
        "paginas": n_pag,
        "escaneado": escaneado,
        "texto": texto_capa if not escaneado else "",
        "ocr": texto_ocr,
        "qr": {"encontrado": bool(qr_url), "datos": qr_datos, "error": qr_error},
        "texto_oculto": {"detectado": bool(motivos_ocultos), "motivos": motivos_ocultos, "fragmentos": fragmentos},
        "fuente_sugerida": "qr" if qr_datos else ("ocr" if escaneado else "texto"),
    }
