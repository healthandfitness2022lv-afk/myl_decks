import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/deck.dart';
import '../services/deck_service.dart';
import '../services/notable_deck_service.dart';
import 'create_deck_screen.dart';

const _ink = Color(0xFF0D171B);
const _panel = Color(0xFF132328);
const _gold = Color(0xFFF3D68A);

class NotableDecksScreen extends StatelessWidget {
  const NotableDecksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final notable = NotableDeckService(uid);
    return Scaffold(
      backgroundColor: _ink,
      appBar: AppBar(backgroundColor: _ink, foregroundColor: _gold, title: const Text('Barajas notables', style: TextStyle(fontWeight: FontWeight.w800))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => CreateDeckScreen(
            onSave: (deck) => notable.publish(
              deck: deck,
              tournament: 'Lista notable',
              result: 'Sin clasificar',
            ),
          ),
        )),
        backgroundColor: _gold,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Crear baraja notable'),
      ),
      body: StreamBuilder<List<Deck>>(
        stream: notable.watch(),
        builder: (context, snapshot) {
          final decks = snapshot.data ?? const <Deck>[];
          if (decks.isEmpty) {
            return const Center(child: Text('Aún no hay listas competitivas cargadas.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: decks.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (_, index) {
              final d = decks[index];
              return Card(
                color: _panel,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: const BorderSide(color: Colors.white12)),
                child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                leading: Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(color: _gold.withValues(alpha: .14), borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.military_tech_rounded, color: _gold),
                ),
                title: Text(d.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                subtitle: Text('${d.race ?? 'Sin raza'} · ${d.cards.fold<int>(0, (n, c) => n + c.count)} cartas\nLista disponible como rival del simulador y Laboratorio ML.'),
                isThreeLine: true,
                trailing: d.ownerId == uid ? IconButton(
                  tooltip: 'Eliminar de notables', icon: const Icon(Icons.delete_outline, color: Colors.white54),
                  onPressed: () => notable.delete(d.id),
                ) : null,
              ));
            },
          );
        },
      ),
    );
  }

  Future<void> _publish(BuildContext context, String uid, NotableDeckService service) async {
    final own = await DeckService(uid).listMine();
    if (!context.mounted) return;
    Deck? selected;
    final tournament = TextEditingController();
    final result = TextEditingController(text: 'Top');
    final player = TextEditingController();
    final notes = TextEditingController();
    final ok = await showDialog<bool>(context: context, builder: (dialog) => StatefulBuilder(
      builder: (_, setDialog) => AlertDialog(
        title: const Text('Subir una lista notable'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<Deck>(
            initialValue: selected, decoration: const InputDecoration(labelText: 'Mazo base'),
            items: [for (final d in own) DropdownMenuItem(value: d, child: Text(d.name))],
            onChanged: (d) => setDialog(() => selected = d),
          ),
          TextField(controller: tournament, decoration: const InputDecoration(labelText: 'Torneo / Premier')),
          TextField(controller: result, decoration: const InputDecoration(labelText: 'Resultado (Ganador, Top 8...)')),
          TextField(controller: player, decoration: const InputDecoration(labelText: 'Jugador/a (opcional)')),
          TextField(controller: notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Notas (opcional)')),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Cancelar')), FilledButton(onPressed: selected == null ? null : () => Navigator.pop(dialog, true), child: const Text('Publicar'))],
      ),
    ));
    if (ok != true || selected == null) return;
    await service.publish(deck: selected!, tournament: tournament.text, result: result.text, player: player.text, notes: notes.text);
  }
}
