-- Fase 8.8b. Prepara los datos de CA_8.8b_PRUEBA. Cada corrida crea 8 reclamos de prueba con un prefijo nuevo (PRUEBA-8B-<fecha y hora>-).
-- Los datos de prueba nunca se ven en la operacion real (llevan el prefijo PRUEBA). No toca ningun dato real.
-- Uso, en la carpeta del proyecto:
--   docker exec -i cumbre_andina_db sh -c 'psql -U "$POSTGRES_USER" -d cumbre_andina -v ON_ERROR_STOP=1 -v p="PRUEBA-8B-$(date +%Y%m%d%H%M%S)-"' < scripts/preparar_prueba_8.8b.sql
-- Casos: R1 feliz (nombre y link), R2 sin marcadores, R3 sin aprobar, R4 aprobada en el reclamo pero rechazada en aprobaciones,
--        R5 con marcador de DNI, R6 nombre sin dato en la boveda, R7 nombre que parece marcador, R8 sin aprobacion.
SELECT set_config('prueba.p', :'p', false);
DO $$
DECLARE p text := current_setting('prueba.p'); k text;
BEGIN
  IF p NOT LIKE 'PRUEBA-8B-%-' THEN RAISE EXCEPTION 'Prefijo invalido: %', p; END IF;
  FOR k IN SELECT unnest(ARRAY['R1','R2','R3','R4','R5','R6','R7','R8']) LOOP
    INSERT INTO negocio.reclamos SELECT (jsonb_populate_record(NULL::negocio.reclamos, to_jsonb(c) || jsonb_build_object('reclamo_id', p||k, 'cliente_id', NULL, 'respuesta_estado', 'aprobada'))).*
      FROM negocio.reclamos c WHERE origen = 'lote_prueba' AND reclamo_id NOT ILIKE 'PRUEBA%' LIMIT 1;
  END LOOP;
  UPDATE negocio.reclamos SET respuesta_borrador = 'Hola [NOMBRE_1], recibimos tu reclamo. Completá tus datos acá: [LINK_FORMULARIO]. Saludos. [NOMBRE_1]' WHERE reclamo_id = p||'R1';
  UPDATE negocio.reclamos SET respuesta_borrador = 'Hola, recibimos tu reclamo. Completá tus datos acá: [LINK_FORMULARIO].' WHERE reclamo_id = p||'R2';
  UPDATE negocio.reclamos SET respuesta_borrador = 'Hola [NOMBRE_1], recibimos tu reclamo.', respuesta_estado = 'pendiente_aprobacion' WHERE reclamo_id = p||'R3';
  UPDATE negocio.reclamos SET respuesta_borrador = 'Hola [NOMBRE_1], recibimos tu reclamo.' WHERE reclamo_id = p||'R4';
  UPDATE negocio.reclamos SET respuesta_borrador = 'Hola [NOMBRE_1], tu DNI [DNI_1] figura en el reclamo.' WHERE reclamo_id = p||'R5';
  UPDATE negocio.reclamos SET respuesta_borrador = 'Hola [NOMBRE_9], recibimos tu reclamo.' WHERE reclamo_id = p||'R6';
  UPDATE negocio.reclamos SET respuesta_borrador = 'Hola [NOMBRE_1], recibimos tu reclamo.' WHERE reclamo_id = p||'R7';
  UPDATE negocio.reclamos SET respuesta_borrador = 'Hola [NOMBRE_1], recibimos tu reclamo.' WHERE reclamo_id = p||'R8';
  FOR k IN SELECT unnest(ARRAY['R1','R2','R3','R4','R5','R6','R7']) LOOP
    INSERT INTO control.aprobaciones (automatizacion_id, objeto, accion, nivel, aprobador, vence, decision, decidido)
    VALUES ('A10', p||k, 'enviar_respuesta_cliente', 'L3', 'Agente de atención', now() + interval '1 day',
            CASE k WHEN 'R4' THEN 'rechazado' WHEN 'R3' THEN NULL ELSE 'aprobado' END, CASE k WHEN 'R3' THEN NULL ELSE now() END);
  END LOOP;
  INSERT INTO boveda.marcadores (documento_id, marcador, tipo, valor_real) VALUES
    (p||'R1','[NOMBRE_1]','NOMBRE','Ana Gómez'), (p||'R3','[NOMBRE_1]','NOMBRE','Luis Peña'), (p||'R4','[NOMBRE_1]','NOMBRE','Eva Soto'),
    (p||'R5','[NOMBRE_1]','NOMBRE','Pablo Ruiz'), (p||'R5','[DNI_1]','DNI','12345678'), (p||'R7','[NOMBRE_1]','NOMBRE','[DNI_7]'), (p||'R8','[NOMBRE_1]','NOMBRE','Sin Aprobacion');
END $$;
SELECT reclamo_id, respuesta_estado FROM negocio.reclamos WHERE reclamo_id LIKE :'p' || '%' ORDER BY reclamo_id;
