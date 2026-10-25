/// A reusable resource preset applied when customising a new VM.
/// Values map to quickemu .conf keys.
class VmProfile {
  const VmProfile({
    required this.id,
    required this.name,
    required this.description,
    this.ram = '',
    this.cpuCores = '',
    this.diskSize = '',
    this.extraConf = const {},
  });

  final String id;
  final String name;
  final String description;
  final String ram;
  final String cpuCores;
  final String diskSize;

  /// Extra .conf keys the profile sets (e.g. tpm/secureboot for Windows).
  final Map<String, String> extraConf;

  /// All values as conf entries (empty values are skipped).
  Map<String, String> toConf() => {
    if (ram.isNotEmpty) 'ram': ram,
    if (cpuCores.isNotEmpty) 'cpu_cores': cpuCores,
    if (diskSize.isNotEmpty) 'disk_size': diskSize,
    ...extraConf,
  };
}

/// Built-in profiles offered in the customisation dialog. "custom"
/// leaves every field as the user left it.
const vmProfiles = <VmProfile>[
  VmProfile(
    id: 'custom',
    name: 'Custom',
    description: 'Choose every resource yourself.',
  ),
  VmProfile(
    id: 'light',
    name: 'Lightweight Linux',
    description: 'Minimal resources for server or lightweight guests.',
    ram: '2G',
    cpuCores: '2',
    diskSize: '32G',
  ),
  VmProfile(
    id: 'desktop',
    name: 'Linux desktop',
    description: 'Balanced resources for a graphical Linux guest.',
    ram: '4G',
    cpuCores: '4',
    diskSize: '64G',
  ),
  VmProfile(
    id: 'windows',
    name: 'Windows 11',
    description: 'TPM 2.0 and secure boot for Windows 11 guests.',
    ram: '8G',
    cpuCores: '4',
    diskSize: '128G',
    extraConf: {'tpm': 'on', 'secureboot': 'on'},
  ),
  VmProfile(
    id: 'macos',
    name: 'macOS',
    description: 'macOS guests need more disk for the installer.',
    ram: '4G',
    cpuCores: '2',
    diskSize: '80G',
  ),
  VmProfile(
    id: 'dev',
    name: 'Development',
    description: 'Extra CPU and RAM for builds and toolchains.',
    ram: '8G',
    cpuCores: '8',
    diskSize: '128G',
  ),
  VmProfile(
    id: 'lab',
    name: 'Lab / testing',
    description: 'Isolated networking for disposable test machines.',
    ram: '4G',
    cpuCores: '2',
    diskSize: '64G',
    extraConf: {'network': 'restrict'},
  ),
];

/// Suggested default resources for an OS family, used to prefill the
/// customisation dialog. Deliberately conservative; quickemu applies
/// its own minimums when fields are left empty.
VmProfile recommendedProfileFor(String osCode) {
  if (osCode.startsWith('windows')) {
    return vmProfiles.firstWhere((p) => p.id == 'windows');
  }
  if (osCode == 'macos') {
    return vmProfiles.firstWhere((p) => p.id == 'macos');
  }
  if (const [
    'ubuntu',
    'fedora',
    'debian',
    'archlinux',
    'opensuse',
    'popos',
    'kubuntu',
    'xubuntu',
    'ubuntu-mate',
    'ubuntu-budgie',
    'ubuntukylin',
    'ubuntustudio',
    'linuxmint',
    'zorin',
    'elementary',
    'endeavouros',
    'manjaro',
    'garuda',
    'kde-neon',
    'cachyos',
  ].contains(osCode)) {
    return vmProfiles.firstWhere((p) => p.id == 'desktop');
  }
  return vmProfiles.firstWhere((p) => p.id == 'light');
}
