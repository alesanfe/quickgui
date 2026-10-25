/// Wire constants of the quickemu structured CLI contract (schemas/v1).
const String quickemuBinary = 'quickemu';
const String quickgetBinary = 'quickget';
const String quickreportBinary = 'quickreport';
const String chunkcheckBinary = 'chunkcheck';

const List<String> formatJsonArgs = ['--format', 'json'];
const List<String> capabilitiesArgs = ['--capabilities'];
const List<String> listVmsArgs = ['--list-vms'];

/// JSON keys of the v1 contract payloads.
const String contractKeyVms = 'vms';
const String contractKeyVmName = 'name';
