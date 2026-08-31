@echo off
setlocal EnableDelayedExpansion

rem ===========================================================================
rem  DSA612S Assignment 1 - launcher
rem
rem  Finds the Ballerina CLI without depending on your PATH, then runs one of
rem  the four packages. Use it from this directory:
rem
rem     run q1-service      Question 1 REST API        (http://localhost:9090)
rem     run q1-client       Question 1 CLI menu
rem     run q1-demo         Question 1 scripted demo
rem     run q2-server       Question 2 gRPC server     (localhost:9091)
rem     run q2-client       Question 2 CLI menu
rem     run q2-demo         Question 2 scripted demo
rem     run build           Build all four packages
rem     run doctor          Show which Ballerina it found
rem
rem  Why this exists: the Ballerina installer sets PATH to "%%BALLERINA_HOME%%\bin",
rem  which only resolves in a terminal started AFTER the install. A terminal (or
rem  VS Code window) opened beforehand still carries the old environment, so `bal`
rem  appears to be missing even though it is installed. This script looks the
rem  location up directly, so it works either way.
rem
rem  It also sizes the JVMs it starts, so the server and the client can run at
rem  the same time on a small machine. See the :launch notes at the bottom.
rem ===========================================================================

rem --- 1. bal already on PATH? ------------------------------------------------
set "BAL="
where bal.bat >nul 2>&1 && set "BAL=bal.bat"

rem --- 2. BALLERINA_HOME in this shell? ---------------------------------------
if not defined BAL if defined BALLERINA_HOME (
    if exist "%BALLERINA_HOME%\bin\bal.bat" set "BAL=%BALLERINA_HOME%\bin\bal.bat"
)

rem --- 3. BALLERINA_HOME as the installer persisted it (registry) -------------
rem     This is what rescues a stale terminal: the value is read from the system
rem     environment rather than from the one this process inherited.
if not defined BAL (
    for /f "tokens=2,*" %%A in (
        'reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v BALLERINA_HOME 2^>nul ^| findstr /i "BALLERINA_HOME"'
    ) do set "REGHOME=%%B"
    if defined REGHOME (
        rem Strip the type column and any trailing backslash the installer adds.
        for /f "tokens=1,*" %%A in ("!REGHOME!") do set "REGHOME=%%B"
        if "!REGHOME:~-1!"=="\" set "REGHOME=!REGHOME:~0,-1!"
        if exist "!REGHOME!\bin\bal.bat" set "BAL=!REGHOME!\bin\bal.bat"
    )
)

rem --- 4. the default install locations ---------------------------------------
if not defined BAL if exist "%ProgramFiles%\Ballerina\bin\bal.bat" set "BAL=%ProgramFiles%\Ballerina\bin\bal.bat"
if not defined BAL if exist "%ProgramFiles(x86)%\Ballerina\bin\bal.bat" set "BAL=%ProgramFiles(x86)%\Ballerina\bin\bal.bat"
if not defined BAL if exist "%LOCALAPPDATA%\Programs\Ballerina\bin\bal.bat" set "BAL=%LOCALAPPDATA%\Programs\Ballerina\bin\bal.bat"

if not defined BAL (
    echo.
    echo   Could not find the Ballerina CLI.
    echo.
    echo   Install Swan Lake 2201.13.5 from https://ballerina.io/downloads/
    echo   then open a NEW terminal and run this script again.
    echo.
    exit /b 1
)

rem --- 5. resolve bal.bat to a full path --------------------------------------
rem     Always invoke Ballerina through its full path. bal.bat locates its own
rem     bundled JRE with %%~sdp0, and that only yields a usable directory when
rem     the script was invoked by path. Called as a quoted bare name -
rem     `call "bal.bat"`, which is what step 1 leaves behind - %%~sdp0 comes back
rem     wrong, every `if exist ...\dependencies\jdk-*` test inside bal.bat fails
rem     and it quits with "Compatible JRE not found" even though the JRE is
rem     sitting right there. Resolving the name to a path first avoids that.
set "BALPATH=%BAL%"
if /i not "%BAL%"=="bal.bat" goto :balpath_done
set "BALPATH="
for /f "delims=" %%I in ('where bal.bat 2^>nul') do if not defined BALPATH set "BALPATH=%%I"
if not defined BALPATH set "BALPATH=%BAL%"
:balpath_done

rem --- 6. the JVM that ships with Ballerina -----------------------------------
rem     Packages are started from their built jar on this JVM instead of through
rem     `bal run`; :launch at the bottom explains why. Resolve it from wherever
rem     bal.bat turned out to be, then fall back to JAVA_HOME or PATH.
set "JAVA="
for %%I in ("%BALPATH%") do set "BALBIN=%%~dpI"
for /d %%D in ("%BALBIN%..\dependencies\jdk-*") do if exist "%%~fD\bin\java.exe" set "JAVA=%%~fD\bin\java.exe"
if not defined JAVA if defined JAVA_HOME if exist "%JAVA_HOME%\bin\java.exe" set "JAVA=%JAVA_HOME%\bin\java.exe"
if not defined JAVA for /f "delims=" %%I in ('where java 2^>nul') do if not defined JAVA set "JAVA=%%I"

rem     Flags shared by every package we start. The defaults are the problem on
rem     a small machine: the JVM sizes its maximum heap at 1/4 of RAM and picks
rem     the G1 collector, whose bookkeeping is committed up front. Two of those
rem     at once (server + client) exhaust the Windows commit limit.
rem       -Xms16m                 start small and grow on demand
rem       -XX:+UseSerialGC        no G1 region tables to commit; fine at this size
rem       -XX:TieredStopAtLevel=1 C1 only, so the C2 compiler never allocates its
rem                               arenas (the "Chunk::new" failure)
rem       -XX:ReservedCodeCacheSize=64m  down from a 240m reservation
set "RUN_OPTS=-Xms16m -XX:+UseSerialGC -XX:TieredStopAtLevel=1 -XX:ReservedCodeCacheSize=64m"

set "ROOT=%~dp0"
set "TARGET=%~1"
if "%TARGET%"=="" set "TARGET=help"

if /i "%TARGET%"=="doctor" (
    echo.
    echo   Ballerina CLI : %BALPATH%
    echo   JVM           : %JAVA%
    echo   Run options   : %RUN_OPTS%
    echo.
    call "%BALPATH%" version
    exit /b !ERRORLEVEL!
)

if /i "%TARGET%"=="build" (
    echo.
    echo   Building all four packages...
    echo.
    rem  Leave the compiler its 2 GB ceiling - it needs the headroom - but move
    rem  it off G1 so its idle footprint is smaller. bal.bat appends JAVA_OPTS
    rem  after its own flags, so this adds to the defaults rather than replacing
    rem  them. Scoped to this script by setlocal; your shell is untouched.
    set "JAVA_OPTS=-XX:+UseSerialGC"
    for %%P in (
        "question1-library-api\asset_service"
        "question1-library-api\asset_client"
        "question2-rental-grpc\rental_server"
        "question2-rental-grpc\rental_client"
    ) do (
        echo   --- %%~P
        pushd "%ROOT%%%~P" || exit /b 1
        call "%BALPATH%" build || (popd & exit /b 1)
        popd
    )
    echo.
    echo   All four packages built.
    exit /b 0
)

if /i "%TARGET%"=="q1-service" (
    echo   Starting the Question 1 REST API on http://localhost:9090
    echo   Web dashboard: http://localhost:9090/    Endpoint index: http://localhost:9090/library
    echo   Press Ctrl+C to stop.
    call :launch "question1-library-api\asset_service" asset_service 384m ""
    exit /b !ERRORLEVEL!
)

if /i "%TARGET%"=="q1-client" (
    call :launch "question1-library-api\asset_client" asset_client 256m ""
    exit /b !ERRORLEVEL!
)

if /i "%TARGET%"=="q1-demo" (
    call :launch "question1-library-api\asset_client" asset_client 256m "demo"
    exit /b !ERRORLEVEL!
)

if /i "%TARGET%"=="q2-server" (
    echo   Starting the Question 2 gRPC server on localhost:9091
    echo   Press Ctrl+C to stop.
    call :launch "question2-rental-grpc\rental_server" rental_server 384m ""
    exit /b !ERRORLEVEL!
)

if /i "%TARGET%"=="q2-client" (
    call :launch "question2-rental-grpc\rental_client" rental_client 256m ""
    exit /b !ERRORLEVEL!
)

if /i "%TARGET%"=="q2-demo" (
    call :launch "question2-rental-grpc\rental_client" rental_client 256m "demo"
    exit /b !ERRORLEVEL!
)

echo.
echo   DSA612S Assignment 1
echo   Using Ballerina at: %BALPATH%
echo.
echo   Question 1 - Library and Resource Management (REST)
echo     run q1-service      start the API on http://localhost:9090
echo     run q1-demo         scripted walk-through of every feature
echo     run q1-client       interactive menu
echo.
echo   Question 2 - Rental Accommodation System (gRPC)
echo     run q2-server       start the gRPC server on localhost:9091
echo     run q2-demo         invoke all eight RPCs in order
echo     run q2-client       interactive menu
echo.
echo   Other
echo     run build           build all four packages
echo     run doctor          show the Ballerina version in use
echo.
echo   Each question needs two terminals: the server in one, the client in the
echo   other. Start the server first and wait for it to report "seed data loaded".
echo.
exit /b 0

rem ===========================================================================
rem  :launch <package dir> <package name> <max heap> <program args>
rem
rem  Rebuilds the package if a source file changed, then runs its jar on a JVM
rem  we size ourselves.
rem
rem  Why not `bal run`: it compiles in one JVM (-Xms256m -Xmx2048m) and then
rem  starts the program in a second one, keeping the compiler JVM alive for as
rem  long as the program runs. Running a server and a client that way means four
rem  JVMs at once. Windows charges every JVM's committed heap against a
rem  system-wide commit limit (RAM + page file), and on a 6 GB machine that limit
rem  is hit before the program reaches main(), so it dies during startup with:
rem
rem      OpenJDK 64-Bit Server VM warning: INFO: os::commit_memory(...) failed;
rem      error='The paging file is too small for this operation to complete'
rem      # There is insufficient memory for the Java Runtime Environment to continue.
rem      # Native memory allocation (mmap) failed ... Error detail: G1 virtual space
rem
rem  Starting the jar directly drops both compiler JVMs and caps what is left.
rem  Nothing about the assignment code changes - `bal run` builds this same jar
rem  and then launches it exactly like this.
rem ===========================================================================
:launch
setlocal EnableDelayedExpansion
set "PKGDIR=%~1"
set "PKGNAME=%~2"
set "MAXHEAP=%~3"
set "PROGARGS=%~4"

pushd "%ROOT%%PKGDIR%" || exit /b 1
set "JAR=target\bin\%PKGNAME%.jar"

rem No JVM to be found - use `bal run` so the script still does something useful.
if not defined JAVA (
    echo   [note] No java.exe found; falling back to `bal run`.
    if "%PROGARGS%"=="" (call "%BALPATH%" run) else (call "%BALPATH%" run -- %PROGARGS%)
    set "CODE=!ERRORLEVEL!"
    popd
    endlocal & exit /b %CODE%
)

rem Build when the jar is missing, or when any .bal / Ballerina.toml is newer
rem than it - otherwise an edit would silently run as the previously built code.
if not exist "%JAR%" goto :launch_build
powershell -NoProfile -ExecutionPolicy Bypass -Command "$j=(Get-Item -LiteralPath '%JAR%').LastWriteTime; $c=@(Get-ChildItem -File -Path '.\*' -Include '*.bal','Ballerina.toml').Where({$_.LastWriteTime -gt $j}).Count; exit [int]($c -gt 0)"
if not errorlevel 1 goto :launch_run

:launch_build
echo   Building %PKGNAME% (sources changed)...
set "JAVA_OPTS=-XX:+UseSerialGC"
call "%BALPATH%" build
set "CODE=!ERRORLEVEL!"
set "JAVA_OPTS="
if not "!CODE!"=="0" (
    popd
    endlocal & exit /b %CODE%
)
echo.

:launch_run
"%JAVA%" -Xmx%MAXHEAP% %RUN_OPTS% -jar "%JAR%" %PROGARGS%
set "CODE=!ERRORLEVEL!"
popd
endlocal & exit /b %CODE%
