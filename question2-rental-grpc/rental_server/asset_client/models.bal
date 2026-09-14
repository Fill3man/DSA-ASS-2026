// Client-side view of the API's data model.
//
// These records mirror `asset_service/types.bal`. They are declared again here
// on purpose: the client is a separate process that only knows the service
// through its HTTP contract, so it keeps its own bindings rather than sharing
// compiled code with the server.

public enum AssetStatus {
    AVAILABLE,
    LOANED_OUT,
    OCCUPIED,
    UNDER_MAINTENANCE,
    DISPOSED
}

public enum ScheduleType {
    MAINTENANCE,
    SERVICING,
    BOOKING,
    RETURN
}

public enum WorkOrderStatus {
    OPEN,
    IN_PROGRESS,
    CLOSED
}

public enum TaskStatus {
    PENDING,
    DONE
}

public type Component record {|
    string compId;
    string name;
    string description = "";
|};

public type Schedule record {|
    string scheduleId;
    ScheduleType 'type;
    string dueDate;
    string endDate?;
    string description = "";
    string reservedBy?;
|};

public type Task record {|
    string taskId;
    string description;
    TaskStatus status = PENDING;
|};

public type WorkOrder record {|
    string orderId;
    WorkOrderStatus status = OPEN;
    string description;
    string openedDate?;
    string closedDate?;
    Task[] tasks = [];
|};

public type Asset record {|
    string assetTag;
    string name;
    string description = "";
    string institution;
    string site;
    AssetStatus status = AVAILABLE;
    string dateAcquired;
    Component[] components = [];
    Schedule[] schedules = [];
    WorkOrder[] workOrders = [];
|};

public type Institution record {|
    string code;
    string name;
    string[] sites = [];
|};

// --- request bodies --------------------------------------------------------

public type AssetInput record {|
    string assetTag;
    string name;
    string description = "";
    string institution;
    string site;
    AssetStatus status = AVAILABLE;
    string dateAcquired;
    Component[] components = [];
    Schedule[] schedules = [];
    WorkOrder[] workOrders = [];
|};

public type AssetPatch record {|
    string name?;
    string description?;
    string institution?;
    string site?;
    AssetStatus status?;
    string dateAcquired?;
|};

public type InstitutionInput record {|
    string code;
    string name;
    string[] sites = [];
|};

public type SiteInput record {|
    string site;
|};

public type LoanRequest record {|
    string borrower;
    string dueDate;
    string notes = "";
|};

public type BookingRequest record {|
    string reservedBy;
    string startDate;
    string endDate;
    string purpose = "";
|};

public type ScheduleInput record {|
    string scheduleId?;
    ScheduleType 'type;
    string dueDate;
    string endDate?;
    string description = "";
    string reservedBy?;
|};

public type SchedulePatch record {|
    ScheduleType 'type?;
    string dueDate?;
    string endDate?;
    string description?;
    string reservedBy?;
|};

public type WorkOrderInput record {|
    string orderId?;
    WorkOrderStatus status = OPEN;
    string description;
    Task[] tasks = [];
|};

public type WorkOrderPatch record {|
    WorkOrderStatus status?;
    string description?;
|};

public type ComponentInput record {|
    string compId?;
    string name;
    string description = "";
|};

// --- response projections --------------------------------------------------

public type AvailabilityView record {|
    string assetTag;
    string name;
    AssetStatus status;
    boolean available;
    string institution;
    string site;
    Schedule[] upcomingSchedules;
    Schedule[] overdueSchedules;
    int openWorkOrders;
|};

public type OverdueItem record {|
    string assetTag;
    string name;
    string institution;
    string site;
    AssetStatus status;
    string scheduleId;
    ScheduleType 'type;
    string dueDate;
    string description;
    string reservedBy?;
    int daysOverdue;
|};

public type OverdueReport record {|
    string asOf;
    int count;
    OverdueItem[] items;
|};

public type LoanReceipt record {|
    string assetTag;
    string name;
    string borrower;
    string loanedOn;
    string dueDate;
    string scheduleId;
    AssetStatus status;
|};

public type ReturnReceipt record {|
    string assetTag;
    string name;
    string borrower;
    string dueDate;
    string returnedOn;
    int daysLate;
    AssetStatus status;
|};

public type BookingReceipt record {|
    string assetTag;
    string name;
    string reservedBy;
    string startDate;
    string endDate;
    int days;
    string scheduleId;
    AssetStatus status;
|};

public type Summary record {|
    string asOf;
    int totalAssets;
    int institutions;
    map<int> assetsByStatus;
    map<int> assetsByInstitution;
    int openWorkOrders;
    int overdueCount;
|};
