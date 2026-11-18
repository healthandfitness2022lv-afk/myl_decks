# DIAGNÓSTICO DE CALIDAD (T-002, parcial)

Fecha: 2026-11-18. Entorno: sesión en la nube.

## Simulador Python (`simulator/`)
Comando: `python -m pytest -q` (venv con `requirements.txt`)

```
1 failed, 571 passed, 244 skipped, 39 xfailed in 86.83s
FAILED tests/test_meta.py::test_trabajos_comandos_y_evaluador - FileNotFoundError: secrets/firebase-admin.json
```

- El único fallo es de entorno: `evaluador.cargar_carta` abre Firestore y exige la credencial Admin (`secrets/`, prohibida). No se "arregló" accediendo a datos reales. Tarea T-004.
- Los 244 omitidos dependen de `simulator/cache/` o credenciales; los 39 xfailed son fallos conocidos marcados.

## Flutter (`flutter analyze`, `flutter test`)
NO EJECUTADO. El SDK no está instalado y la descarga del motor/Dart SDK desde `storage.googleapis.com` falla con `CONNECT tunnel failed, response 403` (proxy de la sesión). No se eludió el bloqueo. Pendiente: ejecutar en un entorno con Flutter (o permitir el dominio) y registrar los hallazgos como tareas.

## Dashboard web / otros
Sin scripts npm propios; no aplica.
