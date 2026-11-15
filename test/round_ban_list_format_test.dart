import 'package:flutter_test/flutter_test.dart';
import 'package:myl_decks/screens/leagues/league_deck_builder_screen.dart';
import 'package:myl_decks/screens/leagues/models.dart';
import 'package:myl_decks/screens/leagues/round_ban_list_viewer.dart';

void main() {
  test('round Ban List format distinguishes all three collections', () {
    expect(
      roundBanListFormatKey({'roundFormat': 'racial_edicion'}),
      'standard',
    );
    expect(
      roundBanListFormatKey({'roundFormat': 'racial_libre'}),
      'racial_libre',
    );
    expect(roundBanListFormatKey({'roundFormat': 'full'}), 'full');
  });

  test('saved Ban List metadata takes precedence over legacy round fields', () {
    expect(
      roundBanListFormatKey({
        'roundFormat': 'racial_edicion',
        'banListFormat': 'full',
      }),
      'full',
    );
  });

  test('Full allows soloLibre cards and never exposes a deck race', () {
    expect(leagueFormatAllowsSoloLibre(RoundFormat.full), isTrue);
    expect(leagueFormatAllowsSoloLibre(RoundFormat.racialLibre), isTrue);
    expect(leagueFormatAllowsSoloLibre(RoundFormat.racialEdicion), isFalse);

    expect(leagueDeckRaceForFormat(RoundFormat.full, 'Dragón'), isNull);
    expect(
      leagueDeckRaceForFormat(RoundFormat.racialLibre, ' Dragón '),
      'Dragón',
    );
  });
}
