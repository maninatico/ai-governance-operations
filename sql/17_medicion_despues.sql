-- Fase 10. Mediciones del DESPUES (solo lectura, no modifica nada).
-- Excluye todo lo que lleve el prefijo PRUEBA. Uso:
--   docker exec -i cumbre_andina_db sh -c 'psql -U "$POSTGRES_USER" -d cumbre_andina -v ON_ERROR_STOP=1' < sql/17_medicion_despues.sql
\pset pager off
\echo '== 1. Facturas del lote por estado =='
SELECT estado, count(*) AS facturas
FROM negocio.comprobantes
WHERE origen = 'lote_prueba' AND comprobante_id NOT LIKE 'PRUEBA%'
GROUP BY estado ORDER BY facturas DESC;

\echo '== 2. Facturas: ejecuciones por automatizacion (A04 a A07), sin PRUEBA =='
SELECT automatizacion_id AS auto,
       count(*) AS ejecuciones,
       count(DISTINCT documento_id) AS documentos,
       round(avg(extract(epoch FROM (fin - inicio)))::numeric, 1) AS seg_promedio,
       count(*) FILTER (WHERE estado = 'error') AS errores,
       count(*) FILTER (WHERE estado = 'derivado_a_cola') AS a_cola,
       count(*) FILTER (WHERE estado = 'bloqueado') AS bloqueadas,
       sum(costo_usd) AS costo_usd
FROM control.ejecuciones
WHERE automatizacion_id IN ('A04','A05','A06','A07')
  AND coalesce(documento_id, '') NOT LIKE 'PRUEBA%'
GROUP BY automatizacion_id ORDER BY automatizacion_id;

\echo '== 3. Reclamos del lote: respuesta y derivacion =='
SELECT count(*) AS reclamos,
       count(categoria) AS con_categoria,
       count(area_derivada) AS derivados,
       count(*) FILTER (WHERE es_pedido_datos_personales) AS pedidos_datos
FROM negocio.reclamos
WHERE origen = 'lote_prueba' AND reclamo_id NOT LIKE 'PRUEBA%';

\echo '== 4. Reclamos: ejecuciones A08 a A10, sin PRUEBA =='
SELECT automatizacion_id AS auto,
       count(*) AS ejecuciones,
       count(DISTINCT documento_id) AS documentos,
       round(avg(extract(epoch FROM (fin - inicio)))::numeric, 1) AS seg_promedio,
       count(*) FILTER (WHERE estado = 'error') AS errores,
       count(*) FILTER (WHERE estado = 'derivado_a_cola') AS a_cola,
       sum(costo_usd) AS costo_usd
FROM control.ejecuciones
WHERE automatizacion_id IN ('A08','A09','A10')
  AND coalesce(documento_id, '') NOT LIKE 'PRUEBA%'
GROUP BY automatizacion_id ORDER BY automatizacion_id;

\echo '== 5. Cola de revision (sin PRUEBA): origen, prioridad y estado =='
SELECT origen, prioridad, estado, count(*) AS casos
FROM control.cola_revision
WHERE documento_id NOT LIKE 'PRUEBA%'
GROUP BY origen, prioridad, estado ORDER BY origen, prioridad, estado;

\echo '== 6. Aprobaciones (sin PRUEBA): por accion y decision =='
SELECT accion, coalesce(decision, 'sin decidir') AS decision, count(*) AS aprobaciones
FROM control.aprobaciones
WHERE objeto NOT LIKE '%PRUEBA%'
GROUP BY accion, decision ORDER BY accion, decision;

\echo '== 7. Totales: ejecuciones y costo de IA (sin PRUEBA) =='
SELECT count(*) AS ejecuciones,
       count(*) FILTER (WHERE intervencion_humana) AS con_humano,
       coalesce(sum(costo_usd), 0) AS costo_usd_total,
       coalesce(sum(tokens_entrada), 0) AS tokens_entrada,
       coalesce(sum(tokens_salida), 0) AS tokens_salida
FROM control.ejecuciones
WHERE coalesce(documento_id, '') NOT LIKE 'PRUEBA%';
