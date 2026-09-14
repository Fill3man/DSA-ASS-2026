import ballerina/grpc;
import ballerina/time;

// Dates, money and label helpers.
//
// Every date on the wire is an ISO-8601 calendar date (`yyyy-MM-dd`). Stay
// windows follow the usual accommodation convention: check-in is inclusive and
// check-out is exclusive, so 12th -> 14th is two nights and a stay ending on the
// 14th does not clash with one starting on the 14th.

const int SECONDS_PER_DAY = 86400;

public isolated function today() returns string {
    time:Civil civil = time:utcToCivil(time:utcNow());
    return formatDate(civil.year, civil.month, civil.day);
}

public isolated function formatDate(int year, int month, int day) returns string {
    return string `${year.toString().padZero(4)}-${month.toString().padZero(2)}-` +
        day.toString().padZero(2);
}

// Rejects anything that is not a real calendar date in `yyyy-MM-dd` form.
public isolated function validateDate(string label, string value) returns grpc:Error? {
    if value.length() != 10 {
        return error grpc:InvalidArgumentError(
            string `${label} '${value}' is not a valid date; expected yyyy-MM-dd`);
    }
    time:Utc|error parsed = time:utcFromString(value + "T00:00:00Z");
    if parsed is error {
        return error grpc:InvalidArgumentError(
            string `${label} '${value}' is not a real calendar date (expected yyyy-MM-dd)`);
    }
}

// Whole days between two already-validated dates; negative if `to` precedes `from`.
public isolated function dayCount(string fromDate, string toDate) returns int|grpc:Error {
    time:Utc|error a = time:utcFromString(fromDate + "T00:00:00Z");
    time:Utc|error b = time:utcFromString(toDate + "T00:00:00Z");
    if a is error || b is error {
        return error grpc:InternalError(
            string `could not measure the interval ${fromDate}..${toDate}`);
    }
    return <int>(time:utcDiffSeconds(b, a) / <decimal>SECONDS_PER_DAY);
}

// Half-open stay windows overlap iff each starts strictly before the other ends.
public isolated function staysOverlap(string aIn, string aOut, string bIn, string bOut)
        returns boolean {
    return aIn < bOut && bIn < aOut;
}

public isolated function shiftDays(string date, int days) returns string|grpc:Error {
    time:Utc|error base = time:utcFromString(date + "T00:00:00Z");
    if base is error {
        return error grpc:InternalError(string `cannot shift invalid date '${date}'`);
    }
    time:Civil civil = time:utcToCivil(
        time:utcAddSeconds(base, <decimal>days * <decimal>SECONDS_PER_DAY));
    return formatDate(civil.year, civil.month, civil.day);
}

// Prices are `double` on the wire; keep them to two decimal places so a total is
// never reported as 1234.5600000000001.
public isolated function round2(float value) returns float {
    decimal exact = <decimal>value;
    return <float>exact.round(2);
}

// Two decimal places for anything shown to a user, so a rate reads as 875.50
// rather than 875.5.
public isolated function money(float value) returns string {
    string text = (<decimal>value).round(2).toString();
    int? dot = text.indexOf(".");
    if dot is () {
        return text + ".00";
    }
    return text.length() - dot - 1 == 1 ? text + "0" : text;
}

public isolated function matchesLoosely(string actual, string candidate) returns boolean {
    return actual.toLowerAscii().trim() == candidate.toLowerAscii().trim();
}
