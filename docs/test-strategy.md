# Estrategia de pruebas y trazabilidad

## Objetivo y priorización

Evitar sobreventa, validaciones sin cupo, devoluciones duplicadas y pérdida de operaciones del conductor al recuperar conexión. Primero se automatizan reglas de mayor impacto y sus invariantes en API/SQL; los E2E prueban que el usuario puede completar los flujos y comprender los errores.

Estas son reglas ficticias del laboratorio, no una descripción de políticas reales de una empresa.

## Criterios de aceptación

| ID | Regla |
|---|---|
| AC-01 | Una compra asigna un asiento libre del viaje a un usuario conocido y registra 5000 CLP simulados. Solo una reserva activa por usuario/viaje. |
| AC-02 | El mismo `request_id` y contenido reintentan una compra sin duplicarla; contenido diferente con la misma clave se rechaza. |
| AC-03 | El propietario puede cambiar a un asiento libre mientras la reserva está confirmada y el viaje no ha salido. |
| AC-04 | Cancelar una reserva confirmada antes de la salida libera el asiento y genera un solo reembolso completo. Repetir la cancelación devuelve ese mismo reembolso. |
| AC-05 | Un usuario con reserva activa puede abordar aun cuando no queden asientos libres. Revalidarlo se rechaza. |
| AC-06 | Sin reserva, puede abordar como walk-in solo si queda asiento. Sin reserva y sin cupos debe rechazarse sin modificar reservas. |
| AC-07 | La salida requiere al menos un pasajero abordado. No puede repetirse ni permite nuevos abordajes/compras después de iniciarse. |
| AC-08 | Offline se opera sobre un manifiesto descargado; validación/salida son provisionales y se guardan con ID único hasta confirmación. |
| AC-09 | La sincronización procesa el orden recibido, aplica reglas vigentes del servidor y persiste la respuesta de cada evento para reintentos. |
| AC-10 | El mismo ID con otro contenido es conflicto. Los rechazos de negocio son terminales para ese ID y no se convierten silenciosamente en éxitos posteriores. |
| AC-11 | Un sobre inválido rechaza todo el lote; con sobre válido los errores de negocio se reportan por evento y los demás pueden procesarse. |
| AC-12 | Los pasajeros no pueden operar endpoints de conductor ni editar/cancelar reservas ajenas. |

Walk-ins asignan asiento con monto cero en esta demo. Su cobro y autorización comercial necesitan definición propia y están fuera del alcance. Una reserva cancelada ya no concede derecho a abordar; el usuario se trata como walk-in y vuelve a evaluarse la capacidad.

## Matriz de automatización

| Casos | Riesgo / resultado esperado | Criterios | Capa |
|---|---|---|---|
| RES-001 | Compra, tarifa y asiento persistidos; respuesta conforme al contrato | 01 | API + contrato + SQL |
| RES-002, 003 | Asiento ocupado, 0, -1, fuera de capacidad, decimal, booleano, texto y null no generan compra | 01 | API + SQL |
| RES-004, 005, 006 | Reintentos, claves conflictivas y doble reserva del mismo usuario | 01, 02 | API + SQL |
| RES-007, 008 | Edición libera asiento anterior o rechaza asiento ocupado sin alterar el original | 03 | API + SQL |
| RES-009 | Cancelación libera asiento y reembolso se registra exactamente una vez | 04 | API + SQL |
| RES-010, 011 | Reserva ajena o abordada no se modifica/cancela | 03, 04, 12 | API + SQL |
| RES-012 | Compra concurrente del mismo asiento: un 201 y un 409 | 01 | HTTP concurrente + SQL |
| RES-013 | Compra después de iniciar viaje rechazada | 07 | API + SQL |
| DRV-001, 002, 003 | Reserva vigente en viaje lleno sí; sin reserva/lleno no; walk-in con cupo sí | 05, 06 | API + SQL |
| DRV-004, 005 | Doble validación y usuario inexistente rechazados | 05, 06 | API + SQL |
| DRV-006 a 009 | Salida con/sin abordados, salida duplicada y abordaje posterior | 07 | API + SQL |
| DRV-010 a 012 | Roles, token ausente y JSON malformado | 12 | API + SQL |
| SYN-001, 002 | Validación/salida ordenadas; replay sin efectos duplicados | 08, 09 | API + SQL |
| SYN-003, 004 | Viaje lleno y manifiesto obsoleto no causan sobreventa | 06, 09 | API + SQL |
| SYN-005 | Mismo event_id con datos distintos produce conflicto | 10 | API + SQL |
| SYN-006, 007 | Sobre inválido no aplica nada; lote válido informa éxitos/rechazos individuales | 11 | API + SQL |
| SYN-008 | Salida antes del abordaje queda rechazada; se necesita nuevo evento para otra intención | 07, 10 | API + SQL |
| SYN-009 | Reserva cancelada no permite abordar un viaje que luego se llena | 04, 06 | API + SQL |
| UI-001, 008 | Compra/edición/reembolso y error de asiento ocupado visibles | 01, 03, 04 | E2E + SQL |
| UI-002, 003 | Regla sin reserva/sin cupos online y offline local | 06, 08 | E2E + SQL |
| UI-004, 005 | Cola sobrevive recarga; sincroniza y muestra conflictos reales | 08, 09 | E2E + SQL |
| UI-006 | Fallo de transporte mantiene la cola para reintento | 08, 09 | E2E + SQL |
| UI-007 | Salida online actualiza servidor e interfaz | 07 | E2E + SQL |

Hay 42 casos de Robot. RES-003 contiene siete filas de datos dentro de un solo caso; el conteo de casos no equivale al número de aserciones o requests.

## Diseño de datos y aislamiento

`demo/data.json` contiene seis IDs ficticios sin datos personales. `T-001` tiene tres asientos, con `U-001` reservado en el asiento 1. `T-FULL` tiene dos asientos reservados por `U-003` y `U-004`. Cada caso recrea la base desde estas fixtures. El navegador es nuevo por caso.

Se usan particiones de equivalencia, valores límite, transiciones de estado, pruebas de permisos y concurrencia. Los oráculos combinan HTTP, contrato, interfaz y SQL; las aserciones de negocio usan valores esperados explícitos y no llaman a la función de producción para calcular el resultado.

## Invariantes y arquitectura

- Asiento único por viaje mientras la reserva no esté cancelada, protegido también por índice parcial UNIQUE.
- Pasajero único por viaje mientras la reserva esté activa.
- `BEGIN IMMEDIATE` serializa lectura/asignación de asientos; el caso concurrente demuestra el conflicto desde HTTP.
- Reembolso único por reserva, protegido por UNIQUE.
- `event_id` único; respuesta y efectos se confirman en la misma transacción antes del ACK HTTP.
- El servidor prevalece ante un manifiesto obsoleto. Una confirmación offline local no garantiza cupo al sincronizar.

## Requerimientos para acordar con Client Manager / Producto

Antes de trasladar esta estrategia a un cliente real habría que acordar:

1. ¿Está permitido subir sin reserva? En esta demo sí, si hay cupo; falta definir cobro y evidencias de autorización.
2. ¿Cuándo vence una reserva? ¿Existe tolerancia de llegada o sobreventa autorizada? Aquí no se modela tiempo ni sobreventa.
3. ¿Cómo se resuelven cupos entre dos conductores/dispositivos offline? Aquí el servidor confirma por orden de sincronización, sin promesa offline de asiento definitivo.
4. ¿Se permite cancelar después de abordar o iniciar viaje? Aquí se rechaza. ¿Hay reembolso parcial, fee o reversa del proveedor de pagos?
5. ¿Qué eventos dependen de otros? Aquí se usa orden de lote y la salida exige abordados; si el abordaje se rechaza y queda la salida sin pasajeros, también se rechaza.
6. ¿Qué IDs, correlación y retención de auditoría necesita soporte? ¿Cómo se deriva un conflicto a operaciones?

## Triaging y validación de entrega

Al fallar un job: descargar artefactos → identificar primer fallo en `log.html` → contrastar HTTP/SQL y screenshot → reproducir con la misma fixture → registrar defecto con pasos y correlación → agregar o ajustar regresión → volver a ejecutar el alcance afectado.

Checklist de entrega:

- [ ] Criterios y restricciones confirmados con Producto/Client Manager.
- [ ] Jobs API/UI y detección de defecto en verde para el commit entregado.
- [ ] Rendimiento ejecutado si cambió la carga o el acceso a datos; umbral acordado para un entorno real.
- [ ] Conflictos offline revisados; no hay aceptación silenciosa de rechazos.
- [ ] Defectos críticos abiertos bloquean la validación de entrega.
- [ ] Evidencias identifican commit, entorno y fecha; adjuntar enlaces al ticket.
- [ ] Aprobación funcional de los flujos críticos y plan de reversa acordados con el equipo.

## Sesión exploratoria complementaria (no automatizada)

Duración sugerida: 30 minutos. Buscar doble clic, navegación atrás, cambio de viaje con cola, almacenamiento local lleno/corrupto, reloj del dispositivo incorrecto, pérdida física de red, cierre de app, múltiples pestañas y mensajes de conflicto en móvil. Registrar observaciones, no presentarlas como pruebas ya ejecutadas. Accesibilidad completa, stress/soak, multi-browser y dispositivos quedan pendientes de un alcance real.
