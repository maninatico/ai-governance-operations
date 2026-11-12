"""Fase 5, paso 3. Limpieza del histórico de Materiales Cumbre Andina (datos sintéticos).
Aplica las reglas aprobadas el 03/11/2026. No modifica datos/historico: escribe en datos/limpio.
Cada corrección conserva el valor original, el corregido y una marca."""
import re, difflib
from pathlib import Path
import pandas as pd

BASE = Path(__file__).resolve().parent.parent / "datos"
H, L = BASE / "historico", BASE / "limpio"
L.mkdir(exist_ok=True)
leer = lambda n: pd.read_csv(H / n, dtype=str, encoding="utf-8-sig")

f, p, c = leer("facturas_historico.csv"), leer("proveedores.csv"), leer("clientes.csv")
maestro = p.set_index("proveedor_id")

# Regla 1. Fechas: día primero, año de 2 dígitos = 20aa, validación contra recepción (0 a 90 días)
def a_iso(t):
    t = str(t).strip()
    if re.fullmatch(r"\d{4}-\d{2}-\d{2}", t):
        return t
    m = re.fullmatch(r"(\d{2})[./-](\d{2})[./-](\d{2}|\d{4})", t)
    if not m:
        return None
    d, mes, a = m.groups()
    return f"{'20' + a if len(a) == 2 else a}-{mes}-{d}"

f["fecha_emision_original"] = f["fecha_emision"]
f["fecha_emision"] = f["fecha_emision_original"].map(a_iso)
f["fecha_normalizada"] = f["fecha_emision"] != f["fecha_emision_original"]
emi, rec = pd.to_datetime(f["fecha_emision"], errors="coerce"), pd.to_datetime(f["fecha_recepcion"])
f["revisar_fecha"] = emi.isna() | (emi > rec) | ((rec - emi).dt.days > 90)

# Regla 2. CUIT inválido: se toma el del maestro por proveedor_id
def cuit_ok(x):
    d = re.sub(r"\D", "", str(x))
    if len(d) != 11:
        return False
    s = sum(int(a) * b for a, b in zip(d[:10], [5, 4, 3, 2, 7, 6, 5, 4, 3, 2]))
    v = 11 - s % 11
    return {11: 0, 10: 9}.get(v, v) == int(d[10])

f["cuit_original"] = f["cuit_emisor"]
f["cuit_corregido"] = ~f["cuit_original"].map(cuit_ok)
f.loc[f["cuit_corregido"], "cuit_emisor"] = f.loc[f["cuit_corregido"], "proveedor_id"].map(maestro["cuit"])

# Regla 3. Razón social: la del maestro si se parece 80% o más; si no, revisión
f["razon_social_original"] = f["razon_social"]
rs_m = f["proveedor_id"].map(maestro["razon_social"])
sim = [difflib.SequenceMatcher(None, a.lower(), b.lower()).ratio() for a, b in zip(f["razon_social_original"], rs_m)]
f["similitud_razon"] = [round(s, 2) for s in sim]
distinta = f["razon_social_original"] != rs_m
f["razon_estandarizada"] = distinta & (f["similitud_razon"] >= 0.8)
f["revisar_razon"] = distinta & (f["similitud_razon"] < 0.8)
f.loc[f["razon_estandarizada"], "razon_social"] = rs_m[f["razon_estandarizada"]]

# Regla 4. Total que no cierra: para analizar se usa neto + IVA; el original se conserva
for col in ["neto", "iva", "total", "alicuota_iva", "minutos_carga"]:
    f[col] = pd.to_numeric(f[col])
f["total_original"] = f["total"]
f["excepcion_monto"] = (f["neto"] + f["iva"] - f["total"]).abs() > 0.05
f.loc[f["excepcion_monto"], "total"] = (f["neto"] + f["iva"]).round(2)

# Regla 5. Duplicadas: no se borran. Original = la que llegó primero (desempate por factura_id)
k = ["proveedor_id", "punto_venta", "numero", "tipo_comprobante"]
f = f.sort_values(["fecha_recepcion", "factura_id"])
f["es_duplicada"] = f.duplicated(k, keep="first")
f["duplicada_de"] = f.groupby(k)["factura_id"].transform("first").where(f["es_duplicada"])
rech = f.groupby(k)["estado"].transform(lambda s: (s == "Rechazada por duplicada").any())
f["detectada_manual"] = rech.where(f["es_duplicada"])
f = f.sort_values("factura_id")

# Regla 6. DNI repetido en clientes: se marcan ambos, no se corrige
c["revisar_dni"] = c["dni"].duplicated(keep=False)

f.to_csv(L / "facturas_limpio.csv", index=False, encoding="utf-8-sig")
c.to_csv(L / "clientes_limpio.csv", index=False, encoding="utf-8-sig")
for n in ["proveedores", "ordenes_de_compra", "reclamos_historico"]:
    leer(f"{n}.csv").to_csv(L / f"{n}_limpio.csv", index=False, encoding="utf-8-sig")

marcas = ["fecha_normalizada", "revisar_fecha", "cuit_corregido", "razon_estandarizada",
          "revisar_razon", "excepcion_monto", "es_duplicada"]
print({m: int(f[m].sum()) for m in marcas}, "| duplicadas no detectadas:",
      int((f["es_duplicada"] & (f["detectada_manual"] == False)).sum()),
      "| clientes a revisar:", int(c["revisar_dni"].sum()))
