import ballerina/log;

// Demonstration data so the client has hosts, guests and listings to work with
// the moment the server starts.
//
// Turn it off with: bal run -- -CseedData=false
configurable boolean seedData = true;

function init() returns error? {
    if !seedData {
        log:printInfo("seed data disabled; starting with an empty store");
        return;
    }

    // Two hosts and two guests, with fixed ids so the client demo can reference
    // them without having to create users first.
    _ = check addUser({
        user_id: "HOST-001",
        name: "Maria Shikongo",
        email: "maria@coastalstays.na",
        role: HOST,
        region: "Erongo"
    });
    _ = check addUser({
        user_id: "HOST-002",
        name: "Johannes Kaapanda",
        email: "johannes@kalaharilodges.na",
        role: HOST,
        region: "Khomas"
    });
    _ = check addUser({
        user_id: "GUEST-001",
        name: "Thandi Nangolo",
        email: "thandi.nangolo@example.na",
        role: GUEST,
        region: "Khomas"
    });
    _ = check addUser({
        user_id: "GUEST-002",
        name: "Peter Mwilima",
        email: "peter.mwilima@example.na",
        role: GUEST,
        region: "Zambezi"
    });

    _ = check addProperty({
        host_id: "HOST-001",
        name: "Swakopmund Beach Apartment",
        location: "Swakopmund",
        region: "Erongo",
        property_type: APARTMENT,
        price_per_night: 950.00,
        status: AVAILABLE,
        max_guests: 4,
        description: "Two-bedroom apartment one street back from the beachfront."
    });
    _ = check addProperty({
        host_id: "HOST-001",
        name: "Walvis Bay Lagoon Guest House",
        location: "Walvis Bay",
        region: "Erongo",
        property_type: GUEST_HOUSE,
        price_per_night: 720.50,
        status: AVAILABLE,
        max_guests: 6,
        description: "Family guest house overlooking the lagoon, breakfast included."
    });
    _ = check addProperty({
        host_id: "HOST-001",
        name: "Henties Bay Fishing Cottage",
        location: "Henties Bay",
        region: "Erongo",
        property_type: HOUSE,
        price_per_night: 1300.00,
        status: MAINTENANCE,
        max_guests: 8,
        description: "Closed for roof repairs until further notice."
    });
    _ = check addProperty({
        host_id: "HOST-002",
        name: "Klein Windhoek Studio",
        location: "Windhoek",
        region: "Khomas",
        property_type: ROOM,
        price_per_night: 480.00,
        status: AVAILABLE,
        max_guests: 2,
        description: "Self-catering studio, ten minutes from the CBD."
    });
    _ = check addProperty({
        host_id: "HOST-002",
        name: "Auas Mountain Lodge",
        location: "Windhoek",
        region: "Khomas",
        property_type: LODGE,
        price_per_night: 2150.00,
        status: AVAILABLE,
        max_guests: 10,
        description: "Eight-chalet lodge on a private reserve south of the city."
    });

    var [users, properties, bookings, cart] = counts();
    log:printInfo("seed data loaded",
        users = users, properties = properties, bookings = bookings, cart = cart);
}
