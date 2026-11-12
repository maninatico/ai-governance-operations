-- =====================================================================
-- 10. Monitoreo, cortacircuitos y alertas (Fase 8.6, automatización A11)
-- Cada flujo corre con su interruptor. Si un flujo acumula errores seguidos
-- (control.interruptores.limite_errores), el monitoreo lo apaga solo y lo deja
-- escrito. Si dos o más flujos están cortados, apaga el interruptor GENERAL.
-- Las alertas quedan en control.alertas; el 8.8 las enviará por correo.
-- Se puede correr más de una vez.
-- =====================================================================

-- 1. Qué automatizaciones forman cada interruptor
CREATE TABLE IF NOT EXISTS control.mapa_flujos (
    flujo            text PRIMARY KEY REFERENCES control.interruptores,
    automatizaciones text[] NOT NULL
);
INSERT INTO control.mapa_flujos (flujo, automatizaciones) VALUES
    ('8.1 Registro de eventos',               ARRAY['A01']),
    ('8.2 Bóveda y seudonimización',          ARRAY['A02']),
    ('8.3 Motor de políticas y aprobaciones', ARRAY['A03']),
    ('8.4 Facturas',                          ARRAY['A04','A05','A06','A07']),
    ('8.5 Reclamos',                          ARRAY['A08','A09','A10']),
    ('8.7 Reporte semanal',                   ARRAY['A12']),
    ('8.8 Desenmascarador y cola',            ARRAY['A13','A14'])
ON CONFLICT (flujo) DO NOTHING;

INSERT INTO control.interruptores (flujo, activo, cambiado_por, motivo)
VALUES ('Vencimiento de aprobaciones', true, 'carga 8.6', 'El silencio nunca es un sí: las aprobaciones vencidas se escalan o se rechazan')
ON CONFLICT (flujo) DO NOTHING;

-- 2. Alertas: una por hecho, sin repetirse (tipo + objeto único)
CREATE TABLE IF NOT EXISTS control.alertas (
    alerta_id        bigserial PRIMARY KEY,
    momento          timestamp NOT NULL DEFAULT now(),
    tipo             text NOT NULL,
    severidad        text NOT NULL CHECK (severidad IN ('S1', 'S2', 'S3')),
    destinatario     text NOT NULL,
    objeto           text NOT NULL,
    detalle          text NOT NULL,
    enviada          boolean NOT NULL DEFAULT false,
    enviada_momento  timestamp,
    UNIQUE (tipo, objeto)
);

-- 3. Revisión de salud. p_prefijo vacío = operación real (ignora filas de prueba).
--    Con prefijo (PRUEBA-...) solo mira las ejecuciones de esa corrida y no toca GENERAL, CBU ni vencidas.
CREATE OR REPLACE FUNCTION control.revisar_salud(p_prefijo text DEFAULT '')
RETURNS TABLE (o_tipo text, o_objeto text, o_resultado text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = control, pg_temp AS $$
DECLARE f record; c record; r record; n int; k int; v_esc int := 0; v_rej int := 0;
BEGIN
    -- a) cortacircuitos por flujo (solo los encendidos)
    FOR f IN SELECT i.flujo, i.limite_errores, i.cambiado, i.errores_seguidos AS previos, m.automatizaciones
             FROM control.interruptores i JOIN control.mapa_flujos m ON m.flujo = i.flujo
             WHERE i.activo AND i.flujo <> 'GENERAL' LOOP
        SELECT count(*) INTO n FROM (
            SELECT bool_and(e.estado = 'error') OVER (ORDER BY e.inicio DESC, e.ejecucion_id DESC) AS seguido
            FROM control.ejecuciones e
            WHERE e.automatizacion_id = ANY (f.automatizaciones) AND e.inicio > f.cambiado
              AND ((p_prefijo = '' AND coalesce(e.documento_id, '') NOT LIKE 'PRUEBA%')
                OR (p_prefijo <> '' AND e.documento_id LIKE p_prefijo || '%'))) x
        WHERE x.seguido;
        IF n <> f.previos THEN
            UPDATE control.interruptores SET errores_seguidos = n WHERE interruptores.flujo = f.flujo;
        END IF;
        IF n >= f.limite_errores THEN
            UPDATE control.interruptores SET activo = false, cambiado = now(),
                   cambiado_por = 'Monitoreo (cortacircuitos)',
                   motivo = 'Cortacircuitos: ' || n || ' errores seguidos'
            WHERE interruptores.flujo = f.flujo;
            INSERT INTO control.auditoria (actor, accion, objeto, detalle, motivo)
            VALUES ('A11', 'cortacircuitos', f.flujo, jsonb_build_object('errores_seguidos', n, 'limite', f.limite_errores, 'prueba', p_prefijo <> ''),
                    'Flujo apagado automáticamente por errores seguidos');
            INSERT INTO control.incidentes (severidad, descripcion, automatizacion_id, detectado)
            VALUES ('S2', CASE WHEN p_prefijo <> '' THEN '[PRUEBA] ' ELSE '' END || 'Cortacircuitos: se apagó "' || f.flujo || '" tras ' || n || ' errores seguidos', f.automatizaciones[1], now());
            INSERT INTO control.alertas (tipo, severidad, destinatario, objeto, detalle, enviada, enviada_momento)   -- las de prueba nacen enviadas: nadie las recibe
            VALUES ('cortacircuitos', 'S2', 'Responsable de Sistemas', p_prefijo || f.flujo || ' @ ' || to_char(now(), 'YYYY-MM-DD HH24:MI:SS'),
                    CASE WHEN p_prefijo <> '' THEN '[PRUEBA] ' ELSE '' END || 'El flujo "' || f.flujo || '" se apagó solo tras ' || n || ' errores seguidos. Revisar la causa antes de encenderlo.',
                    p_prefijo <> '', CASE WHEN p_prefijo <> '' THEN now() END);
            RETURN QUERY SELECT 'cortacircuitos'::text, f.flujo, 'apagado tras ' || n || ' errores seguidos';
        END IF;
    END LOOP;

    IF p_prefijo <> '' THEN RETURN; END IF;

    -- b) dos o más flujos cortados: se apaga el interruptor general
    SELECT count(*) INTO k FROM control.interruptores
     WHERE flujo <> 'GENERAL' AND NOT activo AND motivo LIKE 'Cortacircuitos%';
    IF k >= 2 AND EXISTS (SELECT 1 FROM control.interruptores WHERE flujo = 'GENERAL' AND activo) THEN
        UPDATE control.interruptores SET activo = false, cambiado = now(), cambiado_por = 'Monitoreo (cortacircuitos)',
               motivo = 'Cortacircuitos: ' || k || ' flujos cortados'
        WHERE flujo = 'GENERAL';
        INSERT INTO control.auditoria (actor, accion, objeto, detalle, motivo)
        VALUES ('A11', 'interruptor general apagado', 'GENERAL', jsonb_build_object('flujos_cortados', k),
                'Dos o más flujos cortados por errores seguidos');
        INSERT INTO control.incidentes (severidad, descripcion, detectado)
        VALUES ('S1', 'Se apagó el interruptor GENERAL: ' || k || ' flujos cortados por errores seguidos', now());
        INSERT INTO control.alertas (tipo, severidad, destinatario, objeto, detalle)
        VALUES ('interruptor_general', 'S1', 'Responsable de Sistemas', 'GENERAL @ ' || to_char(now(), 'YYYY-MM-DD HH24:MI:SS'),
                'Se apagó todo el sistema: ' || k || ' flujos cortados por errores seguidos.');
        RETURN QUERY SELECT 'interruptor general'::text, 'GENERAL'::text, 'apagado: ' || k || ' flujos cortados';
    END IF;

    -- c) facturas bloqueadas por cambio de CBU, pendientes en la cola: aviso al Gerente
    FOR c IN SELECT caso_id, documento_id FROM control.cola_revision
             WHERE automatizacion_id = 'A06' AND estado = 'pendiente' AND documento_id NOT LIKE 'PRUEBA%' ORDER BY caso_id LOOP
        INSERT INTO control.alertas (tipo, severidad, destinatario, objeto, detalle)
        VALUES ('cbu_bloqueado', 'S2', 'Gerente de Administración', 'caso ' || c.caso_id,
                'La factura ' || c.documento_id || ' quedó bloqueada por una diferencia o pedido de cambio de CBU. Verificar con el proveedor por un canal conocido.')
        ON CONFLICT (tipo, objeto) DO NOTHING;
        IF FOUND THEN RETURN QUERY SELECT 'alerta CBU'::text, c.documento_id, 'aviso al Gerente de Administración'; END IF;
    END LOOP;

    -- d) aprobaciones vencidas: el silencio nunca es un sí (se escala o se rechaza). Un solo aviso por pasada.
    --    Tiene su propio interruptor ('Vencimiento de aprobaciones') para poder pausarlo, por ejemplo durante una demo.
    IF EXISTS (SELECT 1 FROM control.interruptores WHERE flujo = 'Vencimiento de aprobaciones' AND activo) THEN
        FOR r IN SELECT * FROM control.procesar_vencidas() LOOP
            IF r.resultado LIKE 'escalada%' THEN v_esc := v_esc + 1; ELSE v_rej := v_rej + 1; END IF;
            RETURN QUERY SELECT 'aprobación vencida'::text, r.aprobacion_id::text, r.resultado;
        END LOOP;
        IF v_esc + v_rej > 0 THEN
            INSERT INTO control.alertas (tipo, severidad, destinatario, objeto, detalle)
            VALUES ('aprobaciones_vencidas', 'S3', 'Gerente de Administración', 'lote ' || to_char(now(), 'YYYY-MM-DD HH24:MI:SS'),
                    (v_esc + v_rej) || ' aprobaciones vencieron sin respuesta: ' || v_esc || ' escaladas y ' || v_rej ||
                    ' rechazadas por falta de respuesta. El silencio nunca es un sí: lo que no se aprueba no avanza.')
            ON CONFLICT (tipo, objeto) DO NOTHING;
        END IF;
    END IF;
END $$;

-- 4. Permisos: solo el monitoreo ejecuta y lee
REVOKE ALL ON FUNCTION control.revisar_salud(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION control.revisar_salud(text) TO rol_monitoreo;
GRANT SELECT ON control.mapa_flujos, control.alertas TO rol_monitoreo;
GRANT SELECT ON control.mapa_flujos TO rol_monitoreo;
