import ballerina/http;
import ballerina/url;

// Thin typed wrapper over the REST API.
//
// Every call returns either the decoded record or an `error` whose message has
// already been unpacked from the service's uniform JSON error body, so the menu
// code never has to think about status codes.

// Override with: bal run -- -CapiUrl=http://localhost:9091/library
configurable string apiUrl = "http://localhost:9090/library";

final http:Client api = check new (apiUrl);

// The service replies to every failure with the same JSON shape; this pulls the
// human-readable part back out of the client error the HTTP module raises.
public isolated function explain(error e) returns string {
    if e is http:ClientRequestError {
        return describe(e.detail());
    }
    if e is http:RemoteServerError {
        return describe(e.detail());
    }
    return e.message();
}

isolated function describe(http:Detail detail) returns string {
    anydata body = detail.body;
    if body is map<anydata> {
        anydata message = body["message"];
        if message is string {
            anydata code = body["code"];
            string label = code is string ? code : "ERROR";
            return string `[${detail.statusCode}] ${label}: ${message}`;
        }
    }
    return string `[${detail.statusCode}] ${body.toString()}`;
}

// Path segments may contain spaces ("Main Campus - Library"), so they are
// percent-encoded before being spliced into a URL.
isolated function enc(string segment) returns string {
    string|url:Error encoded = url:encode(segment, "UTF-8");
    return encoded is string ? encoded : segment;
}

// --- reads -----------------------------------------------------------------

public isolated function fetchSummary() returns Summary|error {
    return api->get("/summary");
}

public isolated function fetchInstitutions() returns Institution[]|error {
    return api->get("/institutions");
}

// Global view when both filters are (), campus view otherwise.
public isolated function fetchAssets(string? institution = (), string? site = (),
        string? status = ()) returns Asset[]|error {
    string[] query = [];
    if institution is string && institution.trim().length() > 0 {
        query.push(string `institution=${enc(institution)}`);
    }
    if site is string && site.trim().length() > 0 {
        query.push(string `site=${enc(site)}`);
    }
    if status is string && status.trim().length() > 0 {
        query.push(string `status=${enc(status)}`);
    }
    string path = query.length() == 0
        ? "/assets"
        : "/assets?" + string:'join("&", ...query);
    return api->get(path);
}

public isolated function fetchAsset(string assetTag) returns Asset|error {
    return api->get(string `/assets/${enc(assetTag)}`);
}

public isolated function fetchAvailability(string assetTag) returns AvailabilityView|error {
    return api->get(string `/assets/${enc(assetTag)}/availability`);
}

public isolated function fetchSchedules(string assetTag) returns Schedule[]|error {
    return api->get(string `/assets/${enc(assetTag)}/schedules`);
}

public isolated function fetchWorkOrders(string assetTag) returns WorkOrder[]|error {
    return api->get(string `/assets/${enc(assetTag)}/workorders`);
}

public isolated function fetchOverdue(string? institution = (), string? site = ())
        returns OverdueReport|error {
    string[] query = [];
    if institution is string && institution.trim().length() > 0 {
        query.push(string `institution=${enc(institution)}`);
    }
    if site is string && site.trim().length() > 0 {
        query.push(string `site=${enc(site)}`);
    }
    string path = query.length() == 0
        ? "/maintenance/overdue"
        : "/maintenance/overdue?" + string:'join("&", ...query);
    return api->get(path);
}

// --- assets ----------------------------------------------------------------

public isolated function createAsset(AssetInput input) returns Asset|error {
    return api->post("/assets", input);
}

public isolated function updateAsset(string assetTag, AssetPatch patch) returns Asset|error {
    return api->patch(string `/assets/${enc(assetTag)}`, patch);
}

public isolated function deleteAsset(string assetTag) returns Asset|error {
    return api->delete(string `/assets/${enc(assetTag)}`);
}

// --- loans and bookings ----------------------------------------------------

public isolated function loan(string assetTag, LoanRequest request) returns LoanReceipt|error {
    return api->post(string `/assets/${enc(assetTag)}/loans`, request);
}

public isolated function returnItem(string assetTag) returns ReturnReceipt|error {
    return api->post(string `/assets/${enc(assetTag)}/returns`, ());
}

public isolated function book(string assetTag, BookingRequest request)
        returns BookingReceipt|error {
    return api->post(string `/assets/${enc(assetTag)}/bookings`, request);
}

public isolated function cancelBooking(string assetTag, string scheduleId)
        returns Schedule|error {
    return api->delete(string `/assets/${enc(assetTag)}/bookings/${enc(scheduleId)}`);
}

// --- schedules -------------------------------------------------------------

public isolated function addSchedule(string assetTag, ScheduleInput input)
        returns Schedule|error {
    return api->post(string `/assets/${enc(assetTag)}/schedules`, input);
}

public isolated function modifySchedule(string assetTag, string scheduleId, SchedulePatch patch)
        returns Schedule|error {
    return api->put(string `/assets/${enc(assetTag)}/schedules/${enc(scheduleId)}`, patch);
}

public isolated function removeSchedule(string assetTag, string scheduleId)
        returns Schedule|error {
    return api->delete(string `/assets/${enc(assetTag)}/schedules/${enc(scheduleId)}`);
}

// --- components ------------------------------------------------------------

public isolated function addComponent(string assetTag, ComponentInput input)
        returns Component|error {
    return api->post(string `/assets/${enc(assetTag)}/components`, input);
}

public isolated function removeComponent(string assetTag, string compId)
        returns Component|error {
    return api->delete(string `/assets/${enc(assetTag)}/components/${enc(compId)}`);
}

// --- work orders -----------------------------------------------------------

public isolated function openWorkOrder(string assetTag, WorkOrderInput input)
        returns WorkOrder|error {
    return api->post(string `/assets/${enc(assetTag)}/workorders`, input);
}

public isolated function updateWorkOrder(string assetTag, string orderId, WorkOrderPatch patch)
        returns WorkOrder|error {
    return api->patch(string `/assets/${enc(assetTag)}/workorders/${enc(orderId)}`, patch);
}

public isolated function completeTask(string assetTag, string orderId, string taskId)
        returns Task|error {
    return api->patch(string `/assets/${enc(assetTag)}/workorders/${enc(orderId)}/tasks/${enc(taskId)}`,
        {status: "DONE"});
}

// --- institutions ----------------------------------------------------------

public isolated function addInstitution(InstitutionInput input) returns Institution|error {
    return api->post("/institutions", input);
}

public isolated function removeInstitution(string code) returns Institution|error {
    return api->delete(string `/institutions/${enc(code)}`);
}

public isolated function addSite(string code, string site) returns Institution|error {
    return api->post(string `/institutions/${enc(code)}/sites`, {site: site});
}

public isolated function removeSite(string code, string site) returns Institution|error {
    return api->delete(string `/institutions/${enc(code)}/sites/${enc(site)}`);
}
