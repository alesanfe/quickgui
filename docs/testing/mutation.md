# Manual mutation testing

No mutation framework is wired into CI, so mutants are applied by hand on
the highest-risk files, one at a time:

1. Pick a behavioural decision (boundary, inversion, dropped guard).
2. Apply it with `sed`/`git` on the production file.
3. Run the file's targeted tests — the suite must fail (**killed**) or the
   mutant **survived** and a gap exists.
4. `git checkout` the file and pin the contract with a new test when a
   mutant survives.

## Results

### `lib/infrastructure/quickemu/quickemu_response.dart` (envelope parser)

| Mutant | Veredict | Fix |
|---|---|---|
| `schemaVersion > max` → `>=` | killed | existing v1 tests |
| `success == true` → permissive | survived | fail-closed test added |
| `EMPTY_RESPONSE` check removed | survived | explicit EMPTY vs MALFORMED test |
| `schemaVersion is! int` → `is! num` | survived | fractional-version test |
| `INSUFFICIENT_SPACE` mapping removed | killed | `toFailure` mapping test |
| non-Map message items unfiltered | survived | invalid-item tolerance test |

### `lib/infrastructure/storage/vm_config.dart` (atomic conf store)

| Mutant | Veredict | Fix |
|---|---|---|
| backup rotation `i >= 0` → `i > 0` | killed | rotation test |
| rotation boundary `>` → `>=` | killed | rotation test |
| symlink check `!= link` → `== link` | killed | symlink tests |
| `!replaced` → `replaced` | killed | write tests |
| `break` removed (replace all dup keys) | survived | first-match contract test |

11 mutants, 7 killed outright, 4 survivors → 7 pinning tests added. Both
files now fail closed under every mutant tried.
