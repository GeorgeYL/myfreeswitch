# PTT Demo Acceptance Checklist

## Build
- [ ] Windows minimal build succeeds
- [ ] Linux minimal build succeeds

## FreeSWITCH Runtime
- [ ] FreeSwitchConsole or freeswitch starts successfully
- [ ] `mod_event_socket` loads
- [ ] Port 8021 listens
- [ ] Dialplan file is loaded

## Demo API
- [ ] Health endpoint passes
- [ ] Logs endpoint passes
- [ ] Bot reply endpoint passes
- [ ] Recording lookup endpoint passes

## Functional Demo
- [ ] Site/channel routing works
- [ ] Group isolation works
- [ ] Recording file is created
- [ ] Call metadata is correlated
- [ ] Bot audio can be triggered

## Presentation Assets
- [ ] Technical runbook available
- [ ] Live demo script available
- [ ] Executive 5-minute script available
