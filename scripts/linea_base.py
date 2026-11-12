"""Fase 5, paso 4. KPI del antes (línea base), Materiales Cumbre Andina (datos sintéticos).
Lee datos/limpio (salida de limpiar_historico.py). Escribe datos/limpio/kpi_linea_base_*.csv.
Supuestos aprobados el 03/11/2026: día hábil = lunes a viernes de 8 a 17 (9 h), sin feriados;
el área equivocada se mide por auditoría (archivo de verdad); la plata se calcula en la Fase 10."""
from datetime import datetime, timedelta
from pathlib import Path
import numpy as np
import pandas as pd

BASE = Path(__file__).resolve().parent.parent / "datos"
L = BASE / "limpio"
INICIO, FIN = 8, 17
SLA_REGISTRO_DIAS, SLA_RESPUESTA_HORAS, SLA_RESOLUCION_DIAS = 2, 24, 5

def horas_habiles(a, b):
    """Horas hábiles entre dos momentos (lunes a viernes, 8 a 17)."""
    total, t = 0.0, a
    while t.date() <= b.date():
        if t.weekday() < 5:
            ini = max(t, datetime(t.year, t.month, t.day, INICIO))
            fin = min(b, datetime(t.year, t.month, t.day, FIN))
            if fin > ini:
                total += (fin - ini).total_seconds() / 3600
        t = datetime(t.year, t.month, t.day) + timedelta(days=1)
    return total

# ---------- Facturas ----------
f = pd.read_csv(L / "facturas_limpio.csv", encoding="utf-8-sig")
f["mes"] = f["fecha_emision"].str[:7]  # mes del comprobante (no el de llegada)
reg = f[f["fecha_registro"].notna()].copy()
reg["dias_habiles"] = np.busday_count(pd.to_datetime(reg["fecha_recepcion"]).values.astype("datetime64[D]"),
                                      pd.to_datetime(reg["fecha_registro"]).values.astype("datetime64[D]"))
orig = f[~f["es_duplicada"]].copy()
orig["con_error"] = orig[["fecha_normalizada", "cuit_corregido", "razon_estandarizada", "excepcion_monto"]].any(axis=1)
dup = f[f["es_duplicada"]].copy()
dup["escapada"] = dup["detectada_manual"] == False
dup["pagada_doble"] = dup["escapada"] & (dup["estado"] == "Pagada")

def kpi_facturas(g_reg, g_orig, g_all, g_dup):
    return pd.Series({
        "facturas_recibidas": len(g_orig),
        "dias_hasta_quedar_cargada": round(g_reg["dias_habiles"].mean(), 2),
        "pct_cargadas_tarde": round(100 * (g_reg["dias_habiles"] > SLA_REGISTRO_DIAS).mean(), 1),
        "horas_cargando_a_mano": round(g_all["minutos_carga"].sum() / 60, 1),
        "pct_con_algun_dato_mal": round(100 * g_orig["con_error"].mean(), 1),
        "duplicadas": len(g_dup),
        "duplicadas_escapadas": int(g_dup["escapada"].sum()),
        "pagadas_dos_veces": int(g_dup["pagada_doble"].sum()),
        "pesos_pagados_dos_veces": round(g_dup.loc[g_dup["pagada_doble"], "total"].sum(), 2),
    })

meses = sorted(f["mes"].unique())
fm = pd.DataFrame({m: kpi_facturas(reg[reg.mes == m], orig[orig.mes == m], f[f.mes == m], dup[dup.mes == m]) for m in meses}).T
fm.loc["TOTAL 12 meses"] = kpi_facturas(reg, orig, f, dup)
fm.index.name = "mes"

# ---------- Reclamos ----------
r = pd.read_csv(L / "reclamos_historico_limpio.csv", encoding="utf-8-sig")
v = pd.read_csv(BASE / "verdad" / "reclamos_historico_verdad.csv", encoding="utf-8-sig")
r = r.merge(v[["reclamo_id", "derivacion_correcta"]], on="reclamo_id")
for c in ["fecha_hora_ingreso", "fecha_hora_primera_respuesta", "fecha_hora_cierre"]:
    r[c] = pd.to_datetime(r[c])
r["mes"] = r["fecha_hora_ingreso"].dt.strftime("%Y-%m")
r["horas_primera_respuesta"] = [horas_habiles(a, b) for a, b in zip(r.fecha_hora_ingreso, r.fecha_hora_primera_respuesta)]
r["dias_resolucion"] = np.busday_count(r["fecha_hora_ingreso"].values.astype("datetime64[D]"),
                                       r["fecha_hora_cierre"].values.astype("datetime64[D]"))

def kpi_reclamos(g):
    return pd.Series({
        "reclamos": len(g),
        "horas_hasta_primera_respuesta": round(g["horas_primera_respuesta"].mean(), 1),
        "pct_esperan_mas_de_un_dia": round(100 * (g["horas_primera_respuesta"] > SLA_RESPUESTA_HORAS).mean(), 1),
        "pct_resueltos_a_tiempo": round(100 * (g["dias_resolucion"] <= SLA_RESOLUCION_DIAS).mean(), 1),
        "pct_area_equivocada": round(100 * (g["derivacion_correcta"] == False).mean(), 1),
        "pct_vuelven_a_abrirse": round(100 * (g["reabierto"] == True).mean(), 1),
    })

rm = pd.DataFrame({m: kpi_reclamos(r[r.mes == m]) for m in sorted(r["mes"].unique())}).T
rm.loc["TOTAL 12 meses"] = kpi_reclamos(r)
rm.index.name = "mes"

donde = r.groupby(["sucursal", "categoria_asignada"]).size().rename("reclamos").reset_index()

fm.to_csv(L / "kpi_linea_base_facturas.csv", encoding="utf-8-sig")
rm.to_csv(L / "kpi_linea_base_reclamos.csv", encoding="utf-8-sig")
donde.to_csv(L / "kpi_linea_base_reclamos_donde_y_por_que.csv", index=False, encoding="utf-8-sig")
pd.set_option("display.width", 250)
print(fm.to_string()); print(); print(rm.to_string()); print()
print(r.sucursal.value_counts().to_string()); print(r.categoria_asignada.value_counts().to_string())
