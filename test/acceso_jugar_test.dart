import 'package:flutter_test/flutter_test.dart';
import 'package:myl_decks/screens/jugar_screen.dart';
import 'package:myl_decks/services/acceso_jugar.dart';
import 'package:myl_decks/utils/app_constants.dart';

void main() {
  test('Jugar: el dueño siempre; el resto solo si está en la lista', () {
    expect(
      AccesoJugar.permitido(uid: 'x', email: AppConstants.ownerEmail.toUpperCase()),
      isTrue,
    );
    expect(AccesoJugar.permitido(uid: 'u1', email: 'otro@correo.cl'), isFalse);
    expect(
      AccesoJugar.permitido(
        uid: 'u1',
        email: 'otro@correo.cl',
        uidsHabilitados: const ['u2', 'u1'],
      ),
      isTrue,
    );
    expect(
      AccesoJugar.permitido(uid: null, email: null, uidsHabilitados: const ['u1']),
      isFalse,
    );
  });

  test('Jugar reúne todo lo del simulador, con ELO', () {
    expect(opcionesJugar.map((o) => o.titulo), [
      'Desafío contra la IA',
      'ELO',
      'Simulador de partidas',
      'Lo que gana',
      'Laboratorio',
    ]);
  });
}
