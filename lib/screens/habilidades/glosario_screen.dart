// lib/screens/habilidades/glosario_screen.dart
//
// Glosario de características: qué significa cada una y qué acción ejecuta
// el simulador. Las que no tienen acción guardada muestran la sugerida
// (según el nombre) hasta que se confirma.

import 'package:flutter/material.dart';

import '../../models/card_habilidad.dart';
import '../../services/feature_catalog_service.dart';

const _bg = Color(0xFF0F181B);
const _surface = Color(0xFF132126);
const _gold = Color(0xFFF2D487);
const _green = Color(0xFF34D399);

class GlosarioScreen extends StatefulWidget {
  const GlosarioScreen({super.key});

  @override
  State<GlosarioScreen> createState() => _GlosarioScreenState();
}

class _GlosarioScreenState extends State<GlosarioScreen> {
  late final Stream<List<FeatureDef>> _stream = FeatureCatalogService.stream();
  String _query = '';
  bool _soloPendientes = false;

  Future<void> _editar(FeatureDef f) async {
    final descCtrl = TextEditingController(text: f.descripcion);
    var accion = f.accion;
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => StatefulBuilder(
            builder:
                (ctx, setD) => AlertDialog(
                  backgroundColor: _surface,
                  title: Text(f.name, style: const TextStyle(color: _gold)),
                  content: SizedBox(
                    width: 460,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: descCtrl,
                          maxLines: 3,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'Qué significa',
                            hintText:
                                'Ej: destruye un Aliado oponente; la carta indica fase, coste o raza.',
                          ),
                        ),
                        const SizedBox(height: 14),
                        DropdownButtonFormField<Accion>(
                          initialValue: accion,
                          isExpanded: true,
                          dropdownColor: _surface,
                          decoration: const InputDecoration(
                            labelText: 'Acción del simulador',
                          ),
                          items: [
                            for (final a in Accion.values)
                              DropdownMenuItem(value: a, child: Text(a.label)),
                          ],
                          onChanged: (v) => setD(() => accion = v ?? accion),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          accion.descripcion,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancelar'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Guardar'),
                    ),
                  ],
                ),
          ),
    );
    final desc = descCtrl.text;
    WidgetsBinding.instance.addPostFrameCallback((_) => descCtrl.dispose());
    if (ok != true) return;
    try {
      await FeatureCatalogService.save(f.id, descripcion: desc, accion: accion);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A120C),
        title: const Text(
          'Glosario de características',
          style: TextStyle(color: _gold, fontWeight: FontWeight.bold),
        ),
      ),
      body: StreamBuilder<List<FeatureDef>>(
        stream: _stream,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = snap.data!;
          final definidas = all.where((f) => f.definida).length;
          final q = _query.toLowerCase();
          final list =
              all
                  .where((f) => !_soloPendientes || !f.definida)
                  .where(
                    (f) =>
                        q.isEmpty ||
                        f.name.toLowerCase().contains(q) ||
                        f.group.toLowerCase().contains(q),
                  )
                  .toList();
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Text(
                    '$definidas de ${all.length} características definidas. '
                    'Una característica está definida cuando tiene significado '
                    'y acción confirmada.',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Buscar por nombre o grupo…',
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
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _soloPendientes,
                    onChanged: (v) => setState(() => _soloPendientes = v),
                    title: const Text(
                      'Mostrar solo las pendientes',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                  for (final f in list)
                    Card(
                      color: _surface,
                      margin: const EdgeInsets.only(bottom: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color:
                              f.definida
                                  ? _green.withValues(alpha: .4)
                                  : Colors.white10,
                        ),
                      ),
                      child: ListTile(
                        onTap: () => _editar(f),
                        title: Text(
                          f.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: Text(
                          [
                            '${f.group} · ${f.accion.label}'
                                '${f.accionGuardada == null ? ' (sugerida)' : ''}',
                            if (f.descripcion.isNotEmpty) f.descripcion,
                            if (f.incluye.isNotEmpty)
                              'Incluye: ${f.incluye.join(', ')}',
                          ].join('\n'),
                          style: const TextStyle(color: Colors.white60),
                        ),
                        trailing: Icon(
                          f.definida
                              ? Icons.check_circle_rounded
                              : Icons.edit_note_rounded,
                          color: f.definida ? _green : Colors.white38,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
