// lib/utils/wallpaper_image.dart
//
// El wallpaper de fondo persistido en SharedPreferences es una URL de Drive
// elegida con el picker de carpetas por raza, o vacío si el usuario nunca
// eligió uno (ver [wallpaperFallbackColor] para ese caso). También se
// soportan, por compatibilidad con datos guardados antes de migrar a Drive,
// rutas de asset local ('assets/wallpaper/...').

import 'package:flutter/material.dart';
import '../services/drive_service.dart';

/// Color de fondo sólido cuando no hay wallpaper elegido todavía.
const Color wallpaperFallbackColor = Color(0xFF0D1016);

/// true si [value] no tiene un wallpaper asignado (usuario nuevo, o nunca
/// eligió uno) — el llamador debe pintar [wallpaperFallbackColor] en su lugar.
bool isWallpaperUnset(String value) => value.trim().isEmpty;

ImageProvider wallpaperImageProvider(String value) {
  if (value.startsWith('assets/')) return AssetImage(value);
  return NetworkImage(DriveService.webSafeUrl(value));
}
