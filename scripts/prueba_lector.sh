#!/bin/bash
# Prueba del lector local desde adentro de n8n (misma red que usarán los flujos)
for A in LOTE-003.pdf LOTE-001.pdf LOTE-004.pdf; do
  echo "=== $A"
  docker exec n8n-local wget -qO- -T 120 "http://cumbre_lector:8000/leer?archivo=facturas_pdf/$A" \
    | python3 -c 'import sys,json; r=json.load(sys.stdin); print("escaneado:", r["escaneado"], "| fuente:", r["fuente_sugerida"], "| QR:", (r["qr"]["datos"] or {}).get("importe"), "| texto oculto:", r["texto_oculto"]["detectado"], r["texto_oculto"]["motivos"])' \
    || echo "sin respuesta"
done
