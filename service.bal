import ballerina/grpc;
import ballerina/log;

// gRPC service implementation for the Rental Accommodation System.
//
// The service layer stays deliberately thin: it validates nothing itself and
// holds no state. Every rule lives in `store.bal`, which raises the appropriate
// `grpc:*Error` - those carry real gRPC status codes (NOT_FOUND,
// INVALID_ARGUMENT, PERMISSION_DENIED, FAILED_PRECONDITION, ALREADY_EXISTS,
// ABORTED) rather than a generic UNKNOWN, so a client can react to the code as
// well as the message.
//
// Override the port with: bal run -- -CgrpcPort=9095
configurable int grpcPort = 9091;

listener grpc:Listener rentalListener = new (grpcPort);

@grpc:Descriptor {value: RENTAL_DESC}
service "RentalService" on rentalListener {

    // --- add_property: simple RPC ------------------------------------------

    remote function add_property(AddPropertyRequest value) returns AddPropertyResponse|error {
        Property property = check addProperty(value);
        log:printInfo("listing registered",
            property = property.property_id, host = property.host_id, region = property.region);
        return {
            property_id: property.property_id,
            property: property,
            message: string `'${property.name}' registered in ${property.location}, ` +
                string `${property.region} at N$${money(property.price_per_night)}/night ` +
                string `as ${property.property_id}`
        };
    }

    // --- create_users: client-side streaming -------------------------------

    // Many profiles stream in; exactly one confirmation goes back once the client
    // has signalled that it is done. A profile the store rejects does not abort
    // the batch - it is counted and reported in `errors`, so one bad record
    // cannot cost the client the whole upload.
    remote function create_users(stream<User, grpc:Error?> clientStream)
            returns CreateUsersResponse|error {
        int received = 0;
        int created = 0;
        string[] userIds = [];
        string[] errors = [];

        while true {
            record {|User value;|}|grpc:Error? next = clientStream.next();
            if next is () {
                // Client called complete(): the batch is finished.
                break;
            }
            if next is grpc:Error {
                log:printError("client stream failed mid-batch", next, received = received);
                return next;
            }
            received += 1;
            User user = next.value;
            string|grpc:Error outcome = addUser(user);
            if outcome is string {
                created += 1;
                userIds.push(outcome);
            } else {
                string label = user.name.trim() == "" ? "(unnamed profile)" : user.name;
                errors.push(string `${label}: ${outcome.message()}`);
            }
        }

        int rejected = received - created;
        log:printInfo("user batch processed",
            received = received, created = created, rejected = rejected);
        return {
            created: created,
            rejected: rejected,
            user_ids: userIds,
            errors: errors,
            message: string `Received ${received} profile(s): ${created} registered, ` +
                string `${rejected} rejected.`
        };
    }

    // --- update_property: simple RPC ---------------------------------------

    remote function update_property(UpdatePropertyRequest value)
            returns UpdatePropertyResponse|error {
        UpdateResult result = check updateProperty(value);
        log:printInfo("listing updated",
            property = result.property.property_id, changed = result.changed);
        string summary = result.changed.length() == 0
            ? string `No changes applied to ${result.property.property_id} - ` +
                "every supplied value already matched."
            : string `Updated ${result.property.property_id}: ` +
                string:'join(", ", ...result.changed);
        return {
            property: result.property,
            changed_fields: result.changed,
            message: summary
        };
    }

    // --- remove_property: simple RPC ---------------------------------------

    // The reply carries the host's region's remaining available stock, as the
    // contract requires.
    remote function remove_property(RemovePropertyRequest value)
            returns RemovePropertyResponse|error {
        RemoveResult result = check removeProperty(value.property_id, value.host_id);
        log:printInfo("listing removed",
            property = result.removed.property_id, region = result.removed.region,
            remainingInRegion = result.remaining.length());
        return {
            removed_property_id: result.removed.property_id,
            region: result.removed.region,
            available_in_region: result.remaining,
            message: string `'${result.removed.name}' removed. ` +
                string `${result.remaining.length()} property(ies) still available in ` +
                string `${result.removed.region}.`
        };
    }

    // --- list_available_properties: server-side streaming ------------------

    // Uses the generated caller so each match is written to the wire as its own
    // message - the guest's client can start rendering the first property before
    // the server has finished scanning the rest.
    remote function list_available_properties(RentalServicePropertyCaller caller,
            ListAvailableRequest value) returns error? {
        Property[]|grpc:Error matches = findAvailable(value);
        if matches is grpc:Error {
            // Surfacing the status code to the client, then closing the stream.
            check caller->sendError(matches);
            return;
        }
        log:printInfo("streaming available properties",
            count = matches.length(), location = value.location, region = value.region);
        foreach Property property in matches {
            check caller->sendProperty(property);
        }
        check caller->complete();
    }

    // --- search_property: simple RPC ---------------------------------------

    // A miss is a normal answer here, not an error: the contract asks for a
    // "Not Available" status rather than a NOT_FOUND failure.
    remote function search_property(SearchPropertyRequest value)
            returns SearchPropertyResponse|error {
        string propertyId = value.property_id.trim();
        if propertyId == "" {
            return error grpc:InvalidArgumentError("property_id is required");
        }
        Property? found = getProperty(propertyId);
        if found is () {
            return {
                found: false,
                availability: "NOT AVAILABLE",
                message: string `No property is registered under '${propertyId}'.`
            };
        }
        boolean bookable = found.status == AVAILABLE;
        return {
            found: true,
            availability: bookable ? "AVAILABLE" : "NOT AVAILABLE",
            property: found,
            message: bookable
                ? string `'${found.name}' in ${found.location}, ${found.region} - ` +
                    string `N$${money(found.price_per_night)}/night, sleeps ${found.max_guests}.`
                : string `'${found.name}' exists but is currently ${found.status}.`
        };
    }

    // --- book_property: simple RPC -----------------------------------------

    // Validates the request and parks it in the guest's temporary cart. Nothing
    // is committed until confirm_booking.
    remote function book_property(BookPropertyRequest value) returns BookPropertyResponse|error {
        CartItem item = check addToCart(value);
        int cartSize = cartFor(item.guest_id).length();
        log:printInfo("added to booking cart",
            cartItem = item.cart_item_id, guest = item.guest_id, property = item.property_id);
        return {
            cart_item_id: item.cart_item_id,
            property_id: item.property_id,
            property_name: item.property_name,
            check_in: item.check_in,
            check_out: item.check_out,
            nights: item.nights,
            price_per_night: item.price_per_night,
            estimated_total: item.estimated_total,
            cart_size: cartSize,
            message: string `'${item.property_name}' held for ${item.check_in} to ` +
                string `${item.check_out} (${item.nights} night(s)) - estimated ` +
                string `N$${money(item.estimated_total)}. Call confirm_booking to finalise.`
        };
    }

    // --- confirm_booking: simple RPC ---------------------------------------

    remote function confirm_booking(ConfirmBookingRequest value)
            returns ConfirmBookingResponse|error {
        ConfirmResult result = check confirmBooking(value.guest_id, value.cart_item_id);
        log:printInfo("bookings confirmed",
            guest = value.guest_id, confirmed = result.bookings.length(),
            rejected = result.rejected.length(), total = result.grandTotal);

        string message;
        if result.bookings.length() == 0 {
            message = string `Nothing could be confirmed. ` +
                string `${result.rejected.length()} item(s) were rejected.`;
        } else {
            message = string `${result.bookings.length()} booking(s) confirmed for a total ` +
                string `of N$${money(result.grandTotal)}.`;
            if result.rejected.length() > 0 {
                message += string ` ${result.rejected.length()} item(s) could not be ` +
                    "confirmed and remain in the cart.";
            }
        }
        return {
            bookings: result.bookings,
            grand_total: result.grandTotal,
            cart_remaining: result.remaining,
            rejected: result.rejected,
            message: message
        };
    }
}
