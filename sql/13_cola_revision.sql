-- =====================================================================
-- 13. Cola de revisión humana (Fase 8.8a, automatización A14)
-- La persona elige una decisión de una lista cerrada. El código valida que la decisión
-- corresponda al tipo de caso, hace el cambio y lo deja auditado. Nada se resuelve sin
-- quién decide y un motivo escrito.
-- Las facturas bloqueadas por CBU (A06) NO se resuelven aquí: solo el Gerente de Administración.
-- Se puede correr más de una vez.
-- =====================================================================

-- Tipo de caso a partir del origen, la automatización y el motivo
CREATE OR REPLACE FUNCTION control.clase_caso(p_origen text, p_auto text, p_motivo text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE
        WHEN p_origen = 'seguridad'                                  THEN 'seguridad'
        WHEN p_auto = 'A06'                                          THEN 'cbu'
        WHEN p_auto = 'A05' AND p_motivo ILIKE 'Posible duplicada%'  THEN 'duplicada'
        WHEN p_auto = 'A05'                                          THEN 'no_coincide'
        WHEN p_auto = 'A04'                                          THEN 'tipo_no_reconocido'
        WHEN p_auto = 'A02'                                          THEN 'sin_coincidencia'
        WHEN p_auto = 'A10'                                          THEN 'borrador_descartado'
        WHEN p_auto = 'A13'                                          THEN 'desenmascarador'
        WHEN p_auto = 'A08'                                          THEN 'datos_personales'
        ELSE 'desconocida'
    END
$$;

-- Decisiones permitidas por tipo
CREATE OR REPLACE FUNCTION control.decisiones_caso(p_clase text)
RETURNS text[] LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE p_clase
        WHEN 'duplicada'           THEN ARRAY['Es duplicada', 'No es duplicada']
        WHEN 'no_coincide'         THEN ARRAY['Registrar con dato verificado', 'Dejar en espera']
        WHEN 'tipo_no_reconocido'  THEN ARRAY['Dejar en espera']
        WHEN 'sin_coincidencia'    THEN ARRAY['Asignar cliente', 'Seguir sin identificar']
        WHEN 'borrador_descartado' THEN ARRAY['Pasar a redacción manual']
        WHEN 'desenmascarador'     THEN ARRAY['Pasar a redacción manual']
        WHEN 'datos_personales'    THEN ARRAY['Confirmar derivación al Responsable']
        WHEN 'seguridad'           THEN ARRAY['Ataque confirmado', 'Falsa alarma']
        ELSE ARRAY[]::text[]
    END
$$;

-- Próximo caso para resolver (el más urgente y más antiguo). Excluye los del Gerente (CBU) y los de tipo desconocido (no hay decisión definida: se frenan, no se adivinan).
-- Con p_prefijo solo mira documentos de esa corrida de prueba; sin prefijo, ignora los PRUEBA.
CREATE OR REPLACE FUNCTION control.siguiente_caso(p_prefijo text DEFAULT '')
RETURNS TABLE (o_caso_id bigint, o_origen text, o_automatizacion text, o_documento text, o_motivo text,
               o_prioridad text, o_ingreso timestamp, o_clase text, o_decisiones text, o_contexto text, o_pendientes bigint)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = control, negocio, pg_temp AS $$
DECLARE c record; v_ctx text; v_clase text; v_n bigint;
BEGIN
    SELECT count(*) INTO v_n FROM control.cola_revision q
     WHERE q.estado = 'pendiente' AND control.clase_caso(q.origen, q.automatizacion_id, q.motivo) NOT IN ('cbu', 'desconocida')
       AND ((p_prefijo = '' AND q.documento_id NOT ILIKE 'PRUEBA%') OR (p_prefijo <> '' AND q.documento_id LIKE p_prefijo || '%'));
    SELECT q.* INTO c FROM control.cola_revision q
     WHERE q.estado = 'pendiente' AND control.clase_caso(q.origen, q.automatizacion_id, q.motivo) NOT IN ('cbu', 'desconocida')
       AND ((p_prefijo = '' AND q.documento_id NOT ILIKE 'PRUEBA%') OR (p_prefijo <> '' AND q.documento_id LIKE p_prefijo || '%'))
     ORDER BY CASE q.prioridad WHEN 'alta' THEN 1 WHEN 'media' THEN 2 ELSE 3 END, q.ingreso, q.caso_id LIMIT 1;
    IF NOT FOUND THEN RETURN; END IF;
    v_clase := control.clase_caso(c.origen, c.automatizacion_id, c.motivo);
    SELECT 'Comprobante ' || k.tipo_comprobante || ' ' || k.punto_venta || '-' || k.numero || ', total ' || k.total || ', estado ' || k.estado
           || coalesce(', posible duplicada de ' || k.duplicada_de, '')
      INTO v_ctx FROM negocio.comprobantes k WHERE k.comprobante_id = c.documento_id;
    IF v_ctx IS NULL THEN
        SELECT 'Reclamo (texto enmascarado): ' || left(r.texto_enmascarado, 600) INTO v_ctx FROM negocio.reclamos r WHERE r.reclamo_id = c.documento_id;
    END IF;
    IF v_ctx IS NULL AND v_clase = 'seguridad' THEN
        v_ctx := 'El documento no llegó a registrarse: quedó en cuarentena en la cola. No abrirlo desde acá.';
    END IF;
    RETURN QUERY SELECT c.caso_id, c.origen, c.automatizacion_id, c.documento_id, c.motivo, c.prioridad, c.ingreso,
                        v_clase, array_to_string(control.decisiones_caso(v_clase), ' | '), coalesce(v_ctx, 'Sin más datos'), v_n;
END $$;

-- Resolver un caso. Devuelve una frase con lo que se hizo; si algo no corresponde, frena con error.
CREATE OR REPLACE FUNCTION control.resolver_caso(p_caso bigint, p_decision text, p_quien text, p_motivo text, p_cliente_id text DEFAULT NULL)
RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = control, negocio, pg_temp AS $$
DECLARE c record; v_clase text; v_res text; v_n int;
BEGIN
    IF coalesce(btrim(p_quien), '') = '' THEN RAISE EXCEPTION 'Falta quién decide'; END IF;
    IF length(coalesce(btrim(p_motivo), '')) < 5 THEN RAISE EXCEPTION 'Falta el motivo escrito (mínimo 5 caracteres)'; END IF;
    SELECT * INTO c FROM control.cola_revision WHERE caso_id = p_caso FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'El caso % no existe', p_caso; END IF;
    IF c.estado = 'resuelto' THEN RAISE EXCEPTION 'El caso % ya está resuelto', p_caso; END IF;
    v_clase := control.clase_caso(c.origen, c.automatizacion_id, c.motivo);
    IF v_clase = 'cbu' THEN RAISE EXCEPTION 'Los casos de CBU solo los resuelve el Gerente de Administración'; END IF;
    IF NOT (p_decision = ANY (control.decisiones_caso(v_clase))) THEN
        RAISE EXCEPTION 'La decisión "%" no corresponde a un caso de tipo %', p_decision, v_clase;
    END IF;
    IF p_decision = 'Registrar con dato verificado' AND length(btrim(p_motivo)) < 15 THEN
        RAISE EXCEPTION 'Para registrar con dato verificado hay que escribir qué se verificó y contra qué (mínimo 15 caracteres)';
    END IF;

    IF p_decision = 'Es duplicada' THEN
        UPDATE negocio.comprobantes SET estado = 'Rechazada por duplicada' WHERE comprobante_id = c.documento_id;
        GET DIAGNOSTICS v_n = ROW_COUNT; v_res := 'Factura ' || c.documento_id || ' rechazada por duplicada';
    ELSIF p_decision IN ('No es duplicada', 'Registrar con dato verificado') THEN
        UPDATE negocio.comprobantes SET estado = 'Registrada', fecha_registro = greatest(now(), fecha_recepcion) WHERE comprobante_id = c.documento_id;
        GET DIAGNOSTICS v_n = ROW_COUNT; v_res := 'Factura ' || c.documento_id || ' registrada';
    ELSIF p_decision = 'Dejar en espera' THEN
        UPDATE negocio.comprobantes SET estado = 'En espera' WHERE comprobante_id = c.documento_id;
        GET DIAGNOSTICS v_n = ROW_COUNT; v_res := 'Factura ' || c.documento_id || ' en espera';
    ELSIF p_decision = 'Asignar cliente' THEN
        IF coalesce(btrim(p_cliente_id), '') = '' THEN RAISE EXCEPTION 'Falta el cliente_id a asignar'; END IF;
        IF NOT EXISTS (SELECT 1 FROM negocio.clientes WHERE cliente_id = p_cliente_id) THEN RAISE EXCEPTION 'El cliente % no existe', p_cliente_id; END IF;
        UPDATE negocio.reclamos SET cliente_id = p_cliente_id WHERE reclamo_id = c.documento_id AND cliente_id IS NULL;
        GET DIAGNOSTICS v_n = ROW_COUNT; v_res := 'Reclamo ' || c.documento_id || ' asignado al cliente ' || p_cliente_id;
    ELSIF p_decision = 'Ataque confirmado' THEN
        -- Si el documento llegó a registrarse como factura, se bloquea. Si no (lo frenó el control A04 antes), no hay nada que bloquear.
        UPDATE negocio.comprobantes SET estado = 'Bloqueada' WHERE comprobante_id = c.documento_id;
        GET DIAGNOSTICS v_n = ROW_COUNT;
        IF NOT EXISTS (SELECT 1 FROM control.incidentes WHERE severidad = 'S2' AND resuelto IS NULL
                         AND descripcion LIKE 'Ataque confirmado en el documento ' || c.documento_id || ':%') THEN
            INSERT INTO control.incidentes (severidad, descripcion, automatizacion_id, detectado)
            VALUES ('S2', 'Ataque confirmado en el documento ' || c.documento_id || ': ' || left(c.motivo, 200), c.automatizacion_id, now());
            v_res := 'Ataque confirmado en ' || c.documento_id || ': incidente S2 abierto';
        ELSE
            v_res := 'Ataque confirmado en ' || c.documento_id || ': ya había un incidente S2 abierto para este documento';
        END IF;
        v_res := v_res || CASE WHEN v_n > 0 THEN '; la factura quedó bloqueada'
                               ELSE '; el documento no llegó a registrarse (quedó en cuarentena), no hay factura que bloquear' END;
        v_n := 1;
    ELSE
        -- Seguir sin identificar, Pasar a redacción manual, Confirmar derivación, Falsa alarma: no cambian datos, solo dejan constancia
        v_n := 1; v_res := p_decision || ' (' || c.documento_id || ')';
    END IF;
    IF v_n = 0 THEN RAISE EXCEPTION 'No se pudo aplicar la decisión: el documento % no está en el estado esperado', c.documento_id; END IF;

    UPDATE control.cola_revision SET estado = 'resuelto', decision = p_decision || ': ' || btrim(p_motivo),
           resuelto_por = btrim(p_quien), resuelto = now(), asignado_a = coalesce(asignado_a, btrim(p_quien))
     WHERE caso_id = p_caso;
    INSERT INTO control.auditoria (actor, accion, objeto, detalle, motivo)
    VALUES ('A14', 'caso resuelto', 'cola ' || p_caso,
            jsonb_build_object('decision', p_decision, 'documento', c.documento_id, 'tipo', v_clase, 'quien', btrim(p_quien)), btrim(p_motivo));
    RETURN v_res;
END $$;

REVOKE ALL ON FUNCTION control.clase_caso(text, text, text), control.decisiones_caso(text),
    control.siguiente_caso(text), control.resolver_caso(bigint, text, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION control.clase_caso(text, text, text), control.decisiones_caso(text),
    control.siguiente_caso(text), control.resolver_caso(bigint, text, text, text, text) TO rol_cola;

-- Mínimo privilegio: desde ahora la cola solo cambia datos a través de control.resolver_caso()
-- (que valida el tipo de caso, exige quién y por qué, y deja auditoría).
-- Antes (Fase 7) rol_cola podía cambiar a mano el estado de una factura o la cola; ya no.
REVOKE UPDATE ON negocio.comprobantes, negocio.reclamos, control.cola_revision FROM rol_cola;
