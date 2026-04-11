@echo off
setlocal

rem Build FreeSWITCH minimal PTT solution filter on Windows
rem Usage:
rem   build-ptt-minimal.cmd [Debug|Release] [Win32|x64]

set configuration=Release
set platform=x64

if not "%~1"=="" set configuration=%~1
if not "%~2"=="" set platform=%~2

set procs=%NUMBER_OF_PROCESSORS%
set /a procs-=1
if %procs% LSS 1 set procs=1

call msbuild.cmd

if not exist %msbuild% (
  echo ERROR: Cannot find msbuild. Please install Visual Studio with MSBuild workload.
  exit /b 1
)

echo Building Freeswitch.PTT.Minimal.2017.slnf with %configuration% ^| %platform% ...
%msbuild% Freeswitch.PTT.Minimal.2017.slnf /m:%procs% /verbosity:minimal /property:Configuration=%configuration% /property:Platform=%platform% /fl /flp:logfile=ptt-minimal-%platform%-%configuration%.log;verbosity=normal

if errorlevel 1 (
  echo Build failed. Check log: ptt-minimal-%platform%-%configuration%.log
  exit /b 1
)

echo Build succeeded.
exit /b 0
