-- Deriva según la tabla fija categoría -> área y fija los vencimientos en horas hábiles. No pisa una derivación previa.
UPDATE negocio.reclamos r
SET area_derivada = a.area,
    vence_primera_respuesta = control.sumar_horas_habiles(r.fecha_hora_ingreso, 24),
    vence_resolucion        = control.sumar_horas_habiles(r.fecha_hora_ingreso, 45)
FROM negocio.areas_por_categoria a
WHERE r.reclamo_id = $1 AND a.categoria = r.categoria AND r.area_derivada IS NULL
RETURNING r.reclamo_id, r.categoria, r.area_derivada,
          to_char(r.vence_primera_respuesta, 'YYYY-MM-DD HH24:MI') AS vence_primera_respuesta,
          to_char(r.vence_resolucion, 'YYYY-MM-DD HH24:MI') AS vence_resolucion;
