# Defecto controlado: validación sin reserva en viaje lleno

**Ejercicio reproducible de diagnóstico. No es un incidente real ni un bug abierto de Allride.**

| Campo | Descripción |
|---|---|
| ID | DEMO-BUG-001 |
| Severidad / prioridad propuestas | Crítica / P1 por permitir un abordaje inválido |
| Regla | AC-06: sin reserva y sin cupos no se debe validar |
| Datos | Viaje T-FULL, capacidad 2, ambos asientos reservados; U-002 sin reserva |
| Capa | API de conductor |
| Esperado | HTTP 409 `no_seats`; cero reservas nuevas y cero pasajeros abordados |
| Defecto inyectado | El endpoint devuelve HTTP 200 `walk_in_validated` para ese usuario/viaje lleno |

## Pasos de reproducción

1. Instalar dependencias y ejecutar `python scripts/check_detection.py`.
2. El script sustituye temporalmente la validación en memoria por una implementación defectuosa para ese escenario.
3. Ejecuta exclusivamente `DRV-002` contra una base de datos nueva.
4. La prueba debe fallar con `Expected status: 200 != 409`.
5. El script comprueba que ese fue el único fallo y la causa esperada; devuelve código 0 solo si lo detectó. La función original se restaura en `finally` y no se modifica ningún archivo de aplicación.

Evidencia: `results/mutation/log.html` y `output.xml`. El reporte Robot de este ejercicio tiene una prueba fallida **intencional**; el check de CI es exitoso cuando detecta exactamente ese fallo. Un error de setup o de conexión no cuenta como detección correcta.

## Aislamiento de causa y corrección esperada

Comparar al pasajero con reserva en el mismo viaje (`DRV-001`, éxito) y sin reserva (`DRV-002`, rechazo). Esto aísla la capacidad aplicable al walk-in, evitando bloquear por error a pasajeros cuyo asiento ya está reservado.

La ruta normal evalúa la reserva activa, luego la capacidad; si no hay asiento devuelve conflicto. El índice único de asientos y la transacción serializada protegen además contra carreras. Para cerrar un defecto real: revisar el diff, ejecutar DRV-001/002/003, SYN-003/004/009 y UI-002/003/005, y adjuntar evidencia del commit corregido al ticket.

La inyección demuestra sensibilidad de un caso crítico; no mide un mutation score general del repositorio.
