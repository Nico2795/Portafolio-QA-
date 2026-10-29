# Contrato HTTP de la demo

Base local: `http://127.0.0.1:8000`. JSON UTF-8. Los tokens son fixtures públicas, no secretos.

| Actor | Authorization |
|---|---|
| Conductor | `Bearer demo-driver-001` |
| Usuario U-001 | `Bearer demo-rider-U-001` |
| Usuario U-002 | `Bearer demo-rider-U-002` |

El mismo patrón sirve para U-003 a U-006. La identidad del comprador viene del token; no se acepta suplantación mediante un campo de usuario en la compra.

| Método y ruta | Entrada | Éxito |
|---|---|---|
| GET `/health` | Sin autenticación | 200, status ok |
| GET `/api/trips` | Token de demo | 200, lista de manifiestos |
| GET `/api/driver/manifest/T-001` | Conductor | 200, viaje, pasajeros y cupos |
| POST `/api/reservations` | `trip_id`, `seat` entero, `request_id` | 201 creación; 200 replay |
| PATCH `/api/reservations/{id}` | Propietario, `seat` | 200 reserva actualizada |
| POST `/api/reservations/{id}/cancel` | Propietario, `{}` | 200 reembolso simulado |
| POST `/api/driver/validate` | `trip_id`, `user_id` | 200 validado / walk-in |
| POST `/api/driver/depart` | `trip_id` | 200 departure_started |
| POST `/api/driver/sync` | `events`, lista de 1 a 50 elementos | 200 resultados por evento |

Ejemplo de compra:

```json
{"trip_id":"T-001","seat":2,"request_id":"purchase-example-001"}
```

La tarifa se calcula en el servidor. `request_id` debe ser único por intención de compra. Repetirlo con otro viaje, usuario o asiento devuelve 409. En esta demo la comparación de replay usa el asiento actual de la reserva: un reintento de la compra original después de editarla puede producir conflicto; no hay ledger de solicitudes independiente para compras.

Ejemplo de sincronización:

```json
{"events":[
  {"event_id":"evt-001","kind":"validate","trip_id":"T-001","user_id":"U-001"},
  {"event_id":"evt-002","kind":"depart","trip_id":"T-001"}
]}
```

```json
{"results":[
  {"event_id":"evt-001","status":"accepted","code":"validated","reservation_id":"R-001","seat":1,"replayed":false},
  {"event_id":"evt-002","status":"accepted","code":"departure_started","trip_id":"T-001","replayed":false}
]}
```

Un rechazo de negocio dentro de un lote válido mantiene HTTP 200 pero incluye `status: rejected` y un código, como `no_seats`. El cliente debe inspeccionar cada resultado. La respuesta persistida se devuelve con `replayed: true` al repetir el mismo evento. Un evento rechazado no se reevalúa con ese mismo ID cuando cambie la capacidad: una nueva acción necesita un nuevo ID.

Errores fuera del lote: `{"error":"code"}` con 400 JSON malformado, 401 sin token válido, 403 rol/propietario incorrecto, 404 entidad desconocida, 409 conflicto de negocio o 422 entrada inválida. El cuerpo máximo de escritura es 32 KiB. La demo usa un servidor HTTP de desarrollo ligado a loopback.
