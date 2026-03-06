String normalizeTipo(String? raw) {
  final t = (raw ?? '').trim().toLowerCase();
  if (t.isEmpty) return '';
  if (t == 'aliado' || t == 'gran aliado') return 'aliado';
  if (t == 'talisman' || t == 'talismán') return 'talisman';
  if (t == 'arma' || t == 'armadura') return 'arma';
  if (t == 'oro' || t == 'oros') return 'oro';
  if (t == 'totem' || t == 'tótem' || t == 'totem de raza') return 'totem';
  return t;
}
