import ballerina/grpc;

// In-memory data store for the Rental Accommodation System.
//
// Everything lives in ONE `isolated` module-level variable holding four Ballerina
// maps. A single variable matters: Ballerina only lets a `lock` statement touch
// one isolated variable, and `confirm_booking` has to read the cart, re-check the
// confirmed bookings and the property listing, and write all three - atomically.
// Holding them together makes that one lock, which is what stops two guests from
// confirming the same dates concurrently.
//
// Each map is keyed by the identifier the .proto contract uses, so the store and
// the wire format agree on identity.

// A proposed stay parked in a guest's temporary cart by `book_property`,
// promoted to a `Booking` by `confirm_booking`.
public type CartItem record {|
    string cart_item_id;
    string guest_id;
    string property_id;
    string property_name;
    string check_in;
    string check_out;
    int nights;
    int guests;
    float price_per_night;
    float estimated_total;
    string added_on;
|};

type Store record {|
    map<User> users;
    map<Property> properties;
    map<Booking> bookings;
    map<CartItem> cart;
    // Backs every server-generated identifier.
    int sequence;
|};

isolated Store db = {users: {}, properties: {}, bookings: {}, cart: {}, sequence: 1000};

// Results that need to carry more than one value back to the service layer.
public type UpdateResult record {|
    Property property;
    string[] changed;
|};

public type RemoveResult record {|
    Property removed;
    Property[] remaining;
|};

public type ConfirmResult record {|
    Booking[] bookings;
    float grandTotal;
    int remaining;
    string[] rejected;
|};

// ---------------------------------------------------------------------------
// Users
// ---------------------------------------------------------------------------

// One profile from the `create_users` client stream. Returns the assigned id, or
// a gRPC error explaining why the profile was refused; the service turns those
// refusals into the `errors` list of the single streamed confirmation.
public isolated function addUser(User user) returns string|grpc:Error {
    // Only immutable values may cross into a lock over an isolated variable, so
    // the record's fields are read out here first.
    string suppliedId = user.user_id.trim();
    string name = user.name.trim();
    string email = user.email.trim();
    UserRole role = user.role;
    string region = user.region.trim();

    if name == "" {
        return error grpc:InvalidArgumentError("name must not be empty");
    }
    if email == "" || !email.includes("@") {
        return error grpc:InvalidArgumentError(
            string `'${email}' is not a usable email address`);
    }
    if role == ROLE_UNSPECIFIED {
        return error grpc:InvalidArgumentError(
            string `user '${name}' must be either a HOST or a GUEST`);
    }

    lock {
        if suppliedId != "" && db.users.hasKey(suppliedId) {
            return error grpc:AlreadyExistsError(
                string `user id '${suppliedId}' is already taken`);
        }
        foreach User existing in db.users {
            if matchesLoosely(existing.email, email) {
                return error grpc:AlreadyExistsError(
                    string `email '${email}' is already registered to ${existing.user_id}`);
            }
        }
        string userId = suppliedId;
        if userId == "" {
            db.sequence += 1;
            userId = string `${role == HOST ? "HOST" : "GUEST"}-${db.sequence}`;
        }
        User stored = {
            user_id: userId,
            name: name,
            email: email,
            role: role,
            region: region
        };
        db.users[userId] = stored.clone();
        return userId;
    }
}

public isolated function getUser(string userId) returns User? {
    lock {
        User? found = db.users[userId];
        return found is () ? () : found.clone();
    }
}

public isolated function listUsers() returns User[] {
    lock {
        User[] all = db.users.toArray();
        return all.clone();
    }
}

// Confirms the caller exists and holds the role the operation requires.
isolated function requireRole(string userId, UserRole required) returns grpc:Error? {
    if userId.trim() == "" {
        return error grpc:InvalidArgumentError(
            string `a ${required} id is required for this operation`);
    }
    lock {
        User? found = db.users[userId];
        if found is () {
            return error grpc:NotFoundError(string `no such user '${userId}'; ` +
                "register users first with create_users");
        }
        if found.role != required {
            return error grpc:PermissionDeniedError(string `user '${userId}' is a ` +
                string `${found.role} and cannot act as a ${required}`);
        }
    }
}

// ---------------------------------------------------------------------------
// Properties
// ---------------------------------------------------------------------------

public isolated function addProperty(AddPropertyRequest request) returns Property|grpc:Error {
    string hostId = request.host_id.trim();
    string name = request.name.trim();
    string location = request.location.trim();
    string region = request.region.trim();
    PropertyType propertyType = request.property_type;
    float price = request.price_per_night;
    PropertyStatus status = request.status;
    int maxGuests = request.max_guests;
    string description = request.description;

    check requireRole(hostId, HOST);
    if name == "" {
        return error grpc:InvalidArgumentError("property name must not be empty");
    }
    if location == "" {
        return error grpc:InvalidArgumentError("location must not be empty");
    }
    if price <= 0f {
        return error grpc:InvalidArgumentError(
            string `price_per_night must be greater than zero (got ${price})`);
    }
    if maxGuests <= 0 {
        return error grpc:InvalidArgumentError(
            string `max_guests must be at least 1 (got ${maxGuests})`);
    }
    if propertyType == TYPE_UNSPECIFIED {
        return error grpc:InvalidArgumentError("property_type must be specified");
    }

    // A listing with no region defaults to its host's home region.
    string effectiveRegion = region;
    if effectiveRegion == "" {
        User? host = getUser(hostId);
        effectiveRegion = host is User ? host.region : "";
    }
    if effectiveRegion == "" {
        return error grpc:InvalidArgumentError(
            "region must be supplied, or the host must have a home region");
    }

    lock {
        db.sequence += 1;
        string propertyId = string `PROP-${db.sequence}`;
        Property property = {
            property_id: propertyId,
            host_id: hostId,
            name: name,
            location: location,
            region: effectiveRegion,
            property_type: propertyType,
            // An unspecified status on a brand-new listing means "open for business".
            status: status == STATUS_UNSPECIFIED ? AVAILABLE : status,
            price_per_night: round2(price),
            max_guests: maxGuests,
            description: description
        };
        db.properties[propertyId] = property.clone();
        return property.clone();
    }
}

public isolated function getProperty(string propertyId) returns Property? {
    lock {
        Property? found = db.properties[propertyId];
        return found is () ? () : found.clone();
    }
}

public isolated function updateProperty(UpdatePropertyRequest request)
        returns UpdateResult|grpc:Error {
    string propertyId = request.property_id.trim();
    string hostId = request.host_id.trim();
    // Each field has explicit presence in the contract, so "absent" is
    // distinguishable from "set to zero" and only what was sent is changed.
    string? newName = request?.name;
    string? newLocation = request?.location;
    string? newRegion = request?.region;
    PropertyType? newType = request?.property_type;
    float? newPrice = request?.price_per_night;
    PropertyStatus? newStatus = request?.status;
    int? newMaxGuests = request?.max_guests;
    string? newDescription = request?.description;

    if propertyId == "" {
        return error grpc:InvalidArgumentError("property_id is required");
    }
    if newPrice is float && newPrice <= 0f {
        return error grpc:InvalidArgumentError(
            string `price_per_night must be greater than zero (got ${newPrice})`);
    }
    if newMaxGuests is int && newMaxGuests <= 0 {
        return error grpc:InvalidArgumentError(
            string `max_guests must be at least 1 (got ${newMaxGuests})`);
    }
    if newName is string && newName.trim() == "" {
        return error grpc:InvalidArgumentError("property name must not be empty");
    }

    lock {
        Property? existing = db.properties[propertyId];
        if existing is () {
            return error grpc:NotFoundError(string `no such property '${propertyId}'`);
        }
        Property property = existing.clone();
        if property.host_id != hostId {
            return error grpc:PermissionDeniedError(string `property '${propertyId}' ` +
                string `belongs to host '${property.host_id}', not '${hostId}'`);
        }

        string[] changed = [];
        if newName is string && newName != property.name {
            property.name = newName;
            changed.push("name");
        }
        if newLocation is string && newLocation.trim() != "" && newLocation != property.location {
            property.location = newLocation;
            changed.push("location");
        }
        if newRegion is string && newRegion.trim() != "" && newRegion != property.region {
            property.region = newRegion;
            changed.push("region");
        }
        if newType is PropertyType && newType != TYPE_UNSPECIFIED
                && newType != property.property_type {
            property.property_type = newType;
            changed.push("property_type");
        }
        if newPrice is float && round2(newPrice) != property.price_per_night {
            property.price_per_night = round2(newPrice);
            changed.push("price_per_night");
        }
        if newStatus is PropertyStatus && newStatus != STATUS_UNSPECIFIED
                && newStatus != property.status {
            property.status = newStatus;
            changed.push("status");
        }
        if newMaxGuests is int && newMaxGuests != property.max_guests {
            property.max_guests = newMaxGuests;
            changed.push("max_guests");
        }
        if newDescription is string && newDescription != property.description {
            property.description = newDescription;
            changed.push("description");
        }

        db.properties[propertyId] = property.clone();
        return {property: property.clone(), changed: changed.clone()};
    }
}

// Deleting a listing is refused while it still has a confirmed stay that has not
// yet ended - those guests would otherwise arrive to find no booking.
public isolated function removeProperty(string propertyIdRaw, string hostIdRaw)
        returns RemoveResult|grpc:Error {
    string propertyId = propertyIdRaw.trim();
    string hostId = hostIdRaw.trim();
    string asOf = today();
    if propertyId == "" {
        return error grpc:InvalidArgumentError("property_id is required");
    }

    lock {
        Property? existing = db.properties[propertyId];
        if existing is () {
            return error grpc:NotFoundError(string `no such property '${propertyId}'`);
        }
        Property property = existing.clone();
        if property.host_id != hostId {
            return error grpc:PermissionDeniedError(string `property '${propertyId}' ` +
                string `belongs to host '${property.host_id}', not '${hostId}'`);
        }
        foreach Booking booking in db.bookings {
            if booking.property_id == propertyId && booking.check_out > asOf {
                return error grpc:FailedPreconditionError(string `property ` +
                    string `'${propertyId}' has a confirmed booking ` +
                    string `(${booking.booking_id}) running to ${booking.check_out}; ` +
                    "it cannot be removed until that stay has ended");
            }
        }

        _ = db.properties.remove(propertyId);
        // Any cart entries pointing at a listing that no longer exists are dropped.
        foreach CartItem item in db.cart.toArray() {
            if item.property_id == propertyId {
                _ = db.cart.remove(item.cart_item_id);
            }
        }

        // The reply carries the region's remaining stock, per the contract.
        Property[] remaining = [];
        foreach Property candidate in db.properties {
            if candidate.status == AVAILABLE && matchesLoosely(candidate.region, property.region) {
                remaining.push(candidate);
            }
        }
        Property[] sorted = from Property candidate in remaining
            order by candidate.property_id ascending
            select candidate;
        return {removed: property.clone(), remaining: sorted.clone()};
    }
}

// Backs the server-streaming `list_available_properties`. Any filter left empty
// (or zero) matches everything; supplying both dates additionally excludes
// listings already committed for part of that window.
public isolated function findAvailable(ListAvailableRequest request)
        returns Property[]|grpc:Error {
    string location = request.location.trim();
    string region = request.region.trim();
    float minPrice = request.min_price;
    float maxPrice = request.max_price;
    string checkIn = request.check_in.trim();
    string checkOut = request.check_out.trim();
    int guests = request.guests;

    boolean filterByDate = checkIn != "" && checkOut != "";
    if filterByDate {
        check validateDate("check_in", checkIn);
        check validateDate("check_out", checkOut);
        if checkOut <= checkIn {
            return error grpc:InvalidArgumentError(string `check_out '${checkOut}' must be ` +
                string `after check_in '${checkIn}'`);
        }
    }
    if minPrice < 0f || maxPrice < 0f {
        return error grpc:InvalidArgumentError("price bounds must not be negative");
    }
    if maxPrice > 0f && minPrice > maxPrice {
        return error grpc:InvalidArgumentError(
            string `min_price ${minPrice} is greater than max_price ${maxPrice}`);
    }

    lock {
        Property[] matches = [];
        foreach Property property in db.properties {
            if property.status != AVAILABLE {
                continue;
            }
            if location != "" && !matchesLoosely(property.location, location) {
                continue;
            }
            if region != "" && !matchesLoosely(property.region, region) {
                continue;
            }
            if minPrice > 0f && property.price_per_night < minPrice {
                continue;
            }
            if maxPrice > 0f && property.price_per_night > maxPrice {
                continue;
            }
            if guests > 0 && property.max_guests < guests {
                continue;
            }
            if filterByDate && isCommitted(db.bookings, property.property_id, checkIn, checkOut) {
                continue;
            }
            matches.push(property);
        }
        Property[] sorted = from Property property in matches
            order by property.price_per_night ascending, property.property_id ascending
            select property;
        return sorted.clone();
    }
}

// True when a confirmed booking already covers part of the window.
//
// The bookings map is passed in rather than read from `db` here: an isolated
// variable may only be touched inside a `lock` statement, and every caller is
// already holding that lock. Because this function is `isolated` the reference
// cannot escape, so handing it the live map is safe.
isolated function isCommitted(map<Booking> bookings, string propertyId, string checkIn,
        string checkOut) returns boolean {
    foreach Booking booking in bookings {
        if booking.property_id == propertyId
                && staysOverlap(checkIn, checkOut, booking.check_in, booking.check_out) {
            return true;
        }
    }
    return false;
}

// ---------------------------------------------------------------------------
// Cart and bookings
// ---------------------------------------------------------------------------

// `book_property`: validate the request and park it in the guest's cart. Nothing
// is committed here - `confirm_booking` does that.
public isolated function addToCart(BookPropertyRequest request) returns CartItem|grpc:Error {
    string guestId = request.guest_id.trim();
    string propertyId = request.property_id.trim();
    string checkIn = request.check_in.trim();
    string checkOut = request.check_out.trim();
    int guests = request.guests;

    check requireRole(guestId, GUEST);
    check validateDate("check_in", checkIn);
    check validateDate("check_out", checkOut);
    if checkOut <= checkIn {
        return error grpc:InvalidArgumentError(string `check_out '${checkOut}' must be after ` +
            string `check_in '${checkIn}'`);
    }
    string asOf = today();
    if checkIn < asOf {
        return error grpc:InvalidArgumentError(
            string `check_in '${checkIn}' is in the past (today is ${asOf})`);
    }
    int nights = check dayCount(checkIn, checkOut);
    if nights < 1 {
        return error grpc:InvalidArgumentError("a stay must be at least one night");
    }

    lock {
        Property? found = db.properties[propertyId];
        if found is () {
            return error grpc:NotFoundError(string `no such property '${propertyId}'`);
        }
        Property property = found.clone();
        if property.status != AVAILABLE {
            return error grpc:FailedPreconditionError(string `'${property.name}' is not ` +
                string `available for booking (status ${property.status})`);
        }
        if guests > 0 && guests > property.max_guests {
            return error grpc:InvalidArgumentError(string `'${property.name}' sleeps ` +
                string `${property.max_guests}; ${guests} guests were requested`);
        }
        if isCommitted(db.bookings, propertyId, checkIn, checkOut) {
            return error grpc:AbortedError(string `'${property.name}' is already booked ` +
                string `for part of ${checkIn}..${checkOut}`);
        }
        // The guest's own cart must not double-book the same nights either.
        foreach CartItem item in db.cart {
            if item.guest_id == guestId && item.property_id == propertyId
                    && staysOverlap(checkIn, checkOut, item.check_in, item.check_out) {
                return error grpc:AlreadyExistsError(string `your cart already holds ` +
                    string `${item.check_in}..${item.check_out} for this property ` +
                    string `(${item.cart_item_id})`);
            }
        }

        db.sequence += 1;
        CartItem item = {
            cart_item_id: string `CART-${db.sequence}`,
            guest_id: guestId,
            property_id: propertyId,
            property_name: property.name,
            check_in: checkIn,
            check_out: checkOut,
            nights: nights,
            guests: guests > 0 ? guests : 1,
            price_per_night: property.price_per_night,
            estimated_total: round2(property.price_per_night * <float>nights),
            added_on: asOf
        };
        db.cart[item.cart_item_id] = item.clone();
        return item.clone();
    }
}

public isolated function cartFor(string guestId) returns CartItem[] {
    lock {
        CartItem[] items = [];
        foreach CartItem item in db.cart {
            if item.guest_id == guestId {
                items.push(item);
            }
        }
        CartItem[] sorted = from CartItem item in items
            order by item.cart_item_id ascending
            select item;
        return sorted.clone();
    }
}

// `confirm_booking`: the whole thing runs inside one lock so availability cannot
// change between the re-check and the write.
//
// For every cart item (or just the one named): re-verify the listing is still
// available and the dates are still free, price the stay at the listing's current
// rate, write the Booking and clear the cart entry. Items that can no longer be
// honoured are reported in `rejected` and left in the cart.
public isolated function confirmBooking(string guestIdRaw, string cartItemIdRaw)
        returns ConfirmResult|grpc:Error {
    string guestId = guestIdRaw.trim();
    string cartItemId = cartItemIdRaw.trim();
    string confirmedOn = today();

    check requireRole(guestId, GUEST);

    lock {
        CartItem[] candidates = [];
        foreach CartItem item in db.cart {
            if item.guest_id != guestId {
                continue;
            }
            if cartItemId != "" && item.cart_item_id != cartItemId {
                continue;
            }
            candidates.push(item.clone());
        }
        if candidates.length() == 0 {
            if cartItemId != "" {
                return error grpc:NotFoundError(string `cart item '${cartItemId}' is not ` +
                    string `in ${guestId}'s cart`);
            }
            return error grpc:FailedPreconditionError(
                string `${guestId}'s booking cart is empty; call book_property first`);
        }
        CartItem[] ordered = from CartItem item in candidates
            order by item.check_in ascending, item.cart_item_id ascending
            select item;

        Booking[] confirmed = [];
        string[] rejected = [];
        float grandTotal = 0.0;

        foreach CartItem item in ordered {
            Property? found = db.properties[item.property_id];
            if found is () {
                rejected.push(string `${item.cart_item_id}: property ` +
                    string `'${item.property_id}' no longer exists`);
                _ = db.cart.remove(item.cart_item_id);
                continue;
            }
            Property property = found.clone();
            if property.status != AVAILABLE {
                rejected.push(string `${item.cart_item_id}: '${property.name}' is now ` +
                    string `${property.status}`);
                continue;
            }
            if item.check_out <= confirmedOn {
                rejected.push(string `${item.cart_item_id}: the window ` +
                    string `${item.check_in}..${item.check_out} has already passed`);
                continue;
            }
            // Someone else may have confirmed these dates since the item was added.
            if isCommitted(db.bookings, item.property_id, item.check_in, item.check_out) {
                rejected.push(string `${item.cart_item_id}: '${property.name}' was booked ` +
                    string `by someone else for part of ${item.check_in}..${item.check_out}`);
                continue;
            }
            if property.max_guests < item.guests {
                rejected.push(string `${item.cart_item_id}: '${property.name}' now sleeps ` +
                    string `only ${property.max_guests}`);
                continue;
            }

            // Total cost = current price per night x number of nights.
            int nights = item.nights;
            float total = round2(property.price_per_night * <float>nights);
            db.sequence += 1;
            Booking booking = {
                booking_id: string `BKG-${db.sequence}`,
                guest_id: guestId,
                property_id: property.property_id,
                property_name: property.name,
                check_in: item.check_in,
                check_out: item.check_out,
                nights: nights,
                price_per_night: property.price_per_night,
                total_cost: total,
                confirmed_on: confirmedOn
            };
            db.bookings[booking.booking_id] = booking.clone();
            _ = db.cart.remove(item.cart_item_id);
            confirmed.push(booking);
            grandTotal += total;
        }

        int remaining = 0;
        foreach CartItem item in db.cart {
            if item.guest_id == guestId {
                remaining += 1;
            }
        }

        return {
            bookings: confirmed.clone(),
            grandTotal: round2(grandTotal),
            remaining: remaining,
            rejected: rejected.clone()
        };
    }
}

public isolated function listBookings() returns Booking[] {
    lock {
        Booking[] all = db.bookings.toArray();
        return all.clone();
    }
}

public isolated function counts() returns [int, int, int, int] {
    lock {
        return [
            db.users.length(),
            db.properties.length(),
            db.bookings.length(),
            db.cart.length()
        ];
    }
}
