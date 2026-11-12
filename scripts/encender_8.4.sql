-- Fase 8.4: enciende el interruptor GENERAL y el de 8.4 Facturas para correr el orquestador con el lote de prueba.
-- El cambio queda en la auditoría con su motivo. Para apagar: mismo UPDATE con activo = false.
BEGIN;
UPDATE control.interruptores
SET activo = true, cambiado = now(), cambiado_por = 'Jorge (Analista de Procesos)',
    motivo = 'Prueba del orquestador 8.4 con el lote de octubre 2026; 8.4a a 8.4d probados (PRUEBA 7, 11, 6 y 4 de 4 PASA)'
WHERE flujo IN ('GENERAL', '8.4 Facturas');
INSERT INTO control.auditoria (actor, accion, objeto, detalle, motivo)
VALUES ('Jorge (Analista de Procesos)', 'interruptor encendido', 'GENERAL y 8.4 Facturas',
        jsonb_build_object('flujos', ARRAY['GENERAL', '8.4 Facturas'], 'activo', true),
        'Prueba del orquestador 8.4 con el lote de octubre 2026');
SELECT flujo, activo, cambiado_por FROM control.interruptores ORDER BY flujo;
COMMIT;
