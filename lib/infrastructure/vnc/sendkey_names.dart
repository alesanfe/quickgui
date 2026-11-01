// QEMU sendkey name mapping for typed characters — parity with the
// `--type` loop in the quickemu CLI. Extracted from vm_console_page.

/// Maps a typed character to a QEMU `sendkey` name — parity with the
/// `--type` loop in the Go CLI (letters/digits literal, shifted
/// punctuation named, uppercase via `shift-`).
String keyName(String ch) {
  const named = {
    ' ': 'spc',
    '!': 'shift-1',
    '@': 'shift-2',
    '#': 'shift-3',
    r'$': 'shift-4',
    '%': 'shift-5',
    '^': 'shift-6',
    '&': 'shift-7',
    '*': 'shift-8',
    '(': 'shift-9',
    ')': 'shift-0',
    '-': 'minus',
    '_': 'shift-minus',
    '=': 'equal',
    '+': 'shift-equal',
    '[': 'bracket_left',
    ']': 'bracket_right',
    '{': 'shift-bracket_left',
    '}': 'shift-bracket_right',
    ';': 'semicolon',
    ':': 'shift-semicolon',
    "'": 'apostrophe',
    '"': 'shift-apostrophe',
    '`': 'grave_accent',
    '~': 'shift-grave_accent',
    r'\': 'backslash',
    '|': 'shift-backslash',
    ',': 'comma',
    '<': 'shift-comma',
    '.': 'dot',
    '>': 'shift-dot',
    '/': 'slash',
    '?': 'shift-slash',
    '\n': 'ret',
    '\t': 'tab',
  };
  if (named.containsKey(ch)) return named[ch]!;
  if (RegExp(r'^[a-z0-9]$').hasMatch(ch)) return ch;
  if (RegExp(r'^[A-Z]$').hasMatch(ch)) return 'shift-${ch.toLowerCase()}';
  return 'spc';
}
