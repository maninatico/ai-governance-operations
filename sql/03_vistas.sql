-- =====================================================================
-- Fase 7. Vistas de reportes para Power BI
-- Solo datos seudonimizados o agregados. Power BI (powerbi_lector) lee únicamente este esquema.
-- Supuestos (Fase 5): día hábil = lunes a viernes de 8 a 17, sin feriados;
-- el mes de cada factura es el de su emisión.
-- =====================================================================

-- Días hábiles entre dos fechas: cuenta desde el día de inicio, sin contar el final
CREATE OR REPLACE FUNCTION reportes.dias_habiles(desde date, hasta date)
RETURNS int LANGUAGE sql IMMUTABLE AS $$
    SELECT count(*)::int FROM generate_series(desde, hasta - 1, interval '1 day') d
    WHERE extract(isodow FROM d) < 6;
$$;

-- Horas hábiles entre dos momentos (lunes a viernes, 8 a 17)
CREATE OR REPLACE FUNCTION reportes.horas_habiles(desde timestamp, hasta timestamp)
RETURNS numeric LANGUAGE sql IMMUTABLE AS $$
    SELECT coalesce(sum(extract(epoch FROM
               least(hasta, d + interval '17 hours') - greatest(desde, d + interval '8 hours')) / 3600), 0)
    FROM generate_series(date_trunc('day', desde), date_trunc('day', hasta), interval '1 day') d
    WHERE extract(isodow FROM d) < 6
      AND least(hasta, d + interval '17 hours') > greatest(desde, d + interval '8 hours');
$$;

-- ---------------------------------------------------------------------
-- Facturas por mes
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW reportes.kpi_facturas_mensual AS
WITH base AS (
    SELECT to_char(fecha_emision, 'YYYY-MM') AS mes, c.*,
           CASE WHEN fecha_registro IS NOT NULL THEN reportes.dias_habiles(fecha_recepcion, fecha_registro) END AS dias
    FROM negocio.comprobantes c
    WHERE origen = 'historico'
)
SELECT mes,
       count(*) FILTER (WHERE NOT es_duplicada)                                   AS facturas_recibidas,
       round(avg(dias), 2)                                                        AS dias_hasta_quedar_cargada,
       round(100.0 * avg((dias > 2)::int) FILTER (WHERE dias IS NOT NULL), 1)     AS pct_cargadas_tarde,
       round(sum(minutos_proceso) / 60, 1)                                        AS horas_cargando_a_mano,
       round(100.0 * avg(con_error_datos::int) FILTER (WHERE NOT es_duplicada), 1) AS pct_con_algun_dato_mal,
       count(*) FILTER (WHERE es_duplicada)                                       AS duplicadas,
       count(*) FILTER (WHERE es_duplicada AND NOT detectada_manual)              AS duplicadas_escapadas,
       count(*) FILTER (WHERE es_duplicada AND NOT detectada_manual AND estado = 'Pagada') AS pagadas_dos_veces,
       coalesce(sum(total) FILTER (WHERE es_duplicada AND NOT detectada_manual AND estado = 'Pagada'), 0) AS pesos_pagados_dos_veces,
       count(*) FILTER (WHERE es_duplicada AND NOT detectada_manual AND estado <> 'Pagada') AS duplicadas_todavia_frenables
FROM base
GROUP BY mes;

-- ---------------------------------------------------------------------
-- Reclamos por mes
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW reportes.kpi_reclamos_mensual AS
WITH base AS (
    SELECT to_char(fecha_hora_ingreso, 'YYYY-MM') AS mes, r.*,
           reportes.horas_habiles(fecha_hora_ingreso, fecha_hora_primera_respuesta) AS horas_resp,
           reportes.dias_habiles(fecha_hora_ingreso::date, fecha_hora_cierre::date) AS dias_res
    FROM negocio.reclamos r
    WHERE origen = 'historico'
)
SELECT mes,
       count(*)                                                     AS reclamos,
       round(avg(horas_resp), 1)                                    AS horas_hasta_primera_respuesta,
       round(100.0 * avg((horas_resp > 24)::int), 1)                AS pct_esperan_mas_de_un_dia,
       round(100.0 * avg((dias_res <= 5)::int), 1)                  AS pct_resueltos_a_tiempo,
       round(100.0 * avg((NOT derivacion_correcta)::int), 1)        AS pct_area_equivocada,
       round(100.0 * avg(reabierto::int), 1)                        AS pct_vuelven_a_abrirse
FROM base
GROUP BY mes;

-- ¿Dónde y por qué reclaman? (sin datos personales)
CREATE OR REPLACE VIEW reportes.reclamos_donde_y_por_que AS
SELECT to_char(fecha_hora_ingreso, 'YYYY-MM') AS mes, sucursal, categoria, canal, count(*) AS reclamos
FROM negocio.reclamos
GROUP BY 1, 2, 3, 4;

-- ---------------------------------------------------------------------
-- Gobernanza (se llenan en la Fase 8 con las ejecuciones de n8n)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW reportes.inventario AS
SELECT automatizacion_id, nombre, proceso, usa_ia, nivel, riesgo, dueno, version, estado, modelo_ia
FROM control.automatizaciones;

CREATE OR REPLACE VIEW reportes.salud_automatizaciones AS
SELECT automatizacion_id, date_trunc('day', inicio)::date AS dia,
       count(*) AS ejecuciones,
       count(*) FILTER (WHERE estado = 'ok') AS exitosas,
       count(*) FILTER (WHERE estado = 'derivado_a_cola') AS derivadas_a_cola,
       count(*) FILTER (WHERE estado = 'bloqueado') AS bloqueadas,
       count(*) FILTER (WHERE intervencion_humana) AS con_intervencion_humana,
       round(sum(costo_usd), 4) AS costo_ia_usd
FROM control.ejecuciones
GROUP BY 1, 2;

CREATE OR REPLACE VIEW reportes.cola_revision AS
SELECT caso_id, origen, automatizacion_id, motivo, prioridad, ingreso, estado, resuelto,
       round(extract(epoch FROM (resuelto - ingreso)) / 3600, 1) AS horas_hasta_resolver
FROM control.cola_revision;     -- sin documento_id ni nombres: solo el caso y su motivo

CREATE OR REPLACE VIEW reportes.aprobaciones AS
SELECT aprobacion_id, automatizacion_id, accion, nivel, pedido, vence, decision, decidido,
       escalado_a IS NOT NULL AS escalada,
       round(extract(epoch FROM (decidido - pedido)) / 3600, 1) AS horas_hasta_decidir
FROM control.aprobaciones;

CREATE OR REPLACE VIEW reportes.reidentificaciones_por_mes AS
SELECT to_char(momento, 'YYYY-MM') AS mes, tipo_uso, count(*) AS usos,
       count(*) FILTER (WHERE tipo_uso = 'consulta manual' AND aprobado_por IS NOT NULL) AS manuales_aprobadas
FROM control.reidentificaciones
GROUP BY 1, 2;

CREATE OR REPLACE VIEW reportes.incidentes AS
SELECT incidente_id, severidad, automatizacion_id, detectado, contenido, resuelto,
       round(extract(epoch FROM (contenido - detectado)) / 3600, 1) AS horas_hasta_contener,
       datos_personales_involucrados
FROM control.incidentes;

-- Permisos: ALTER DEFAULT PRIVILEGES de 02_roles.sql cubre vistas nuevas; esto cubre las ya creadas
GRANT SELECT ON ALL TABLES IN SCHEMA reportes TO rol_powerbi, rol_monitoreo;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA reportes TO rol_powerbi, rol_monitoreo;
