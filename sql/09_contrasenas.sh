#!/bin/sh
# Fase 7 (ampliado en 8.3). Se ejecuta al final, cuando ya existen todos los usuarios.
# Define las contraseñas de los usuarios a partir de variables de entorno (.env).
# Las contraseñas nunca quedan escritas en los scripts. Si falta alguna, se detiene (falla segura).
set -e
for v in PW_N8N_FACTURAS PW_N8N_RECLAMOS PW_N8N_BOVEDA PW_N8N_COLA PW_N8N_MONITOREO PW_POWERBI_LECTOR PW_GERENTE_ADM PW_N8N_POLITICAS; do
  eval "valor=\${$v:-}"
  if [ -z "$valor" ] || [ "$valor" = "cambiar" ]; then echo "Falta definir $v en .env" >&2; exit 1; fi
done
psql -v ON_ERROR_STOP=1 --username "${POSTGRES_USER:-postgres}" --dbname "${POSTGRES_DB:-cumbre_andina}" \
  -v p1="$PW_N8N_FACTURAS" -v p2="$PW_N8N_RECLAMOS" -v p3="$PW_N8N_BOVEDA" -v p4="$PW_N8N_COLA" \
  -v p5="$PW_N8N_MONITOREO" -v p6="$PW_POWERBI_LECTOR" -v p7="$PW_GERENTE_ADM" -v p8="$PW_N8N_POLITICAS" <<'EOSQL'
ALTER ROLE n8n_facturas   PASSWORD :'p1';
ALTER ROLE n8n_reclamos   PASSWORD :'p2';
ALTER ROLE n8n_boveda     PASSWORD :'p3';
ALTER ROLE n8n_cola       PASSWORD :'p4';
ALTER ROLE n8n_monitoreo  PASSWORD :'p5';
ALTER ROLE powerbi_lector PASSWORD :'p6';
ALTER ROLE gerente_adm    PASSWORD :'p7';
ALTER ROLE n8n_politicas  PASSWORD :'p8';
EOSQL
echo "Contraseñas definidas para 8 usuarios."
