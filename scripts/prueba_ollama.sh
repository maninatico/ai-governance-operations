#!/bin/bash
# Prueba de velocidad y formato de los modelos locales de Ollama (servidor por Tailscale)
SERVIDOR="http://100.80.133.118:11434"
PROMPT='Devolve solo JSON con las claves numero y total. Texto: Factura A 0001-00008635, total $ 982.276,14'
for MODELO in qwen3.5:9b gemma4:12b; do
  echo "=== $MODELO"
  INICIO=$(date +%s.%N)
  curl -s --max-time 180 "$SERVIDOR/api/generate" \
    -d "{\"model\":\"$MODELO\",\"prompt\":\"$PROMPT\",\"stream\":false,\"format\":\"json\",\"think\":false}" \
    | python3 -c 'import sys,json; r=json.load(sys.stdin); print("respuesta:", r.get("response","").strip()); print("error:", r.get("error"))' 2>/dev/null || echo "sin respuesta"
  FIN=$(date +%s.%N)
  python3 -c "print(\"segundos:\", round($FIN - $INICIO, 1))"
done
