import sys
f = sys.argv[1]
s = open(f, encoding="utf-8", newline="").read()
def rep(a, b, n=1):
    global s
    assert s.count(a) == n, (a[:60], s.count(a))
    s = s.replace(a, b)

rep("""const _orange = Color(0xFFF59E0B);
""", """const _orange = Color(0xFFF59E0B);

/// IA de las simulaciones: la rápida es la heurística; la buena decide la
/// Vigilia (incluye "pasar") y los ataques simulando (≈20 veces más lenta).
const _ias = {'heuristico': 'IA rápida', 'busqueda_vigilia': 'IA buena'};
String _nombreIa(Object? j) => _ias['${j ?? 'heuristico'}'] ?? '$j';
""")

rep("""  int _n = 1000;
  bool _enviando = false;
""", """  int _n = 1000;
  bool _enviando = false;
  String _jugador = 'heuristico';
  bool _comparar = false;
  final _semilla = TextEditingController();

  @override
  void dispose() {
    _semilla.dispose();
    super.dispose();
  }
""")

rep("""    setState(() => _enviando = true);
    try {
      await _sims.add({
        'ownerUid': _uid,
        'createdBy': FirebaseAuth.instance.currentUser?.email,
        'deckA': _a,
        'deckB': _b,
        'n': _n,
        'seed': DateTime.now().millisecondsSinceEpoch % 100000,
        'jugador': 'heuristico',
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {""", """    setState(() => _enviando = true);
    try {
      // Misma semilla = mismos barajados y dados: sirve para comparar IAs.
      final seed = int.tryParse(_semilla.text.trim()) ??
          DateTime.now().millisecondsSinceEpoch % 100000;
      for (final jugador in _comparar ? _ias.keys : [_jugador]) {
        await _sims.add({
          'ownerUid': _uid,
          'createdBy': FirebaseAuth.instance.currentUser?.email,
          'deckA': _a,
          'deckB': _b,
          'n': _n,
          'seed': seed,
          'jugador': jugador,
          if (_comparar) 'comparacion': seed,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {""")

rep("""                  const SizedBox(height: 12),
                  SegmentedButton<int>(""", """                  const SizedBox(height: 12),
                  SegmentedButton<String>(
                    segments: [
                      for (final e in _ias.entries)
                        ButtonSegment(value: e.key, label: Text(e.value)),
                    ],
                    selected: {_jugador},
                    onSelectionChanged:
                        _comparar ? null : (s) => setState(() => _jugador = s.first),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: _comparar,
                    onChanged: (v) => setState(() => _comparar = v ?? false),
                    title: const Text(
                      'Comparar IA rápida vs IA buena (misma semilla)',
                      style: TextStyle(color: Colors.white),
                    ),
                    subtitle: const Text(
                      'Crea dos simulaciones iguales, una con cada IA. La IA buena '
                      'tarda ~6 s por partida: usa 1 narrada o 100.',
                      style: TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ),
                  TextField(
                    controller: _semilla,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Semilla (opcional, vacío = al azar)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<int>(""")

rep("""                Text(
                  '${d['n']} partidas',
                  style: const TextStyle(color: Colors.white54),
                ),""", """                Text(
                  '${d['n']} partidas · ${_nombreIa(d['jugador'])} · semilla ${d['seed']}',
                  style: const TextStyle(color: Colors.white54),
                ),""")

rep("""  Future<void> _repetir(BuildContext context) async {""",
    """  Future<void> _repetir(BuildContext context, {String? jugador}) async {""")
rep("""        'jugador': d['jugador'] ?? 'heuristico',
        'status': 'pending',""", """        'jugador': jugador ?? d['jugador'] ?? 'heuristico',
        'status': 'pending',""")

rep("""            label: const Text(
              'Repetir esta partida (misma semilla)',
              style: TextStyle(color: _gold),
            ),
          ),
        ),""", """            label: const Text(
              'Repetir esta partida (misma semilla)',
              style: TextStyle(color: _gold),
            ),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _repetir(
              context,
              jugador: doc.data()['jugador'] == 'busqueda_vigilia'
                  ? 'heuristico'
                  : 'busqueda_vigilia',
            ),
            icon: const Icon(Icons.compare_arrows, color: _gold),
            label: Text(
              'Misma semilla con la '
              '${doc.data()['jugador'] == 'busqueda_vigilia' ? 'IA rápida' : 'IA buena'}',
              style: const TextStyle(color: _gold),
            ),
          ),
        ),""")
open(f, "w", encoding="utf-8", newline="").write(s)
print("ok")
