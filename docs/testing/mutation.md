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


## Go tools campaign (quickemu repo)

Same procedure per tool - mutate, run that tool.s tests, restore.
Caution: git checkout <file> restores HEAD and discards ALL uncommitted
work in that file - stash or commit the refactor first.

| File | Mutant | Veredict |
|---|---|---|
| tools/quickemu-ports | stale() lease-expiry inverted | killed |
| tools/quickemu-ports | stale() drops !Alive(pid) | killed |
| tools/quickemu-toml | flat() drops section prefix | killed |
| tools/quickemu-archive | safeMember() drops ../ check | **survived - justified**: filepath.IsLocal() blocks the slip anyway (defence in depth) |

3/4 killed; the survivor is masked by a compensating control, not by a
missing test.

## In-process CLI coverage pattern (quickemu Go tools)

go test -cover only counts in-process execution, so each CLI was
refactored main() to run() int (die()/ok() return codes instead of
os.Exit) and a shared harness re-execs the instrumented test binary:

- TestMain checks QE_HELPER=1, rebuilds os.Args from QE_HELPER_ARGS,
  runs run() and writes the rc to QE_HELPER_RC.
- The helper MUST be marked by a dedicated non-empty flag - an empty
  args var must never imply helper mode (fork-bomb: the child would run
  the whole suite, which spawns more children).
- -test.run=^$ is passed as argv to the child as a second guard.
- Helper exit -1 means it died via die()/os.Exit mid-flow; its stdout
  envelope is still emitted before exit and stays assertable.
