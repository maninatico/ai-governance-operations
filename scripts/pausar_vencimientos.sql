-- Pausa el procesamiento de aprobaciones vencidas (interruptor "Vencimiento de aprobaciones").
-- Lo pendiente sigue pendiente: pausar NO aprueba nada. Se usa para conservar el estado de las aprobaciones
-- hasta terminar las mediciones de la Fase 10. Se reanuda con scripts/reanudar_vencimientos.sql.
UPDATE control.interruptores
   SET activo = false, cambiado = now(), cambiado_por = 'Jorge (Analista de Procesos)',
       motivo = 'Pausado hasta terminar las mediciones de la Fase 10: 137 aprobaciones de pago vencen el 09/11 y 95 respuestas el 11/11'
 WHERE flujo = 'Vencimiento de aprobaciones';

INSERT INTO control.auditoria (actor, accion, objeto, detalle, motivo)
VALUES ('Jorge (Analista de Procesos)', 'interruptor apagado', 'control.interruptores: Vencimiento de aprobaciones',
        jsonb_build_object('flujo', 'Vencimiento de aprobaciones', 'activo', false),
        'Pausado hasta terminar las mediciones de la Fase 10');

SELECT flujo, activo, cambiado_por, motivo FROM control.interruptores WHERE flujo = 'Vencimiento de aprobaciones';
