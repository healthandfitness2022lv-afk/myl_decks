// lib/screens/create_tournament_screen.dart
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Clipboard + input formatters
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Nombres de las 4 ediciones fijas
const List<String> kTournamentEditions = [
  'Espada Sagrada',
  'Helénica',
  'Hijos de Daana',
  'Dominios de Ra',
];

class CreateTournamentScreen extends StatefulWidget {
  final String? editTournamentId;
  const CreateTournamentScreen({super.key, this.editTournamentId});

  @override
  State<CreateTournamentScreen> createState() => _CreateTournamentScreenState();
}

class _CreateTournamentScreenState extends State<CreateTournamentScreen> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _maxParticipantsCtrl = TextEditingController();

  DateTime? _date;
  bool _loading = false;

  // Configuración adicional
  int _bestOf = 3; // debe ser impar: 1,3,5,7...
  String? _selectedEdition; // null = cualquier edición
  List<String> _editions = [];
  String _classificationFormat = 'Swiss'; // 'Swiss' o 'Single Elimination'

  // Visibilidad: 'open' o 'invite'
  String _visibility = 'open';
  String? _inviteCode;

  final List<int> _bestOfOptions = [1, 3, 5, 7];

  int _swissRounds = 3; // rondas (partidas para cada jugador)
  int _swissQualifiers = 4; // cuantos clasifican luego de esas rondas
  // -----------------------------

  @override
  void initState() {
    super.initState();
    _loadEditions();
    if (widget.editTournamentId != null) _loadTournament();
  }

  /// Cargamos las 4 ediciones fijas y la opción "Cualquiera"
  void _loadEditions() {
    setState(() {
      _editions = ['Cualquiera'] + kTournamentEditions;
      _selectedEdition = 'Cualquiera';
    });
  }

  Future<void> _loadTournament() async {
    setState(() => _loading = true);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('tournaments')
          .doc(widget.editTournamentId)
          .get();
      final data = doc.data();
      if (data != null) {
        _nameCtrl.text = (data['name'] ?? '').toString();
        _descCtrl.text = (data['description'] ?? '').toString();
        final ts = data['date'] as Timestamp?;
        if (ts != null) _date = ts.toDate();

        final maxP = data['maxParticipants'];
        if (maxP != null) _maxParticipantsCtrl.text = maxP.toString();

        final bo = data['bestOf'];
        if (bo != null && bo is int) _bestOf = bo;

        final edRestr = (data['editionRestriction'] ?? '').toString();
        if (edRestr.isNotEmpty && _editions.contains(edRestr)) {
          _selectedEdition = edRestr;
        } else {
          _selectedEdition = 'Cualquiera';
        }

        final fmt = (data['classificationFormat'] ?? '').toString();
        if (fmt.isNotEmpty) _classificationFormat = fmt;
        final vis = (data['visibility'] ?? 'open').toString();
        _visibility = (vis == 'invite') ? 'invite' : 'open';
        _inviteCode = (data['inviteCode'])?.toString();

        // Swiss extras (si existen)
        final sr = data['swissRounds'];
        if (sr != null && sr is int) _swissRounds = sr;
        final sq = data['swissQualifiers'];
        if (sq != null && sq is int) _swissQualifiers = sq;
      }
    } catch (e) {
      // silencioso
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDate() async {
  final now = DateTime.now();
  final picked = await showDatePicker(
    context: context,
    initialDate: _date ?? now,
    firstDate: DateTime(now.year - 2),
    lastDate: DateTime(now.year + 3),
  );
  if (picked != null) {
    // Guardamos SOLO la fecha (sin hora): midnight local
    setState(() => _date = DateTime(picked.year, picked.month, picked.day));
  }
}


  String _generateInviteCode([int length = 6]) {
    const chars = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'; // sin O, I, 0,1 para evitar confusión
    final rnd = Random.secure();
    return List.generate(length, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

  Future<void> _copyInviteCode() async {
    final code = _inviteCode;
    if (code == null || code.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No hay código para copiar')));
      return;
    }

    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Código copiado al portapapeles')));
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('El nombre es obligatorio')));
      return;
    }

    final maxP = int.tryParse(_maxParticipantsCtrl.text.trim());
    if (maxP == null || maxP < 2 || maxP > 256) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Número de participantes inválido (2-256)')));
      return;
    }

    if (_classificationFormat == 'Swiss') {
      if (_swissRounds < 1) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rondas Swiss inválidas (>=1)')));
        return;
      }
      if (_swissQualifiers < 1 || _swissQualifiers > maxP) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Número de clasificados inválido')));
        return;
      }
    }

    if (_bestOf < 1 || _bestOf % 2 == 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Best-of inválido (debe ser impar: 1,3,5...)')));
      return;
    }

    setState(() => _loading = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final col = FirebaseFirestore.instance.collection('tournaments');

      // si está en modo invite, genera código si no existe
      if (_visibility == 'invite' && (_inviteCode == null || _inviteCode!.isEmpty)) {
        _inviteCode = _generateInviteCode(6);
      }

      final payload = <String, dynamic>{
        'name': name,
        'description': _descCtrl.text.trim(),
        'date': _date != null ? Timestamp.fromDate(_date!) : null,
        'ownerUid': uid,
        'updatedAt': FieldValue.serverTimestamp(),
        'maxParticipants': maxP,
        'bestOf': _bestOf,
        'classificationFormat': _classificationFormat,
        'visibility': _visibility, // 'open' o 'invite'
        'inviteCode': (_visibility == 'invite') ? _inviteCode : null,
        'editionRestriction': (_selectedEdition == null || _selectedEdition == 'Cualquiera') ? null : _selectedEdition,
      };

      // Swiss extras
      if (_classificationFormat == 'Swiss') {
        payload['swissRounds'] = _swissRounds;
        payload['swissQualifiers'] = _swissQualifiers;
      }

      // limpia nulls
      payload.removeWhere((k, v) => v == null);

      String tournamentId;
      if (widget.editTournamentId != null) {
        await col.doc(widget.editTournamentId).update(payload);
        tournamentId = widget.editTournamentId!;
      } else {
        payload['createdAt'] = FieldValue.serverTimestamp();
        payload['participants'] = <Map<String, dynamic>>[]; // array vacío inicial
        final docRef = await col.add(payload);
        tournamentId = docRef.id;
        // GENERAR primera ronda automática (placeholder seeds) solo en creación
        await _createInitialRound(tournamentId, maxP);
      }

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Torneo guardado')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error guardando: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Crea la ronda 1 en la subcolección `matches` del torneo.
  /// - Para Swiss: genera emparejamientos aleatorios entre los slots 1..maxParticipants.
  /// - Para Single Elimination: empareja slots y marca byes si target>n.
  Future<void> _createInitialRound(String tournamentId, int maxParticipants) async {
    final colMatches =
        FirebaseFirestore.instance.collection('tournaments').doc(tournamentId).collection('matches');
    final tDoc = FirebaseFirestore.instance.collection('tournaments').doc(tournamentId);
    final format = _classificationFormat;

    // create slot labels
    final slots = List<int>.generate(maxParticipants, (i) => i + 1);
    final rnd = Random.secure();

    if (format == 'Swiss') {
      // barajar y emparejar slots para ronda 1
      slots.shuffle(rnd);
      final pairs = <Map<String, dynamic>>[];
      for (int i = 0; i < slots.length; i += 2) {
        final a = slots[i];
        final b = (i + 1 < slots.length) ? slots[i + 1] : null;
        pairs.add({
          'seedA': a,
          'seedB': b,
          'playerA': null,
          'playerB': null,
          'round': 1,
          'bestOf': _bestOf,
          'status': 'scheduled',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      // batch write
      final batch = FirebaseFirestore.instance.batch();
      for (final p in pairs) {
        final d = colMatches.doc();
        batch.set(d, p);
      }
      // guarda meta útil sobre swiss
      batch.set(tDoc, {
        'swissRounds': _swissRounds,
        'swissQualifiers': _swissQualifiers,
        'meta_rounds_generated': 1,
      }, SetOptions(merge: true));
      await batch.commit();
    } else {
      // Single Elimination: emparejamos para la primera ronda.
      // Calculamos la potencia de 2 >= n para determinar byes.
      int n = slots.length;
      int target = 1;
      while (target < n) {
        target <<= 1;
      }
      // slots con null para byes si hace falta
      final slotList = List<int?>.from(slots);
      if (target > n) slotList.addAll(List<int?>.filled(target - n, null));

      final pairs = <Map<String, dynamic>>[];
      for (int i = 0; i < target ~/ 2; i++) {
        final a = slotList[i];
        final b = slotList[target - 1 - i];
        pairs.add({
          'seedA': a,
          'seedB': b,
          'playerA': null,
          'playerB': null,
          'round': 1,
          'bestOf': _bestOf,
          'status': 'scheduled',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      // guardamos la estructura básica de la primera ronda.
      final batch = FirebaseFirestore.instance.batch();
      for (final p in pairs) {
        final d = colMatches.doc();
        batch.set(d, p);
      }
      // guardamos meta (poder generar siguientes rondas con winners)
      batch.set(tDoc, {
        'meta_bracket_size': target,
        'meta_rounds_generated': 1,
      }, SetOptions(merge: true));
      await batch.commit();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _maxParticipantsCtrl.dispose();
    super.dispose();
  }

  Widget _numberField({
    required TextEditingController controller,
    required String label,
    String hint = '',
    int? maxLength,
    String? suffix,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(labelText: label, hintText: hint, counterText: '', suffixText: suffix),
      maxLength: maxLength,
    );
  }

  String _formatDateOnly(DateTime dt) {
  final d = dt.toLocal();
  final day = d.day.toString().padLeft(2, '0');
  final month = d.month.toString().padLeft(2, '0');
  final year = d.year.toString();
  return '$day/$month/$year';
}


  @override
  Widget build(BuildContext context) {
    final dateText = _date == null ? 'Fecha no seleccionada' : _formatDateOnly(_date!);


    return Scaffold(
      appBar: AppBar(
        title: Text(widget.editTournamentId != null ? 'Editar torneo' : 'Crear torneo'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Nombre')),
                  const SizedBox(height: 12),
                  TextField(
                      controller: _descCtrl, decoration: const InputDecoration(labelText: 'Descripción'), maxLines: 3),
                  const SizedBox(height: 12),

                  // fila: max participantes y (si Swiss) número de rondas
                  Row(
                    children: [
                      Expanded(
                        child: _numberField(
                          controller: _maxParticipantsCtrl,
                          label: 'Máx participantes',
                          hint: '2 - 256',
                          maxLength: 3,
                        ),
                      ),
                      const SizedBox(width: 12),
                      // si Swiss, mostramos ronda en bloque más abajo; aquí dejamos espacio
                      if (_classificationFormat != 'Swiss') const SizedBox(width: 0),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // ---------- Selector de formato y Best-of (siempre visible el selector) ----------
                  Row(
                    children: [
                      // Best-of (siempre accesible)
                      Expanded(
                        child: DropdownButton<int>(
                          value: _bestOf,
                          isExpanded: true,
                          items: _bestOfOptions
                              .map((v) => DropdownMenuItem(value: v, child: Text('Best of $v')))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setState(() => _bestOf = v);
                          },
                        ),
                      ),

                      const SizedBox(width: 16),

                      // Formato de clasificación (SIEMPRE visible para poder cambiarlo)
                      Expanded(
                        child: DropdownButton<String>(
                          value: _classificationFormat,
                          isExpanded: true,
                          items: ['Swiss', 'Single Elimination']
                              .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setState(() => _classificationFormat = v);
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // ---------- Opciones específicas de Swiss ----------
                  if (_classificationFormat == 'Swiss') ...[
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            initialValue: _swissRounds.toString(),
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: const InputDecoration(labelText: 'Rondas (Swiss)', hintText: 'ej. 3'),
                            onChanged: (v) {
                              final x = int.tryParse(v) ?? 1;
                              setState(() => _swissRounds = x);
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            initialValue: _swissQualifiers.toString(),
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration:
                                const InputDecoration(labelText: 'Clasifican tras Swiss', hintText: 'ej. 4'),
                            onChanged: (v) {
                              final x = int.tryParse(v) ?? 1;
                              setState(() => _swissQualifiers = x);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],

                  // visibilidad
                  Row(
                    children: [
                      const Text('Visibilidad: ', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(width: 12),
                      ChoiceChip(
                        label: const Text('Abierto'),
                        selected: _visibility == 'open',
                        onSelected: (sel) => setState(() {
                          if (sel) _visibility = 'open';
                        }),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Por invitación'),
                        selected: _visibility == 'invite',
                        onSelected: (sel) => setState(() {
                          if (sel) _visibility = 'invite';
                          if (_visibility == 'invite' && (_inviteCode == null || _inviteCode!.isEmpty)) {
                            _inviteCode = _generateInviteCode();
                          }
                        }),
                      ),
                      const SizedBox(width: 12),
                      if (_visibility == 'invite' && _inviteCode != null)
                        Row(
                          children: [
                            SelectableText('Código: $_inviteCode', style: const TextStyle(fontWeight: FontWeight.w600)),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.copy),
                              onPressed: _copyInviteCode,
                              tooltip: 'Copiar código',
                            ),
                          ],
                        ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // edición restrictiva (opcional)
                  Row(
                    children: [
                      const Text('Restricción edición: ', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _editions.isEmpty
                            ? const Text('Cargando ediciones...')
                            : DropdownButton<String>(
                                isExpanded: true,
                                value: _selectedEdition ?? 'Cualquiera',
                                items: _editions.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                                onChanged: (v) {
                                  setState(() => _selectedEdition = v);
                                },
                              ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  // fecha
                  Row(
                    children: [
                      Expanded(child: Text(dateText)),
                      FilledButton(onPressed: _pickDate, child: const Text('Elegir fecha')),
                    ],
                  ),

                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _save,
                      child: const Text('Guardar torneo'),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
