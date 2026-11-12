"""Fase 7, paso 4. Carga los datos (histórico limpio) en Postgres.
Conexión por variables de entorno (nunca en el código): PGHOST, PGPORT, PGDATABASE, PGUSER, PGPASSWORD.
Corre después de sql/01_esquema.sql y sql/02_roles.sql. Usa el usuario dueño de la base.

Los datos personales van solo a la bóveda. El texto de los reclamos se guarda enmascarado:
  capa 1: cruce con la propia base (datos del cliente que reclama)
  capa 2: patrones (DNI, teléfono, correo) para lo que quede
  (capa 3, detección de nombres con NER, se implementa en A02 en la Fase 8)
Falla segura: si después de enmascarar queda algún dato personal reconocible, el script se detiene."""
import re
from pathlib import Path
import pandas as pd
import psycopg2
from psycopg2.extras import execute_values

BASE = Path(__file__).resolve().parent.parent / "datos"
L, V = BASE / "limpio", BASE / "verdad"
leer = lambda p: pd.read_csv(p, dtype=str, encoding="utf-8-sig").where(lambda d: d.notna(), None)
conn = psycopg2.connect("")
cur = conn.cursor()

def cargar(tabla, df, columnas):
    d = df[columnas].astype(object)
    d = d.where(d.notna(), None)          # vacíos y NaN se cargan como NULL
    execute_values(cur, f"INSERT INTO {tabla} ({', '.join(columnas)}) VALUES %s",
                   d.itertuples(index=False, name=None), page_size=2000)
    print(f"{tabla}: {len(df):,}")

# Proveedores (todos personas jurídicas en el caso) y sus CBU (bóveda)
p = leer(L / "proveedores_limpio.csv")
p["tipo_persona"] = "juridica"
p["activo"] = p["activo"].map({"True": True, "False": False})
cargar("negocio.proveedores", p, ["proveedor_id", "tipo_persona", "razon_social", "cuit", "rubro",
                                  "alicuota_iva", "condicion_pago_dias", "activo"])
p["vigente_desde"], p["verificado_por"], p["canal_verificacion"] = "2025-01-01", "Alta inicial", "Alta inicial"
cargar("boveda.cuentas_bancarias", p, ["proveedor_id", "banco", "cbu", "vigente_desde", "verificado_por", "canal_verificacion"])

# Clientes: ID y datos comerciales en negocio; datos personales en la bóveda
c = leer(L / "clientes_limpio.csv")
c["revisar_dni"] = c["revisar_dni"].map({"True": True, "False": False})
cargar("negocio.clientes", c, ["cliente_id", "tipo_cliente", "sucursal_habitual"])
cargar("boveda.clientes_datos", c, ["cliente_id", "nombre", "apellido", "dni", "telefono", "email",
                                    "direccion", "localidad", "revisar_dni"])

cargar("negocio.ordenes_compra", leer(L / "ordenes_de_compra_limpio.csv"),
       ["oc_id", "proveedor_id", "fecha_oc", "monto_neto_oc", "estado_oc"])

# Comprobantes: primero originales, después duplicadas (que apuntan a su original)
f = leer(L / "facturas_limpio.csv")
f = f.rename(columns={"factura_id": "comprobante_id", "minutos_carga": "minutos_proceso"})
bool_ = lambda s: s.map({"True": True, "False": False})
for col in ["es_duplicada", "fecha_normalizada", "cuit_corregido", "razon_estandarizada", "excepcion_monto"]:
    f[col] = bool_(f[col])
f["detectada_manual"] = f["detectada_manual"].map({"True": True, "False": False})
f["con_error_datos"] = f[["fecha_normalizada", "cuit_corregido", "razon_estandarizada", "excepcion_monto"]].any(axis=1)
f["fuente_lectura"], f["origen"] = "manual", "historico"
cols = ["comprobante_id", "proveedor_id", "tipo_comprobante", "punto_venta", "numero", "fecha_emision",
        "fecha_recepcion", "fecha_registro", "canal", "fuente_lectura", "oc_id", "neto", "alicuota_iva", "iva",
        "total", "total_original", "minutos_proceso", "con_error_datos", "es_duplicada", "duplicada_de",
        "detectada_manual", "estado", "origen"]
cargar("negocio.comprobantes", f[~f["es_duplicada"]], cols)
cargar("negocio.comprobantes", f[f["es_duplicada"]], cols)

# Reclamos: enmascarado del texto + marcadores en la bóveda
r = leer(L / "reclamos_historico_limpio.csv")
r = r.merge(leer(V / "reclamos_historico_verdad.csv")[["reclamo_id", "derivacion_correcta"]], on="reclamo_id")
datos = c.set_index("cliente_id")
PATRONES = [("DNI", r"\b\d{7,8}\b"), ("TEL", r"\b\d{2,4}-\d{4}-\d{4}\b"), ("EMAIL", r"[\w.+-]+@[\w-]+(\.[\w-]+)+")]
marcadores, textos = [], []
for rid, cid, texto in zip(r["reclamo_id"], r["cliente_id"], r["texto"]):
    cuenta, d = {}, datos.loc[cid]
    def marcar(tipo, valor):
        cuenta[tipo] = cuenta.get(tipo, 0) + 1
        m = f"[{tipo}_{cuenta[tipo]}]"
        marcadores.append((rid, m, tipo, valor))
        return m
    # capa 1: cruce con la base propia
    for tipo, valor in [("NOMBRE", f"{d['nombre']} {d['apellido']}"), ("DNI", d["dni"]), ("TEL", d["telefono"]),
                        ("EMAIL", d["email"]), ("DIRECCION", d["direccion"])]:
        if valor and valor in texto:
            texto = texto.replace(valor, marcar(tipo, valor))
    # capa 2: patrones para lo que quede
    for tipo, patron in PATRONES:
        texto = re.sub(patron, lambda mm: marcar(tipo, mm.group(0)), texto)
    # falla segura: ningún dato del cliente puede quedar en el texto
    restos = [v for v in [d["dni"], d["telefono"], d["email"], d["direccion"], d["apellido"]] if v and v in texto]
    if restos:
        raise SystemExit(f"Falla segura: {rid} conserva datos personales después de enmascarar. No se carga nada.")
    textos.append(texto)
r["texto_enmascarado"], r["origen"] = textos, "historico"
r["reabierto"] = bool_(r["reabierto"])
r["derivacion_correcta"] = bool_(r["derivacion_correcta"])
r = r.rename(columns={"categoria_asignada": "categoria"})
cargar("negocio.reclamos", r, ["reclamo_id", "cliente_id", "sucursal", "canal", "fecha_hora_ingreso", "texto_enmascarado",
                               "categoria", "area_derivada", "fecha_hora_primera_respuesta", "fecha_hora_cierre",
                               "reabierto", "derivacion_correcta", "agente", "origen"])
execute_values(cur, "INSERT INTO boveda.marcadores (documento_id, marcador, tipo, valor_real) VALUES %s", marcadores)
print(f"boveda.marcadores: {len(marcadores):,} (en {len({m[0] for m in marcadores}):,} reclamos)")

cur.execute("INSERT INTO control.auditoria (actor, accion, objeto, detalle) VALUES (%s, %s, %s, %s)",
            ("cargar_base.py", "carga inicial", "base completa", '{"origen": "historico limpio, Fase 5"}'))
conn.commit()
print("Carga confirmada.")
