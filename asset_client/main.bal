import ballerina/io;
import ballerina/time;

// Command-line front end for the Library and Resource Management API.
//
//   bal run                 interactive menu
//   bal run -- demo         scripted walk-through of every feature
//
// Both modes talk to the service purely over HTTP/REST via `api.bal`.

public function main(string... args) returns error? {
    if args.length() > 0 && args[0].toLowerAscii() == "demo" {
        return runDemo();
    }
    return runMenu();
}

// ---------------------------------------------------------------------------
// Interactive menu
// ---------------------------------------------------------------------------

function runMenu() returns error? {
    io:println();
    io:println("=========================================================");
    io:println("  Distributed Library and Resource Management System");
    io:println("  Ministry of Higher Education, Training and Innovations");
    io:println(string `  Connected to: ${apiUrl}`);
    io:println("=========================================================");

    Summary|error probe = fetchSummary();
    if probe is error {
        failure(string `Cannot reach the API at ${apiUrl} - ${explain(probe)}`);
        failure("Start the service first:  cd asset_service && bal run");
        return;
    }
    printSummary(probe);

    while true {
        io:println();
        io:println("  ---------------- MAIN MENU ----------------");
        io:println("   1  Global view - every asset in the ministry");
        io:println("   2  Campus view - filter by institution / site");
        io:println("   3  Overdue dashboard");
        io:println("   4  Loan an asset out");
        io:println("   5  Take a loaned asset back");
        io:println("   6  Book a lab / meeting room");
        io:println("   7  Cancel a booking");
        io:println("   8  Schedule manager (add / modify / remove)");
        io:println("   9  Asset details and availability");
        io:println("  10  Create an asset");
        io:println("  11  Update an asset's status");
        io:println("  12  Delete an asset");
        io:println("  13  Institution manager");
        io:println("  14  Work orders");
        io:println("  15  Refresh summary");
        io:println("   0  Exit");
        string choice = ask("  Choose");

        match choice {
            "1" => {
                doGlobalView();
            }
            "2" => {
                doCampusView();
            }
            "3" => {
                doOverdue();
            }
            "4" => {
                doLoan();
            }
            "5" => {
                doReturn();
            }
            "6" => {
                doBooking();
            }
            "7" => {
                doCancelBooking();
            }
            "8" => {
                doScheduleManager();
            }
            "9" => {
                doAssetDetail();
            }
            "10" => {
                doCreateAsset();
            }
            "11" => {
                doUpdateStatus();
            }
            "12" => {
                doDeleteAsset();
            }
            "13" => {
                doInstitutionManager();
            }
            "14" => {
                doWorkOrders();
            }
            "15" => {
                Summary|error summary = fetchSummary();
                if summary is error {
                    failure(explain(summary));
                } else {
                    printSummary(summary);
                }
            }
            "0" => {
                io:println("  Goodbye.");
                return;
            }
            _ => {
                failure("Unknown option. Enter a number from the menu.");
            }
        }
    }
}

function ask(string prompt) returns string {
    return io:readln(prompt + ": ").trim();
}

// Prompts until the answer is one of `allowed`, or blank if `optional`.
function askChoice(string prompt, string[] allowed, boolean optional = false) returns string {
    while true {
        string answer = ask(string `${prompt} [${string:'join("/", ...allowed)}]`).toUpperAscii();
        if answer == "" && optional {
            return "";
        }
        if allowed.indexOf(answer) is int {
            return answer;
        }
        failure("Please enter one of: " + string:'join(", ", ...allowed));
    }
}

// --- menu actions ----------------------------------------------------------

function doGlobalView() {
    Asset[]|error assets = fetchAssets();
    if assets is error {
        failure(explain(assets));
        return;
    }
    printAssets(assets, "Global view - all assets across the ministry");
}

function doCampusView() {
    Institution[]|error institutions = fetchInstitutions();
    if institutions is error {
        failure(explain(institutions));
        return;
    }
    printInstitutions(institutions);
    string code = ask("  Institution code or name (blank = all)");
    string site = ask("  Site / campus (blank = all)");
    Asset[]|error assets = fetchAssets(code, site);
    if assets is error {
        failure(explain(assets));
        return;
    }
    string scope = code == "" ? "all institutions" : code;
    printAssets(assets, string `Campus view - ${scope}${site == "" ? "" : " / " + site}`);
}

function doOverdue() {
    string code = ask("  Restrict to institution (blank = ministry-wide)");
    OverdueReport|error report = fetchOverdue(code);
    if report is error {
        failure(explain(report));
        return;
    }
    printOverdue(report, code == "" ? "ministry-wide" : code);
}

function doLoan() {
    Asset[]|error available = fetchAssets((), (), "AVAILABLE");
    if available is error {
        failure(explain(available));
        return;
    }
    printAssets(available, "Assets available to loan");
    string tag = ask("  Asset tag to loan");
    string borrower = ask("  Borrower (student/staff number and name)");
    string dueDate = ask("  Return due date (yyyy-MM-dd)");
    string notes = ask("  Notes (optional)");

    LoanReceipt|error receipt = loan(tag, {borrower: borrower, dueDate: dueDate, notes: notes});
    if receipt is error {
        failure(explain(receipt));
        return;
    }
    success(string `${receipt.assetTag} loaned to ${receipt.borrower}, due ${receipt.dueDate}.`);
    note(string `Status is now ${receipt.status}; return schedule ${receipt.scheduleId} created.`);
}

function doReturn() {
    Asset[]|error onLoan = fetchAssets((), (), "LOANED_OUT");
    if onLoan is error {
        failure(explain(onLoan));
        return;
    }
    printAssets(onLoan, "Assets currently on loan");
    string tag = ask("  Asset tag to return");
    ReturnReceipt|error receipt = returnItem(tag);
    if receipt is error {
        failure(explain(receipt));
        return;
    }
    success(string `${receipt.assetTag} returned by ${receipt.borrower}.`);
    if receipt.daysLate > 0 {
        note(string `Returned ${receipt.daysLate} day(s) late (was due ${receipt.dueDate}).`);
    } else {
        note("Returned on time.");
    }
    note(string `Status is now ${receipt.status}.`);
}

function doBooking() {
    Asset[]|error spaces = fetchAssets((), (), "AVAILABLE");
    if spaces is error {
        failure(explain(spaces));
        return;
    }
    printAssets(spaces, "Bookable resources");
    string tag = ask("  Asset tag to book");
    string reservedBy = ask("  Reserved by");
    string startDate = ask("  Start date (yyyy-MM-dd)");
    string endDate = ask("  End date (yyyy-MM-dd)");
    string purpose = ask("  Purpose (optional)");

    BookingReceipt|error receipt = book(tag, {
        reservedBy: reservedBy,
        startDate: startDate,
        endDate: endDate,
        purpose: purpose
    });
    if receipt is error {
        failure(explain(receipt));
        return;
    }
    success(string `${receipt.assetTag} booked for ${receipt.reservedBy}.`);
    note(string `${receipt.startDate} to ${receipt.endDate} (${receipt.days} day(s)), ` +
        string `booking id ${receipt.scheduleId}, status ${receipt.status}.`);
}

function doCancelBooking() {
    string tag = ask("  Asset tag");
    Schedule[]|error schedules = fetchSchedules(tag);
    if schedules is error {
        failure(explain(schedules));
        return;
    }
    printSchedules(schedules, tag);
    string scheduleId = ask("  Booking id to cancel");
    Schedule|error cancelled = cancelBooking(tag, scheduleId);
    if cancelled is error {
        failure(explain(cancelled));
        return;
    }
    success(string `Cancelled ${cancelled.scheduleId} (${cancelled.'type}) on ${tag}.`);
}

function doScheduleManager() {
    string tag = ask("  Asset tag");
    Schedule[]|error current = fetchSchedules(tag);
    if current is error {
        failure(explain(current));
        return;
    }
    printSchedules(current, tag);

    io:println();
    io:println("   a  Add a schedule");
    io:println("   m  Modify a schedule");
    io:println("   r  Remove a schedule");
    string action = ask("  Choose").toLowerAscii();

    if action == "a" {
        string scheduleType = askChoice("  Type", ["MAINTENANCE", "SERVICING", "BOOKING"]);
        string dueDate = ask("  Due / start date (yyyy-MM-dd)");
        string endDate = ask("  End date (blank if none)");
        string description = ask("  Description");
        ScheduleInput input = {
            'type: <ScheduleType>scheduleType,
            dueDate: dueDate,
            description: description
        };
        if endDate != "" {
            input.endDate = endDate;
        }
        Schedule|error created = addSchedule(tag, input);
        if created is error {
            failure(explain(created));
            return;
        }
        success(string `Added ${created.scheduleId} (${created.'type}) due ${created.dueDate}.`);
    } else if action == "m" {
        string scheduleId = ask("  Schedule id to modify");
        string dueDate = ask("  New due date (blank to keep)");
        string description = ask("  New description (blank to keep)");
        SchedulePatch patch = {};
        if dueDate != "" {
            patch.dueDate = dueDate;
        }
        if description != "" {
            patch.description = description;
        }
        Schedule|error updated = modifySchedule(tag, scheduleId, patch);
        if updated is error {
            failure(explain(updated));
            return;
        }
        success(string `${updated.scheduleId} now due ${updated.dueDate}: ${updated.description}`);
    } else if action == "r" {
        string scheduleId = ask("  Schedule id to remove");
        Schedule|error removed = removeSchedule(tag, scheduleId);
        if removed is error {
            failure(explain(removed));
            return;
        }
        success(string `Removed ${removed.scheduleId}.`);
    } else {
        failure("Unknown action.");
    }
}

function doAssetDetail() {
    string tag = ask("  Asset tag");
    Asset|error asset = fetchAsset(tag);
    if asset is error {
        failure(explain(asset));
        return;
    }
    printAssetDetail(asset);
    AvailabilityView|error view = fetchAvailability(tag);
    if view is AvailabilityView {
        printAvailability(view);
    }
}

function doCreateAsset() {
    Institution[]|error institutions = fetchInstitutions();
    if institutions is error {
        failure(explain(institutions));
        return;
    }
    printInstitutions(institutions);
    string tag = ask("  Asset tag (unique)");
    string name = ask("  Name");
    string description = ask("  Description");
    string institution = ask("  Institution (code or full name)");
    string site = ask("  Site / campus (must be listed above)");
    string dateAcquired = ask("  Date acquired (yyyy-MM-dd)");

    Asset|error created = createAsset({
        assetTag: tag,
        name: name,
        description: description,
        institution: institution,
        site: site,
        dateAcquired: dateAcquired
    });
    if created is error {
        failure(explain(created));
        return;
    }
    success(string `Created ${created.assetTag} at ${created.institution} / ${created.site}.`);
}

function doUpdateStatus() {
    string tag = ask("  Asset tag");
    string status = askChoice("  New status",
        ["AVAILABLE", "LOANED_OUT", "OCCUPIED", "UNDER_MAINTENANCE", "DISPOSED"]);
    Asset|error updated = updateAsset(tag, {status: <AssetStatus>status});
    if updated is error {
        failure(explain(updated));
        return;
    }
    success(string `${updated.assetTag} is now ${updated.status}.`);
}

function doDeleteAsset() {
    string tag = ask("  Asset tag to delete");
    string confirm = ask(string `  Type the tag again to confirm deletion of ${tag}`);
    if confirm != tag {
        failure("Confirmation did not match; nothing deleted.");
        return;
    }
    Asset|error removed = deleteAsset(tag);
    if removed is error {
        failure(explain(removed));
        return;
    }
    success(string `Deleted ${removed.assetTag} - ${removed.name}.`);
}

function doInstitutionManager() {
    Institution[]|error institutions = fetchInstitutions();
    if institutions is error {
        failure(explain(institutions));
        return;
    }
    printInstitutions(institutions);

    io:println();
    io:println("   a  Add an institution");
    io:println("   r  Remove an institution");
    io:println("   s  Add a site / campus");
    io:println("   d  Remove a site / campus");
    string action = ask("  Choose").toLowerAscii();

    if action == "a" {
        string code = ask("  Code (e.g. NUST)");
        string name = ask("  Full name");
        string sites = ask("  Sites, comma separated");
        string[] siteList = [];
        foreach string part in re `,`.split(sites) {
            if part.trim() != "" {
                siteList.push(part.trim());
            }
        }
        Institution|error created = addInstitution({code: code, name: name, sites: siteList});
        if created is error {
            failure(explain(created));
            return;
        }
        success(string `Registered ${created.code} - ${created.name}.`);
    } else if action == "r" {
        string code = ask("  Code to remove");
        Institution|error removed = removeInstitution(code);
        if removed is error {
            failure(explain(removed));
            return;
        }
        success(string `Removed ${removed.code} from the listings.`);
    } else if action == "s" {
        string code = ask("  Institution code");
        string site = ask("  New site / campus");
        Institution|error updated = addSite(code, site);
        if updated is error {
            failure(explain(updated));
            return;
        }
        success(string `${updated.code} now has ${updated.sites.length()} site(s).`);
    } else if action == "d" {
        string code = ask("  Institution code");
        string site = ask("  Site / campus to remove");
        Institution|error updated = removeSite(code, site);
        if updated is error {
            failure(explain(updated));
            return;
        }
        success(string `${updated.code} now has ${updated.sites.length()} site(s).`);
    } else {
        failure("Unknown action.");
    }
}

function doWorkOrders() {
    string tag = ask("  Asset tag");
    WorkOrder[]|error orders = fetchWorkOrders(tag);
    if orders is error {
        failure(explain(orders));
        return;
    }
    heading(string `Work orders on ${tag}`);
    if orders.length() == 0 {
        note("No work orders raised.");
    }
    foreach WorkOrder workOrder in orders {
        io:println(string `  [${workOrder.orderId}] ${workOrder.status}: ${workOrder.description}`);
        foreach Task task in workOrder.tasks {
            io:println(string `      * [${task.taskId}] ${task.status} - ${task.description}`);
        }
    }

    io:println();
    io:println("   o  Open a work order");
    io:println("   t  Mark a task DONE");
    io:println("   c  Close a work order");
    string action = ask("  Choose").toLowerAscii();

    if action == "o" {
        string description = ask("  Fault description");
        WorkOrder|error created = openWorkOrder(tag, {description: description});
        if created is error {
            failure(explain(created));
            return;
        }
        success(string `Opened ${created.orderId} on ${tag}.`);
    } else if action == "t" {
        string orderId = ask("  Work order id");
        string taskId = ask("  Task id");
        Task|error updated = completeTask(tag, orderId, taskId);
        if updated is error {
            failure(explain(updated));
            return;
        }
        success(string `Task ${updated.taskId} marked ${updated.status}.`);
    } else if action == "c" {
        string orderId = ask("  Work order id to close");
        WorkOrder|error closed = updateWorkOrder(tag, orderId, {status: CLOSED});
        if closed is error {
            failure(explain(closed));
            return;
        }
        success(string `${closed.orderId} is now ${closed.status}.`);
    } else {
        failure("Unknown action.");
    }
}

// ---------------------------------------------------------------------------
// Scripted demonstration
// ---------------------------------------------------------------------------

// Runs one pass over every client requirement without needing a human at the
// keyboard: viewing, loaning, booking, scheduling and error handling.
function runDemo() returns error? {
    io:println();
    io:println("=========================================================");
    io:println("  SCRIPTED DEMONSTRATION");
    io:println(string `  Target: ${apiUrl}`);
    io:println("=========================================================");

    Summary|error probe = fetchSummary();
    if probe is error {
        failure(string `Cannot reach the API - ${explain(probe)}`);
        failure("Start the service first:  cd asset_service && bal run");
        return probe;
    }
    printSummary(probe);

    // Unique suffix so the demo can be re-run against a live server.
    time:Civil now = time:utcToCivil(time:utcNow());
    string run = string `${now.hour.toString().padZero(2)}${now.minute.toString().padZero(2)}` +
        (<int>(now.second ?: 0d)).toString().padZero(2);

    // 1 - global view
    Asset[] all = check fetchAssets();
    printAssets(all, "1. Global view - every asset across the ministry");

    // 2 - campus view
    Asset[] campus = check fetchAssets("NUST", "Main Campus - Library");
    printAssets(campus, "2. Campus view - NUST / Main Campus - Library");

    // 3 - overdue dashboard, ministry-wide then narrowed
    printOverdue(check fetchOverdue(), "ministry-wide");
    printOverdue(check fetchOverdue("NUST"), "NUST only");

    // 4 - institution management
    heading("4. Institution manager");
    string code = string `DEMO${run}`;
    Institution registered = check addInstitution({
        code: code,
        name: string `Demo Institute ${run}`,
        sites: ["Demo Campus"]
    });
    success(string `Registered ${registered.code} - ${registered.name}`);
    Institution withSite = check addSite(code, "Second Campus");
    success(string `Sites now: ${string:'join(", ", ...withSite.sites)}`);
    Institution withoutSite = check removeSite(code, "Second Campus");
    success(string `After removal: ${string:'join(", ", ...withoutSite.sites)}`);

    // 5 - create an asset under the new institution
    heading("5. Create an asset");
    string demoTag = string `DEMO-LT-${run}`;
    Asset created = check createAsset({
        assetTag: demoTag,
        name: "Demonstration Laptop",
        description: "Created by the scripted client demo.",
        institution: code,
        site: "Demo Campus",
        dateAcquired: "2026-01-15"
    });
    success(string `Created ${created.assetTag} at ${created.institution} / ${created.site}`);

    // 6 - loaning
    heading("6. Loaning");
    LoanReceipt receipt = check loan(demoTag, {
        borrower: "222055555 - Demo Student",
        dueDate: check plusDays(30),
        notes: "Semester loan issued by the CLI demo."
    });
    success(string `Loaned to ${receipt.borrower}, due ${receipt.dueDate} (${receipt.status})`);
    printAvailability(check fetchAvailability(demoTag));

    LoanReceipt|error doubleLoan = loan(demoTag, {borrower: "Someone else", dueDate: check plusDays(10)});
    if doubleLoan is error {
        success("Second loan correctly refused - " + explain(doubleLoan));
    } else {
        failure("BUG: the same asset was loaned out twice.");
    }

    ReturnReceipt returned = check returnItem(demoTag);
    success(string `Returned by ${returned.borrower}; ${returned.daysLate} day(s) late; ` +
        string `status ${returned.status}`);

    // 7 - booking a space, including the overlap rule
    heading("7. Booking a lab / meeting room");
    string bookFrom = check plusDays(60);
    string bookTo = check plusDays(62);
    BookingReceipt booking = check book("NUST-LAB-MR-014", {
        reservedBy: "DSA612S Group 7",
        startDate: bookFrom,
        endDate: bookTo,
        purpose: "Assignment 1 presentation rehearsal"
    });
    success(string `Booked ${booking.assetTag} ${booking.startDate}..${booking.endDate} ` +
        string `(${booking.days} days) as ${booking.scheduleId}`);

    BookingReceipt|error clash = book("NUST-LAB-MR-014", {
        reservedBy: "Another group",
        startDate: check plusDays(61),
        endDate: check plusDays(63),
        purpose: "Should be refused"
    });
    if clash is error {
        success("Overlapping booking correctly refused - " + explain(clash));
    } else {
        failure("BUG: overlapping bookings were both accepted.");
    }
    printSchedules(check fetchSchedules("NUST-LAB-MR-014"), "NUST-LAB-MR-014");
    Schedule cancelled = check cancelBooking("NUST-LAB-MR-014", booking.scheduleId);
    success(string `Cancelled booking ${cancelled.scheduleId}`);

    // 8 - schedule manager
    heading("8. Schedule manager");
    Schedule added = check addSchedule(demoTag, {
        'type: MAINTENANCE,
        dueDate: check plusDays(90),
        description: "Annual service"
    });
    success(string `Added ${added.scheduleId} due ${added.dueDate}`);
    Schedule moved = check modifySchedule(demoTag, added.scheduleId, {
        dueDate: check plusDays(120),
        description: "Annual service (rescheduled)"
    });
    success(string `Moved to ${moved.dueDate}: ${moved.description}`);
    printSchedules(check fetchSchedules(demoTag), demoTag);
    Schedule dropped = check removeSchedule(demoTag, moved.scheduleId);
    success(string `Removed ${dropped.scheduleId}`);

    // 9 - components and work orders
    heading("9. Components and work orders");
    Component component = check addComponent(demoTag,
        {name: "Battery Pack", description: "56Wh replaceable cell"});
    success(string `Added component ${component.compId} - ${component.name}`);

    WorkOrder workOrder = check openWorkOrder(demoTag, {
        description: "Screen flickers under load",
        tasks: [{taskId: "T-DEMO-1", description: "Reseat display cable"}]
    });
    success(string `Opened ${workOrder.orderId}; asset is now UNDER_MAINTENANCE`);

    WorkOrder|error prematureClose = updateWorkOrder(demoTag, workOrder.orderId, {status: CLOSED});
    if prematureClose is error {
        success("Closing with an unfinished task correctly refused - " + explain(prematureClose));
    } else {
        failure("BUG: a work order closed with outstanding tasks.");
    }
    Task done = check completeTask(demoTag, workOrder.orderId, "T-DEMO-1");
    success(string `Task ${done.taskId} marked ${done.status}`);
    WorkOrder closed = check updateWorkOrder(demoTag, workOrder.orderId, {status: CLOSED});
    success(string `${closed.orderId} is now ${closed.status}`);
    printAssetDetail(check fetchAsset(demoTag));

    // 10 - error handling on wrong API calls
    heading("10. Error handling");
    demoFailure("Unknown asset", fetchAsset("NO-SUCH-TAG"));
    demoFailure("Duplicate asset tag", createAsset({
        assetTag: demoTag,
        name: "Duplicate",
        institution: code,
        site: "Demo Campus",
        dateAcquired: "2026-01-15"
    }));
    demoFailure("Impossible date", createAsset({
        assetTag: string `BAD-${run}`,
        name: "Bad date",
        institution: code,
        site: "Demo Campus",
        dateAcquired: "2026-02-30"
    }));
    demoFailure("Unregistered institution", createAsset({
        assetTag: string `BAD2-${run}`,
        name: "Bad institution",
        institution: "Hogwarts School of Engineering",
        site: "Nowhere",
        dateAcquired: "2026-01-15"
    }));
    demoFailure("Removing an institution that still owns assets", removeInstitution(code));

    // 11 - tidy up so the demo can be re-run
    heading("11. Clean-up");
    Component removedComponent = check removeComponent(demoTag, component.compId);
    success(string `Removed component ${removedComponent.compId}`);
    Asset deleted = check deleteAsset(demoTag);
    success(string `Deleted ${deleted.assetTag}`);
    Institution deregistered = check removeInstitution(code);
    success(string `Deregistered ${deregistered.code}`);

    printSummary(check fetchSummary());
    io:println();
    io:println("  Demonstration complete.");
    return;
}

// Prints the outcome of a call that is expected to fail.
function demoFailure(string label, any|error outcome) {
    if outcome is error {
        success(string `${label} correctly rejected - ${explain(outcome)}`);
    } else {
        failure(string `BUG: ${label} was accepted when it should have been rejected.`);
    }
}

// Today plus `days`, as `yyyy-MM-dd`.
function plusDays(int days) returns string|error {
    time:Utc target = time:utcAddSeconds(time:utcNow(), <decimal>days * 86400d);
    time:Civil civil = time:utcToCivil(target);
    return string `${civil.year.toString().padZero(4)}-` +
        string `${civil.month.toString().padZero(2)}-${civil.day.toString().padZero(2)}`;
}
