# FreeSWITCH PTT Demo Reference Workflow

## 1. Feasibility Analysis

Use this phase when the user asks whether FreeSWITCH can satisfy a training intercom requirement.

Checklist:
- Confirm grouping model: site, channel, isolation, membership.
- Confirm call mode: conference-based grouping for group-internal audio and group separation.
- Confirm required capabilities: recording, log correlation, third-party API, bot replies, startup/build/test procedure.
- Map each requirement to an existing FreeSWITCH capability or a small companion service.

Expected conclusion for this repository:
- FreeSWITCH is suitable for the media/control plane.
- A lightweight companion API service handles log aggregation, recordings lookup, and bot response APIs.

## 2. Demo Implementation Surface

Primary files:
- `conf/vanilla/dialplan/default/20_ptt_training_demo.xml`
- `scripts/python/ptt_demo/ptt_demo_service.py`
- `scripts/python/ptt_demo/requirements.txt`
- `scripts/python/ptt_demo/generate_bot_audio.ps1`
- `scripts/python/ptt_demo/generate_bot_audio_linux.sh`
- `docs/ptt-training-demo.md`

Implementation expectations:
- Route short dial strings to site/channel conference rooms.
- Export room/site/channel variables for logging.
- Start recording on answer.
- Expose API endpoints for health, logs, recording fetch, and bot reply triggers.
- Keep Windows and Linux helper scripts aligned.

## 3. Windows Minimal Build

Preferred assets:
- `Freeswitch.PTT.Minimal.2017.slnf`
- `build-ptt-minimal.cmd`
- `docs/ptt-vs-minimal-build.md`

Procedure:
1. Build the minimal solution first.
2. If build fails, inspect the first blocking compiler/linker error.
3. Fix root-cause compatibility issues locally and rerun the same minimal build.
4. Do not widen to the full solution unless the user explicitly needs more modules.

Known compatibility themes already handled in this repo:
- enum-to-enum explicit casts required by new MSVC
- legacy typedef collisions with modern MSVC stdint support
- legacy `inline` compatibility in vendored libs colliding with modern Windows SDK headers

## 4. Linux Minimal Build

Preferred assets:
- `build/modules.conf.ptt.minimal`
- `build-ptt-minimal-linux.sh`
- `docs/ptt-linux-minimal-build.md`

Procedure:
1. Swap in minimal modules.
2. Run bootstrap/configure/make/install.
3. Restore original `modules.conf` unless explicitly told to keep it.

## 5. Demo Runtime Validation

Windows runtime:
- Start `x64/Release/FreeSwitchConsole.exe`
- Verify ESL: `Test-NetConnection 127.0.0.1 -Port 8021`
- Run `scripts/python/ptt_demo/run_demo.ps1`
- Smoke test with `scripts/python/ptt_demo/api_smoke_test.ps1`

Linux runtime:
- Run `scripts/python/ptt_demo/run_demo_linux.sh`
- Optional systemd install: `scripts/python/ptt_demo/install_systemd_service.sh`
- Smoke test with `scripts/python/ptt_demo/api_smoke_test_linux.sh`

Pass conditions:
- FreeSWITCH starts successfully.
- Port 8021 listens.
- API health endpoint returns success.
- Bot reply endpoint works.
- Logs and recordings endpoints return expected data after test calls.

## 6. Demo Output Materials

Existing delivery assets:
- `docs/ptt-training-demo.md`
- `docs/ptt-training-live-script.md`
- `docs/ptt-training-exec-5min.md`
- `docs/ptt-vs-minimal-build.md`
- `docs/ptt-linux-minimal-build.md`

When the user asks for presentation or operations content:
- reuse these docs first
- extend rather than duplicate unless a different audience is required

## 7. Working Rules For This Skill

- Prefer the smallest runnable path.
- Reuse existing files in this repository before adding new ones.
- Keep Windows and Linux workflows symmetric when adding helper scripts.
- After the first substantive code fix, run the narrowest possible validation.
- If the user asks for full end-to-end execution, proceed in this order: build, start FreeSWITCH, verify 8021, start API, run smoke test, then optional SIP handset validation.
