/// Declarative machine description the user edits in the Automation
/// page — serialised to the TOML profile `quickprovision run` consumes.
///
/// Field names mirror tools/quickprovision's Profile struct: only the
/// sections the engine reads are emitted, and empty values are omitted
/// so the engine's own defaults apply.
class AutomationProfile {
  const AutomationProfile({
    required this.os,
    required this.release,
    this.edition = '',
    this.arch = 'amd64',
    this.name = '',
    this.description = '',
    this.cpus = 2,
    this.ram = '4G',
    this.diskSize = '32G',
    this.hostname = '',
    this.username = 'dev',
    this.lang = '',
    this.timezone = '',
    this.provider = '',
    this.sshTimeoutMin = 30,
    this.installTimeoutMin = 45,
    this.packages = const [],
    this.services = const [],
    this.checks = const [],
    this.shutdown = true,
    this.snapshot = 'prepared',
  });

  final String os;
  final String release;
  final String edition;
  final String arch;

  /// Profile name — also the default hostname seed.
  final String name;
  final String description;

  final int cpus;
  final String ram;
  final String diskSize;

  final String hostname;
  final String username;
  final String lang;
  final String timezone;

  /// Provider id (`nocloud-image`, `ubuntu-autoinstall`); empty = auto.
  final String provider;
  final int sshTimeoutMin;
  final int installTimeoutMin;

  final List<String> packages;
  final List<String> services;
  final List<AutomationCheck> checks;

  final bool shutdown;
  final String snapshot;

  /// Filename-safe slug for the generated profile file.
  String get slug {
    final base = (name.isNotEmpty ? name : '$os-$release').toLowerCase();
    final b = StringBuffer();
    for (final r in base.runes) {
      final c = String.fromCharCode(r);
      if (RegExp('[a-z0-9-]').hasMatch(c)) {
        b.write(c);
      } else if (c == '_' || c == ' ' || c == '.') {
        b.write('-');
      }
    }
    final s = b.toString().replaceAll(RegExp('-+'), '-');
    return s.replaceAll(RegExp(r'^-|-$'), '');
  }

  /// TOML escaping for basic strings — control chars and quotes must
  /// not break the engine's parser even for hostile input.
  static String _q(String v) =>
      '"${v.replaceAll(r'\', r'\\').replaceAll('"', r'\"').replaceAll('\n', r'\n')}"';

  static String _arr(List<String> items) => '[${items.map(_q).join(', ')}]';

  /// The TOML document quickprovision loads. `[automation]` is only emitted
  /// when it carries a non-default value; verify checks become
  /// `[[verify]]` tables in declaration order.
  String toToml() {
    final b = StringBuffer()
      ..writeln('[profile]')
      ..writeln('name = ${_q(name.isNotEmpty ? name : slug)}');
    if (description.isNotEmpty) {
      b.writeln('description = ${_q(description)}');
    }
    b
      ..writeln()
      ..writeln('[system]')
      ..writeln('os = ${_q(os)}')
      ..writeln('release = ${_q(release)}');
    if (edition.isNotEmpty) b.writeln('edition = ${_q(edition)}');
    b.writeln('arch = ${_q(arch)}');
    b
      ..writeln()
      ..writeln('[machine]')
      ..writeln('cpus = $cpus')
      ..writeln('ram = ${_q(ram)}')
      ..writeln('disk_size = ${_q(diskSize)}')
      ..writeln()
      ..writeln('[identity]')
      ..writeln('hostname = ${_q(hostname.isNotEmpty ? hostname : slug)}')
      ..writeln('username = ${_q(username)}')
      ..writeln('allow_pw_auth = false');
    if (lang.isNotEmpty || timezone.isNotEmpty) {
      b
        ..writeln()
        ..writeln('[locale]');
      if (lang.isNotEmpty) b.writeln('lang = ${_q(lang)}');
      if (timezone.isNotEmpty) b.writeln('timezone = ${_q(timezone)}');
    }
    b
      ..writeln()
      ..writeln('[automation]');
    if (provider.isNotEmpty) b.writeln('provider = ${_q(provider)}');
    b.writeln('ssh_timeout_min = $sshTimeoutMin');
    if (installTimeoutMin != 45) {
      b.writeln('install_timeout_min = $installTimeoutMin');
    }
    if (packages.isNotEmpty || services.isNotEmpty) {
      b
        ..writeln()
        ..writeln('[provision]');
      if (packages.isNotEmpty) b.writeln('packages = ${_arr(packages)}');
      if (services.isNotEmpty) b.writeln('services = ${_arr(services)}');
    }
    for (final c in checks) {
      b
        ..writeln()
        ..writeln('[[verify]]')
        ..writeln('name = ${_q(c.name)}')
        ..writeln('run = ${_q(c.run)}');
      if (c.expect.isNotEmpty) b.writeln('expect = ${_q(c.expect)}');
    }
    b
      ..writeln()
      ..writeln('[finalize]')
      ..writeln('shutdown = $shutdown');
    if (snapshot.isNotEmpty) b.writeln('snapshot = ${_q(snapshot)}');
    return b.toString();
  }
}

/// A post-provision check — `run` executes over SSH in the guest and
/// passes when rc==0 and `expect` (when set) appears in the output.
class AutomationCheck {
  const AutomationCheck({
    required this.name,
    required this.run,
    this.expect = '',
  });

  final String name;
  final String run;
  final String expect;
}

/// The stock verify menu — checks that hold on every unattended path
/// the engine supports. POSIX syntax for Linux guests; PowerShell for
/// Windows (the unattend path installs OpenSSH with PowerShell as the
/// default shell); none for visual runs, which end at launch.
List<AutomationCheck> defaultChecks({
  required String hostname,
  required String os,
  List<String> packages = const [],
}) {
  if (os == 'macos') return const []; // visual install — nothing to check
  if (os.startsWith('windows')) {
    return [
      const AutomationCheck(name: 'ssh-alive', run: r'$true'),
      AutomationCheck(name: 'hostname', run: 'hostname', expect: hostname),
      const AutomationCheck(
        name: 'network-dns',
        run: r'(Resolve-DnsName example.com -ErrorAction SilentlyContinue) -ne $null',
      ),
      // tools-present skipped: winget IDs aren't executable names.
    ];
  }
  return [
    const AutomationCheck(name: 'ssh-alive', run: 'true'),
    AutomationCheck(name: 'hostname', run: 'hostname', expect: hostname),
    const AutomationCheck(name: 'network-dns', run: 'getent hosts example.com'),
    if (packages.isNotEmpty)
      AutomationCheck(
        name: 'tools-present',
        run: 'command -v ${packages.join(' && command -v ')}',
      ),
  ];
}
