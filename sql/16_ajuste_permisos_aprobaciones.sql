-- =====================================================================
-- 16. Ajuste de permisos (hallado en la Fase 9, prueba de permisos)
-- Desde la Fase 7, el usuario de los flujos de facturas (rol_flujo_facturas) podía escribir directo en
-- control.aprobaciones, incluida la columna decision. Es decir, podía "aprobar" un pago sin pasar por la
-- persona. Ningún flujo lo necesita: las aprobaciones se piden con control.pedir_aprobacion() y se deciden con
-- control.registrar_decision(), ambas con SECURITY DEFINER. Queda solo la lectura (el orquestador consulta
-- las decisiones).
-- Se puede correr más de una vez.
-- =====================================================================
REVOKE INSERT, UPDATE ON control.aprobaciones FROM rol_flujo_facturas;
