# Estructura del repositorio (propuesta de orden)

- `lib/` app Flutter; `lib/screens/simulador/` tableros y pantallas del simulador.
- `simulator/` motor e IA en Python. `dashboard/` dashboard web. `tools/` scripts de administración (tocan datos reales: no ejecutar desde agentes).
- `docs/` documentación; `docs/capturas/` imágenes de referencia (antes `flutter_01.png` en la raíz).
- `tmp/` contiene respaldos y borradores versionados (parches, `.bak`, `.tgz`, resultados). Está referenciado por `simulator/REGLAS.md` (`tmp/pdfs/dar_primer_bloque.txt`), por lo que NO se movió. Propuesta para el humano: mover el texto del D.A.R. a `docs/referencias/` y archivar o borrar el resto.

## Tablero del simulador (T-007)
Lienzo fijo escalado con `FittedBox` (1600×960 horizontal, 900×1540 vertical). Cambios: líneas propias y mano más altas que las del rival, mano rival y divisor más bajos, registro (9 líneas) al centro de la columna izquierda y fase al centro de la derecha, columnas simétricas. El teléfono (`_campoTelefono`) no cambió.
Pendiente: verificar con `flutter analyze`, `flutter test` y captura con Playwright (build web) en un entorno con Flutter.
