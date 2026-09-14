import ballerina/grpc;
import ballerina/io;

// Console rendering and gRPC error reporting for the rental client.

const string RULE = "-----------------------------------------------------------------------------------";

isolated function pad(string value, int width) returns string {
    if value.length() > width {
        return width <= 1 ? value.substring(0, width) : value.substring(0, width - 1) + "~";
    }
    return value.padEnd(width);
}

isolated function heading(string title) {
    io:println();
    io:println(RULE);
    io:println("  " + title.toUpperAscii());
    io:println(RULE);
}

isolated function note(string message) {
    io:println("  " + message);
}

isolated function success(string message) {
    io:println("  OK  " + message);
}

isolated function failure(string message) {
    io:println("  !!  " + message);
}

// The server raises typed `grpc:*Error`s, which carry real gRPC status codes.
// Recovering the code on this side is what lets a client branch on the reason a
// call failed rather than parsing the message text.
isolated function statusOf(error e) returns string {
    if e is grpc:InvalidArgumentError {
        return "INVALID_ARGUMENT";
    }
    if e is grpc:NotFoundError {
        return "NOT_FOUND";
    }
    if e is grpc:AlreadyExistsError {
        return "ALREADY_EXISTS";
    }
    if e is grpc:PermissionDeniedError {
        return "PERMISSION_DENIED";
    }
    if e is grpc:FailedPreconditionError {
        return "FAILED_PRECONDITION";
    }
    if e is grpc:AbortedError {
        return "ABORTED";
    }
    if e is grpc:UnavailableError {
        return "UNAVAILABLE";
    }
    if e is grpc:UnauthenticatedError {
        return "UNAUTHENTICATED";
    }
    if e is grpc:InternalError {
        return "INTERNAL";
    }
    if e is grpc:ResourceExhaustedError {
        return "RESOURCE_EXHAUSTED";
    }
    return "ERROR";
}

isolated function explain(error e) returns string {
    return string `[${statusOf(e)}] ${e.message()}`;
}

isolated function propertyHeader() {
    io:println("  " + pad("PROPERTY ID", 13) + pad("NAME", 34) + pad("LOCATION", 14) +
        pad("REGION", 10) + pad("TYPE", 13) + pad("N$/NIGHT", 11) + pad("SLEEPS", 8) + "STATUS");
    io:println("  " + "".padEnd(13, "-") + "".padEnd(34, "-") + "".padEnd(14, "-") +
        "".padEnd(10, "-") + "".padEnd(13, "-") + "".padEnd(11, "-") + "".padEnd(8, "-") +
        "".padEnd(14, "-"));
}

isolated function propertyRow(Property property) {
    io:println("  " + pad(property.property_id, 13) + pad(property.name, 34) +
        pad(property.location, 14) + pad(property.region, 10) +
        pad(property.property_type, 13) +
        pad(formatMoney(property.price_per_night), 11) +
        pad(property.max_guests.toString(), 8) + property.status);
}

isolated function printProperties(Property[] properties, string title) {
    heading(title);
    if properties.length() == 0 {
        note("No properties match.");
        return;
    }
    propertyHeader();
    foreach Property property in properties {
        propertyRow(property);
    }
    io:println();
    note(string `${properties.length()} property(ies).`);
}

isolated function printBookings(Booking[] bookings) {
    if bookings.length() == 0 {
        note("No bookings confirmed.");
        return;
    }
    io:println("  " + pad("BOOKING ID", 13) + pad("PROPERTY", 32) + pad("CHECK-IN", 12) +
        pad("CHECK-OUT", 12) + pad("NIGHTS", 8) + pad("N$/NIGHT", 11) + "TOTAL N$");
    io:println("  " + "".padEnd(13, "-") + "".padEnd(32, "-") + "".padEnd(12, "-") +
        "".padEnd(12, "-") + "".padEnd(8, "-") + "".padEnd(11, "-") + "".padEnd(12, "-"));
    foreach Booking booking in bookings {
        io:println("  " + pad(booking.booking_id, 13) + pad(booking.property_name, 32) +
            pad(booking.check_in, 12) + pad(booking.check_out, 12) +
            pad(booking.nights.toString(), 8) +
            pad(formatMoney(booking.price_per_night), 11) +
            formatMoney(booking.total_cost));
    }
}

// Two decimal places, so a price reads as 950.00 rather than 950.0.
isolated function formatMoney(float value) returns string {
    decimal exact = (<decimal>value).round(2);
    string text = exact.toString();
    int? dot = text.indexOf(".");
    if dot is () {
        return text + ".00";
    }
    int decimals = text.length() - dot - 1;
    if decimals == 1 {
        return text + "0";
    }
    return text;
}
