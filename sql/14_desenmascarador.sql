-- =====================================================================
-- 14. Desenmascarador controlado (Fase 8.8b, automatización A13)
-- Toma un borrador de respuesta que una persona YA aprobó (8.3) y cambia los marcadores por
-- los datos reales de la bóveda. Reglas:
--   * Solo el NOMBRE se devuelve. Cualquier otro tipo de marcador (DNI, teléfono, CBU...) no se
--     reemplaza: el caso va a la cola de revisión humana con el motivo.
--   * Solo si el borrador está aprobado. Se comprueba el estado del reclamo Y la última decisión
--     en control.aprobaciones (si no coinciden, frena).
--   * La respuesta final vive en la bóveda (tiene un nombre real); el monitoreo y la cola no la ven.
--   * No envía nada: queda "lista para enviar".
--   * Cada dato devuelto queda en control.reidentificaciones. La auditoría no guarda valores reales.
--   * Repetirlo no duplica nada (una respuesta final por reclamo).
-- Se puede correr más de una vez.
-- =====================================================================

CREATE TABLE IF NOT EXISTS boveda.respuestas_salida (
    reclamo_id       text PRIMARY KEY REFERENCES negocio.reclamos,
    aprobacion_id    bigint NOT NULL REFERENCES control.aprobaciones,
    aprobado_por     text NOT NULL,
    texto_final      text NOT NULL,
    estado           text NOT NULL DEFAULT 'lista_para_enviar' CHECK (estado IN ('lista_para_enviar')),
    generado         timestamp NOT NULL DEFAULT now(),
    CONSTRAINT sin_marcadores CHECK (texto_final !~ '\[[A-Z]+_[0-9]+\]' AND texto_final NOT LIKE '%[LINK_FORMULARIO]%')
);

-- Reclamos con respuesta aprobada que todavía no tienen respuesta final ni un caso de A13 (resuelto o no:
-- la decisión de la persona sobre un caso derivado es final, no se reintenta solo).
-- Sin prefijo ignora los PRUEBA; con prefijo solo mira los de esa corrida.
CREATE OR REPLACE FUNCTION boveda.pendientes_desenmascarar(p_prefijo text DEFAULT '')
RETURNS TABLE (o_reclamo text)
LANGUAGE sql SECURITY DEFINER SET search_path = boveda, negocio, control, pg_temp AS $$
    SELECT r.reclamo_id FROM negocio.reclamos r
     WHERE r.respuesta_estado = 'aprobada' AND r.respuesta_borrador IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM boveda.respuestas_salida s WHERE s.reclamo_id = r.reclamo_id)
       AND NOT EXISTS (SELECT 1 FROM control.cola_revision q WHERE q.documento_id = r.reclamo_id AND q.automatizacion_id = 'A13')
       AND ((p_prefijo = '' AND r.reclamo_id NOT ILIKE 'PRUEBA%') OR (p_prefijo <> '' AND r.reclamo_id LIKE p_prefijo || '%'))
     ORDER BY r.reclamo_id
$$;

CREATE OR REPLACE FUNCTION boveda.desenmascarar_respuesta(p_reclamo text)
RETURNS TABLE (o_resultado text, o_detalle text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = boveda, negocio, control, pg_temp AS $$
DECLARE
    -- Dirección FICTICIA (dominio reservado .example): el formulario real es una mejora pendiente del proyecto.
    c_link constant text := 'https://formulario.cumbreandina.example/datos';
    r record; a record; m record; v_txt text; v_quien text; v_otros text[]; v_marcas text[]; v_sin text[]; v_n int := 0;
BEGIN
    SELECT reclamo_id, respuesta_borrador, respuesta_estado INTO r FROM negocio.reclamos WHERE reclamo_id = p_reclamo FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'El reclamo % no existe', p_reclamo; END IF;
    IF r.respuesta_estado IS DISTINCT FROM 'aprobada' OR coalesce(btrim(r.respuesta_borrador), '') = '' THEN
        RAISE EXCEPTION 'La respuesta del reclamo % no está aprobada', p_reclamo;
    END IF;
    SELECT * INTO a FROM control.aprobaciones WHERE accion = 'enviar_respuesta_cliente' AND objeto = p_reclamo ORDER BY aprobacion_id DESC LIMIT 1;
    IF NOT FOUND OR a.decision IS DISTINCT FROM 'aprobado' THEN
        -- Inconsistencia de integridad: el reclamo dice aprobado pero no hay aprobación que lo respalde. No se devuelve nada; va a una persona.
        INSERT INTO control.cola_revision (origen, automatizacion_id, documento_id, motivo, prioridad)
        SELECT 'reclamos', 'A13', p_reclamo, 'El reclamo figura aprobado pero no hay una aprobación vigente que lo respalde. No se devolvió ningún dato.', 'alta'
         WHERE NOT EXISTS (SELECT 1 FROM control.cola_revision WHERE documento_id = p_reclamo AND automatizacion_id = 'A13' AND estado <> 'resuelto');
        RETURN QUERY SELECT 'derivada'::text, 'Sin aprobación vigente que respalde ' || p_reclamo; RETURN;
    END IF;
    v_quien := coalesce(a.escalado_a, a.aprobador);

    IF EXISTS (SELECT 1 FROM boveda.respuestas_salida WHERE reclamo_id = p_reclamo) THEN
        RETURN QUERY SELECT 'ya_generada'::text, 'El reclamo ' || p_reclamo || ' ya tiene su respuesta final'; RETURN;
    END IF;

    -- marcadores distintos del borrador
    SELECT coalesce(array_agg(DISTINCT x[1]), ARRAY[]::text[]) INTO v_marcas
      FROM regexp_matches(r.respuesta_borrador, '\[[A-Z]+_[0-9]+\]', 'g') AS x;
    -- tipos que no se devuelven
    SELECT coalesce(array_agg(mk ORDER BY mk), ARRAY[]::text[]) INTO v_otros FROM unnest(v_marcas) mk WHERE mk !~ '^\[NOMBRE_[0-9]+\]$';
    IF cardinality(v_otros) > 0 THEN
        INSERT INTO control.cola_revision (origen, automatizacion_id, documento_id, motivo, prioridad)
        SELECT 'reclamos', 'A13', p_reclamo, 'El borrador aprobado usa marcadores que no se devuelven (solo se devuelve el nombre): ' || array_to_string(v_otros, ', '), 'media'
         WHERE NOT EXISTS (SELECT 1 FROM control.cola_revision WHERE documento_id = p_reclamo AND automatizacion_id = 'A13' AND estado <> 'resuelto');
        RETURN QUERY SELECT 'derivada'::text, 'Marcadores no permitidos en ' || p_reclamo || ': ' || array_to_string(v_otros, ', '); RETURN;
    END IF;
    -- marcadores de nombre sin dato en la bóveda
    SELECT coalesce(array_agg(mk ORDER BY mk), ARRAY[]::text[]) INTO v_sin FROM unnest(v_marcas) mk
     WHERE NOT EXISTS (SELECT 1 FROM boveda.marcadores b WHERE b.documento_id = p_reclamo AND b.marcador = mk AND b.tipo = 'NOMBRE');
    IF cardinality(v_sin) > 0 THEN
        INSERT INTO control.cola_revision (origen, automatizacion_id, documento_id, motivo, prioridad)
        SELECT 'reclamos', 'A13', p_reclamo, 'Marcador sin dato en la bóveda: ' || array_to_string(v_sin, ', '), 'media'
         WHERE NOT EXISTS (SELECT 1 FROM control.cola_revision WHERE documento_id = p_reclamo AND automatizacion_id = 'A13' AND estado <> 'resuelto');
        RETURN QUERY SELECT 'derivada'::text, 'Sin dato en la bóveda para ' || p_reclamo || ': ' || array_to_string(v_sin, ', '); RETURN;
    END IF;

    v_txt := replace(r.respuesta_borrador, '[LINK_FORMULARIO]', c_link);
    FOR m IN SELECT b.marcador, b.valor_real FROM boveda.marcadores b WHERE b.documento_id = p_reclamo AND b.marcador = ANY (v_marcas) ORDER BY b.marcador LOOP
        v_txt := replace(v_txt, m.marcador, m.valor_real);
        v_n := v_n + 1;
    END LOOP;
    -- falla segura: si quedó algún marcador (por ejemplo un nombre que parece marcador), no se guarda nada y va a una persona
    IF v_txt ~ '\[[A-Z]+_[0-9]+\]' OR v_txt LIKE '%[LINK_FORMULARIO]%' THEN
        INSERT INTO control.cola_revision (origen, automatizacion_id, documento_id, motivo, prioridad)
        SELECT 'reclamos', 'A13', p_reclamo, 'Tras reemplazar quedaron marcadores sin resolver. No se guardó ninguna respuesta final.', 'alta'
         WHERE NOT EXISTS (SELECT 1 FROM control.cola_revision WHERE documento_id = p_reclamo AND automatizacion_id = 'A13' AND estado <> 'resuelto');
        RETURN QUERY SELECT 'derivada'::text, 'Marcadores sin resolver en ' || p_reclamo; RETURN;
    END IF;

    INSERT INTO boveda.respuestas_salida (reclamo_id, aprobacion_id, aprobado_por, texto_final) VALUES (p_reclamo, a.aprobacion_id, v_quien, v_txt);
    INSERT INTO control.reidentificaciones (solicitante, documento_id, marcador, tipo_uso, motivo, aprobado_por)
    SELECT 'A13', p_reclamo, mk, 'flujo aprobado', 'Respuesta aprobada en la aprobación ' || a.aprobacion_id, v_quien FROM unnest(v_marcas) mk;
    INSERT INTO control.auditoria (actor, accion, objeto, detalle, motivo)
    VALUES ('A13', 'respuesta desenmascarada', 'boveda.respuestas_salida ' || p_reclamo,
            jsonb_build_object('aprobacion_id', a.aprobacion_id, 'marcadores_devueltos', v_n, 'aprobado_por', v_quien),
            'Respuesta aprobada: solo se devuelve el nombre; queda lista para enviar, no se envía');
    RETURN QUERY SELECT 'generada'::text, 'Respuesta final de ' || p_reclamo || ' lista para enviar (' || v_n || ' marcadores devueltos)';
END $$;

REVOKE ALL ON TABLE boveda.respuestas_salida FROM PUBLIC;
REVOKE ALL ON FUNCTION boveda.pendientes_desenmascarar(text), boveda.desenmascarar_respuesta(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION boveda.pendientes_desenmascarar(text), boveda.desenmascarar_respuesta(text) TO rol_boveda;
GRANT SELECT ON boveda.respuestas_salida TO rol_boveda;
