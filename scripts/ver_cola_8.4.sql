-- Casos de facturas reales (sin PRUEBA) en la cola de revisión, del más nuevo al más viejo.
SELECT documento_id, automatizacion_id AS etapa, prioridad, left(motivo, 140) AS motivo
FROM control.cola_revision
WHERE origen IN ('facturas', 'seguridad') AND documento_id NOT LIKE 'PRUEBA%'
  AND ingreso::date = current_date
ORDER BY automatizacion_id, documento_id;
