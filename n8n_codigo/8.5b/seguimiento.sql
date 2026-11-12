-- Seguimiento de plazos. Parámetros: hora de referencia (vacía = ahora) y prefijo (vacío = reclamos reales).
-- Aviso a las 16 horas hábiles sin primera respuesta; a las 24, se escala al Jefe de Atención por la cola.
WITH p AS (SELECT coalesce(nullif($1, '')::timestamp, now()::timestamp) AS ahora, $2::text AS prefijo),
pend AS (
  SELECT r.reclamo_id, r.area_derivada, r.fecha_hora_ingreso, r.vence_primera_respuesta, r.aviso_enviado, r.escalado,
         control.sumar_horas_habiles(r.fecha_hora_ingreso, 16) AS aviso_desde, p.ahora
  FROM negocio.reclamos r, p
  WHERE r.fecha_hora_primera_respuesta IS NULL AND r.area_derivada IS NOT NULL
    AND r.fecha_hora_ingreso <= p.ahora
    AND (CASE WHEN p.prefijo = '' THEN r.reclamo_id NOT LIKE 'PRUEBA%' ELSE r.reclamo_id LIKE p.prefijo || '%' END)),
esc AS (
  UPDATE negocio.reclamos r SET escalado = true, aviso_enviado = true
  FROM pend WHERE r.reclamo_id = pend.reclamo_id AND NOT pend.escalado AND pend.ahora >= pend.vence_primera_respuesta
  RETURNING r.reclamo_id),
cola AS (
  INSERT INTO control.cola_revision (origen, automatizacion_id, documento_id, motivo, prioridad, asignado_a)
  SELECT 'reclamos', 'A09', pend.reclamo_id,
         'Sin primera respuesta en 24 horas hábiles (venció ' || to_char(pend.vence_primera_respuesta, 'DD/MM HH24:MI') || '). Área: ' || pend.area_derivada,
         'alta', 'Jefe de Atención'
  FROM esc JOIN pend USING (reclamo_id)),
avi AS (
  UPDATE negocio.reclamos r SET aviso_enviado = true
  FROM pend WHERE r.reclamo_id = pend.reclamo_id AND NOT pend.aviso_enviado
    AND pend.ahora >= pend.aviso_desde AND pend.ahora < pend.vence_primera_respuesta
  RETURNING r.reclamo_id)
SELECT pend.reclamo_id, pend.area_derivada,
       CASE WHEN esc.reclamo_id IS NOT NULL THEN 'escalado' ELSE 'aviso' END AS accion,
       to_char(pend.vence_primera_respuesta, 'YYYY-MM-DD HH24:MI') AS vence_primera_respuesta
FROM pend LEFT JOIN esc USING (reclamo_id) LEFT JOIN avi USING (reclamo_id)
WHERE esc.reclamo_id IS NOT NULL OR avi.reclamo_id IS NOT NULL
ORDER BY 1;
