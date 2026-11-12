"""Fase 8.4b. Genera 2 Factura C de proveedores monotributistas (datos ficticios) en
datos/lote_prueba/pruebas_extra/. Una con texto y otra escaneada, las dos con QR de ARCA.
Los proveedores y sus OC se cargan con sql/07_monotributistas_prueba.sql.
Uso: python scripts/generar_monotributistas.py   (requiere reportlab, pillow, qrcode)
"""
import base64, json, random
from pathlib import Path
import qrcode
from PIL import Image, ImageDraw, ImageFont, ImageFilter
from reportlab.lib.pagesizes import A4
from reportlab.lib.utils import ImageReader
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas

random.seed(4211)
SALIDA = Path(__file__).resolve().parent.parent / "datos" / "lote_prueba" / "pruebas_extra"
FUENTE = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
FUENTE_B = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
pdfmetrics.registerFont(TTFont("Dj", FUENTE)); pdfmetrics.registerFont(TTFont("DjB", FUENTE_B))
F, FB = "Dj", "DjB"

FACTURAS = [
    dict(archivo="MONO-PRV-121.pdf", formato="texto", nombre="Tomás Ezequiel Barrionuevo (ficticio)",
         cuit="20-21524864-0", email="tomas.barrionuevo@sanitarios-tb.example", telefono="11-4732-5590",
         punto_venta="0002", numero="00000147", fecha="2026-10-14", oc_id="OC-L0901", total=415230.00,
         detalle="Instalación de sanitarios según orden de compra", banco="Banco de la Nación",
         cbu="0113822557617344074725", cae="76421093385512"),
    dict(archivo="MONO-PRV-122.pdf", formato="escaneado", nombre="Valeria Soledad Quintana (ficticia)",
         cuit="27-36422304-3", email="vquintana.pinturas@correo-vq.example", telefono="11-5218-0476",
         punto_venta="0001", numero="00000032", fecha="2026-10-16", oc_id="OC-L0902", total=185910.50,
         detalle="Pintura de fachada según orden de compra", banco="Credicoop",
         cbu="1918123124042492728569", cae="76429981204473"),
]


def ars(x):
    return f"{x:,.2f}".replace(",", "X").replace(".", ",").replace("X", ".")


def qr_arca(d):
    payload = {"ver": 1, "fecha": d["fecha"], "cuit": int(d["cuit"].replace("-", "")),
               "ptoVta": int(d["punto_venta"]), "tipoCmp": 11, "nroCmp": int(d["numero"]),
               "importe": d["total"], "moneda": "PES", "ctz": 1, "tipoDocRec": 80,
               "nroDocRec": 30712345670, "tipoCodAut": "E", "codAut": int(d["cae"])}
    b64 = base64.b64encode(json.dumps(payload, separators=(",", ":")).encode()).decode()
    return qrcode.make("https://www.afip.gob.ar/fe/qr/?p=" + b64, box_size=6, border=2).convert("RGB")


def lineas(d):
    return [
        (FB, 16, d["nombre"]),
        (F, 9, f"CUIT: {d['cuit']}   Responsable Monotributo"),
        (F, 9, f"{d['email']}   Tel. {d['telefono']}"),
        None,
        (FB, 13, f"FACTURA C   N° {d['punto_venta']}-{d['numero']}"),
        (F, 10, f"Fecha de emisión: {d['fecha']}"),
        None,
        (FB, 10, "Cliente: MATERIALES CUMBRE ANDINA S.R.L. (empresa ficticia)"),
        (F, 9, f"CUIT: 30-71234567-0 (ficticio)   Orden de compra: {d['oc_id']}"),
        None,
        (F, 10, f"Detalle: {d['detalle']}"),
        None,
        (F, 11, f"Subtotal: $ {ars(d['total'])}"),
        (FB, 13, f"TOTAL: $ {ars(d['total'])}"),
        None,
        (F, 9, f"Datos para el pago: {d['banco']}   CBU {d['cbu']}"),
        (F, 9, "Condición de pago: 30 días"),
        None,
        (F, 7, "Documento generado con datos sintéticos para el proyecto de portafolio. No válido como comprobante."),
    ]


def pdf_texto(ruta, d, qr):
    c = canvas.Canvas(str(ruta), pagesize=A4)
    c.drawImage(ImageReader(qr), 430, 330, width=120, height=120)
    c.setFont(F, 7); c.drawString(430, 322, f"CAE N° {d['cae']}")
    y = 800
    for l in lineas(d):
        if l is None:
            y -= 14; continue
        c.setFont(l[0], l[1]); c.drawString(50, y, l[2]); y -= l[1] + 8
    c.showPage(); c.save()


def pdf_escaneado(ruta, d, qr):
    img = Image.new("RGB", (1240, 1754), (250, 249, 245))
    dr = ImageDraw.Draw(img)
    img.paste(qr.resize((250, 250)), (900, 1050))
    dr.text((900, 1305), f"CAE N° {d['cae']}", fill=(25, 25, 25), font=ImageFont.truetype(FUENTE, 20))
    y = 90
    for l in lineas(d):
        if l is None:
            y += 30; continue
        tam = int(l[1] * 2.6)
        dr.text((100, y), l[2], fill=(25, 25, 25), font=ImageFont.truetype(FUENTE_B if l[0] == FB else FUENTE, tam))
        y += tam + 18
    img = img.rotate(random.uniform(-1.2, 1.2), expand=False, fillcolor=(250, 249, 245)).filter(ImageFilter.GaussianBlur(0.6))
    img.save(str(ruta), "PDF", resolution=150)


SALIDA.mkdir(parents=True, exist_ok=True)
for d in FACTURAS:
    (pdf_texto if d["formato"] == "texto" else pdf_escaneado)(SALIDA / d["archivo"], d, qr_arca(d))
    print("generado", d["archivo"])
