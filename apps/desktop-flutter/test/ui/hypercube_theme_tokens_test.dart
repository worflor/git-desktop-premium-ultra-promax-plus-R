import 'package:flutter_test/flutter_test.dart';
import 'package:git_desktop/ui/tokens.dart';

void main() {
  test('hypercube theme colors mirror effective CSS tokens for all themes', () {
    final expected = <AppThemeId,
        ({
          int chromatic1,
          int chromatic2,
          int core,
          int positive,
          int negative
        })>{
      AppThemeId.aether: (
        chromatic1: 0xFFFF00FF,
        chromatic2: 0xFF00FFFF,
        core: 0xFFFFFFFF,
        positive: 0xFF00FFFF,
        negative: 0xFFFF00FF,
      ),
      AppThemeId.helix: (
        chromatic1: 0xFFCD7F2D,
        chromatic2: 0xFF4E7F5E,
        core: 0xFFFFCC66,
        positive: 0xFF0F8F5E,
        negative: 0xFF4E7F5E,
      ),
      AppThemeId.quanta: (
        chromatic1: 0xFF00FF88,
        chromatic2: 0xFF00E0FF,
        core: 0xFFFF00CC,
        positive: 0xFFFFFFFF,
        negative: 0xFF00FF88,
      ),
      AppThemeId.petrichor: (
        chromatic1: 0xFF4B95AF,
        chromatic2: 0xFF40515F,
        core: 0xFF23323D,
        positive: 0xFF40515F,
        negative: 0xFF4B95AF,
      ),
      AppThemeId.redshift: (
        chromatic1: 0xFFFF0044,
        chromatic2: 0xFFFF7700,
        core: 0xFFFFFFFF,
        positive: 0xFFFF7700,
        negative: 0xFFFF0044,
      ),
      AppThemeId.halo: (
        chromatic1: 0xFFD4AF37,
        chromatic2: 0xFFEDC9AF,
        core: 0xFFE89B4F,
        positive: 0xFF4D453B,
        negative: 0xFFD4AF37,
      ),
      AppThemeId.crafty: (
        chromatic1: 0xFF8B5A2B,
        chromatic2: 0xFF70D655,
        core: 0xFFFFFFFF,
        positive: 0xFF70D655,
        negative: 0xFF8B5A2B,
      ),
      AppThemeId.blackboard: (
        chromatic1: 0xFF96D2FF,
        chromatic2: 0xFFFFFFFF,
        core: 0xFF96D2FF,
        positive: 0xFFFFFFCC,
        negative: 0xFF96D2FF,
      ),
      AppThemeId.nightwalker: (
        chromatic1: 0xFF00F0FF,
        chromatic2: 0xFFFF00CC,
        core: 0xFFFFFFFF,
        positive: 0xFF00FFAA,
        negative: 0xFF00F0FF,
      ),
    };

    for (final entry in expected.entries) {
      final tokens = AppTokens.fromId(entry.key);
      expect(tokens.hyperChromatic1.value, entry.value.chromatic1);
      expect(tokens.hyperChromatic2.value, entry.value.chromatic2);
      expect(tokens.hyperCore.value, entry.value.core);
      expect(tokens.hypercubePositive.value, entry.value.positive);
      expect(tokens.hypercubeNegative.value, entry.value.negative);
    }
  });
}
