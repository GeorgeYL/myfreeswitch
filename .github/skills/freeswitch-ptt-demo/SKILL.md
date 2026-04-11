---
name: freeswitch-ptt-demo
description: 'Analyze, implement, build, test, and run a FreeSWITCH PTT training demo on Windows or Linux. Use when asked to assess feasibility, create a PTT/intercom demo, generate dialplan/API/scripts/docs, produce demo runbooks, fix Windows VS2022/MSVC build blockers, create minimal build workflows, or run smoke tests for the training intercom solution.'
argument-hint: 'Describe the desired phase, e.g. feasibility, scaffold demo, build windows, build linux, run demo, or full end-to-end.'
user-invocable: true
disable-model-invocation: false
---

# FreeSWITCH PTT Demo Workflow

This skill packages the repeatable workflow for the training intercom demo built in this repository.

## When to Use
- Analyze whether a training PTT/intercom requirement can be implemented with FreeSWITCH.
- Scaffold or update the demo for grouped half/full duplex talk channels, recordings, logs, bot replies, and external APIs.
- Build the Windows minimal solution or Linux minimal module set.
- Run the Python demo API, smoke tests, and startup scripts.
- Repair common VS2022/MSVC compatibility issues encountered while building this repo.
- Generate operator docs, live demo scripts, and short executive presentation flows.

## Repository Artifacts Used By This Skill
- Main demo guide: `docs/ptt-training-demo.md`
- Windows minimal build guide: `docs/ptt-vs-minimal-build.md`
- Linux minimal build guide: `docs/ptt-linux-minimal-build.md`
- Dialplan demo entry: `conf/vanilla/dialplan/default/20_ptt_training_demo.xml`
- Demo API: `scripts/python/ptt_demo/ptt_demo_service.py`
- Windows runner: `scripts/python/ptt_demo/run_demo.ps1`
- Linux runner: `scripts/python/ptt_demo/run_demo_linux.sh`
- Windows minimal build script: `build-ptt-minimal.cmd`
- Linux minimal build script: `build-ptt-minimal-linux.sh`

## Procedure
1. Read the requested phase and map it to one of: feasibility, implementation, build, smoke test, runbook, or end-to-end.
2. Load the detailed procedure from [workflow reference](./references/workflow.md).
3. Reuse existing demo files first; extend them instead of creating parallel variants unless the user asks for a separate mode.
4. For Windows builds, prefer the minimal solution filter and focused validation before wider fixes.
5. For Linux builds, prefer the minimal modules workflow and one-click run scripts.
6. If the build fails, fix the concrete first blocker and rerun the narrowest validation immediately.
7. Finish with executable validation when the environment allows it.

## Output Expectations
- If asked for analysis, provide a clear feasibility conclusion and the smallest viable architecture.
- If asked for implementation, update config/code/docs/scripts together so the demo is runnable.
- If asked for build help, prefer the minimal build path first.
- If asked for testing or execution, include exact commands and expected pass conditions.

## References
- [Workflow Reference](./references/workflow.md)

## Templates
- [Feasibility Template](./assets/feasibility-template.md)
- [Build Triage Template](./assets/build-triage-template.md)
- [Acceptance Checklist](./assets/acceptance-checklist.md)
