# MyL Mazos

Aplicación Flutter para gestión de mazos, teams y ligas de Mitos y Leyendas.

## Deploy oficial

La aplicación y el dashboard se publican en Firebase Hosting. El script incluye
automáticamente `dashboard/index.html` dentro del build web antes de desplegar.

Deploy completo, incluyendo reglas e índices de Firestore:

```powershell
.\deploy.ps1
```

Solo Hosting, sin modificar Firestore:

```powershell
.\deploy.ps1 -HostingOnly
```

Omitir pruebas, únicamente cuando ya fueron ejecutadas previamente:

```powershell
.\deploy.ps1 -SkipTests
```

- MyL Mazos (aplicación completa): https://mylmazos.web.app/
- NexusTCG (solo marketplace): https://nexustcg.web.app/
- Dashboard público: https://mylmazos.web.app/dashboard/

Ambos sitios se pueden desplegar juntos con `./deploy.ps1` o por separado:

```powershell
.\deploy.ps1 -Site MyLMazos -HostingOnly
.\deploy.ps1 -Site NexusTCG -HostingOnly
```

Las dos aplicaciones comparten Firebase, pero se compilan como productos
independientes. NexusTCG no expone rutas de mazos, inventario, ligas ni
comunidad.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

# Simulador de partidas

Ver [simulator/README.md](simulator/README.md).
