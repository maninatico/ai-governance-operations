-- =====================================================================
-- 15. Re-identificación manual (Fase 8.8c, automatización A13)
-- Ver un dato real fuera de un flujo aprobado. Dos pasos separados:
--   1) pedir_consulta_manual: crea la solicitud (política reidentificar_manual, L3, Gerente de Administración).
--      No devuelve ningún dato.
--   2) ver_dato_aprobado: si el Gerente aprobó, entrega el dato UNA sola vez por aprobación, dentro de las 24 horas
--      de la decisión, y solo a quien lo pidió.
-- Reglas:
--   * El motivo escrito tiene mínimo 15 caracteres. Todos los tipos de dato se pueden pedir, siempre con aprobación.
--   * Quien pide no puede ser quien aprueba.
--   * Cada vista queda en control.reidentificaciones ('consulta manual', con aprobador y motivo).
--     La auditoría registra el hecho, nunca el valor real.
-- Se puede correr más de una vez.
-- =====================================================================

ALTER TABLE control.reidentificaciones ADD COLUMN IF NOT EXISTS aprobacion_id bigint REFERENCES control.aprobaciones;
CREATE UNIQUE INDEX IF NOT EXISTS ux_reident_aprobacion ON control.reidentificaciones (aprobacion_id) WHERE tipo_uso = 'consulta manual';

CREATE OR REPLACE FUNCTION boveda.pedir_consulta_manual(p_solicitante text, p_documento text, p_marcador text, p_motivo text)
RETURNS TABLE (o_aprobacion_id bigint, o_mensaje text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = boveda, control, pg_temp AS $$
DECLARE v_tipo text; v_ap record;
BEGIN
    IF coalesce(btrim(p_solicitante), '') = '' THEN RAISE EXCEPTION 'Falta quién pide'; END IF;
    IF char_length(btrim(coalesce(p_motivo, ''))) < 15 THEN
        RAISE EXCEPTION 'Falta el motivo escrito (mínimo 15 caracteres): para qué se necesita ver el dato real';
    END IF;
    SELECT tipo INTO v_tipo FROM boveda.marcadores WHERE documento_id = p_documento AND marcador = p_marcador;
    IF NOT FOUND THEN RAISE EXCEPTION 'No existe el marcador % en el documento %', p_marcador, p_documento; END IF;
    SELECT * INTO v_ap FROM control.pedir_aprobacion('A13', 'REIDENT:' || p_documento || '|' || p_marcador, 'reidentificar_manual', NULL, p_motivo);
    IF p_solicitante IN (v_ap.aprobador, coalesce(v_ap.segundo_aprobador, '')) THEN
        RAISE EXCEPTION 'Quien aprueba no puede pedir su propia consulta';   -- revierte también la solicitud recién creada
    END IF;
    INSERT INTO control.auditoria (actor, accion, objeto, detalle, motivo)
    VALUES (p_solicitante, 'consulta manual pedida', p_documento,
            jsonb_build_object('aprobacion_id', v_ap.aprobacion_id, 'marcador', p_marcador, 'tipo', v_tipo), p_motivo);
    RETURN QUERY SELECT v_ap.aprobacion_id, 'Solicitud ' || v_ap.aprobacion_id || ' creada. La decide ' || v_ap.aprobador || ' antes de ' || v_ap.vence || '. Todavía no se ve ningún dato.';
END $$;

CREATE OR REPLACE FUNCTION boveda.ver_dato_aprobado(p_aprobacion_id bigint, p_solicitante text)
RETURNS TABLE (o_documento text, o_marcador text, o_tipo text, o_valor text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = boveda, control, pg_temp AS $$
DECLARE a record; v_doc text; v_mar text; v_tipo text; v_val text; v_pidio text; v_motivo text; v_quien text;
BEGIN
    SELECT * INTO a FROM control.aprobaciones WHERE aprobacion_id = p_aprobacion_id;
    IF NOT FOUND OR a.accion <> 'reidentificar_manual' THEN RAISE EXCEPTION 'La aprobación % no existe o no es una consulta manual', p_aprobacion_id; END IF;
    SELECT actor, motivo INTO v_pidio, v_motivo FROM control.auditoria
     WHERE accion = 'consulta manual pedida' AND (detalle->>'aprobacion_id')::bigint = p_aprobacion_id ORDER BY auditoria_id LIMIT 1;
    IF v_pidio IS DISTINCT FROM p_solicitante THEN RAISE EXCEPTION 'La consulta % la pidió otra persona', p_aprobacion_id; END IF;
    IF a.decision IS DISTINCT FROM 'aprobado' THEN RAISE EXCEPTION 'La consulta % no está aprobada (estado: %)', p_aprobacion_id, coalesce(a.decision, 'sin decidir'); END IF;
    IF a.decidido < now() - interval '24 hours' THEN RAISE EXCEPTION 'La aprobación % venció: pasaron más de 24 horas desde la decisión', p_aprobacion_id; END IF;
    v_doc := split_part(substr(a.objeto, 9), '|', 1);
    v_mar := split_part(a.objeto, '|', 2);
    SELECT tipo, valor_real INTO v_tipo, v_val FROM boveda.marcadores WHERE documento_id = v_doc AND marcador = v_mar;
    IF NOT FOUND THEN RAISE EXCEPTION 'El marcador % ya no existe en %', v_mar, v_doc; END IF;
    v_quien := coalesce(a.escalado_a, a.aprobador);
    -- una sola vez por aprobación: el índice único frena el segundo intento
    BEGIN
        INSERT INTO control.reidentificaciones (solicitante, documento_id, marcador, tipo_uso, motivo, aprobado_por, aprobacion_id)
        VALUES (p_solicitante, v_doc, v_mar, 'consulta manual', v_motivo, v_quien, p_aprobacion_id);
    EXCEPTION WHEN unique_violation THEN
        RAISE EXCEPTION 'La aprobación % ya se usó: el dato se muestra una sola vez', p_aprobacion_id;
    END;
    INSERT INTO control.auditoria (actor, accion, objeto, detalle, motivo)
    VALUES (p_solicitante, 'consulta manual entregada', v_doc,
            jsonb_build_object('aprobacion_id', p_aprobacion_id, 'marcador', v_mar, 'tipo', v_tipo, 'aprobado_por', v_quien),
            'Dato real entregado una sola vez; el valor no se guarda en la auditoría');
    RETURN QUERY SELECT v_doc, v_mar, v_tipo, v_val;
END $$;

REVOKE ALL ON FUNCTION boveda.pedir_consulta_manual(text, text, text, text), boveda.ver_dato_aprobado(bigint, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION boveda.pedir_consulta_manual(text, text, text, text), boveda.ver_dato_aprobado(bigint, text) TO rol_boveda;
