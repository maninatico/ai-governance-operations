-- =====================================================================
-- Fase 9. Prueba de permisos y reglas de la base (59 casos).
-- Cada usuario de la base intenta lo que NO debe (tiene que ser denegado o rechazado) y lo que SI debe poder.
-- Más las reglas que hace cumplir la propia base (auditoría inmutable, doble control, un CBU vigente, etc.).
-- Todo corre dentro de una transacción que se deshace: no deja ningún dato.
-- Uso, desde la carpeta del proyecto:
--   docker exec -i cumbre_andina_db sh -c 'psql -U "$POSTGRES_USER" -d cumbre_andina -v ON_ERROR_STOP=1' < scripts/pruebas_permisos_y_reglas.sql
-- Resultado esperado: permisos 49 de 49 y reglas 10 de 10. Cualquier FALLA es un permiso de más o una regla que no frena.
-- =====================================================================
BEGIN;
CREATE TEMP TABLE casos (n serial, grupo text, quien text, descripcion text, sentencia text, esperado text);
CREATE TEMP TABLE res (n int, grupo text, quien text, descripcion text, esperado text, obtenido text, ok boolean);
GRANT ALL ON casos, res TO PUBLIC;
GRANT USAGE ON SEQUENCE casos_n_seq TO PUBLIC;

INSERT INTO casos (grupo, quien, descripcion, sentencia, esperado) VALUES
-- n8n_facturas
('permisos','n8n_facturas','no ve el CBU','SELECT cbu FROM boveda.cuentas_bancarias','DENEGADO'),
('permisos','n8n_facturas','no ve datos de clientes de la boveda','SELECT * FROM boveda.clientes_datos','DENEGADO'),
('permisos','n8n_facturas','no ve la tabla de clientes','SELECT * FROM negocio.clientes','DENEGADO'),
('permisos','n8n_facturas','no ve los marcadores','SELECT * FROM boveda.marcadores','DENEGADO'),
('permisos','n8n_facturas','no modifica un CBU','UPDATE boveda.cuentas_bancarias SET cbu = repeat(''0'',22)','DENEGADO'),
('permisos','n8n_facturas','no cambia las politicas','UPDATE control.politicas SET aprobador = ''x''','DENEGADO'),
('permisos','n8n_facturas','no toca los interruptores','UPDATE control.interruptores SET activo = true','DENEGADO'),
('permisos','n8n_facturas','no decide aprobaciones','UPDATE control.aprobaciones SET decision = ''aprobado''','DENEGADO'),
('permisos','n8n_facturas','lee proveedores (lo que necesita)','SELECT count(*) FROM negocio.proveedores','PERMITIDO'),
-- n8n_reclamos
('permisos','n8n_reclamos','no ve facturas','SELECT * FROM negocio.comprobantes','DENEGADO'),
('permisos','n8n_reclamos','no entra a los marcadores','SELECT * FROM boveda.marcadores','DENEGADO'),
('permisos','n8n_reclamos','no ve el CBU','SELECT cbu FROM boveda.cuentas_bancarias','DENEGADO'),
('permisos','n8n_reclamos','no toca los interruptores','UPDATE control.interruptores SET activo = true','DENEGADO'),
('permisos','n8n_reclamos','no decide aprobaciones','UPDATE control.aprobaciones SET decision = ''aprobado''','DENEGADO'),
('permisos','n8n_reclamos','lee reclamos (lo que necesita)','SELECT count(*) FROM negocio.reclamos','PERMITIDO'),
-- n8n_boveda
('permisos','n8n_boveda','no ve el CBU','SELECT cbu FROM boveda.cuentas_bancarias','DENEGADO'),
('permisos','n8n_boveda','no decide aprobaciones','UPDATE control.aprobaciones SET decision = ''aprobado''','DENEGADO'),
('permisos','n8n_boveda','no cambia el estado de facturas','UPDATE negocio.comprobantes SET estado = ''Pagada''','DENEGADO'),
('permisos','n8n_boveda','lee marcadores (lo que necesita)','SELECT count(*) FROM boveda.marcadores','PERMITIDO'),
-- n8n_cola
('permisos','n8n_cola','no marca una factura como pagada a mano','UPDATE negocio.comprobantes SET estado = ''Pagada''','DENEGADO'),
('permisos','n8n_cola','no cambia reclamos a mano','UPDATE negocio.reclamos SET respuesta_estado = ''aprobada''','DENEGADO'),
('permisos','n8n_cola','no cierra casos a mano','UPDATE control.cola_revision SET estado = ''resuelto''','DENEGADO'),
('permisos','n8n_cola','no ve marcadores','SELECT * FROM boveda.marcadores','DENEGADO'),
('permisos','n8n_cola','no ve el CBU','SELECT cbu FROM boveda.cuentas_bancarias','DENEGADO'),
('permisos','n8n_cola','no decide aprobaciones','UPDATE control.aprobaciones SET decision = ''aprobado''','DENEGADO'),
('permisos','n8n_cola','usa la funcion de la cola (lo que necesita)','SELECT count(*) FROM control.siguiente_caso()','PERMITIDO'),
-- n8n_monitoreo
('permisos','n8n_monitoreo','no borra la auditoria','DELETE FROM control.auditoria','DENEGADO'),
('permisos','n8n_monitoreo','no ve marcadores','SELECT * FROM boveda.marcadores','DENEGADO'),
('permisos','n8n_monitoreo','no ve el CBU','SELECT cbu FROM boveda.cuentas_bancarias','DENEGADO'),
('permisos','n8n_monitoreo','no decide aprobaciones','UPDATE control.aprobaciones SET decision = ''aprobado''','DENEGADO'),
('permisos','n8n_monitoreo','no cambia facturas','UPDATE negocio.comprobantes SET estado = ''Pagada''','DENEGADO'),
('permisos','n8n_monitoreo','no edita el texto de las alertas','UPDATE control.alertas SET detalle = ''x''','DENEGADO'),
('permisos','n8n_monitoreo','apaga flujos (lo que necesita)','UPDATE control.interruptores SET activo = activo','PERMITIDO'),
-- powerbi_lector
('permisos','powerbi_lector','no ve facturas','SELECT * FROM negocio.comprobantes','DENEGADO'),
('permisos','powerbi_lector','no ve reclamos','SELECT * FROM negocio.reclamos','DENEGADO'),
('permisos','powerbi_lector','no ve la boveda','SELECT * FROM boveda.marcadores','DENEGADO'),
('permisos','powerbi_lector','no ve el CBU','SELECT cbu FROM boveda.cuentas_bancarias','DENEGADO'),
('permisos','powerbi_lector','no ve la auditoria','SELECT * FROM control.auditoria','DENEGADO'),
('permisos','powerbi_lector','no ve alertas','SELECT * FROM control.alertas','DENEGADO'),
('permisos','powerbi_lector','no escribe nada','UPDATE control.interruptores SET activo = true','DENEGADO'),
('permisos','powerbi_lector','lee las vistas de reportes (lo que necesita)','SELECT count(*) FROM reportes.kpi_facturas_mensual','PERMITIDO'),
-- gerente_adm
('permisos','gerente_adm','no pisa un CBU existente','UPDATE boveda.cuentas_bancarias SET cbu = repeat(''0'',22)','DENEGADO'),
('permisos','gerente_adm','no ve facturas','SELECT * FROM negocio.comprobantes','DENEGADO'),
('permisos','gerente_adm','no decide aprobaciones','UPDATE control.aprobaciones SET decision = ''aprobado''','DENEGADO'),
('permisos','gerente_adm','no carga un segundo CBU vigente (indice unico)','INSERT INTO boveda.cuentas_bancarias (proveedor_id,banco,cbu,vigente_desde,verificado_por,canal_verificacion) SELECT proveedor_id,''B'',repeat(''1'',22),current_date,''x'',''y'' FROM boveda.cuentas_bancarias WHERE vigente_hasta IS NULL LIMIT 1','RECHAZADO'),
('permisos','gerente_adm','cierra el CBU anterior (lo que necesita)','UPDATE boveda.cuentas_bancarias SET vigente_hasta = vigente_desde WHERE cuenta_id = (SELECT min(cuenta_id) FROM boveda.cuentas_bancarias WHERE vigente_hasta IS NULL)','PERMITIDO'),
-- n8n_politicas
('permisos','n8n_politicas','no ve marcadores','SELECT * FROM boveda.marcadores','DENEGADO'),
('permisos','n8n_politicas','no ve el CBU','SELECT cbu FROM boveda.cuentas_bancarias','DENEGADO'),
('permisos','n8n_politicas','no cambia facturas','UPDATE negocio.comprobantes SET estado = ''Pagada''','DENEGADO'),
-- auditoria inmutable, incluso para el administrador
('reglas','postgres','la auditoria no se edita','UPDATE control.auditoria SET detalle = ''{}''::jsonb','RECHAZADO'),
('reglas','postgres','la auditoria no se borra','DELETE FROM control.auditoria','RECHAZADO'),
('reglas','postgres','la auditoria no se vacia','TRUNCATE control.auditoria','RECHAZADO'),
-- reglas de la base
('reglas','postgres','un monotributista (persona humana) no puede tener CUIT en el maestro','UPDATE negocio.proveedores SET cuit = ''20-12345678-9'' WHERE proveedor_id = (SELECT proveedor_id FROM negocio.proveedores WHERE tipo_persona = ''humana'' LIMIT 1)','RECHAZADO'),
('reglas','postgres','sin segundo aprobador no se aprueba un pago con doble control','INSERT INTO control.aprobaciones (automatizacion_id,objeto,accion,nivel,aprobador,vence,decision,decidido) VALUES (''A07'',''PRUEBA-REGLA'',''aprobar_pago'',''L3 + doble control'',''Gerente de Administración'',now()+interval ''1 day'',''aprobado'',now())','RECHAZADO'),
('reglas','postgres','la re-identificacion manual exige aprobador','INSERT INTO control.reidentificaciones (solicitante,documento_id,marcador,tipo_uso,motivo) VALUES (''x'',''PRUEBA-REGLA'',''[NOMBRE_1]'',''consulta manual'',''motivo'')','RECHAZADO'),
('reglas','postgres','un solo CBU vigente por proveedor','INSERT INTO boveda.cuentas_bancarias (proveedor_id,banco,cbu,vigente_desde,verificado_por,canal_verificacion) SELECT proveedor_id,''B'',repeat(''1'',22),current_date,''x'',''y'' FROM boveda.cuentas_bancarias WHERE vigente_hasta IS NULL LIMIT 1','RECHAZADO'),
('reglas','postgres','un caso de la cola no se cierra sin decision y responsable','UPDATE control.cola_revision SET estado = ''resuelto'' WHERE caso_id = (SELECT max(caso_id) FROM control.cola_revision WHERE estado <> ''resuelto'')','RECHAZADO'),
('reglas','postgres','toda aprobacion tiene vencimiento','INSERT INTO control.aprobaciones (automatizacion_id,objeto,accion,nivel,aprobador) VALUES (''A07'',''PRUEBA-REGLA'',''aprobar_pago'',''L3'',''Gerente de Administración'')','RECHAZADO'),
('reglas','postgres','una decision sin fecha de decision no se acepta','INSERT INTO control.aprobaciones (automatizacion_id,objeto,accion,nivel,aprobador,vence,decision) VALUES (''A07'',''PRUEBA-REGLA'',''aprobar_pago'',''L3'',''Gerente de Administración'',now()+interval ''1 day'',''aprobado'')','RECHAZADO');

DO $$
DECLARE c record; r text; e text; st text;
BEGIN
  FOR c IN SELECT * FROM casos ORDER BY n LOOP
    r := NULL;
    BEGIN
      IF c.quien <> 'postgres' THEN EXECUTE format('SET LOCAL ROLE %I', c.quien); END IF;
      EXECUTE c.sentencia;
      r := 'PERMITIDO';
    EXCEPTION WHEN insufficient_privilege THEN r := 'DENEGADO';
              WHEN OTHERS THEN r := 'RECHAZADO'; e := SQLERRM;
    END;
    RESET ROLE;
    INSERT INTO res VALUES (c.n, c.grupo, c.quien, c.descripcion, c.esperado, r, r = c.esperado);
  END LOOP;
END $$;
SELECT n, grupo, quien, descripcion, esperado, obtenido, CASE WHEN ok THEN 'PASA' ELSE 'FALLA' END AS resultado FROM res ORDER BY n;
SELECT grupo, count(*) FILTER (WHERE ok) AS pasan, count(*) AS total FROM res GROUP BY grupo ORDER BY grupo;
ROLLBACK;
