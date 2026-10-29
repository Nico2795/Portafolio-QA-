# Validación local — 29 de octubre de 2026

Entorno: Windows, Python 3.12.4, Chrome headless. Dependencias instaladas desde `requirements.txt` en un entorno virtual nuevo, sin acceso a paquetes globales.

| Comprobación | Resultado |
|---|---|
| `python scripts/run_tests.py --output results/final` | 42 casos aprobados, 0 fallidos: 34 API/integración + 8 E2E |
| `python scripts/check_detection.py` | Detecta el defecto controlado: DRV-002 falla por HTTP 200 en lugar de 409; el verificador devuelve 0 |
| `python scripts/performance.py` | 100 solicitudes, 4 workers, 0 errores; p95 4,92 ms en esta ejecución local |
| Workflow YAML | Lectura sintáctica y comprobación de eventos/jobs |
| Interfaz | Captura inicial revisada visualmente; los flujos funcionales se verificaron con Selenium |

Los resultados de rendimiento son una muestra local, no un SLA ni un benchmark productivo. Los reportes completos se generan en `results/`, se excluyen de Git y se publican como artefactos cuando corre Actions.

La validación local no acredita una ejecución exitosa en el runner Linux de GitHub. Consultar el historial del workflow para la evidencia de CI del commit publicado. La protección de ramas y la validación funcional con un cliente real requieren configuración/acuerdo específicos.
