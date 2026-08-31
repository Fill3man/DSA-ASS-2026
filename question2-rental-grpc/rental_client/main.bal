import ballerina/grpc;
import ballerina/io;
import ballerina/time;

// gRPC client for the Rental Accommodation System.
//
//   bal run                interactive menu (Host and Guest roles)
//   bal run -- demo        scripted run that invokes all eight remote functions
//
// Override the server address with:
//   bal run -- -CserverUrl=http://localhost:9095 demo
configurable string serverUrl = "http://localhost:9091";

final RentalServiceClient rental = check new (serverUrl);

public function main(string... args) returns error? {
    if args.length() > 0 && args[0].toLowerAscii() == "demo" {
        return runDemo();
    }
    return runMenu();
}

// ---------------------------------------------------------------------------
// Scripted demonstration - exercises every RPC in the contract
// ---------------------------------------------------------------------------

function runDemo() returns error? {
    io:println();
    io:println("===================================================================");
    io:println("  RENTAL ACCOMMODATION SYSTEM - gRPC CLIENT DEMONSTRATION");
    io:println(string `  Server: ${serverUrl}`);
    io:println("===================================================================");

    // Unique per run so the demo can be repeated against a live server.
    string run = check runTag();
    string checkIn = check plusDays(40);
    string checkOut = check plusDays(43);

    // -- 1. create_users (CLIENT-SIDE STREAMING) ----------------------------
    heading("1. create_users - client-side streaming");
    note("Streaming four profiles to the server, then waiting for one confirmation.");

    Create_usersStreamingClient userStream = check rental->create_users();
    string hostEmail = string `host.${run}@stays.na`;
    User[] batch = [
        {user_id: "", name: string `Demo Host ${run}`, email: hostEmail, role: HOST, region: "Oshana"},
        {user_id: "", name: string `Demo Guest ${run}`, email: string `guest.${run}@example.na`, role: GUEST, region: "Khomas"},
        // Deliberately invalid: no usable email address.
        {user_id: "", name: string `Broken Profile ${run}`, email: "not-an-email", role: GUEST, region: "Erongo"},
        // Deliberately duplicated: same email as the first profile.
        {user_id: "", name: string `Duplicate Host ${run}`, email: hostEmail, role: HOST, region: "Oshana"}
    ];
    foreach User user in batch {
        check userStream->sendUser(user);
        note(string `  -> sent ${user.name} <${user.email}> as ${user.role}`);
    }
    // Signals end-of-stream; the server replies only after this.
    check userStream->complete();

    CreateUsersResponse? confirmation = check userStream->receiveCreateUsersResponse();
    if confirmation is () {
        failure("The server closed the stream without a confirmation.");
        return;
    }
    success(confirmation.message);
    note(string `Registered ids: ${string:'join(", ", ...confirmation.user_ids)}`);
    foreach string rejection in confirmation.errors {
        note(string `  rejected -> ${rejection}`);
    }
    if confirmation.user_ids.length() < 2 {
        failure("Expected at least a host and a guest to be created; stopping.");
        return;
    }
    string hostId = confirmation.user_ids[0];
    string guestId = confirmation.user_ids[1];
    note(string `Using host ${hostId} and guest ${guestId} for the rest of the run.`);

    // -- 2. add_property (SIMPLE RPC) ---------------------------------------
    heading("2. add_property - simple RPC");
    AddPropertyResponse added = check rental->add_property({
        host_id: hostId,
        name: string `Ongwediva Town House ${run}`,
        location: "Ongwediva",
        region: "Oshana",
        property_type: HOUSE,
        price_per_night: 875.50,
        status: AVAILABLE,
        max_guests: 5,
        description: "Three-bedroom house near the trade fair grounds."
    });
    success(added.message);
    string demoPropertyId = added.property_id;

    // A second listing, so a removal can be demonstrated later without touching
    // the one that ends up with a confirmed booking.
    AddPropertyResponse spare = check rental->add_property({
        host_id: hostId,
        name: string `Oshakati Guest Flat ${run}`,
        location: "Oshakati",
        region: "Oshana",
        property_type: APARTMENT,
        price_per_night: 610.00,
        status: AVAILABLE,
        max_guests: 3,
        description: "One-bedroom flat, secure parking."
    });
    success(spare.message);

    // -- 3. search_property (SIMPLE RPC) ------------------------------------
    heading("3. search_property - simple RPC");
    SearchPropertyResponse hit = check rental->search_property({property_id: demoPropertyId});
    note(string `${demoPropertyId} -> found=${hit.found}, availability=${hit.availability}`);
    success(hit.message);

    SearchPropertyResponse miss = check rental->search_property({property_id: "PROP-DOES-NOT-EXIST"});
    note(string `PROP-DOES-NOT-EXIST -> found=${miss.found}, availability=${miss.availability}`);
    success(miss.message);

    // -- 4. update_property (SIMPLE RPC) ------------------------------------
    heading("4. update_property - simple RPC");
    note("Only the fields actually sent are changed; the rest keep their values.");
    UpdatePropertyResponse updated = check rental->update_property({
        property_id: demoPropertyId,
        host_id: hostId,
        price_per_night: 799.99,
        description: "Three-bedroom house near the trade fair grounds. Winter rate."
    });
    success(updated.message);
    note(string `Changed: ${string:'join(", ", ...updated.changed_fields)}`);
    note(string `Price is now N$${formatMoney(updated.property.price_per_night)}/night.`);

    // -- 5. list_available_properties (SERVER-SIDE STREAMING) ---------------
    heading("5. list_available_properties - server-side streaming");
    note("Unfiltered: every available listing, streamed one message at a time.");
    int total = check streamProperties({});

    note("");
    note(string `Filtered: Oshana region, under N$900, 4+ guests, free ${checkIn}..${checkOut}`);
    int filtered = check streamProperties({
        region: "Oshana",
        max_price: 900.0,
        guests: 4,
        check_in: checkIn,
        check_out: checkOut
    });
    note(string `${total} available overall, ${filtered} matching the filter.`);

    // -- 6. book_property (SIMPLE RPC) --------------------------------------
    heading("6. book_property - simple RPC (into the temporary cart)");
    BookPropertyResponse held = check rental->book_property({
        guest_id: guestId,
        property_id: demoPropertyId,
        check_in: checkIn,
        check_out: checkOut,
        guests: 4
    });
    success(held.message);
    note(string `Cart item ${held.cart_item_id}: ${held.nights} night(s) x ` +
        string `N$${formatMoney(held.price_per_night)} = N$${formatMoney(held.estimated_total)}`);
    note(string `Cart now holds ${held.cart_size} item(s).`);

    var outcome1 = rental->book_property({
        guest_id: guestId,
        property_id: demoPropertyId,
        check_in: checkOut,
        check_out: checkIn,
        guests: 2
    });
    expectFailure("Check-out before check-in", outcome1);
    var outcome2 = rental->book_property({
        guest_id: guestId,
        property_id: demoPropertyId,
        check_in: checkIn,
        check_out: checkOut,
        guests: 2
    });
    expectFailure("Same dates already in this guest's cart", outcome2);
    var outcome3 = rental->book_property({
        guest_id: guestId,
        property_id: demoPropertyId,
        check_in: check plusDays(80),
        check_out: check plusDays(82),
        guests: 99
    });
    expectFailure("More guests than the property sleeps", outcome3);

    // -- 7. confirm_booking (SIMPLE RPC) ------------------------------------
    heading("7. confirm_booking - simple RPC");
    note("Re-checks availability, prices the stay, then clears the cart.");
    ConfirmBookingResponse confirmed = check rental->confirm_booking({
        guest_id: guestId,
        cart_item_id: ""
    });
    success(confirmed.message);
    printBookings(confirmed.bookings);
    io:println();
    note(string `Grand total: N$${formatMoney(confirmed.grand_total)}`);
    note(string `Items left in the cart: ${confirmed.cart_remaining}`);
    foreach string rejection in confirmed.rejected {
        note(string `  rejected -> ${rejection}`);
    }

    var outcome4 = rental->confirm_booking({
        guest_id: guestId,
        cart_item_id: ""
    });
    expectFailure("Confirming again with an empty cart", outcome4);

    // -- 8. the no-double-booking rule --------------------------------------
    heading("8. Date-overlap protection");
    note(string `A second guest tries the same property for ${checkIn}..${checkOut}.`);
    var outcome5 = rental->book_property({
        guest_id: "GUEST-002",
        property_id: demoPropertyId,
        check_in: checkIn,
        check_out: checkOut,
        guests: 2
    });
    expectFailure("Overlapping dates for another guest", outcome5);
    note("A stay that starts exactly when the confirmed one ends is fine:");
    BookPropertyResponse adjacent = check rental->book_property({
        guest_id: "GUEST-002",
        property_id: demoPropertyId,
        check_in: checkOut,
        check_out: check plusDays(45),
        guests: 2
    });
    success(adjacent.message);
    ConfirmBookingResponse adjacentConfirmed = check rental->confirm_booking({
        guest_id: "GUEST-002",
        cart_item_id: adjacent.cart_item_id
    });
    success(adjacentConfirmed.message);

    // -- 9. remove_property (SIMPLE RPC) ------------------------------------
    heading("9. remove_property - simple RPC");
    var outcome6 = rental->remove_property({property_id: demoPropertyId, host_id: hostId});
    expectFailure("Removing a property with a confirmed future stay", outcome6);

    note("Removing the second, unbooked listing instead:");
    RemovePropertyResponse removed = check rental->remove_property({
        property_id: spare.property_id,
        host_id: hostId
    });
    success(removed.message);
    printProperties(removed.available_in_region,
        string `Still available in ${removed.region}`);

    // -- 10. authorisation and validation -----------------------------------
    heading("10. Role and ownership checks");
    var outcome7 = rental->add_property({
        host_id: guestId,
        name: "Should be refused",
        location: "Windhoek",
        region: "Khomas",
        property_type: ROOM,
        price_per_night: 100.0,
        status: AVAILABLE,
        max_guests: 1,
        description: ""
    });
    expectFailure("A guest trying to register a listing", outcome7);
    var outcome8 = rental->update_property({
        property_id: demoPropertyId,
        host_id: "HOST-002",
        price_per_night: 1.0
    });
    expectFailure("A host editing someone else's listing", outcome8);
    var outcome9 = rental->add_property({
        host_id: hostId,
        name: "Free house",
        location: "Ongwediva",
        region: "Oshana",
        property_type: HOUSE,
        price_per_night: -50.0,
        status: AVAILABLE,
        max_guests: 2,
        description: ""
    });
    expectFailure("A negative nightly rate", outcome9);
    var outcome10 = rental->add_property({
        host_id: "HOST-NOBODY",
        name: "Ghost listing",
        location: "Rundu",
        region: "Kavango East",
        property_type: HOUSE,
        price_per_night: 500.0,
        status: AVAILABLE,
        max_guests: 2,
        description: ""
    });
    expectFailure("An unknown host", outcome10);
    var outcome11 = rental->book_property({
        guest_id: guestId,
        property_id: demoPropertyId,
        check_in: "2026-13-45",
        check_out: "2026-13-46",
        guests: 1
    });
    expectFailure("A malformed date", outcome11);

    io:println();
    io:println(RULE);
    note("All eight remote functions were invoked successfully.");
    io:println(RULE);
    return;
}

// Consumes the server stream, printing each property as it arrives.
function streamProperties(ListAvailableRequest request) returns int|error {
    stream<Property, grpc:Error?> properties = check rental->list_available_properties(request);
    int count = 0;
    propertyHeader();
    while true {
        record {|Property value;|}|grpc:Error? next = properties.next();
        if next is () {
            // End of stream: the server called complete(). The stream is closed
            // for us at this point, so calling close() here would itself error.
            break;
        }
        if next is grpc:Error {
            failure(explain(next));
            // Abandoning a stream part-way does need an explicit close.
            check properties.close();
            return count;
        }
        count += 1;
        propertyRow(next.value);
    }
    if count == 0 {
        note("  (the server streamed no properties)");
    }
    return count;
}

// Reports the outcome of a call that is expected to be refused.
function expectFailure(string label, any|error outcome) {
    if outcome is error {
        success(string `${label} correctly refused - ${explain(outcome)}`);
    } else {
        failure(string `BUG: ${label} was accepted when it should have been refused.`);
    }
}

function runTag() returns string|error {
    time:Civil now = time:utcToCivil(time:utcNow());
    return string `${now.hour.toString().padZero(2)}${now.minute.toString().padZero(2)}` +
        (<int>(now.second ?: 0d)).toString().padZero(2);
}

function plusDays(int days) returns string|error {
    time:Civil civil = time:utcToCivil(
        time:utcAddSeconds(time:utcNow(), <decimal>days * 86400d));
    return string `${civil.year.toString().padZero(4)}-` +
        string `${civil.month.toString().padZero(2)}-${civil.day.toString().padZero(2)}`;
}

// ---------------------------------------------------------------------------
// Interactive menu
// ---------------------------------------------------------------------------

function runMenu() returns error? {
    io:println();
    io:println("===================================================================");
    io:println("  Rental Accommodation System - Ministry of Tourism");
    io:println(string `  gRPC server: ${serverUrl}`);
    io:println("===================================================================");

    // A cheap round trip that proves the server is reachable before showing a menu.
    SearchPropertyResponse|error probe = rental->search_property({property_id: "PROP-1005"});
    if probe is error {
        failure(string `Cannot reach the server - ${explain(probe)}`);
        failure("Start it first:  cd rental_server && bal run");
        return;
    }

    while true {
        io:println();
        io:println("  ---------------- MENU ----------------");
        io:println("   1  Register users            (create_users, client streaming)");
        io:println("   2  Add a property            (add_property)");
        io:println("   3  Update a property         (update_property)");
        io:println("   4  Remove a property         (remove_property)");
        io:println("   5  Browse available          (list_available_properties, server streaming)");
        io:println("   6  Search by property id     (search_property)");
        io:println("   7  Book a property           (book_property)");
        io:println("   8  Confirm bookings          (confirm_booking)");
        io:println("   9  Run the full scripted demo");
        io:println("   0  Exit");
        string choice = ask("  Choose");

        match choice {
            "1" => {
                check menuCreateUsers();
            }
            "2" => {
                check menuAddProperty();
            }
            "3" => {
                check menuUpdateProperty();
            }
            "4" => {
                check menuRemoveProperty();
            }
            "5" => {
                check menuBrowse();
            }
            "6" => {
                check menuSearch();
            }
            "7" => {
                check menuBook();
            }
            "8" => {
                check menuConfirm();
            }
            "9" => {
                check runDemo();
            }
            "0" => {
                io:println("  Goodbye.");
                return;
            }
            _ => {
                failure("Unknown option.");
            }
        }
    }
}

function ask(string prompt) returns string {
    return io:readln(prompt + ": ").trim();
}

function askInt(string prompt, int fallback) returns int {
    string raw = ask(prompt);
    if raw == "" {
        return fallback;
    }
    int|error parsed = int:fromString(raw);
    return parsed is int ? parsed : fallback;
}

function askFloat(string prompt, float fallback) returns float {
    string raw = ask(prompt);
    if raw == "" {
        return fallback;
    }
    float|error parsed = float:fromString(raw);
    return parsed is float ? parsed : fallback;
}

function menuCreateUsers() returns error? {
    note("Enter profiles one at a time. Leave the name blank to finish and send.");
    Create_usersStreamingClient userStream = check rental->create_users();
    int sent = 0;
    while true {
        string name = ask("  Name (blank to finish)");
        if name == "" {
            break;
        }
        string email = ask("  Email");
        string roleText = ask("  Role [HOST/GUEST]").toUpperAscii();
        UserRole role = roleText == "HOST" ? HOST : (roleText == "GUEST" ? GUEST : ROLE_UNSPECIFIED);
        string region = ask("  Region");
        check userStream->sendUser({
            user_id: "",
            name: name,
            email: email,
            role: role,
            region: region
        });
        sent += 1;
    }
    if sent == 0 {
        note("Nothing sent.");
        // The stream is still open, so close it before returning.
        check userStream->complete();
        _ = check userStream->receiveCreateUsersResponse();
        return;
    }
    check userStream->complete();
    CreateUsersResponse? response = check userStream->receiveCreateUsersResponse();
    if response is () {
        failure("No confirmation received.");
        return;
    }
    success(response.message);
    if response.user_ids.length() > 0 {
        note(string `Ids: ${string:'join(", ", ...response.user_ids)}`);
    }
    foreach string rejection in response.errors {
        note(string `  rejected -> ${rejection}`);
    }
}

function menuAddProperty() returns error? {
    string hostId = ask("  Host id (e.g. HOST-001)");
    string name = ask("  Property name");
    string location = ask("  Location (town/city)");
    string region = ask("  Region");
    string typeText = ask("  Type [APARTMENT/HOUSE/GUEST_HOUSE/LODGE/ROOM/CAMPSITE]").toUpperAscii();
    float price = askFloat("  Price per night", 500.0);
    int maxGuests = askInt("  Max guests", 2);
    string description = ask("  Description");

    AddPropertyResponse|error response = rental->add_property({
        host_id: hostId,
        name: name,
        location: location,
        region: region,
        property_type: toPropertyType(typeText),
        price_per_night: price,
        status: AVAILABLE,
        max_guests: maxGuests,
        description: description
    });
    if response is error {
        failure(explain(response));
        return;
    }
    success(response.message);
    propertyHeader();
    propertyRow(response.property);
}

function menuUpdateProperty() returns error? {
    string propertyId = ask("  Property id");
    string hostId = ask("  Your host id");
    string priceText = ask("  New price per night (blank to keep)");
    string statusText = ask("  New status [AVAILABLE/UNAVAILABLE/MAINTENANCE] (blank to keep)").toUpperAscii();
    string nameText = ask("  New name (blank to keep)");

    UpdatePropertyRequest request = {property_id: propertyId, host_id: hostId};
    if priceText != "" {
        float|error parsed = float:fromString(priceText);
        if parsed is float {
            request.price_per_night = parsed;
        }
    }
    if statusText != "" {
        request.status = toPropertyStatus(statusText);
    }
    if nameText != "" {
        request.name = nameText;
    }

    UpdatePropertyResponse|error response = rental->update_property(request);
    if response is error {
        failure(explain(response));
        return;
    }
    success(response.message);
    propertyHeader();
    propertyRow(response.property);
}

function menuRemoveProperty() returns error? {
    string propertyId = ask("  Property id to remove");
    string hostId = ask("  Your host id");
    RemovePropertyResponse|error response = rental->remove_property({
        property_id: propertyId,
        host_id: hostId
    });
    if response is error {
        failure(explain(response));
        return;
    }
    success(response.message);
    printProperties(response.available_in_region,
        string `Still available in ${response.region}`);
}

function menuBrowse() returns error? {
    string location = ask("  Location (blank = any)");
    string region = ask("  Region (blank = any)");
    float minPrice = askFloat("  Minimum price (blank = 0)", 0.0);
    float maxPrice = askFloat("  Maximum price (blank = no limit)", 0.0);
    int guests = askInt("  Guests (blank = any)", 0);
    string checkIn = ask("  Check-in yyyy-MM-dd (blank = ignore dates)");
    string checkOut = ask("  Check-out yyyy-MM-dd (blank = ignore dates)");

    heading("Available properties");
    int count = check streamProperties({
        location: location,
        region: region,
        min_price: minPrice,
        max_price: maxPrice,
        guests: guests,
        check_in: checkIn,
        check_out: checkOut
    });
    io:println();
    note(string `${count} property(ies) streamed.`);
}

function menuSearch() returns error? {
    string propertyId = ask("  Property id");
    SearchPropertyResponse|error response = rental->search_property({property_id: propertyId});
    if response is error {
        failure(explain(response));
        return;
    }
    note(string `found=${response.found}, availability=${response.availability}`);
    success(response.message);
    if response.found {
        propertyHeader();
        propertyRow(response.property);
    }
}

function menuBook() returns error? {
    string guestId = ask("  Guest id (e.g. GUEST-001)");
    string propertyId = ask("  Property id");
    string checkIn = ask("  Check-in yyyy-MM-dd");
    string checkOut = ask("  Check-out yyyy-MM-dd");
    int guests = askInt("  Guests", 1);

    BookPropertyResponse|error response = rental->book_property({
        guest_id: guestId,
        property_id: propertyId,
        check_in: checkIn,
        check_out: checkOut,
        guests: guests
    });
    if response is error {
        failure(explain(response));
        return;
    }
    success(response.message);
    note(string `Cart item ${response.cart_item_id}; ${response.nights} night(s); ` +
        string `estimated N$${formatMoney(response.estimated_total)}`);
}

function menuConfirm() returns error? {
    string guestId = ask("  Guest id");
    string cartItemId = ask("  Cart item id (blank = confirm the whole cart)");
    ConfirmBookingResponse|error response = rental->confirm_booking({
        guest_id: guestId,
        cart_item_id: cartItemId
    });
    if response is error {
        failure(explain(response));
        return;
    }
    success(response.message);
    printBookings(response.bookings);
    io:println();
    note(string `Grand total: N$${formatMoney(response.grand_total)}`);
    note(string `Cart remaining: ${response.cart_remaining}`);
    foreach string rejection in response.rejected {
        note(string `  rejected -> ${rejection}`);
    }
}

function toPropertyType(string text) returns PropertyType {
    match text {
        "APARTMENT" => {
            return APARTMENT;
        }
        "HOUSE" => {
            return HOUSE;
        }
        "GUEST_HOUSE" => {
            return GUEST_HOUSE;
        }
        "LODGE" => {
            return LODGE;
        }
        "ROOM" => {
            return ROOM;
        }
        "CAMPSITE" => {
            return CAMPSITE;
        }
    }
    return TYPE_UNSPECIFIED;
}

function toPropertyStatus(string text) returns PropertyStatus {
    match text {
        "AVAILABLE" => {
            return AVAILABLE;
        }
        "UNAVAILABLE" => {
            return UNAVAILABLE;
        }
        "MAINTENANCE" => {
            return MAINTENANCE;
        }
    }
    return STATUS_UNSPECIFIED;
}
