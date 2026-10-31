import 'package:flutter_test/flutter_test.dart';
import 'package:quickgui/features/automation/domain/automation_profile.dart';

void main() {
  group('AutomationProfile.toToml', () {
    test('emits required sections and defaults', () {
      const p = AutomationProfile(
        os: 'debian-cloud',
        release: '12',
        name: 'debian-dev',
        hostname: 'debian-dev',
        packages: ['git', 'curl'],
        services: ['qemu-guest-agent'],
        checks: [
          AutomationCheck(name: 'ssh-alive', run: 'true'),
          AutomationCheck(
            name: 'hostname',
            run: 'hostname',
            expect: 'debian-dev',
          ),
        ],
      );
      final toml = p.toToml();
      expect(toml, contains('[profile]'));
      expect(toml, contains('os = "debian-cloud"'));
      expect(toml, contains('release = "12"'));
      expect(toml, contains('arch = "amd64"'));
      expect(toml, contains('cpus = 2'));
      expect(toml, contains('ram = "4G"'));
      expect(toml, contains('hostname = "debian-dev"'));
      expect(toml, contains('allow_pw_auth = false'));
      expect(toml, contains('ssh_timeout_min = 30'));
      expect(toml, contains('packages = ["git", "curl"]'));
      expect(toml, contains('services = ["qemu-guest-agent"]'));
      expect(toml, contains('[[verify]]'));
      expect(toml, contains('expect = "debian-dev"'));
      expect(toml, contains('shutdown = true'));
      expect(toml, contains('snapshot = "prepared"'));
      // No provider pinned → [automation] omits the key so the
      // engine's inference runs.
      expect(toml, isNot(contains('provider =')));
    });

    test('omits empty optionals and escapes strings', () {
      const p = AutomationProfile(
        os: 'alpine-cloud',
        release: 'v3.22',
        name: 'we"ird',
        description: 'line1\nline2',
      );
      final toml = p.toToml();
      expect(toml, isNot(contains('edition =')));
      expect(toml, isNot(contains('[provision]')));
      expect(toml, isNot(contains('[locale]')));
      expect(toml, contains(r'name = "we\"ird"'));
      expect(toml, contains(r'description = "line1\nline2"'));
    });

    test('emits provider and non-default install timeout when set', () {
      const p = AutomationProfile(
        os: 'ubuntu',
        release: '24.04',
        provider: 'nocloud-image',
        installTimeoutMin: 90,
      );
      final toml = p.toToml();
      expect(toml, contains('provider = "nocloud-image"'));
      expect(toml, contains('install_timeout_min = 90'));
    });
  });

  group('AutomationProfile.slug', () {
    test('sanitises to a DNS-safe filename stem', () {
      const p = AutomationProfile(os: 'x', release: '1', name: 'My Dev_VM.2 ');
      expect(p.slug, 'my-dev-vm-2');
    });

    test('falls back to os-release when name is empty', () {
      const p = AutomationProfile(os: 'debian-cloud', release: '12');
      expect(p.slug, 'debian-cloud-12');
    });
  });

  group('defaultChecks', () {
    test('includes ssh, hostname and dns; tools only with packages', () {
      final noTools = defaultChecks(hostname: 'h', os: 'ubuntu-server');
      expect(
        noTools.map((c) => c.name),
        containsAll(['ssh-alive', 'hostname', 'network-dns']),
      );
      expect(noTools.any((c) => c.name == 'tools-present'), isFalse);
      final withTools = defaultChecks(
        hostname: 'h',
        os: 'debian',
        packages: ['git'],
      );
      final tools = withTools.firstWhere((c) => c.name == 'tools-present');
      expect(tools.run, 'command -v git');
      final multi = defaultChecks(
        hostname: 'h',
        os: 'debian',
        packages: ['git', 'curl'],
      );
      expect(
        multi.firstWhere((c) => c.name == 'tools-present').run,
        'command -v git && command -v curl',
      );
    });

    test('windows guests get PowerShell-safe checks', () {
      final checks = defaultChecks(hostname: 'h', os: 'windows');
      expect(
        checks.map((c) => c.name),
        containsAll(['ssh-alive', 'hostname', 'network-dns']),
      );
      expect(checks.firstWhere((c) => c.name == 'ssh-alive').run, r'$true');
      expect(
        checks.firstWhere((c) => c.name == 'network-dns').run,
        contains('Resolve-DnsName'),
      );
      expect(checks.any((c) => c.run.contains('command -v')), isFalse);
    });

    test('visual runs (macos) get no checks', () {
      expect(defaultChecks(hostname: 'h', os: 'macos'), isEmpty);
    });
  });
}
