-- Fase 8.5: enciende el interruptor de 8.5 Reclamos (GENERAL ya está encendido) para correr el orquestador con el lote.
-- El cambio queda en la auditoría con su motivo. Para apagar: mismo UPDATE con activo = false.
BEGIN;
UPDATE control.interruptores
SET activo = true, cambiado = now(), cambiado_por = 'Jorge (Analista de Procesos)',
    motivo = 'Prueba del orquestador 8.5 con el lote de octubre 2026; 8.5a a 8.5c probados (PRUEBA 100 de 100, 10 de 10 y 4 de 4)'
WHERE flujo = '8.5 Reclamos';
INSERT INTO control.auditoria (actor, accion, objeto, detalle, motivo)
VALUES ('Jorge (Analista de Procesos)', 'interruptor encendido', '8.5 Reclamos',
        jsonb_build_object('flujo', '8.5 Reclamos', 'activo', true),
        'Prueba del orquestador 8.5 con el lote de octubre 2026');
SELECT flujo, activo, cambiado_por FROM control.interruptores WHERE flujo IN ('GENERAL', '8.4 Facturas', '8.5 Reclamos') ORDER BY flujo;
COMMIT;
