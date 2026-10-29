# Guía de demostración e entrevista

## Presentación de cinco minutos

1. **Contexto:** explicar que se construyó un entorno ficticio para demostrar QA de transporte sin exponer repositorios o datos de trabajo.
2. **Riesgo central:** mostrar el caso sin reserva/sin cupos. Contrastar con un usuario reservado que sí puede abordar el mismo viaje lleno.
3. **Arquitectura:** pruebas de API para reglas, SQL para persistencia y E2E para interacción. Cada suite levanta su propio servicio/base y cada caso empieza limpio.
4. **Offline:** descargar el manifiesto, activar offline, validar U-001 e iniciar salida. Mostrar dos pendientes, recargar, volver online y sincronizar. El estado SQL cambia solo al confirmar el servidor.
5. **Calidad de entrega:** mostrar reportes de Actions y el defecto controlado. Explicar que una prueba debe detectar errores, además de pasar cuando todo funciona.

## Demostración manual de conflicto offline

Usar una base nueva y la app en dos ventanas (cada una con almacenamiento independiente, por ejemplo normal e incógnito):

1. Ventana A: cargar T-001, pasar offline y validar U-006 sin reserva. Queda pendiente.
2. Ventana B: comprar asiento 2 como U-002; en el conductor validar U-005, que recibe el asiento 3.
3. Ventana A: volver online y sincronizar. Ver `Conflictos: ... no_seats` y el manifiesto reconciliado lleno.

No prometer que el abordaje offline está confirmado: el cupo local puede quedar desactualizado. En producción la política operativa ante este conflicto debe acordarse con negocio y seguridad del transporte.

## Decisiones que conviene poder explicar

- **Robot Framework:** keywords legibles para QA/negocio y reutilización de librerías Python. Selenium cubre web y RequestsLibrary cubre REST.
- **SQLite:** reproduce asignación transaccional y consultas de integridad sin infraestructura externa. No representa el comportamiento/performance de una base distribuida real.
- **IDs idempotentes:** permiten repetir sincronizaciones tras perder el ACK sin repetir efectos. No se usa el reloj del conductor como autoridad.
- **Pruebas negativas:** verifican tanto el rechazo como la ausencia de efectos secundarios.
- **Esperas:** se espera una condición visible; no hay sleeps fijos ni reintentos de pruebas para ocultar inestabilidad.
- **CI/CD:** API/UI separadas para diagnóstico, artefactos incluso ante fallos y ZIP solo si pasan los checks requeridos. No hay despliegue productivo.

## Validación con Client Manager

Presentar las preguntas de `test-strategy.md`, acordar criterios observables y obtener validación funcional de los flujos de mayor riesgo. Comunicar un defecto con impacto, datos mínimos y pasos reproducibles; evitar convertir una regla ambigua de negocio en un bug técnico sin acordarla.

## Texto breve para compartir el proyecto

> Comparto un proyecto demostrativo de QA Automation orientado a transporte. Incluye casos positivos y negativos de reservas, asientos, cancelaciones, reembolsos y operaciones del conductor online/offline, con Robot Framework, Selenium, validaciones de API/SQL y GitHub Actions. El repositorio utiliza exclusivamente datos sintéticos y documenta decisiones, riesgos y evidencias de ejecución.

Este texto describe el contenido del proyecto. Personalizar la explicación según lo que se pueda defender y demostrar; el repo no acredita por sí solo experiencia laboral ni conocimientos que no se hayan revisado.
