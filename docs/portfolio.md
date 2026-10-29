# Portafolio web

Sitio público: https://nicolas-bustamante-qa.quick-okapi-8636.chatgpt.site

La página presenta a Nicolás Bustamante, el proyecto Transit QA Lab, cuatro casos destacados y acceso directo al reporte Robot y al código. Usa únicamente información profesional facilitada para el portafolio y datos sintéticos del laboratorio.

## Construcción local

Desde el entorno Python del proyecto:

```bash
python scripts/run_tests.py --output results/portfolio
python scripts/build_portfolio.py --results results/portfolio
python -m http.server 8765 --bind 127.0.0.1 --directory _site
```

Abrir http://127.0.0.1:8765. El build copia `portfolio/`, la captura `docs/demo.png`, `report.html` y `log.html` a `_site/`, y genera `evidence.json` con el conteo y entorno de ejecución. Rechaza reportes sin casos, con fallos, errores o pruebas omitidas. `_site/` no se versiona.

El explorador de casos es una presentación interactiva de escenarios documentados; no ejecuta el backend de transporte en el navegador. La aplicación completa se ejecuta localmente siguiendo el README.

## Publicación

El alojamiento actual es Sites, con acceso público. En esta máquina la copia de publicación está en `sites/qa-portfolio/`, con su propio repositorio y `.openai/hosting.json`; conserva ese `project_id` al actualizar. Ese directorio se excluye del repositorio QA.

Actualizar archivos en GitHub no despliega automáticamente Sites. Después de regenerar `_site/`, hay que actualizar la copia del sitio, sincronizar su fuente, guardar una versión y desplegarla con el flujo de Sites. La configuración de alojamiento y la publicación se gestionan por separado del workflow de pruebas del repositorio.

También puede alojarse `_site/` en GitHub Pages u otro servicio estático. Para Pages primero se debe habilitar su fuente de publicación en los ajustes de GitHub; no hay un workflow de Pages activo que falle por una configuración pendiente.

## Validación realizada

- Vista previa local revisada visualmente.
- Cambio al escenario de manifiesto offline comprobado en el navegador.
- Sintaxis de `app.js`, enlaces locales, assets y metadatos verificados.
- Reporte incorporado: 42 casos aprobados, 0 fallidos, de la ejecución local documentada.
- Publicación confirmada por Sites. La automatización del navegador quedó detenida al no poder verificar la URL de una ventana de Chrome; no se completó una revisión adicional en móvil.
