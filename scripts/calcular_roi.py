#!/usr/bin/env python3
"""Fase 10. Modelo de ROI con supuestos escritos. Uso: python3 scripts/calcular_roi.py [--csv]
(con --csv escribe datos/tablero/roi_escenarios.csv y roi_sensibilidad.csv para el tablero)
Todo valor sale de la linea base (Fase 5), del lote medido (sql/17) o de un SUPUESTO marcado.
Pesos argentinos nominales, 12 meses, sin inflacion (supuesto declarado)."""
import copy
import csv
import os
import sys

# --- Datos de la linea base (Fase 5, 12 meses) ---
FACTURAS_AÑO = 10800
HORAS_TIPEO_AÑO = 1702
DUPLICADAS = 324
DUPLICADAS_NO_DETECTADAS = 187
PAGADAS_DOS_VECES = 166
MONTO_PAGADO_DOS_VECES = 168_800_000   # $ 168,8 millones
# --- Medido en el lote (sql/17 y orquestador) ---
CORREOS_LOTE = 153
CASOS_HUMANOS_LOTE = 11 + 4 + 2        # cola 11, bloqueadas CBU 4, sospechosas 2
# --- Supuestos (todos escritos en 10_KPI_y_ROI.md) ---
SUELDO_BASE = 1_366_648                # Administrativo A, Comercio, haberes octubre 2026 (iProfesional)
HORAS_MES = 160
BASE = dict(
    factor_hora=1.5,                   # 1,0 / 1,5 / 2,0
    min_por_caso=10,                   # minutos humanos por caso derivado a una persona
    pct_casos=CASOS_HUMANOS_LOTE / CORREOS_LOTE,
    deteccion=1.0,                     # fraccion de duplicadas frenadas (lote: 3 de 3)
    recuperable=0.5,                   # fraccion de lo pagado dos veces que se recupera igual
    servidor_mes=300_000,
    mant_horas_mes=8,
    horas_construccion=15,             # declaradas por Jorge al 09/11/2026 (dijo 12 y luego 15)
    horas_mercado=200, mult_mercado=3.0,
)

def costo_hora(p):
    return SUELDO_BASE / HORAS_MES * p["factor_hora"]

def calcular(p):
    ch = costo_hora(p)
    casos = FACTURAS_AÑO * p["pct_casos"]
    horas_humanas = casos * p["min_por_caso"] / 60
    horas_ahorradas = max(HORAS_TIPEO_AÑO - horas_humanas, 0)
    ahorro_horas = horas_ahorradas * ch
    # pagos duplicados: el 166/187 de las no detectadas termina pagado
    fraccion_pagada = PAGADAS_DOS_VECES / DUPLICADAS_NO_DETECTADAS
    pagadas_despues = DUPLICADAS * (1 - p["deteccion"]) * fraccion_pagada
    evitadas = max(PAGADAS_DOS_VECES - pagadas_despues, 0)
    monto_unit = MONTO_PAGADO_DOS_VECES / PAGADAS_DOS_VECES
    ahorro_errores = evitadas * monto_unit * (1 - p["recuperable"])
    costo_año = 12 * p["servidor_mes"] + 12 * p["mant_horas_mes"] * ch
    neto = ahorro_horas + ahorro_errores - costo_año
    inv_a = p["horas_construccion"] * ch
    inv_b = p["horas_mercado"] * ch * p["mult_mercado"]
    r = lambda inv: (neto - inv) / inv
    rec = lambda inv: inv / (neto / 12) if neto > 0 else float("inf")
    return dict(costo_hora=ch, casos=casos, horas_humanas=horas_humanas, horas_ahorradas=horas_ahorradas,
                ahorro_horas=ahorro_horas, evitadas=evitadas, ahorro_errores=ahorro_errores,
                costo_año=costo_año, neto=neto, inv_a=inv_a, inv_b=inv_b,
                roi_a=r(inv_a), roi_b=r(inv_b), rec_a=rec(inv_a), rec_b=rec(inv_b))

def m(x): return f"{x/1e6:,.1f}".replace(",", "X").replace(".", ",").replace("X", ".")
def n(x): return f"{x:,.0f}".replace(",", ".")


def exportar_csv(carpeta="datos/tablero"):
    """Escribe los CSV para Power BI (punto decimal; importar con configuracion regional en ingles)."""
    os.makedirs(carpeta, exist_ok=True)
    def fila_escenario(nombre, p):
        c = calcular(p)
        f = lambda x: "" if x == float("inf") else round(x, 2)
        return [nombre, round(c["costo_hora"], 2), round(c["horas_ahorradas"], 1), round(c["ahorro_horas"]),
                round(c["ahorro_errores"]), round(c["costo_año"]), round(c["neto"]), round(c["inv_a"]), round(c["inv_b"]),
                round(c["roi_a"] * 100, 1), round(c["roi_b"] * 100, 1), f(c["rec_a"]), f(c["rec_b"])]
    sin_extra = copy.deepcopy(BASE); sin_extra["deteccion"] = 1 - (DUPLICADAS_NO_DETECTADAS / DUPLICADAS)
    peor = copy.deepcopy(BASE); peor.update(factor_hora=1.0, min_por_caso=30, pct_casos=0.30, deteccion=0.42, recuperable=0.9, servidor_mes=600_000)
    with open(os.path.join(carpeta, "roi_escenarios.csv"), "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["escenario", "costo_hora", "horas_ahorradas", "ahorro_por_horas", "ahorro_por_errores", "costo_anual",
                    "beneficio_neto_anual", "inversion_A", "inversion_B", "roi_A_pct", "roi_B_pct", "recupero_A_meses", "recupero_B_meses"])
        w.writerow(fila_escenario("Base", BASE))
        w.writerow(fila_escenario("Sin pagos duplicados extra evitados", sin_extra))
        w.writerow(fila_escenario("Peor caso combinado", peor))
    variables = [
        ("Costo por hora (factor)", "factor_hora", [1.0, 1.5, 2.0]),
        ("Minutos por caso", "min_por_caso", [5, 10, 15, 30]),
        ("Casos a una persona", "pct_casos", [CASOS_HUMANOS_LOTE / CORREOS_LOTE, 0.20, 0.30]),
        ("Duplicadas frenadas", "deteccion", [1.0, 0.9, 0.7, 0.42]),
        ("Parte recuperable", "recuperable", [0.0, 0.5, 0.9]),
        ("Servidor por mes", "servidor_mes", [150_000, 300_000, 600_000]),
        ("Horas de construccion", "horas_construccion", [15, 40, 80]),
    ]
    with open(os.path.join(carpeta, "roi_sensibilidad.csv"), "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["variable", "valor", "beneficio_neto_anual", "roi_A_pct", "roi_B_pct", "recupero_A_meses", "recupero_B_meses"])
        for nombre, clave, vals in variables:
            for v in vals:
                p = copy.deepcopy(BASE); p[clave] = v
                c = calcular(p)
                w.writerow([nombre, round(v, 4), round(c["neto"]), round(c["roi_a"] * 100, 1), round(c["roi_b"] * 100, 1),
                            round(c["rec_a"], 2), round(c["rec_b"], 2)])
    print("CSV escritos en", carpeta)


if __name__ == "__main__":
    if "--csv" in sys.argv:
        exportar_csv(); sys.exit(0)
    b = calcular(BASE)
    print("== BASE ==")
    for k, v in b.items(): print(f"{k:16} {v:,.2f}")
    print("\n== costo por hora ==")
    for f in (1.0, 1.5, 2.0):
        print(f, n(SUELDO_BASE / HORAS_MES * f))
    print("\n== SENSIBILIDAD (una variable por vez, resto en base) ==")
    casos = [
        ("costo por hora", "factor_hora", [1.0, 1.5, 2.0]),
        ("minutos por caso", "min_por_caso", [5, 10, 15, 30]),
        ("% de casos a persona", "pct_casos", [CASOS_HUMANOS_LOTE / CORREOS_LOTE, 0.20, 0.30]),
        ("deteccion de duplicadas", "deteccion", [1.0, 0.9, 0.7, 0.42]),
        ("recuperable", "recuperable", [0.0, 0.5, 0.9]),
        ("servidor por mes", "servidor_mes", [150_000, 300_000, 600_000]),
        ("horas de construccion", "horas_construccion", [15, 40, 80]),
    ]
    for nombre, clave, vals in casos:
        for v in vals:
            p = copy.deepcopy(BASE); p[clave] = v
            c = calcular(p)
            print(f"{nombre:26} {v!s:>10}  neto/año ${m(c['neto']):>7}M  ROI A {c['roi_a']*100:>8,.0f}%  ROI B {c['roi_b']*100:>7,.0f}%  recupero A {c['rec_a']:.1f} m  B {c['rec_b']:.1f} m")
    print("\n== PEOR CASO COMBINADO ==")
    p = copy.deepcopy(BASE); p.update(factor_hora=1.0, min_por_caso=30, pct_casos=0.30, deteccion=0.42, recuperable=0.9, servidor_mes=600_000)
    c = calcular(p); print({k: round(v, 2) for k, v in c.items()})
    print("\n== SIN NINGUN PAGO DUPLICADO EVITADO (solo horas) ==")
    p = copy.deepcopy(BASE)
    p["deteccion"] = 1 - (DUPLICADAS_NO_DETECTADAS / DUPLICADAS) ; # = 0.4228 (detecta lo mismo que el manual)
    c = calcular(p); print({k: round(v, 2) for k, v in c.items()})
