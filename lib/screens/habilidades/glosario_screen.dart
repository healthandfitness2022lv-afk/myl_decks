// lib/screens/habilidades/glosario_screen.dart
//
// Glosario de acciones: qué hace cada acción que el simulador sabe ejecutar.
// Es solo de consulta; las acciones se definen en el enum `Accion`.

import 'package:flutter/material.dart';

import '../../domain/catalogo_acciones.dart';

const _bg = Color(0xFF0F181B);
const _surface = Color(0xFF132126);
const _gold = Color(0xFFF2D487);

class GlosarioScreen extends StatefulWidget {
  const GlosarioScreen({super.key});

  @override
  State<GlosarioScreen> createState() => _GlosarioScreenState();
}

class _GlosarioScreenState extends State<GlosarioScreen> {
  final List<AccionDef> _acciones = catalogoAcciones();
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    final list =
        _acciones
            .where(
              (a) =>
                  q.isEmpty ||
                  a.name.toLowerCase().contains(q) ||
                  a.descripcion.toLowerCase().contains(q),
            )
            .toList();
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A120C),
        title: const Text(
          'Glosario de acciones',
          style: TextStyle(color: _gold, fontWeight: FontWeight.bold),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Text(
                '${_acciones.length} acciones que el simulador sabe ejecutar.',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 10),
              TextField(
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Buscar acción…',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: _surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (v) => setState(() => _query = v.trim()),
              ),
              const SizedBox(height: 10),
              for (final a in list)
                Card(
                  color: _surface,
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: Colors.white10),
                  ),
                  child: ListTile(
                    title: Text(
                      a.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      a.descripcion,
                      style: const TextStyle(color: Colors.white60),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
