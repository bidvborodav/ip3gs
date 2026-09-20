# Task 7 — Wire-up, real-device verification, docs

**Axis:** Rules. Closes the loop: real binaries plus a real device confirm the
assumed CLI contract from Tasks 2–4.

**Files:** modify `docs/` as findings land; modify
`Sources/ip3gs/DeviceBridge/DeviceBridge.swift` if the spike shows the assumed
contract is wrong.

**Produces:** nothing new. This task exists to convert assumptions into
observations — see [`../research.md`](../research.md) for the question list
it is meant to answer.

- [ ] **Step 1: setup and build**

```bash
brew install pkg-config                      # last missing autotools prerequisite
sudo xcode-select -s /Applications/Xcode-beta.app   # user must run this
./Tools/setup.sh
xcodegen generate
xcodebuild -project ip3gs.xcodeproj -scheme ip3gs -configuration Debug build
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 2: check the binaries are actually portable**

```bash
otool -L Tools/bin/afcclient Tools/bin/ideviceinfo
```

Any `/opt/homebrew/...` dylib reference means the app will not run on a clean
Mac. See [`../architecture.md`](../architecture.md#binary-resolution-and-portability).

- [ ] **Step 3: connect a real iPhone 3GS via USB and launch the app**

Expected: status bar reads "Trust this computer on the iPhone" on first
connect, then "N photos found" after trusting.

- [ ] **Step 4: work the research questions**

Run each probe in [`../research.md`](../research.md#how-to-settle-them) and
compare against the parsing logic in `DeviceBridge.swift`.

Where reality differs, fix the parsing **and** update the test fixtures. The
fakes encode the *assumed* contract; leaving them stale keeps the suite green
against a world that does not exist.

Pay particular attention to Q4 (binary payload through a `String` pipe) — if
downloaded files are corrupt or zero-length, that is the cause, and the fix
reaches back into Task 2's `ProcessRunning` signature.

- [ ] **Step 5: confirm the download**

```bash
ls ~/Pictures/ip3gs/
file ~/Pictures/ip3gs/*.JPG      # must report real JPEG data, not ASCII text
```

Expected: photo files present, matching the grid, and openable in Preview.

- [ ] **Step 6: fold findings back into the docs**

- Confirmed behavior → move from [`../research.md`](../research.md) into
  [`../domain.md`](../domain.md), dropping the **[assumed]** marker.
- Corrected behavior → update `domain.md`, the code, and the fixtures.
- Update [`README.md`](README.md) execution state and root `CLAUDE.md` if the
  build/run commands changed.

- [ ] **Step 7: commit** — `docs: confirm device wiring against real hardware`
