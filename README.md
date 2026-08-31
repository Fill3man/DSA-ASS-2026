# DSA612S — Assignment 1

Distributed Systems and Applications · Namibia University of Science and Technology

Two independent distributed systems, both written in **Ballerina** (Swan Lake `2201.13.5`):

| | System | Style | Marks |
|---|---|---|---|
| **Question 1** | [Distributed Library and Resource Management System](question1-library-api/) | RESTful API + CLI client + web dashboard | 50 (+10 bonus) |
| **Question 2** | [Rental Accommodation System](question2-rental-grpc/) | gRPC, 8 RPCs incl. client- and server-streaming | 50 |

Each question lives in its own directory with its own README, and each is made up of
two runnable Ballerina packages — a server and a client — so the two processes
communicate over the network exactly as a distributed system should.

---

## Repository layout

```
.
├── README.md                          this file
├── run.cmd                            launcher (PowerShell / cmd)
├── run.sh                             launcher (bash / Git Bash / macOS / Linux)
├── .gitignore
│
├── question1-library-api/
│   ├── README.md                      API reference, run instructions, rubric map
│   ├── asset_service/                 Ballerina HTTP service (port 9090)
│   │   ├── types.bal                  domain model + request/response records
│   │   ├── errors.bal                 distinct error types
│   │   ├── util.bal                   ISO-8601 date arithmetic
│   │   ├── store.bal                  table<Asset> key(assetTag) + institutions
│   │   ├── operations.bal             components, schedules, work orders, loans, reports
│   │   ├── service.bal                the REST resources + status-code mapping
│   │   ├── ui_service.bal             serves the web dashboard (bonus)
│   │   ├── catalogue.bal              self-describing endpoint index
│   │   ├── seed.bal                   demonstration data
│   │   └── resources/index.html       the web dashboard (bonus)
│   └── asset_client/                  Ballerina CLI client
│       ├── models.bal                 client-side bindings
│       ├── api.bal                    typed HTTP wrapper
│       ├── views.bal                  console rendering
│       └── main.bal                   interactive menu + scripted demo
│
└── question2-rental-grpc/
    ├── README.md                      RPC reference, run instructions, rubric map
    ├── proto/rental.proto             the service contract
    ├── rental_server/                 Ballerina gRPC service (port 9091)
    │   ├── rental_pb.bal              generated from rental.proto
    │   ├── util.bal                   date/money helpers
    │   ├── store.bal                  in-memory state, one isolated variable
    │   ├── service.bal                the eight remote functions
    │   └── seed.bal                   demonstration data
    └── rental_client/                 Ballerina gRPC client
        ├── rental_pb.bal              generated from rental.proto
        ├── views.bal                  console rendering + gRPC status decoding
        └── main.bal                   interactive menu + scripted demo
```

---

## Prerequisites

- **Ballerina Swan Lake 2201.13.5** — <https://ballerina.io/downloads/>
- **JDK 21** (bundled with the Ballerina installer; only needed separately if you
  use the plain `.zip` distribution)

Check your install:

```bash
bal version
```

A different Swan Lake update should still work; `bal` will warn that the
`distribution` in `Ballerina.toml` does not match and carry on.

---

## Running everything

Each question needs **two terminals** — one for the server, one for the client.
Start the server first and wait for it to log `seed data loaded`.

### The easy way — the launcher

Run these **from the repository root**. The launcher locates the Ballerina CLI
itself, so it works even when `bal` is not on your PATH.

PowerShell — note the leading `.\`:

```powershell
.\run.cmd doctor            show which Ballerina it found

.\run.cmd q1-service        Terminal 1  — REST API on http://localhost:9090
.\run.cmd q1-demo           Terminal 2  — scripted walk-through of every feature
.\run.cmd q1-client         Terminal 2  — interactive menu

.\run.cmd q2-server         Terminal 1  — gRPC server on localhost:9091
.\run.cmd q2-demo           Terminal 2  — invokes all eight RPCs in order
.\run.cmd q2-client         Terminal 2  — interactive menu

.\run.cmd build             build all four packages
```

Git Bash, macOS or Linux — same targets, `./run.sh` instead:

```bash
./run.sh doctor
./run.sh q1-service
./run.sh q1-demo
```

Both scripts print the full list of targets if you run them with no arguments.

### Or call `bal` directly

```bash
# Question 1 — Terminal 1 / Terminal 2
cd question1-library-api/asset_service  && bal run
cd question1-library-api/asset_client   && bal run -- demo    # or: bal run

# Question 2 — Terminal 1 / Terminal 2
cd question2-rental-grpc/rental_server  && bal run
cd question2-rental-grpc/rental_client  && bal run -- demo    # or: bal run
```

Then open **<http://localhost:9090/>** for the web dashboard (the bonus
deliverable), and **<http://localhost:9090/library>** for a JSON index of every
endpoint.

Both questions can run at the same time — Q1 uses port 9090 and Q2 uses 9091.

> Run `bal run` from inside the package directory. Question 1 reads
> `resources/index.html` relative to the working directory to serve the dashboard.
> `run.cmd` handles this for you.

> On a machine with little RAM, prefer the launcher. `bal run` keeps its 2 GB-max
> compiler JVM alive alongside the program, so a server and a client together can
> overrun the Windows commit limit and die at startup with *"The paging file is
> too small for this operation to complete"*. See
> [Troubleshooting](#troubleshooting).

---

## Troubleshooting

**`bal : The term 'bal' is not recognized...`**

Ballerina is probably installed fine — the terminal just cannot see it. The
installer adds `%BALLERINA_HOME%\bin` to the system PATH, which only resolves in a
terminal started *after* the install. A terminal — or a VS Code window — opened
beforehand still carries the old environment.

Three ways out, in order of preference:

1. Quit VS Code **completely** and reopen it. Opening a new integrated terminal is
   not enough — it inherits VS Code's environment.
2. Use `.\run.cmd` / `./run.sh`, which look the location up directly and do not
   care about PATH.
3. Fix just the terminal you have open:

   ```powershell
   $env:PATH = "C:\Program Files\Ballerina\bin;$env:PATH"
   bal version
   ```

`C:\Program Files\Ballerina\bin` has also been added to the User PATH as a literal
path, so new terminals resolve `bal` without depending on `%BALLERINA_HOME%` being
expanded. Check with `where bal` (cmd/PowerShell) or `which bal` (bash).

**Navigating the project from the terminal**

```powershell
cd "C:\Users\Matti\Desktop\DSA Assignment"     # repository root — run the launcher from here
cd question1-library-api\asset_service          # Q1 API      — bal run
cd question1-library-api\asset_client           # Q1 client   — bal run -- demo
cd question2-rental-grpc\rental_server          # Q2 server   — bal run
cd question2-rental-grpc\rental_client          # Q2 client   — bal run -- demo
cd ..\..                                        # back to the root
```

`bal run` must be issued from inside one of those four package directories — a
Ballerina package is the directory containing `Ballerina.toml`. The launcher
targets exist so you do not have to remember which is which.

**`The paging file is too small for this operation to complete`**

```
OpenJDK 64-Bit Server VM warning: INFO: os::commit_memory(...) failed;
error='The paging file is too small for this operation to complete'
# There is insufficient memory for the Java Runtime Environment to continue.
# Native memory allocation (mmap) failed ... Error detail: G1 virtual space
# An error report file with more information is saved as: ...\hs_err_pid<n>.log
```

The program never reached `main()` — the JVM could not reserve its heap at
startup. This is not about free RAM; Windows enforces a system-wide *commit
limit* (RAM + page file) and charges every JVM's committed heap against it.

`bal run` is expensive here because it compiles in one JVM (`-Xmx2048m`) and then
starts the program in a second one, **keeping the compiler JVM alive for as long
as the program runs**. A server plus a client is four JVMs, and each one sizes its
maximum heap at 1/4 of RAM by default and picks the G1 collector, whose
bookkeeping is committed up front.

Use `.\run.cmd` / `./run.sh` instead of `bal run`. They build once and then start
the package's jar directly, which drops both compiler JVMs and sizes the two that
remain (256 MB for a client, 384 MB for a server, serial collector). On a 6 GB
machine that is the difference between ~1.5 GB of committed heap and ~250 MB.
`.\run.cmd doctor` prints the JVM and the flags in use.

If you still run out — the commit limit is shared with everything else on the
machine — check the headroom and reclaim some:

```powershell
# how close to the limit are you?
$c = Get-Counter '\Memory\Committed Bytes','\Memory\Commit Limit'
"{0:N2} GB of {1:N2} GB committed" -f ($c.CounterSamples[0].CookedValue/1GB), ($c.CounterSamples[1].CookedValue/1GB)
```

The usual culprits are WSL (`wsl --shutdown` returns a few GB), a MySQL service
left running, spare VS Code windows, and orphaned Ballerina JVMs from a crashed
run — `Get-Process java` then `Stop-Process`. Raising the page file
(System → About → Advanced system settings → Performance → Advanced → Virtual
memory) lifts the limit itself.

**`Address already in use` / `BindException`** — a previous server is still
running. Find and stop it:

```powershell
Get-NetTCPConnection -LocalPort 9090,9091 -State Listen |
    ForEach-Object { Stop-Process -Id $_.OwningProcess -Force }
```

**The client prints `Cannot reach the API`** — the server is not up yet. Wait for
`seed data loaded` in the server terminal, then retry.

**`WARNING: Ballerina distribution '...' does not match`** — harmless. It means
your Swan Lake update differs from the `distribution` in `Ballerina.toml`; the
build still succeeds.

---

## What each system does

### Question 1 — Library and Resource Management

A shared asset registry for the Ministry of Higher Education, Training and
Innovations, spanning the campuses of every registered institution. It tracks
books, electronic resources (laptops, thin clients, 3D printers) and physical
spaces (labs, meeting rooms). Every asset carries its components, its calendar of
schedules, and any work orders raised against it.

The service holds assets in a `table<Asset> key(assetTag)`, so the runtime itself
enforces that `assetTag` is unique. Loans, bookings, maintenance dates and work
orders all move an asset through the status lifecycle
`AVAILABLE → LOANED_OUT / OCCUPIED / UNDER_MAINTENANCE → DISPOSED`, and the
overdue dashboard reads straight off the same calendar.

Three front ends consume the one API: a scripted demo, an interactive CLI menu,
and a browser dashboard.

### Question 2 — Rental Accommodation System

A short-term rental platform for the Ministry of Tourism, with two roles. **Hosts**
register, update and remove listings. **Guests** browse and search, put proposed
stays into a temporary cart, then confirm them.

The contract in [`rental.proto`](question2-rental-grpc/proto/rental.proto) defines
eight operations, including one client-streaming RPC (`create_users`) and one
server-streaming RPC (`list_available_properties`). Confirming a booking
re-verifies the dates, rejects any overlap with an existing confirmed stay, and
computes the total as *price per night × number of nights*.

---

## Design notes common to both systems

**Concurrency.** Ballerina's HTTP and gRPC listeners handle requests
concurrently, so shared state cannot simply be a global variable. Both systems
keep their state in module-level `isolated` variables, read and written only
inside `lock` blocks, with values cloned on the way in and out. Question 2 goes
one step further and holds all four of its collections inside a *single*
`isolated` record — Ballerina only lets one `lock` statement touch one isolated
variable, and `confirm_booking` has to read the cart, re-check the confirmed
bookings and the listing, and write all three atomically.

**Dates.** Every date on the wire is an ISO-8601 calendar date (`yyyy-MM-dd`),
which sorts chronologically as a string. Dates are validated by round-tripping
them through `time:utcFromString`, so `2026-02-30` is rejected rather than
silently rolled over. Question 1 treats booking windows as *inclusive* on both
ends (a room booked for the 20th–21st is busy on both days); Question 2 follows
the accommodation convention of an *exclusive* check-out, so a stay ending on the
23rd does not clash with one starting on the 23rd. Both are documented where they
are implemented.

**Errors.** Neither system leaks a stack trace. Question 1 maps each distinct
error type onto exactly one HTTP status code (400/404/409/422) and returns a
uniform JSON error body. Question 2 raises typed `grpc:*Error`s, which travel as
real gRPC status codes (`NOT_FOUND`, `INVALID_ARGUMENT`, `PERMISSION_DENIED`,
`FAILED_PRECONDITION`, `ALREADY_EXISTS`, `ABORTED`), so the client can branch on
the code rather than parse the message.

**Seed data.** Both servers load demonstration data at start-up, with dates
computed relative to *today* so the overdue dashboard and the availability
filters always have something meaningful to show. Disable it with
`bal run -- -CseedData=false`.

---

## Mark allocation traceability

### Question 1 (50)

| Deliverable | Marks | Where |
|---|---|---|
| Working solution — setup, compilation, repository structure | 10 | Two packages that build with `bal build`; this README |
| Create and manage resources (add, update, look up, remove) | 5 | `POST/GET/PUT/PATCH/DELETE /library/assets[/{assetTag}]` — [service.bal](question1-library-api/asset_service/service.bal) |
| View all assets | 2 | `GET /library/assets` |
| View assets by institution and site | 3 | `GET /library/assets?institution=&site=`, `GET /library/institutions/{code}/assets` |
| Check item status and booking schedules | 5 | `GET /library/assets/{assetTag}/availability`, `GET .../schedules`, `GET /library/maintenance/overdue` |
| Manage institutions (add/remove from listings) | 5 | `POST/GET/PUT/DELETE /library/institutions[/{code}]` plus `/sites` |
| Manage schedules (add/remove for a resource) | 3 | `POST/PUT/DELETE /library/assets/{assetTag}/schedules[/{scheduleId}]` |
| Error and wrong API-call handling | 2 | `toApiError` + catch-all resource in [service.bal](question1-library-api/asset_service/service.bal) |
| Database integration — map/table keyed on `assetTag` | 5 | `table<Asset> key(assetTag)` in [store.bal](question1-library-api/asset_service/store.bal) |
| Client — loaning, viewing, scheduling | 10 | [asset_client/main.bal](question1-library-api/asset_client/main.bal) |
| **Bonus** — web/mobile interface | ~10 | [resources/index.html](question1-library-api/asset_service/resources/index.html) served at `/` |

Also implemented beyond the mark sheet: components add/remove, work orders with
sub-tasks, loan/return with late-day calculation, booking overlap rejection, and a
self-describing endpoint catalogue at `GET /library`.

### Question 2 (50)

| Deliverable | Marks | Where |
|---|---|---|
| Protocol buffer definition — all services, messages, streaming types | 15 | [proto/rental.proto](question2-rental-grpc/proto/rental.proto) |
| gRPC client — invokes all remote functions | 10 | [rental_client/main.bal](question2-rental-grpc/rental_client/main.bal) |
| gRPC server — persistence, validation, price calculation | 25 | [rental_server/store.bal](question2-rental-grpc/rental_server/store.bal), [service.bal](question2-rental-grpc/rental_server/service.bal) |

---

## Group members

| Student number | Name | Contribution |
|---|---|---|
| | | |
| | | |
| | | |

> Fill this in before submitting, and make sure every member appears as a
> contributor in the repository history — the brief requires it.
