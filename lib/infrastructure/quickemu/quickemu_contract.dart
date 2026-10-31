/// Wire constants of the quickemu structured CLI contract (schemas/v1).
const String quickemuBinary = 'quickemu';
const String quickgetBinary = 'quickget';
const String quickreportBinary = 'quickreport';

/// The automation engine — a sibling of the quickemu toolchain that
/// quickgui shells out to for install/provision/verify runs.
const String quickprovisionBinary = 'quickprovision';

/// The old standalone `chunkcheck` helper is now a `quickget` subcommand.
const List<String> chunkcheckSubcommand = ['chunkcheck'];

const List<String> formatJsonArgs = ['--format', 'json'];
const List<String> capabilitiesArgs = ['--capabilities'];
const List<String> listVmsArgs = ['--list-vms'];

/// JSON keys of the v1 contract payloads.
const String contractKeyVms = 'vms';
const String contractKeyVmName = 'name';
