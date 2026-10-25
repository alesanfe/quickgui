import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/core/constants/preference_keys.dart';
import 'package:quickgui/features/diagnostics/infrastructure/system_host_probe.dart';

import '../../../support/fakes/fake_preferences_repository.dart';

HostRun scriptRunner(Map<String, ProcessResult> responses) {
  return (exe, args) async {
    final key = '$exe ${args.join(' ')}';
    return responses[key] ??
        responses[exe] ??
        (throw StateError('unexpected call: $key'));
  };
}

ProcessResult ok(Object stdout) => ProcessResult(0, 0, stdout, '');
ProcessResult fail([int code = 1]) => ProcessResult(0, code, '', 'err');

void main() {
  late FakePreferencesRepository prefs;

  SystemHostProbe probe(Map<String, ProcessResult> responses) =>
      SystemHostProbe(prefs, run: scriptRunner(responses));

  setUp(() => prefs = FakePreferencesRepository());

  group('hasTool', () {
    test('is true when which succeeds', () async {
      final p = probe({'which quickemu': ok('/usr/bin/quickemu')});
      expect(await p.hasTool('quickemu'), isTrue);
    });
    test('is false when which fails', () async {
      final p = probe({'which quickget': fail()});
      expect(await p.hasTool('quickget'), isFalse);
    });
  });

  group('workingDirectory', () {
    test('returns the stored preference', () async {
      prefs.store[prefWorkingDirectory] = '/data/vms';
      final p = probe({});
      expect(await p.workingDirectory(), '/data/vms');
    });
    test('falls back when the preference is empty or missing', () async {
      prefs.store[prefWorkingDirectory] = '   ';
      // whitespace is not empty so it is returned verbatim
      final p = probe({});
      expect(await p.workingDirectory(), '   ');
      prefs.store.remove(prefWorkingDirectory);
      expect(await p.workingDirectory(), isNotEmpty);
    });
  });

  group('freeSpaceBytes', () {
    const dfOut =
        'Filesystem     1024-blocks    Used Available Capacity Mounted on\n'
        '/dev/sda1        100000000 5000000  95000000       5% /data';
    test('parses the available column in KiB to bytes', () async {
      final p = probe({'df -Pk /data': ok(dfOut)});
      expect(await p.freeSpaceBytes('/data'), 95000000 * 1024);
    });
    test('is null when df fails', () async {
      final p = probe({'df -Pk /gone': fail()});
      expect(await p.freeSpaceBytes('/gone'), isNull);
    });
    test('is null on a single-line reply', () async {
      final p = probe({'df -Pk /x': ok('header only')});
      expect(await p.freeSpaceBytes('/x'), isNull);
    });
    test('is null when the available column is not numeric', () async {
      final p = probe({'df -Pk /x': ok('fs used avail\ndev 1 NaN')});
      expect(await p.freeSpaceBytes('/x'), isNull);
    });
  });

  group('terminalEmulator', () {
    test('uses the x-terminal-emulator alternative when supported', () async {
      final p = probe({
        'which x-terminal-emulator': ok('/usr/bin/x-terminal-emulator\n'),
        'readlink -f /usr/bin/x-terminal-emulator': ok('/usr/bin/kitty\n'),
      });
      expect(await p.terminalEmulator(), 'kitty');
    });
    test('returns null for an unsupported alternative', () async {
      final p = probe({
        'which x-terminal-emulator': ok('/usr/bin/x-terminal-emulator\n'),
        'readlink -f /usr/bin/x-terminal-emulator': ok('/usr/bin/ed\n'),
      });
      expect(await p.terminalEmulator(), isNull);
    });
    test('falls back to the candidate when readlink fails', () async {
      final p = probe({
        'which x-terminal-emulator': ok('/usr/bin/konsole\n'),
        'readlink -f /usr/bin/konsole': fail(),
      });
      expect(await p.terminalEmulator(), 'konsole');
    });
    test('scans the supported list when no alternative exists', () async {
      var calls = 0;
      final p = SystemHostProbe(
        prefs,
        run: (exe, args) async {
          calls++;
          // which x-terminal-emulator fails; the first scan hits gnome-terminal
          if (args.first == 'x-terminal-emulator') return fail();
          return args.first == 'alacritty' ||
                  args.first == 'cool-retro-term' ||
                  args.first == 'foot'
              ? fail()
              : ok('/usr/bin/${args.first}');
        },
      );
      expect(await p.terminalEmulator(), 'gnome-terminal');
      expect(calls, greaterThan(1));
    });
    test('returns null when nothing is installed', () async {
      final p = SystemHostProbe(prefs, run: (exe, args) async => fail());
      expect(await p.terminalEmulator(), isNull);
    });
  });

  group('missingMacosRequirements', () {
    test('reports flags absent from the host cpu', () async {
      // /proc/cpuinfo is real here; pick a requirement the host lacks when
      // possible, otherwise assert the known-present flag is filtered out.
      final cpuinfo = await File('/proc/cpuinfo').readAsString();
      final hasSse42 = cpuinfo.toLowerCase().contains('sse4_2');
      final p = probe({});
      final missing = await p.missingMacosRequirements('ventura');
      expect(missing.contains('sse4_2'), isNot(hasSse42));
    });
    test('uses the default requirement for unknown releases', () async {
      final p = probe({});
      final missing = await p.missingMacosRequirements('hurd');
      final hasSse41 = (await File(
        '/proc/cpuinfo',
      ).readAsString()).toLowerCase().contains('sse4_1');
      expect(missing, hasSse41 ? isEmpty : ['sse4_1']);
    });
  });

  test('canWriteToDirectory defers to the platform probe', () async {
    final dir = Directory.systemTemp.createTempSync('qg-probe-');
    addTearDown(dir.deleteSync);
    final p = probe({});
    expect(await p.canWriteToDirectory(dir.path), isTrue);
    expect(await p.canWriteToDirectory('${dir.path}/missing/sub'), isFalse);
  });

  test('homeDirectory and appVersion expose environment values', () {
    final p = probe({});
    expect(p.homeDirectory, Platform.environment['HOME'] ?? '');
    expect(p.appVersion, isNotEmpty);
  });
}
