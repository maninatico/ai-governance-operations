#!/usr/bin/env python3
"""Exporta los flujos CA_* de n8n como JSON sin credenciales (entregable de la Fase 8).

Lee una COPIA de la base de n8n (no la base en uso), asi no hay riesgo de tocar nada.
Uso, desde la carpeta del proyecto en WSL:
    python3 scripts/exportar_flujos.py ~/N8N/backups/2026-11-09-d-docker/database.sqlite

Escribe n8n_codigo/flujos/<nombre>.json y n8n_codigo/flujos/INDICE.md.
Quita: credenciales (id y nombre), datos fijados (pinData), direcciones IP privadas y correos.
Los reemplaza por marcadores y cuenta cuantos cambio, para que se pueda revisar.
"""
import json
import os
import re
import sqlite3
import sys

if len(sys.argv) != 2:
    sys.exit("Falta la ruta a la copia de database.sqlite")

origen = os.path.expanduser(sys.argv[1])
if not os.path.isfile(origen):
    sys.exit("No existe: " + origen)

carpeta = os.path.join("n8n_codigo", "flujos")
os.makedirs(carpeta, exist_ok=True)

RE_IP = re.compile(r"\b(?:10|100|192\.168|172\.(?:1[6-9]|2\d|3[01]))\.\d{1,3}\.\d{1,3}(?:\.\d{1,3})?\b")
RE_MAIL = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")
cuenta = {"credenciales": 0, "ip": 0, "correos": 0}


def limpiar(valor):
    if isinstance(valor, dict):
        salida = {}
        for k, v in valor.items():
            if k == "credentials":
                cuenta["credenciales"] += len(v) if isinstance(v, dict) else 1
                continue
            salida[k] = limpiar(v)
        return salida
    if isinstance(valor, list):
        return [limpiar(x) for x in valor]
    if isinstance(valor, str):
        nuevo, n = RE_IP.subn("<IP_PRIVADA>", valor)
        cuenta["ip"] += n
        nuevo, n = RE_MAIL.subn("<CORREO>", nuevo)
        cuenta["correos"] += n
        return nuevo
    return valor


con = sqlite3.connect(origen)
filas = con.execute(
    "select name, nodes, connections, settings, active from workflow_entity "
    "where name like 'CA\\_%' escape '\\' order by name"
).fetchall()

indice = []
for nombre, nodes, connections, settings, activo in filas:
    flujo = {
        "name": nombre,
        "nodes": limpiar(json.loads(nodes)),
        "connections": json.loads(connections),
        "settings": json.loads(settings) if settings else {},
    }
    with open(os.path.join(carpeta, nombre + ".json"), "w", encoding="utf-8") as f:
        json.dump(flujo, f, ensure_ascii=False, indent=2)
    indice.append((nombre, bool(activo), len(flujo["nodes"])))

with open(os.path.join(carpeta, "INDICE.md"), "w", encoding="utf-8") as f:
    f.write("# Flujos de n8n exportados (sin credenciales)\n\n")
    f.write("Origen: copia de la base de n8n del respaldo indicado al exportar. ")
    f.write("Se quitaron credenciales, datos fijados, IP privadas y correos.\n\n")
    f.write("| Flujo | Publicado | Nodos |\n|---|---|---|\n")
    for nombre, activo, n in indice:
        f.write("| %s | %s | %d |\n" % (nombre, "si" if activo else "no", n))

print("Flujos exportados:", len(indice))
print("Credenciales quitadas:", cuenta["credenciales"])
print("IP privadas reemplazadas:", cuenta["ip"])
print("Correos reemplazados:", cuenta["correos"])
print("Carpeta:", carpeta)
