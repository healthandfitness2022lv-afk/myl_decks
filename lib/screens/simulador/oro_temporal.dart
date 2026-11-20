import 'package:flutter/material.dart';

/// Un Oro generado por una habilidad (Herrero, Saladino, Dragones, Imhotep,
/// Jano…): se ve en la Reserva como una ficha punteada hasta que se gasta o
/// termina el turno (reporte g3hq).
class OroTemporal extends StatelessWidget {
  final double ancho;
  final double alto;

  const OroTemporal({super.key, required this.ancho, required this.alto});

  static const _oro = Color(0xFFE8C766);

  @override
  Widget build(BuildContext context) => Container(
    width: ancho,
    height: alto,
    decoration: BoxDecoration(
      color: _oro.withValues(alpha: .14),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: _oro.withValues(alpha: .8), width: 1.5),
    ),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(Icons.monetization_on_outlined, color: _oro, size: 22),
            SizedBox(height: 2),
            Text(
              'Oro\ntemporal',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _oro,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
