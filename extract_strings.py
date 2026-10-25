import re, glob

pot = open('assets/translations/quickgui.pot', encoding='utf-8').read()
pot_ids = set(re.findall(r'msgid "(.*)"', pot))
used = set()
pat = re.compile(r"""context\.t\(\s*'((?:[^'\\]|\\.)*)'""")
for f in glob.glob('lib/**/*.dart', recursive=True):
    src = open(f, encoding='utf-8').read()
    for m in pat.finditer(src):
        used.add(m.group(1))
missing = sorted(used - pot_ids)
with open('missing_strings.txt', 'w', encoding='utf-8') as fh:
    fh.write('\n'.join(missing))
print(len(missing))
