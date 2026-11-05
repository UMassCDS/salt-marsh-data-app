import 'package:flutter_test/flutter_test.dart';
import 'package:mass_marsh_app/services/protocol_service.dart';
import 'package:mass_marsh_app/services/species_service.dart';
import '../support/live_env.dart';
import '../support/sync_harness.dart';

void main() {
  setUpAll(useInMemorySqlite);

  group('forms and species from a real backend', skip: skipWithoutBackend, () {
    late LiveRun live;
    late String originalProtocol;

    setUpAll(() async {
      live = await LiveRun.start();
      originalProtocol = (await live.backend.protocolSettings(live.managerToken, live.orgId))['protocol_code'] as String;
    });
    tearDownAll(() => live.backend.setProtocol(live.managerToken, live.orgId, originalProtocol, subclassOptions: const []));

    test('every species the backend serves can be cached by the app', () async {
      final species = await live.backend.species();

      expect(species, isNotEmpty);
      for (final item in species) {
        expect(() => speciesCacheRow(item), returnsNormally, reason: 'species ${item['species_code']}');
      }
    });

    test('every available protocol reaches the app as a form it can read', () async {
      final settings = await live.backend.protocolSettings(live.managerToken, live.orgId);
      final codes = (settings['available_protocols'] as List).map((p) => p['code'] as String).toList();
      expect(codes, isNotEmpty);

      for (final code in codes) {
        await live.backend.setProtocol(live.managerToken, live.orgId, code);

        final form = ProtocolDefinition.fromApiResponse(await live.backend.mobileProtocol(live.orgId));

        expect(form.protocolCode, code);
        expect(form.speciesConfig.coverIncrement, isPositive, reason: code);
      }
    });

    test("an organization's own subclass choices reach the app", () async {
      const choices = ['Low marsh', 'High marsh', 'Pool'];
      await live.backend.setProtocol(live.managerToken, live.orgId, originalProtocol, subclassOptions: choices);

      final form = ProtocolDefinition.fromApiResponse(await live.backend.mobileProtocol(live.orgId));

      expect(form.subclassOptions, choices);
    });
  });
}
