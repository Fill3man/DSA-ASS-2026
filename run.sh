#!/usr/bin/env bash
# ===========================================================================
#  DSA612S Assignment 1 - launcher (bash / Git Bash / macOS / Linux)
#
#    ./run.sh q1-service    Question 1 REST API      (http://localhost:9090)
#    ./run.sh q1-client     Question 1 CLI menu
#    ./run.sh q1-demo       Question 1 scripted demo
#    ./run.sh q2-server     Question 2 gRPC server   (localhost:9091)
#    ./run.sh q2-client     Question 2 CLI menu
#    ./run.sh q2-demo       Question 2 scripted demo
#    ./run.sh build         Build all four packages
#    ./run.sh doctor        Show which Ballerina it found
#
#  Locates the Ballerina CLI without relying on PATH, so it also works in a
#  terminal that was opened before Ballerina was installed.
#
#  It also sizes the JVMs it starts, so the server and the client can run at
#  the same time on a small machine. See the launch() notes below.
# ===========================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

find_bal() {
    if command -v bal >/dev/null 2>&1; then
        echo "bal"; return 0
    fi
    if [[ -n "${BALLERINA_HOME:-}" && -x "$BALLERINA_HOME/bin/bal" ]]; then
        echo "$BALLERINA_HOME/bin/bal"; return 0
    fi
    local candidate
    for candidate in \
        "/c/Program Files/Ballerina/bin/bal.bat" \
        "/c/Program Files (x86)/Ballerina/bin/bal.bat" \
        "$HOME/AppData/Local/Programs/Ballerina/bin/bal.bat" \
        "/usr/lib/ballerina/bin/bal" \
        "/usr/local/bin/bal" \
        "/Library/Ballerina/bin/bal"
    do
        if [[ -f "$candidate" ]]; then
            echo "$candidate"; return 0
        fi
    done
    return 1
}

if ! BAL="$(find_bal)"; then
    cat >&2 <<'EOF'

  Could not find the Ballerina CLI.

  Install Swan Lake 2201.13.5 from https://ballerina.io/downloads/
  then open a NEW terminal and run this script again.

EOF
    exit 1
fi

# The JVM that ships with Ballerina, found next to the CLI itself. Packages are
# started from their built jar on this JVM rather than through `bal run`; see
# launch() for why. Falls back to JAVA_HOME, then to whatever is on PATH.
find_java() {
    local balpath baldir root candidate
    balpath="$BAL"
    if [[ "$balpath" != */* ]]; then
        balpath="$(command -v "$BAL" 2>/dev/null || true)"
    fi
    if [[ -n "$balpath" ]]; then
        baldir="$(cd "$(dirname "$balpath")" && pwd)"
        root="$(cd "$baldir/.." && pwd)"
        for candidate in "$root"/dependencies/jdk-*/bin/java "$root"/dependencies/jdk-*/bin/java.exe; do
            if [[ -x "$candidate" ]]; then echo "$candidate"; return 0; fi
        done
    fi
    if [[ -n "${JAVA_HOME:-}" && -x "$JAVA_HOME/bin/java" ]]; then
        echo "$JAVA_HOME/bin/java"; return 0
    fi
    if command -v java >/dev/null 2>&1; then
        echo "java"; return 0
    fi
    return 1
}
JAVA="$(find_java || true)"

# Flags shared by every package we start. The defaults are the problem on a
# small machine: the JVM sizes its maximum heap at 1/4 of RAM and picks the G1
# collector, whose bookkeeping is committed up front. Two of those at once
# (server + client) exhaust the system commit limit.
#   -Xms16m                 start small and grow on demand
#   -XX:+UseSerialGC        no G1 region tables to commit; fine at this size
#   -XX:TieredStopAtLevel=1 C1 only, so the C2 compiler never allocates its
#                           arenas (the "Chunk::new" failure)
#   -XX:ReservedCodeCacheSize=64m  down from a 240m reservation
RUN_OPTS=(-Xms16m -XX:+UseSerialGC -XX:TieredStopAtLevel=1 -XX:ReservedCodeCacheSize=64m)

# launch <package dir> <package name> <max heap> [program args...]
#
# Rebuilds the package if a source file changed, then runs its jar on a JVM we
# size ourselves.
#
# Why not `bal run`: it compiles in one JVM (-Xms256m -Xmx2048m) and then starts
# the program in a second one, keeping the compiler JVM alive for as long as the
# program runs. Running a server and a client that way means four JVMs at once.
# Windows charges every JVM's committed heap against a system-wide commit limit
# (RAM + page file), and on a 6 GB machine that limit is hit before the program
# reaches main(), so it dies during startup with:
#
#     OpenJDK 64-Bit Server VM warning: INFO: os::commit_memory(...) failed;
#     error='The paging file is too small for this operation to complete'
#     # There is insufficient memory for the Java Runtime Environment to continue.
#     # Native memory allocation (mmap) failed ... Error detail: G1 virtual space
#
# Starting the jar directly drops both compiler JVMs and caps what is left.
# Nothing about the assignment code changes - `bal run` builds this same jar and
# then launches it exactly like this.
launch() {
    local dir="$1" pkg="$2" heap="$3"
    shift 3
    cd "$ROOT/$dir"
    local jar="target/bin/$pkg.jar"

    if [[ -z "$JAVA" ]]; then
        echo "  [note] No java found; falling back to \`bal run\`."
        if (( $# )); then "$BAL" run -- "$@"; else "$BAL" run; fi
        return $?
    fi

    # Build when the jar is missing, or when any .bal / Ballerina.toml is newer
    # than it - otherwise an edit would silently run as the previously built code.
    local stale=0
    if [[ ! -f "$jar" ]]; then
        stale=1
    elif [[ -n "$(find . -maxdepth 1 \( -name '*.bal' -o -name 'Ballerina.toml' \) -newer "$jar" -print -quit 2>/dev/null)" ]]; then
        stale=1
    fi

    if (( stale )); then
        echo "  Building $pkg (sources changed)..."
        # Leave the compiler its 2 GB ceiling - it needs the headroom - but move
        # it off G1 so its idle footprint is smaller. bal appends JAVA_OPTS after
        # its own flags, so this adds to the defaults rather than replacing them.
        JAVA_OPTS=-XX:+UseSerialGC "$BAL" build
        echo
    fi

    "$JAVA" -Xmx"$heap" "${RUN_OPTS[@]}" -jar "$jar" "$@"
}

case "${1:-help}" in
    doctor)
        echo
        echo "  Ballerina CLI : $BAL"
        echo "  JVM           : ${JAVA:-<none found>}"
        echo "  Run options   : ${RUN_OPTS[*]}"
        echo
        "$BAL" version
        ;;
    build)
        echo
        echo "  Building all four packages..."
        echo
        for pkg in \
            question1-library-api/asset_service \
            question1-library-api/asset_client \
            question2-rental-grpc/rental_server \
            question2-rental-grpc/rental_client
        do
            echo "  --- $pkg"
            (cd "$ROOT/$pkg" && JAVA_OPTS=-XX:+UseSerialGC "$BAL" build)
        done
        echo
        echo "  All four packages built."
        ;;
    q1-service)
        echo "  Starting the Question 1 REST API on http://localhost:9090"
        echo "  Web dashboard: http://localhost:9090/   Endpoint index: http://localhost:9090/library"
        echo "  Press Ctrl+C to stop."
        launch question1-library-api/asset_service asset_service 384m
        ;;
    q1-client) launch question1-library-api/asset_client asset_client 256m ;;
    q1-demo)   launch question1-library-api/asset_client asset_client 256m demo ;;
    q2-server)
        echo "  Starting the Question 2 gRPC server on localhost:9091"
        echo "  Press Ctrl+C to stop."
        launch question2-rental-grpc/rental_server rental_server 384m
        ;;
    q2-client) launch question2-rental-grpc/rental_client rental_client 256m ;;
    q2-demo)   launch question2-rental-grpc/rental_client rental_client 256m demo ;;
    *)
        cat <<EOF

  DSA612S Assignment 1
  Using Ballerina at: $BAL

  Question 1 - Library and Resource Management (REST)
    ./run.sh q1-service      start the API on http://localhost:9090
    ./run.sh q1-demo         scripted walk-through of every feature
    ./run.sh q1-client       interactive menu

  Question 2 - Rental Accommodation System (gRPC)
    ./run.sh q2-server       start the gRPC server on localhost:9091
    ./run.sh q2-demo         invoke all eight RPCs in order
    ./run.sh q2-client       interactive menu

  Other
    ./run.sh build           build all four packages
    ./run.sh doctor          show the Ballerina version in use

  Each question needs two terminals: the server in one, the client in the
  other. Start the server first and wait for it to report "seed data loaded".

EOF
        ;;
esac
