# Question 2 — Rental Accommodation System (gRPC)

A distributed short-term-rental platform for the Ministry of Tourism, built on
gRPC with Ballerina. Two roles: **HOST** (manages listings) and **GUEST**
(browses, searches, books).

## Running it

Two terminals. From the **repository root**, using the launcher (works even when
`bal` is not on your PATH — see Troubleshooting in the [root README](../README.md)):

```
run q2-server                    Terminal 1 — localhost:9091
run q2-demo                      Terminal 2 — invokes all eight RPCs in order
run q2-client                    Terminal 2 — interactive menu
```

Or call `bal` directly, from **inside each package directory**:

```bash
# Terminal 1 — the server
cd rental_server
bal run                          # listens on localhost:9091

# Terminal 2 — the client
cd rental_client
bal run -- demo                  # invokes all eight RPCs in order
bal run                          # interactive menu
```

Configuration:

| Option | Default | Effect |
|---|---|---|
| `bal run -- -CgrpcPort=9095` | 9091 | Port the server listens on |
| `bal run -- -CseedData=false` | true | Start with an empty store |
| `bal run -- -CserverUrl=http://host:port demo` | `http://localhost:9091` | Where the client connects |

## The contract

[`proto/rental.proto`](proto/rental.proto) defines the service. Eight operations,
of which two are streaming:

| RPC | Style | What it does |
|---|---|---|
| `add_property` | Simple | A host registers a listing; returns a unique `property_id` |
| `create_users` | **Client streaming** | Many `User` profiles stream in; one `CreateUsersResponse` comes back after the client completes |
| `update_property` | Simple | A host changes listing details by `property_id` |
| `remove_property` | Simple | A host deletes a listing; the reply carries the region's remaining available stock |
| `list_available_properties` | **Server streaming** | Matching properties are streamed back one message at a time |
| `search_property` | Simple | Look up one listing; a miss returns `availability: "NOT AVAILABLE"` rather than an error |
| `book_property` | Simple | Validates a proposed stay and parks it in the guest's temporary cart |
| `confirm_booking` | Simple | Re-checks availability, computes the total, clears the cart |

Messages, enums (`UserRole`, `PropertyType`, `PropertyStatus`) and the two
streaming declarations are all in that one file.

`UpdatePropertyRequest` uses proto3 `optional` on every mutable field. That gives
the fields explicit presence, so "not sent" is distinguishable from "set to 0 or
empty string" — a host can change just the price without resending the whole
listing, and the response reports exactly which fields changed in
`changed_fields`.

### Regenerating the stubs

`rental_pb.bal` is generated from the contract and committed to both packages so
the repository builds without running the code generator. After editing
`rental.proto`, regenerate both copies:

```bash
cd question2-rental-grpc
bal grpc --input proto/rental.proto --output rental_server
bal grpc --input proto/rental.proto --output rental_client
```

> `bal grpc` downloads a `protoc` binary on first use. If that download fails
> behind a TLS-inspecting proxy, fetch it manually into your temp directory and
> `bal grpc` will reuse it:
> `curl -L -o "$TEMP/protoc-3.21.7-windows-x86_64.exe" https://repo1.maven.org/maven2/com/google/protobuf/protoc/3.21.7/protoc-3.21.7-windows-x86_64.exe`

## Business rules

**Roles are enforced.** `add_property`, `update_property` and `remove_property`
require a registered `HOST`; `book_property` and `confirm_booking` require a
registered `GUEST`. A guest attempting to register a listing gets
`PERMISSION_DENIED`, as does a host editing a listing they do not own.

**Stay windows are half-open.** Check-in is inclusive, check-out exclusive — so
20th → 23rd is three nights, and a stay starting on the 23rd does *not* clash with
one ending on the 23rd. Two stays overlap iff each starts strictly before the
other ends.

**Booking is two-phase.** `book_property` validates and reserves nothing — it puts
a `CartItem` in the guest's cart with an *estimated* total. `confirm_booking` is
where commitment happens: inside one lock it re-reads the listing, re-checks for
overlaps (someone else may have confirmed those dates in the meantime), prices the
stay at the listing's *current* rate, writes the `Booking` and removes the cart
entry. Items that can no longer be honoured are returned in `rejected` and left in
the cart rather than silently dropped.

**Total cost** = `price_per_night × nights`, rounded to two decimals.

**A listing with a confirmed future stay cannot be removed** — `remove_property`
returns `FAILED_PRECONDITION` naming the booking, so guests are never orphaned.

## Error handling

The server raises typed `grpc:*Error`s, which travel to the client as real gRPC
status codes rather than a generic `UNKNOWN`:

| Status | Raised when |
|---|---|
| `INVALID_ARGUMENT` | Malformed date, check-out not after check-in, non-positive price, too many guests, missing id, unspecified enum |
| `NOT_FOUND` | Unknown user or property |
| `ALREADY_EXISTS` | Duplicate user id or email; the same dates already in this guest's cart |
| `PERMISSION_DENIED` | Wrong role, or a host acting on another host's listing |
| `FAILED_PRECONDITION` | Listing not `AVAILABLE`; empty cart; removing a listing with a confirmed future stay |
| `ABORTED` | The requested dates were taken by a confirmed booking |

The client decodes the status back out in `statusOf` ([views.bal](rental_client/views.bal))
and prints it alongside the message, e.g.
`[ABORTED] 'Ongwediva Town House' is already booked for part of 2026-09-20..2026-09-23`.

One deliberate exception: `search_property` treats a miss as a normal answer
(`found: false`, `availability: "NOT AVAILABLE"`) because the brief asks for a
"Not Available" status rather than a failure.

## Seed data

The server starts with two hosts, two guests and five listings across the Erongo
and Khomas regions — including one in `MAINTENANCE` status, so the availability
filter has something to exclude.

| Id | Role / listing |
|---|---|
| `HOST-001` | Maria Shikongo (Erongo) |
| `HOST-002` | Johannes Kaapanda (Khomas) |
| `GUEST-001` | Thandi Nangolo |
| `GUEST-002` | Peter Mwilima |
| `PROP-1001` | Swakopmund Beach Apartment — N$950.00, sleeps 4 |
| `PROP-1002` | Walvis Bay Lagoon Guest House — N$720.50, sleeps 6 |
| `PROP-1003` | Henties Bay Fishing Cottage — `MAINTENANCE` |
| `PROP-1004` | Klein Windhoek Studio — N$480.00, sleeps 2 |
| `PROP-1005` | Auas Mountain Lodge — N$2150.00, sleeps 10 |

## The client

`bal run` gives a menu with one entry per RPC, so each remote function can be
invoked interactively — including streaming profiles in one at a time for
`create_users` and consuming the server stream for
`list_available_properties`.

`bal run -- demo` runs a scripted pass that invokes all eight RPCs and then
deliberately provokes each refusal, printing the gRPC status code it got back.
It is idempotent enough to re-run: user emails and property names are suffixed
with a per-run timestamp, and the demo removes the spare listing it creates.

## Implementation notes

**All state in one isolated variable.** `store.bal` holds users, properties,
bookings and the cart in a single module-level `isolated` record. That is not
incidental — Ballerina permits a `lock` statement to touch only one isolated
variable, and `confirm_booking` must read the cart, re-check the bookings and the
listing, and write all three atomically. Keeping them together makes that one
lock, which is exactly what stops two guests confirming the same dates
concurrently.

**Cloning at the boundary.** Values are cloned going into and out of every lock,
so no caller can hold a reference into live server state. Request records are read
into immutable locals *before* the lock, because Ballerina only lets immutable
values (or fresh clones) cross into a lock over an isolated variable.

**Server streaming uses the generated caller.** `list_available_properties` takes
a `RentalServicePropertyCaller` and calls `sendProperty` per match, then
`complete()`. Each property is therefore its own message on the wire, so a guest's
client can render the first result before the server has finished scanning the
rest.

**Client streaming does not fail the batch.** `create_users` pulls from the client
stream until it is exhausted. A profile the store refuses is counted and described
in the `errors` list rather than aborting the upload, so one bad record does not
cost the client the whole batch. The single confirmation is sent only after the
client calls `complete()`.

**The service layer is thin.** Every rule lives in `store.bal`; `service.bal`
translates results into response messages and logs. That is why the remote
functions read as a handful of lines each.
