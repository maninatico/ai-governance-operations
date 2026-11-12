-- =====================================================================
-- 11. Envío de alertas por correo (Fase 8.6b)
-- El monitoreo lee las alertas pendientes, las envía y las marca como enviadas.
-- Solo puede marcar enviada y enviada_momento; el resto de la alerta no se edita.
-- Se puede correr más de una vez.
-- =====================================================================
GRANT INSERT ON control.alertas TO rol_monitoreo;                               -- las pruebas siembran alertas
GRANT UPDATE (enviada, enviada_momento) ON control.alertas TO rol_monitoreo;
GRANT USAGE ON SEQUENCE control.alertas_alerta_id_seq TO rol_monitoreo;
