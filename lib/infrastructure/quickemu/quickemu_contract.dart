/// Wire constants of the quickemu structured CLI contract (schemas/v1).
const String quickemuBinary = 'quickemu';
const String quickgetBinary = 'quickget';
const String quickreportBinary = 'quickreport';
/// The old standalone `chunkcheck` helper is now a `quickget` subcommand.
const List<String> chunkcheckSubcommand = ['chunkcheck'];

const List<String> formatJsonArgs = ['--format', 'json'];
const List<String> capabilitiesArgs = ['--capabilities'];
const List<String> listVmsArgs = ['--list-vms'];

/// JSON keys of the v1 contract payloads.
const String contractKeyVms = 'vms';
const String contractKeyVmName = 'name';
