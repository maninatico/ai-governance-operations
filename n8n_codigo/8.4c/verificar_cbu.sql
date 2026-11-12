-- CA84c_Verificar_CBU
-- La bóveda responde solo sí o no: el flujo nunca ve el CBU registrado.
SELECT ($2 ~ '^\d{22}$') AS cbu_leido,
       CASE WHEN $2 ~ '^\d{22}$' THEN boveda.cbu_coincide($1, $2) ELSE false END AS coincide;

-- CA84c_Bloquear_pago
-- Bloquea la factura y la manda a la cola con prioridad alta. No toca la bóveda.
WITH upd AS (
  UPDATE negocio.comprobantes SET estado = 'Bloqueada'
  WHERE comprobante_id = $1 AND estado IN ('Recibida', 'En cola de revisión')
  RETURNING comprobante_id)
INSERT INTO control.cola_revision (origen, automatizacion_id, documento_id, motivo, prioridad)
SELECT 'facturas', 'A06', $1, $2, 'alta' FROM upd
RETURNING 'Bloqueada' AS estado;
