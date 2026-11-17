// lib/screens/habilidades/card_habilidades_section.dart
//
// Sección "Habilidades para el simulador" en el detalle de carta (solo el
// dueño de la app). Guarda directo en cards/{id}.habilidades.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../models/card_habilidad.dart';
import '../../models/card_myl.dart';
import '../../domain/catalogo_acciones.dart';
import 'glosario_screen.dart';
import 'habilidad_editor.dart';

const _gold = Color(0xFFF2D487);
const _green = Color(0xFF34D399);
const _orange = Color(0xFFF59E0B);

class CardHabilidadesSection extends StatefulWidget {
  final CardMyL card;

  /// Puede venir de `habilidadTextoIA`: es el texto transcrito desde la
  /// imagen, que el simulador usa antes que el campo legado de la carta.
  final String? textoCarta;
  const CardHabilidadesSection({
    super.key,
    required this.card,
    this.textoCarta,
  });

  @override
  State<CardHabilidadesSection> createState() => _CardHabilidadesSectionState();
}

class _CardHabilidadesSectionState extends State<CardHabilidadesSection> {
  final List<AccionDef> _features = catalogoAcciones();
  bool _saving = false;
  late final _notasCtrl = TextEditingController(
    text: widget.card.notasSimulador,
  );

  @override
  void didUpdateWidget(covariant CardHabilidadesSection old) {
    super.didUpdateWidget(old);
    // Refleja cambios guardados desde otro lado, sin pisar lo que se escribe.
    if (old.card.notasSimulador != widget.card.notasSimulador &&
        _notasCtrl.text == old.card.notasSimulador) {
      _notasCtrl.text = widget.card.notasSimulador;
    }
  }

  @override
  void dispose() {
    _notasCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardarNotas() async {
    final texto = _notasCtrl.text.trim();
    setState(() => _saving = true);
    try {
      await _ref.update({
        'notasSimulador': texto.isEmpty ? FieldValue.delete() : texto,
        'notasSimuladorAt': FieldValue.serverTimestamp(),
        // Una carta con notas pendientes no está completa.
        if (texto.isNotEmpty) 'habilidadesRevisadas': false,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            texto.isEmpty ? 'Notas borradas' : 'Notas guardadas para revisión',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  DocumentReference<Map<String, dynamic>> get _ref =>
      FirebaseFirestore.instance.collection('cards').doc(widget.card.id);

  Future<void> _guardar(
    List<CardHabilidad> habilidades, {
    bool? revisadas,
  }) async {
    setState(() => _saving = true);
    try {
      await _ref.update({
        'habilidades': habilidades.map((h) => h.toMap()).toList(),
        // Cambiar las habilidades vuelve a pedir revisión, salvo que se
        // indique explícitamente.
        'habilidadesRevisadas': revisadas ?? false,
        'habilidadesUpdatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('No se pudo guardar: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editar(List<AccionDef> features, [int? index]) async {
    final list = [...widget.card.habilidades];
    final result = await showHabilidadEditor(
      context,
      features: features,
      inicial: index == null ? null : list[index],
      textoCarta: widget.textoCarta ?? widget.card.habilidad,
      tipoCarta: widget.card.tipo,
    );
    if (result == null) return;
    if (index == null) {
      list.add(result);
    } else {
      list[index] = result;
    }
    await _guardar(list);
  }

  Future<void> _borrar(int index) async {
    final ok = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Eliminar habilidad'),
            content: Text(widget.card.habilidades[index].resumen),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Eliminar'),
              ),
            ],
          ),
    );
    if (ok != true) return;
    await _guardar([...widget.card.habilidades]..removeAt(index));
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    final sinTexto = (widget.textoCarta ?? card.habilidad).trim().isEmpty;
    final revisada = card.habilidadesRevisadas;
    final conNotas = card.notasSimulador.isNotEmpty;

    return Builder(
      builder: (context) {
        final features = _features;
        return Card(
          color: const Color(0xFF132126),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color:
                  conNotas
                      ? _orange.withValues(alpha: .6)
                      : revisada
                      ? _green.withValues(alpha: .5)
                      : Colors.white10,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.psychology_alt_rounded, color: _gold),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Habilidades para el simulador',
                        style: TextStyle(
                          color: _gold,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    if (_saving)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    IconButton(
                      tooltip: 'Glosario de acciones',
                      icon: const Icon(
                        Icons.menu_book_rounded,
                        color: Colors.white70,
                      ),
                      onPressed:
                          () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const GlosarioScreen(),
                            ),
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (sinTexto)
                  const Text(
                    'Esta carta no tiene el texto de habilidad cargado. Si de '
                    'verdad no tiene habilidad, márcala como programada.',
                    style: TextStyle(color: Colors.white54),
                  ),
                if (!card.habilidadesRevisadas && card.habilidades.isEmpty)
                  const Text(
                    'Mientras no esté marcada como programada, el simulador la '
                    'juega sin habilidad y la cuenta como pendiente.',
                    style: TextStyle(color: Colors.white54),
                  ),
                for (var i = 0; i < card.habilidades.length; i++)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: ListTile(
                      title: Text(
                        card.habilidades[i].featureName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        card.habilidades[i].resumen,
                        style: const TextStyle(color: Colors.white70),
                      ),
                      onTap:
                          features.isEmpty ? null : () => _editar(features, i),
                      trailing: IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.white54,
                        ),
                        onPressed: _saving ? null : () => _borrar(i),
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed:
                          features.isEmpty || _saving
                              ? null
                              : () => _editar(features),
                      icon: const Icon(Icons.add),
                      label: const Text('Agregar habilidad'),
                    ),
                    FilterChip(
                      selected: card.habilidadesRevisadas,
                      selectedColor: _green.withValues(alpha: .25),
                      checkmarkColor: _green,
                      label: Text(
                        conNotas
                            ? 'Pendiente (tiene notas)'
                            : card.habilidadesRevisadas
                            ? 'Programada completa'
                            : 'Marcar como programada',
                      ),
                      onSelected:
                          _saving || (conNotas && !card.habilidadesRevisadas)
                              ? null
                              : (v) => _guardar(card.habilidades, revisadas: v),
                    ),
                  ],
                ),
                ...[
                  const SizedBox(height: 14),
                  const Text(
                    'Notas para el simulador',
                    style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Si la carta tiene algo que el editor no permite expresar, '
                    'descríbelo aquí. Quedará pendiente hasta que se mejore el '
                    'simulador.',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _notasCtrl,
                    minLines: 2,
                    maxLines: 5,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText:
                          'Ej: "solo si el oponente tiene más aliados", '
                          '"el arma también da imbloqueable"…',
                      hintStyle: const TextStyle(color: Colors.white30),
                      filled: true,
                      fillColor: Colors.black26,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _saving ? null : _guardarNotas,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Guardar notas'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
