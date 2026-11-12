-- Pasa al reclamo lo que decidió el agente en el formulario. Parámetro: prefijo (vacío = reclamos reales).
WITH ult AS (
  SELECT DISTINCT ON (a.objeto) a.objeto, a.aprobacion_id, a.decision, a.motivo
  FROM control.aprobaciones a JOIN negocio.reclamos r ON r.reclamo_id = a.objeto
  WHERE a.accion = 'enviar_respuesta_cliente' AND r.respuesta_estado = 'pendiente_aprobacion'
    AND (CASE WHEN $1 = '' THEN a.objeto NOT LIKE 'PRUEBA%' ELSE a.objeto LIKE $1 || '%' END)
  ORDER BY a.objeto, a.aprobacion_id DESC),
upd AS (
  UPDATE negocio.reclamos r
  SET respuesta_estado = CASE ult.decision WHEN 'aprobado' THEN 'aprobada' ELSE 'rechazada' END
  FROM ult WHERE r.reclamo_id = ult.objeto AND ult.decision IS NOT NULL
  RETURNING r.reclamo_id, r.respuesta_estado, ult.aprobacion_id, ult.motivo),
cola AS (
  INSERT INTO control.cola_revision (origen, automatizacion_id, documento_id, motivo, prioridad, asignado_a)
  SELECT 'reclamos', 'A10', reclamo_id, 'Borrador rechazado en la aprobación ' || aprobacion_id || ': ' || coalesce(motivo, 'sin motivo') || '. Redactar a mano.', 'media', 'Agente de atención'
  FROM upd WHERE respuesta_estado = 'rechazada')
SELECT reclamo_id, respuesta_estado AS estado, aprobacion_id FROM upd
UNION ALL
SELECT objeto, 'pendiente_aprobacion', aprobacion_id FROM ult WHERE decision IS NULL
ORDER BY 1;
