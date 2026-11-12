-- =====================================================================
-- 12. Reporte semanal (Fase 8.7, automatización A12)
-- Una función arma el reporte con conteos (sin datos personales) y lo guarda en control.reportes.
-- Un reporte real por semana (por fecha de corte): llamarla de nuevo devuelve el mismo.
-- Con p_prueba = true crea uno marcado de prueba, que no ocupa la semana.
-- Se puede correr más de una vez.
-- =====================================================================

CREATE TABLE IF NOT EXISTS control.reportes (
    reporte_id      bigserial PRIMARY KEY,
    generado        timestamp NOT NULL DEFAULT now(),
    periodo_desde   date NOT NULL,
    periodo_hasta   date NOT NULL,
    es_prueba       boolean NOT NULL DEFAULT false,
    datos           jsonb NOT NULL,
    texto           text NOT NULL,
    enviado         boolean NOT NULL DEFAULT false,
    enviado_momento timestamp
);
CREATE UNIQUE INDEX IF NOT EXISTS ux_reportes_semana ON control.reportes (periodo_hasta) WHERE NOT es_prueba;

CREATE OR REPLACE FUNCTION control.generar_reporte_semanal(p_prueba boolean DEFAULT false, p_ahora timestamp DEFAULT now())
RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = control, negocio, pg_temp AS $$
DECLARE
    v_hasta date := p_ahora::date;
    v_desde date := p_ahora::date - 7;
    v_id bigint;
    v_fact jsonb; v_fact_total int;
    v_recl jsonb; v_recl_total int; v_pedidos int;
    v_cola jsonb; v_cola_total int;
    v_aprob_pend int; v_venc int;
    v_act jsonb; v_cortes int; v_alertas jsonb; v_alertas_total int; v_alertas_env int;
    v_apagados text[];
    v_datos jsonb; v_texto text; r record;
BEGIN
    IF NOT p_prueba THEN
        SELECT reporte_id INTO v_id FROM control.reportes WHERE periodo_hasta = v_hasta AND NOT es_prueba;
        IF FOUND THEN RETURN v_id; END IF;
    END IF;

    SELECT coalesce(jsonb_object_agg(estado, n), '{}'::jsonb), coalesce(sum(n), 0)::int INTO v_fact, v_fact_total
      FROM (SELECT estado, count(*) AS n FROM negocio.comprobantes
             WHERE origen = 'lote_prueba' AND comprobante_id NOT ILIKE 'PRUEBA%' GROUP BY estado) x;

    SELECT coalesce(jsonb_object_agg(e, n), '{}'::jsonb), coalesce(sum(n), 0)::int INTO v_recl, v_recl_total
      FROM (SELECT coalesce(respuesta_estado, 'sin borrador') AS e, count(*) AS n FROM negocio.reclamos
             WHERE origen = 'lote_prueba' AND reclamo_id NOT ILIKE 'PRUEBA%' GROUP BY 1) x;
    SELECT count(*)::int INTO v_pedidos FROM negocio.reclamos
     WHERE origen = 'lote_prueba' AND reclamo_id NOT ILIKE 'PRUEBA%' AND es_pedido_datos_personales;

    SELECT coalesce(jsonb_object_agg(origen || ' / ' || prioridad, n), '{}'::jsonb), coalesce(sum(n), 0)::int INTO v_cola, v_cola_total
      FROM (SELECT origen, prioridad, count(*) AS n FROM control.cola_revision
             WHERE estado = 'pendiente' AND documento_id NOT ILIKE 'PRUEBA%' GROUP BY 1, 2) x;

    SELECT count(*)::int INTO v_aprob_pend FROM control.aprobaciones WHERE decision IS NULL AND objeto NOT ILIKE 'PRUEBA%';
    SELECT count(*)::int INTO v_venc FROM control.auditoria WHERE accion = 'aprobación vencida' AND momento >= v_desde;

    SELECT coalesce(jsonb_object_agg(a, d), '{}'::jsonb) INTO v_act FROM (
        SELECT automatizacion_id AS a, jsonb_build_object('total', count(*),
               'con_error', count(*) FILTER (WHERE estado = 'error'),
               'a_la_cola', count(*) FILTER (WHERE estado = 'derivado_a_cola'),
               'bloqueadas', count(*) FILTER (WHERE estado = 'bloqueado')) AS d
          FROM control.ejecuciones
         WHERE inicio >= v_desde AND coalesce(documento_id, '') NOT ILIKE 'PRUEBA%' GROUP BY automatizacion_id) x;

    -- Cortes reales: se excluyen los de prueba (marca 'prueba' en el detalle) y el único corte de prueba del 08/11/2026,
    -- anterior a esa marca (la hizo la prueba CA_8.6_PRUEBA sobre el flujo 8.7).
    SELECT count(*)::int INTO v_cortes FROM control.auditoria
     WHERE accion IN ('cortacircuitos', 'interruptor general apagado') AND momento >= v_desde
       AND coalesce(detalle->>'prueba', 'false') <> 'true'
       AND NOT (objeto = '8.7 Reporte semanal' AND momento < timestamp '2026-11-09 00:00');

    SELECT coalesce(jsonb_object_agg(tipo, n), '{}'::jsonb), coalesce(sum(n), 0)::int, coalesce(sum(env), 0)::int
      INTO v_alertas, v_alertas_total, v_alertas_env
      FROM (SELECT tipo, count(*) AS n, count(*) FILTER (WHERE enviada) AS env FROM control.alertas
             WHERE momento >= v_desde AND objeto NOT ILIKE 'PRUEBA-%' GROUP BY tipo) x;

    SELECT coalesce(array_agg(flujo ORDER BY flujo), ARRAY[]::text[]) INTO v_apagados FROM control.interruptores WHERE NOT activo;

    v_datos := jsonb_build_object('periodo_desde', v_desde, 'periodo_hasta', v_hasta,
        'facturas', v_fact, 'facturas_total', v_fact_total,
        'reclamos', v_recl, 'reclamos_total', v_recl_total, 'pedidos_datos_personales', v_pedidos,
        'cola_pendiente', v_cola, 'cola_pendiente_total', v_cola_total,
        'aprobaciones_sin_decision', v_aprob_pend, 'aprobaciones_vencidas_periodo', v_venc,
        'actividad', v_act, 'cortes_periodo', v_cortes,
        'alertas_periodo', v_alertas, 'alertas_total', v_alertas_total, 'alertas_enviadas', v_alertas_env,
        'interruptores_apagados', to_jsonb(v_apagados));

    v_texto := 'Reporte semanal. Materiales Cumbre Andina (empresa ficticia, datos sintéticos)' || E'\n'
        || 'Período: ' || v_desde || ' a ' || v_hasta || E'\n\n'
        || 'FACTURAS (estado actual del lote de prueba)' || E'\n' || '- Total: ' || v_fact_total || E'\n';
    FOR r IN SELECT key, value FROM jsonb_each_text(v_fact) ORDER BY key LOOP
        v_texto := v_texto || '- ' || r.key || ': ' || r.value || E'\n';
    END LOOP;
    v_texto := v_texto || E'\n' || 'RECLAMOS (estado actual del lote de prueba)' || E'\n' || '- Total: ' || v_recl_total || E'\n';
    FOR r IN SELECT key, value FROM jsonb_each_text(v_recl) ORDER BY key LOOP
        v_texto := v_texto || '- Respuesta ' || r.key || ': ' || r.value || E'\n';
    END LOOP;
    v_texto := v_texto || '- Pedidos de datos personales derivados al Responsable: ' || v_pedidos || E'\n\n'
        || 'COLA DE REVISION HUMANA (pendiente)' || E'\n' || '- Total: ' || v_cola_total || E'\n';
    FOR r IN SELECT key, value FROM jsonb_each_text(v_cola) ORDER BY key LOOP
        v_texto := v_texto || '- ' || r.key || ': ' || r.value || E'\n';
    END LOOP;
    v_texto := v_texto || '- Aprobaciones sin decisión: ' || v_aprob_pend || E'\n'
        || '- Aprobaciones vencidas procesadas en el período: ' || v_venc || E'\n\n'
        || 'ACTIVIDAD DE LAS AUTOMATIZACIONES (últimos 7 días)' || E'\n';
    IF v_act = '{}'::jsonb THEN v_texto := v_texto || '- Sin ejecuciones en el período' || E'\n'; END IF;
    FOR r IN SELECT key, value FROM jsonb_each(v_act) ORDER BY key LOOP
        v_texto := v_texto || '- ' || r.key || ': ' || (r.value->>'total') || ' ejecuciones, ' || (r.value->>'con_error') || ' con error, '
                 || (r.value->>'a_la_cola') || ' derivadas a la cola, ' || (r.value->>'bloqueadas') || ' bloqueadas' || E'\n';
    END LOOP;
    v_texto := v_texto || E'\n' || 'CONTROL' || E'\n'
        || '- Cortes del monitoreo en el período: ' || v_cortes || E'\n'
        || '- Alertas generadas en el período: ' || v_alertas_total || ' (enviadas por correo: ' || v_alertas_env || ')' || E'\n'
        || '- Interruptores apagados: ' || CASE WHEN cardinality(v_apagados) = 0 THEN 'ninguno' ELSE array_to_string(v_apagados, ', ') END || E'\n\n'
        || 'Este reporte solo contiene conteos. No incluye datos personales.' || E'\n'
        || 'Las ejecuciones de pruebas sin prefijo PRUEBA (por ejemplo las del 8.4a) se cuentan como reales.';

    INSERT INTO control.reportes (periodo_desde, periodo_hasta, es_prueba, datos, texto)
    VALUES (v_desde, v_hasta, p_prueba, v_datos, v_texto) RETURNING reporte_id INTO v_id;

    INSERT INTO control.auditoria (actor, accion, objeto, detalle)
    VALUES ('A12', 'reporte generado', 'control.reportes ' || v_id, jsonb_build_object('prueba', p_prueba, 'periodo_hasta', v_hasta));
    RETURN v_id;
END $$;

REVOKE ALL ON FUNCTION control.generar_reporte_semanal(boolean, timestamp) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION control.generar_reporte_semanal(boolean, timestamp) TO rol_monitoreo;
GRANT SELECT ON control.reportes TO rol_monitoreo;
GRANT UPDATE (enviado, enviado_momento) ON control.reportes TO rol_monitoreo;
