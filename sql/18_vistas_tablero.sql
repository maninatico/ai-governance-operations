-- =====================================================================
-- Fase 11. Vistas del tablero de gobernanza (Power BI)
-- 1) Las vistas de gobernanza dejan de mostrar registros de prueba (prefijo PRUEBA).
-- 2) Vistas nuevas con el "despues" (lote) y el estado de los interruptores.
-- Sigue sin datos personales: solo conteos y atributos de control.
-- Uso: docker exec -i cumbre_andina_db sh -c 'psql -U "$POSTGRES_USER" -d cumbre_andina -v ON_ERROR_STOP=1' < sql/18_vistas_tablero.sql
-- =====================================================================

-- 1) Sin registros de prueba (mismas columnas que antes)
CREATE OR REPLACE VIEW reportes.salud_automatizaciones AS
SELECT automatizacion_id, date_trunc('day', inicio)::date AS dia,
       count(*) AS ejecuciones,
       count(*) FILTER (WHERE estado = 'ok') AS exitosas,
       count(*) FILTER (WHERE estado = 'derivado_a_cola') AS derivadas_a_cola,
       count(*) FILTER (WHERE estado = 'bloqueado') AS bloqueadas,
       count(*) FILTER (WHERE intervencion_humana) AS con_intervencion_humana,
       round(sum(costo_usd), 4) AS costo_ia_usd
FROM control.ejecuciones
WHERE coalesce(documento_id, '') NOT LIKE 'PRUEBA%'
GROUP BY 1, 2;

CREATE OR REPLACE VIEW reportes.cola_revision AS
SELECT caso_id, origen, automatizacion_id, motivo, prioridad, ingreso, estado, resuelto,
       round(extract(epoch FROM (resuelto - ingreso)) / 3600, 1) AS horas_hasta_resolver
FROM control.cola_revision
WHERE documento_id NOT LIKE 'PRUEBA%';

CREATE OR REPLACE VIEW reportes.aprobaciones AS
SELECT aprobacion_id, automatizacion_id, accion, nivel, pedido, vence, decision, decidido,
       escalado_a IS NOT NULL AS escalada,
       round(extract(epoch FROM (decidido - pedido)) / 3600, 1) AS horas_hasta_decidir
FROM control.aprobaciones
WHERE objeto NOT LIKE '%PRUEBA%';

CREATE OR REPLACE VIEW reportes.reidentificaciones_por_mes AS
SELECT to_char(momento, 'YYYY-MM') AS mes, tipo_uso, count(*) AS usos,
       count(*) FILTER (WHERE tipo_uso = 'consulta manual' AND aprobado_por IS NOT NULL) AS manuales_aprobadas
FROM control.reidentificaciones
WHERE documento_id NOT LIKE 'PRUEBA%'
GROUP BY 1, 2;

CREATE OR REPLACE VIEW reportes.incidentes AS
SELECT incidente_id, severidad, automatizacion_id, detectado, contenido, resuelto,
       round(extract(epoch FROM (contenido - detectado)) / 3600, 1) AS horas_hasta_contener,
       datos_personales_involucrados
FROM control.incidentes
WHERE descripcion NOT LIKE '%PRUEBA%';

-- 2) El "despues" del lote de prueba (sin prefijo PRUEBA)
CREATE OR REPLACE VIEW reportes.despues_facturas_lote AS
SELECT estado, count(*) AS facturas
FROM negocio.comprobantes
WHERE origen = 'lote_prueba' AND comprobante_id NOT LIKE 'PRUEBA%'
GROUP BY estado;

CREATE OR REPLACE VIEW reportes.despues_reclamos_lote AS
SELECT count(*) AS reclamos,
       count(categoria) AS con_categoria,
       count(area_derivada) AS derivados_a_un_area,
       count(*) FILTER (WHERE es_pedido_datos_personales) AS pedidos_de_datos_personales
FROM negocio.reclamos
WHERE origen = 'lote_prueba' AND reclamo_id NOT LIKE 'PRUEBA%';

-- Controles activos: estado de los interruptores (sin datos personales)
CREATE OR REPLACE VIEW reportes.interruptores AS
SELECT flujo, activo, errores_seguidos, limite_errores, cambiado
FROM control.interruptores;

GRANT SELECT ON ALL TABLES IN SCHEMA reportes TO rol_powerbi, rol_monitoreo;
