-- =====================================================================
-- Fase 8.3. Motor de políticas y aprobaciones (A03)
-- Las reglas viven en una tabla, no en el código de los flujos: cambiar una regla es
-- cambiar un dato, y cada cambio queda en la auditoría.
-- Decisiones posibles: permitir, permitir_con_revision, pedir_aprobacion, bloquear.
-- Falla segura: una acción que no está en la tabla se bloquea.
-- =====================================================================

-- Horas hábiles (lunes a viernes, 8 a 17): suma n horas hábiles a un momento
CREATE OR REPLACE FUNCTION control.sumar_horas_habiles(desde timestamp, horas numeric)
RETURNS timestamp LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE t timestamp := desde; resto numeric := horas * 60; dia_ini timestamp; dia_fin timestamp; disp numeric;
BEGIN
    LOOP
        IF extract(isodow FROM t) >= 6 THEN
            t := date_trunc('day', t) + interval '1 day' + interval '8 hours'; CONTINUE;
        END IF;
        dia_ini := date_trunc('day', t) + interval '8 hours';
        dia_fin := date_trunc('day', t) + interval '17 hours';
        IF t < dia_ini THEN t := dia_ini; END IF;
        IF t >= dia_fin THEN t := date_trunc('day', t) + interval '1 day' + interval '8 hours'; CONTINUE; END IF;
        disp := extract(epoch FROM (dia_fin - t)) / 60;
        IF resto <= disp THEN RETURN t + resto * interval '1 minute'; END IF;
        resto := resto - disp;
        t := date_trunc('day', t) + interval '1 day' + interval '8 hours';
    END LOOP;
END $$;

CREATE TABLE IF NOT EXISTS control.politicas (
    accion             text PRIMARY KEY,
    descripcion        text NOT NULL,
    nivel              text NOT NULL CHECK (nivel IN ('L0', 'L1', 'L2', 'L3', 'L4')),
    decision           text NOT NULL CHECK (decision IN ('permitir', 'permitir_con_revision', 'pedir_aprobacion', 'bloquear')),
    aprobador          text,
    umbral_doble_control numeric(14,2),     -- por encima de este monto, hace falta un segundo aprobador
    segundo_aprobador  text,
    plazo_horas_habiles numeric(5,1),
    escalar_a          text,               -- si vence sin respuesta; NULL = se rechaza por defecto
    si_vence           text NOT NULL DEFAULT 'No se ejecuta',
    version            int NOT NULL DEFAULT 1,
    actualizado        timestamp NOT NULL DEFAULT now(),
    actualizado_por    text NOT NULL DEFAULT current_user,
    CONSTRAINT aprobacion_completa CHECK (decision <> 'pedir_aprobacion' OR (aprobador IS NOT NULL AND plazo_horas_habiles > 0)),
    CONSTRAINT doble_control_completo CHECK (umbral_doble_control IS NULL OR segundo_aprobador IS NOT NULL)
);

-- Reglas iniciales (04_Politicas.md, sección 3, y niveles de la Fase 2)
INSERT INTO control.politicas (accion, descripcion, nivel, decision, aprobador, umbral_doble_control, segundo_aprobador, plazo_horas_habiles, escalar_a, si_vence) VALUES
 ('clasificar_documento',   'Clasificar un correo, comprobante o reclamo', 'L0', 'permitir', NULL, NULL, NULL, NULL, NULL, 'No aplica'),
 ('enmascarar_texto',       'Seudonimizar y enmascarar datos personales', 'L0', 'permitir', NULL, NULL, NULL, NULL, NULL, 'No aplica'),
 ('derivar_reclamo',        'Derivar un reclamo al área según la tabla categoría a área', 'L1', 'permitir', NULL, NULL, NULL, NULL, NULL, 'No aplica'),
 ('registrar_comprobante',  'Registrar en el ERP un comprobante que pasó todos los controles', 'L2', 'permitir_con_revision', NULL, NULL, NULL, NULL, NULL, 'No aplica'),
 ('aprobar_pago',           'Aprobar una factura para pago', 'L3', 'pedir_aprobacion', 'Gerente de Administración', 5000000, 'Socio gerente', 9, 'Socio gerente', 'Se escala; la factura no se aprueba'),
 ('enviar_respuesta_cliente','Enviar a un cliente la respuesta revisada', 'L3', 'pedir_aprobacion', 'Agente de atención', NULL, NULL, 24, 'Jefe de Atención', 'Se escala al Jefe de Atención'),
 ('reidentificar_manual',   'Ver un dato real fuera de un flujo aprobado', 'L3', 'pedir_aprobacion', 'Gerente de Administración', NULL, NULL, 9, NULL, 'No se re-identifica'),
 ('reactivar_flujo',        'Reactivar un flujo apagado por el cortacircuitos', 'L3', 'pedir_aprobacion', 'Responsable de Sistemas', NULL, NULL, 9, NULL, 'Sigue apagado'),
 ('cambiar_cbu',            'Cambiar la cuenta bancaria de un proveedor', 'L4', 'bloquear', 'Gerente de Administración', NULL, NULL, NULL, NULL, 'La automatización solo alerta; el Gerente verifica por otro canal')
ON CONFLICT (accion) DO NOTHING;

-- Cada cambio de una regla queda en la auditoría (versión anterior y nueva)
CREATE OR REPLACE FUNCTION control.auditar_politicas() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = control, pg_temp AS $$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        NEW.version := OLD.version + 1; NEW.actualizado := now(); NEW.actualizado_por := current_user;
    END IF;
    INSERT INTO control.auditoria (actor, accion, objeto, detalle, motivo)
    VALUES (current_user, 'politica ' || lower(TG_OP), 'control.politicas/' || coalesce(NEW.accion, OLD.accion),
            jsonb_build_object('antes', CASE WHEN TG_OP = 'INSERT' THEN NULL ELSE to_jsonb(OLD) END,
                               'despues', CASE WHEN TG_OP = 'DELETE' THEN NULL ELSE to_jsonb(NEW) END), NULL);
    RETURN coalesce(NEW, OLD);
END $$;
DROP TRIGGER IF EXISTS tg_auditar_politicas ON control.politicas;
CREATE TRIGGER tg_auditar_politicas BEFORE INSERT OR UPDATE OR DELETE ON control.politicas
    FOR EACH ROW EXECUTE FUNCTION control.auditar_politicas();

-- Doble control en dos pasos: primero decide el aprobador, después el segundo
ALTER TABLE control.aprobaciones ADD COLUMN IF NOT EXISTS monto numeric(14,2);
ALTER TABLE control.aprobaciones ADD COLUMN IF NOT EXISTS primera_decision text CHECK (primera_decision IN ('aprobado', 'rechazado'));
ALTER TABLE control.aprobaciones ADD COLUMN IF NOT EXISTS primera_decidido timestamp;

-- 1. Evaluar: ¿qué dice la política para esta acción y este monto?
CREATE OR REPLACE FUNCTION control.evaluar_politica(p_accion text, p_monto numeric DEFAULT NULL)
RETURNS TABLE (accion text, decision text, nivel text, aprobador text, segundo_aprobador text,
               doble_control boolean, plazo_horas_habiles numeric, motivo text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = control, pg_temp AS $$
DECLARE p control.politicas;
BEGIN
    SELECT * INTO p FROM control.politicas WHERE politicas.accion = p_accion;
    IF NOT FOUND THEN
        RETURN QUERY SELECT p_accion, 'bloquear'::text, 'L4'::text, NULL::text, NULL::text, false, NULL::numeric,
                            'Falla segura: la acción no está en la tabla de políticas'::text;
        RETURN;
    END IF;
    RETURN QUERY SELECT p.accion, p.decision, p.nivel, p.aprobador,
        CASE WHEN p.umbral_doble_control IS NOT NULL AND coalesce(p_monto, 0) > p.umbral_doble_control THEN p.segundo_aprobador END,
        (p.umbral_doble_control IS NOT NULL AND coalesce(p_monto, 0) > p.umbral_doble_control),
        p.plazo_horas_habiles, p.descripcion;
END $$;

-- 2. Pedir aprobación: crea la solicitud con su vencimiento en horas hábiles
CREATE OR REPLACE FUNCTION control.pedir_aprobacion(p_automatizacion text, p_objeto text, p_accion text,
                                                    p_monto numeric DEFAULT NULL, p_motivo text DEFAULT NULL)
RETURNS TABLE (aprobacion_id bigint, aprobador text, segundo_aprobador text, nivel text, vence timestamp)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = control, pg_temp AS $$
DECLARE e record; v_id bigint; v_vence timestamp;
BEGIN
    SELECT * INTO e FROM control.evaluar_politica(p_accion, p_monto);
    IF e.decision <> 'pedir_aprobacion' THEN
        RAISE EXCEPTION 'La acción % no requiere aprobación (decisión: %)', p_accion, e.decision;
    END IF;
    v_vence := control.sumar_horas_habiles(now()::timestamp, e.plazo_horas_habiles);
    INSERT INTO control.aprobaciones (automatizacion_id, objeto, accion, nivel, aprobador, segundo_aprobador, vence, monto, motivo)
    VALUES (p_automatizacion, p_objeto, p_accion, CASE WHEN e.doble_control THEN 'L3 + doble control' ELSE 'L3' END,
            e.aprobador, e.segundo_aprobador, v_vence, p_monto, p_motivo)
    RETURNING aprobaciones.aprobacion_id INTO v_id;
    INSERT INTO control.auditoria (actor, accion, objeto, detalle)
    VALUES (p_automatizacion, 'aprobación pedida', p_objeto,
            jsonb_build_object('aprobacion_id', v_id, 'accion', p_accion, 'monto', p_monto, 'doble_control', e.doble_control));
    RETURN QUERY SELECT v_id, e.aprobador, e.segundo_aprobador,
                        CASE WHEN e.doble_control THEN 'L3 + doble control' ELSE 'L3' END, v_vence;
END $$;

-- 3. Registrar la decisión de una persona (formulario de n8n). Hace cumplir quién puede decidir.
CREATE OR REPLACE FUNCTION control.registrar_decision(p_aprobacion_id bigint, p_decisor text, p_decision text, p_motivo text)
RETURNS TABLE (aprobacion_id bigint, estado text, mensaje text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = control, pg_temp AS $$
DECLARE a control.aprobaciones; v_estado text;
BEGIN
    IF p_decision NOT IN ('aprobado', 'rechazado') THEN RAISE EXCEPTION 'Decisión inválida: %', p_decision; END IF;
    IF coalesce(trim(p_motivo), '') = '' THEN RAISE EXCEPTION 'Toda decisión necesita un motivo'; END IF;
    SELECT * INTO a FROM control.aprobaciones WHERE aprobaciones.aprobacion_id = p_aprobacion_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Aprobación % inexistente', p_aprobacion_id; END IF;
    IF a.decision IS NOT NULL THEN RAISE EXCEPTION 'La aprobación % ya fue decidida: %', p_aprobacion_id, a.decision; END IF;
    IF now() > a.vence AND a.escalado_a IS NULL THEN RAISE EXCEPTION 'La aprobación % venció sin respuesta', p_aprobacion_id; END IF;

    IF a.nivel = 'L3 + doble control' AND a.primera_decision IS NULL THEN
        -- primer paso: decide el aprobador principal (o a quien se escaló)
        IF p_decisor NOT IN (a.aprobador, coalesce(a.escalado_a, '')) THEN
            RAISE EXCEPTION '% no puede decidir el primer paso de la aprobación %', p_decisor, p_aprobacion_id; END IF;
        IF p_decision = 'rechazado' THEN
            UPDATE control.aprobaciones SET primera_decision = 'rechazado', primera_decidido = now(),
                   decision = 'rechazado', decidido = now(), motivo = p_motivo WHERE aprobaciones.aprobacion_id = p_aprobacion_id;
            v_estado := 'rechazado';
        ELSE
            UPDATE control.aprobaciones SET primera_decision = 'aprobado', primera_decidido = now(), motivo = p_motivo
            WHERE aprobaciones.aprobacion_id = p_aprobacion_id;
            v_estado := 'falta segundo aprobador';
        END IF;
    ELSE
        IF a.nivel = 'L3 + doble control' THEN
            IF p_decisor <> a.segundo_aprobador THEN
                RAISE EXCEPTION 'El segundo paso de la aprobación % lo decide %, no %', p_aprobacion_id, a.segundo_aprobador, p_decisor; END IF;
        ELSIF p_decisor NOT IN (a.aprobador, coalesce(a.escalado_a, '')) THEN
            RAISE EXCEPTION '% no puede decidir la aprobación % (le corresponde a %)', p_decisor, p_aprobacion_id, a.aprobador;
        END IF;
        UPDATE control.aprobaciones SET decision = p_decision, decidido = now(), motivo = p_motivo
        WHERE aprobaciones.aprobacion_id = p_aprobacion_id;
        v_estado := p_decision;
    END IF;
    INSERT INTO control.auditoria (actor, accion, objeto, detalle, motivo)
    VALUES (p_decisor, 'decisión de aprobación', a.objeto,
            jsonb_build_object('aprobacion_id', p_aprobacion_id, 'decision', p_decision, 'estado', v_estado), p_motivo);
    RETURN QUERY SELECT p_aprobacion_id, v_estado,
        CASE v_estado WHEN 'falta segundo aprobador' THEN 'Primer paso aprobado. Falta la decisión de ' || a.segundo_aprobador
                      ELSE 'Decisión registrada: ' || v_estado END;
END $$;

-- 4. Vencidas: el silencio nunca es un sí. Se escala o se rechaza por defecto. Lo llama el monitoreo (8.6).
CREATE OR REPLACE FUNCTION control.procesar_vencidas()
RETURNS TABLE (aprobacion_id bigint, resultado text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = control, pg_temp AS $$
DECLARE a record;
BEGIN
    FOR a IN SELECT ap.*, p.escalar_a AS p_escalar, p.plazo_horas_habiles AS p_plazo, p.si_vence
             FROM control.aprobaciones ap JOIN control.politicas p ON p.accion = ap.accion
             WHERE ap.decision IS NULL AND ap.vence < now() FOR UPDATE OF ap LOOP
        IF a.p_escalar IS NOT NULL AND a.escalado_a IS NULL THEN
            UPDATE control.aprobaciones SET escalado_a = a.p_escalar,
                   vence = control.sumar_horas_habiles(now()::timestamp, a.p_plazo)
            WHERE aprobaciones.aprobacion_id = a.aprobacion_id;
            RETURN QUERY SELECT a.aprobacion_id, 'escalada a ' || a.p_escalar;
        ELSE
            UPDATE control.aprobaciones SET decision = 'rechazado', decidido = now(),
                   motivo = 'Vencida sin respuesta: ' || a.si_vence
            WHERE aprobaciones.aprobacion_id = a.aprobacion_id;
            RETURN QUERY SELECT a.aprobacion_id, 'rechazada por vencimiento';
        END IF;
        INSERT INTO control.auditoria (actor, accion, objeto, detalle)
        VALUES ('motor de políticas', 'aprobación vencida', a.objeto, jsonb_build_object('aprobacion_id', a.aprobacion_id));
    END LOOP;
END $$;

-- Reporte para Power BI
CREATE OR REPLACE VIEW reportes.politicas AS
SELECT accion, descripcion, nivel, decision, aprobador, umbral_doble_control, segundo_aprobador,
       plazo_horas_habiles, escalar_a, si_vence, version, actualizado
FROM control.politicas;

-- Usuario del motor: lee políticas y aprobaciones; todo cambio pasa por las funciones
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rol_politicas') THEN CREATE ROLE rol_politicas NOLOGIN; END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'n8n_politicas') THEN CREATE ROLE n8n_politicas LOGIN; END IF; END $$;
GRANT rol_politicas TO n8n_politicas;
REVOKE ALL ON control.politicas FROM PUBLIC;
REVOKE ALL ON FUNCTION control.evaluar_politica(text, numeric), control.pedir_aprobacion(text, text, text, numeric, text),
                       control.registrar_decision(bigint, text, text, text), control.procesar_vencidas() FROM PUBLIC;
GRANT USAGE ON SCHEMA control TO rol_politicas;
GRANT SELECT ON control.politicas, control.aprobaciones TO rol_politicas;
GRANT EXECUTE ON FUNCTION control.evaluar_politica(text, numeric), control.pedir_aprobacion(text, text, text, numeric, text),
                          control.registrar_decision(bigint, text, text, text), control.procesar_vencidas(),
                          control.sumar_horas_habiles(timestamp, numeric) TO rol_politicas;
GRANT EXECUTE ON FUNCTION control.procesar_vencidas() TO rol_monitoreo;
GRANT SELECT ON control.politicas TO rol_monitoreo;
GRANT SELECT ON reportes.politicas TO rol_powerbi, rol_monitoreo;
