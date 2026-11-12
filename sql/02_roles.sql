-- =====================================================================
-- Fase 7. Usuarios con permisos mínimos por flujo
-- Ejecutar después de 01_esquema.sql, con el usuario dueño de la base. Se puede volver a correr:
-- los roles son de todo el servidor y solo se crean si no existen.
-- Regla: cada flujo y cada herramienta tiene su usuario y ve solo lo que necesita
-- (matriz de acceso de la Fase 2). Las contraseñas NUNCA van en este script:
-- se definen aparte con  ALTER ROLE <usuario> PASSWORD '...';
-- =====================================================================

-- Nadie tiene acceso por defecto
REVOKE ALL ON SCHEMA boveda, negocio, control, reportes FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA boveda, negocio, control FROM PUBLIC;

-- ---------------------------------------------------------------------
-- Funciones puente: dejan usar un dato de la bóveda sin poder leerla
-- (SECURITY DEFINER: corren con permisos del dueño, devuelven solo lo mínimo)
-- ---------------------------------------------------------------------

-- A06: ¿el CBU coincide con el vigente? Devuelve sí o no, nunca el CBU.
CREATE OR REPLACE FUNCTION boveda.cbu_coincide(p_proveedor text, p_cbu text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = boveda, pg_temp AS $$
    SELECT EXISTS (SELECT 1 FROM boveda.cuentas_bancarias
                   WHERE proveedor_id = p_proveedor AND vigente_hasta IS NULL AND cbu = p_cbu);
$$;

-- A02: ¿qué cliente_id tiene este DNI o teléfono? Devuelve los IDs, nunca los datos.
-- Si devuelve 0 o más de 1, el caso va a la cola de revisión.
CREATE OR REPLACE FUNCTION boveda.buscar_cliente(p_dni text, p_telefono text)
RETURNS SETOF text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = boveda, pg_temp AS $$
    SELECT cliente_id FROM boveda.clientes_datos
    WHERE (p_dni IS NOT NULL AND dni = p_dni) OR (p_telefono IS NOT NULL AND telefono = p_telefono);
$$;

-- A02: ¿qué proveedor_id tiene este CUIT? Busca en empresas y en personas humanas.
CREATE OR REPLACE FUNCTION boveda.buscar_proveedor(p_cuit text)
RETURNS SETOF text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = boveda, negocio, pg_temp AS $$
    SELECT proveedor_id FROM negocio.proveedores WHERE cuit = p_cuit
    UNION
    SELECT proveedor_id FROM boveda.proveedores_personas WHERE cuit = p_cuit;
$$;

REVOKE ALL ON FUNCTION boveda.cbu_coincide(text, text), boveda.buscar_cliente(text, text),
                       boveda.buscar_proveedor(text) FROM PUBLIC;

-- ---------------------------------------------------------------------
-- Roles por función (sin login)
-- ---------------------------------------------------------------------
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rol_flujo_facturas') THEN CREATE ROLE rol_flujo_facturas NOLOGIN; END IF; END $$;   -- A04, A05, A06, A07
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rol_flujo_reclamos') THEN CREATE ROLE rol_flujo_reclamos NOLOGIN; END IF; END $$;   -- A08, A09, A10
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rol_boveda') THEN CREATE ROLE rol_boveda NOLOGIN; END IF; END $$;   -- A02, A13
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rol_cola') THEN CREATE ROLE rol_cola NOLOGIN; END IF; END $$;   -- A14 (formulario de revisión)
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rol_monitoreo') THEN CREATE ROLE rol_monitoreo NOLOGIN; END IF; END $$;   -- A01 (lectura), A11, A12
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rol_powerbi') THEN CREATE ROLE rol_powerbi NOLOGIN; END IF; END $$;   -- tablero
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rol_gerente_cbu') THEN CREATE ROLE rol_gerente_cbu NOLOGIN; END IF; END $$;   -- persona: único que registra un CBU nuevo (L4)

-- Todos los flujos registran su huella (A01) y consultan interruptores
GRANT USAGE ON SCHEMA control TO rol_flujo_facturas, rol_flujo_reclamos, rol_boveda, rol_cola, rol_monitoreo;
GRANT INSERT ON control.ejecuciones, control.auditoria TO rol_flujo_facturas, rol_flujo_reclamos, rol_boveda, rol_cola, rol_monitoreo;
GRANT USAGE ON SEQUENCE control.ejecuciones_ejecucion_id_seq, control.auditoria_auditoria_id_seq
    TO rol_flujo_facturas, rol_flujo_reclamos, rol_boveda, rol_cola, rol_monitoreo;
GRANT SELECT ON control.interruptores, control.automatizaciones TO rol_flujo_facturas, rol_flujo_reclamos, rol_boveda, rol_cola;

-- Facturas
GRANT USAGE ON SCHEMA negocio, boveda TO rol_flujo_facturas;
GRANT SELECT ON negocio.proveedores, negocio.ordenes_compra TO rol_flujo_facturas;
GRANT SELECT, INSERT, UPDATE ON negocio.comprobantes TO rol_flujo_facturas;
GRANT EXECUTE ON FUNCTION boveda.cbu_coincide(text, text) TO rol_flujo_facturas;
GRANT SELECT, INSERT, UPDATE ON control.aprobaciones TO rol_flujo_facturas;
GRANT INSERT ON control.cola_revision TO rol_flujo_facturas;
GRANT USAGE ON SEQUENCE control.aprobaciones_aprobacion_id_seq, control.cola_revision_caso_id_seq TO rol_flujo_facturas;

-- Reclamos (no ve CBU ni comprobantes ni la bóveda)
GRANT USAGE ON SCHEMA negocio TO rol_flujo_reclamos;
GRANT SELECT ON negocio.clientes TO rol_flujo_reclamos;
GRANT SELECT, INSERT, UPDATE ON negocio.reclamos TO rol_flujo_reclamos;
GRANT INSERT ON control.cola_revision TO rol_flujo_reclamos;
GRANT USAGE ON SEQUENCE control.cola_revision_caso_id_seq TO rol_flujo_reclamos;

-- Bóveda: seudonimiza, enmascara y re-identifica. No ve CBU.
GRANT USAGE ON SCHEMA boveda, negocio TO rol_boveda;
GRANT SELECT, INSERT ON boveda.clientes_datos, boveda.marcadores TO rol_boveda;
GRANT SELECT ON boveda.proveedores_personas TO rol_boveda;
GRANT SELECT, INSERT ON negocio.clientes TO rol_boveda;
GRANT EXECUTE ON FUNCTION boveda.buscar_cliente(text, text), boveda.buscar_proveedor(text) TO rol_boveda;
GRANT INSERT ON control.reidentificaciones, control.cola_revision TO rol_boveda;
GRANT USAGE ON SEQUENCE control.reidentificaciones_reidentificacion_id_seq, control.cola_revision_caso_id_seq TO rol_boveda;

-- Cola de revisión: lee y resuelve casos; actualiza el estado del documento
GRANT USAGE ON SCHEMA negocio TO rol_cola;
GRANT SELECT, UPDATE ON control.cola_revision TO rol_cola;
GRANT SELECT, UPDATE (estado, fecha_registro) ON negocio.comprobantes TO rol_cola;
GRANT SELECT, UPDATE (categoria, area_derivada, cliente_id) ON negocio.reclamos TO rol_cola;

-- Monitoreo y reporte: lee el control, maneja interruptores e incidentes
GRANT USAGE ON SCHEMA reportes TO rol_monitoreo;
GRANT SELECT ON ALL TABLES IN SCHEMA control TO rol_monitoreo;
GRANT UPDATE ON control.interruptores TO rol_monitoreo;
GRANT INSERT, UPDATE ON control.incidentes TO rol_monitoreo;
GRANT USAGE ON SEQUENCE control.incidentes_incidente_id_seq TO rol_monitoreo;

-- Power BI: solo las vistas de reportes (datos seudonimizados o agregados)
GRANT USAGE ON SCHEMA reportes TO rol_powerbi, rol_monitoreo;
ALTER DEFAULT PRIVILEGES IN SCHEMA reportes GRANT SELECT ON TABLES TO rol_powerbi, rol_monitoreo;

-- Gerente de Administración: único que registra un CBU nuevo, después de verificar por otro canal
GRANT USAGE ON SCHEMA boveda, control TO rol_gerente_cbu;
GRANT SELECT, INSERT ON boveda.cuentas_bancarias TO rol_gerente_cbu;
GRANT UPDATE (vigente_hasta) ON boveda.cuentas_bancarias TO rol_gerente_cbu;
GRANT USAGE ON SEQUENCE boveda.cuentas_bancarias_cuenta_id_seq TO rol_gerente_cbu;
GRANT INSERT ON control.auditoria TO rol_gerente_cbu;
GRANT USAGE ON SEQUENCE control.auditoria_auditoria_id_seq TO rol_gerente_cbu;

-- ---------------------------------------------------------------------
-- Usuarios con login (uno por credencial de n8n o herramienta)
-- ---------------------------------------------------------------------
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'n8n_facturas') THEN CREATE ROLE n8n_facturas LOGIN; END IF; END $$;
GRANT rol_flujo_facturas TO n8n_facturas;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'n8n_reclamos') THEN CREATE ROLE n8n_reclamos LOGIN; END IF; END $$;
GRANT rol_flujo_reclamos TO n8n_reclamos;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'n8n_boveda') THEN CREATE ROLE n8n_boveda LOGIN; END IF; END $$;
GRANT rol_boveda TO n8n_boveda;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'n8n_cola') THEN CREATE ROLE n8n_cola LOGIN; END IF; END $$;
GRANT rol_cola TO n8n_cola;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'n8n_monitoreo') THEN CREATE ROLE n8n_monitoreo LOGIN; END IF; END $$;
GRANT rol_monitoreo TO n8n_monitoreo;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'powerbi_lector') THEN CREATE ROLE powerbi_lector LOGIN; END IF; END $$;
GRANT rol_powerbi TO powerbi_lector;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'gerente_adm') THEN CREATE ROLE gerente_adm LOGIN; END IF; END $$;
GRANT rol_gerente_cbu TO gerente_adm;
