-- Reanuda el procesamiento de aprobaciones vencidas. Ojo: lo que ya esté vencido se procesa en la próxima pasada
-- del monitoreo (cada 10 minutos): se escala o se rechaza, con un solo aviso agrupado.
UPDATE control.interruptores
   SET activo = true, cambiado = now(), cambiado_por = 'Jorge (Analista de Procesos)',
       motivo = 'Reanudado: terminadas las mediciones de la Fase 10'
 WHERE flujo = 'Vencimiento de aprobaciones';

INSERT INTO control.auditoria (actor, accion, objeto, detalle, motivo)
VALUES ('Jorge (Analista de Procesos)', 'interruptor encendido', 'control.interruptores: Vencimiento de aprobaciones',
        jsonb_build_object('flujo', 'Vencimiento de aprobaciones', 'activo', true),
        'Reanudado: terminadas las mediciones de la Fase 10');

SELECT flujo, activo, cambiado_por, motivo FROM control.interruptores WHERE flujo = 'Vencimiento de aprobaciones';
