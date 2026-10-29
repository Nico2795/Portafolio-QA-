*** Settings ***
Documentation    Ordered offline reconciliation, replay and stale-manifest conflicts.
Resource    ../../resources/api.resource
Suite Setup    Start Test Environment
Suite Teardown    Stop Test Environment
Test Setup    Reset Synthetic Data
Test Tags    api    offline    sync    regression

*** Test Cases ***
SYN-001 Offline Boarding Then Departure Reconcile In Order
    [Tags]    smoke    critical
    ${boarding}=    New Offline Event    evt-001
    ${departure}=    New Offline Event    evt-002    kind=depart
    ${r}=    Sync Events    ${boarding}    ${departure}
    Should Be Equal    ${r.json()}[results][0][status]    accepted
    Should Be Equal    ${r.json()}[results][1][status]    accepted
    SQL Value Should Be    SELECT status FROM reservations WHERE id='R-001'    boarded
    SQL Value Should Be    SELECT status FROM trips WHERE id='T-001'    departed

SYN-002 Retrying Same Offline Batch Does Not Duplicate Operations
    [Tags]    critical    idempotency
    ${boarding}=    New Offline Event    evt-001    user=U-002
    ${departure}=    New Offline Event    evt-002    kind=depart
    Sync Events    ${boarding}    ${departure}
    ${retry}=    Sync Events    ${boarding}    ${departure}
    Should Be Equal    ${retry.json()}[results][0][replayed]    ${TRUE}
    Should Be Equal    ${retry.json()}[results][1][replayed]    ${TRUE}
    SQL Value Should Be    SELECT COUNT(*) FROM reservations WHERE user_id='U-002'    1
    SQL Value Should Be    SELECT COUNT(*) FROM events    2

SYN-003 Offline Passenger Without Reservation On Full Trip Is Rejected
    [Tags]    critical    negative
    ${event}=    New Offline Event    evt-full    user=U-002    trip=T-FULL
    ${r}=    Sync Events    ${event}
    Should Be Equal    ${r.json()}[results][0][code]    no_seats
    Should Be Equal    ${r.json()}[results][0][status]    rejected
    No Extra Reservation Should Exist

SYN-004 Stale Manifest Cannot Oversell Seats During Sync
    [Tags]    critical    conflict
    # Driver downloaded a manifest with two free seats. Both sell while offline.
    ${snapshot}=    GET On Session    driver    /api/driver/manifest/T-001    expected_status=200
    Should Be Equal As Integers    ${snapshot.json()}[available_seats]    2
    Buy Ticket
    Validate Passenger    user=U-005
    ${event}=    New Offline Event    evt-stale    user=U-006
    ${r}=    Sync Events    ${event}
    Should Be Equal    ${r.json()}[results][0][code]    no_seats
    SQL Value Should Be    SELECT COUNT(*) FROM reservations WHERE trip_id='T-001' AND status!='cancelled'    3
    SQL Value Should Be    SELECT COUNT(*) FROM reservations WHERE user_id='U-006'    0

SYN-005 Same Event ID With Different Payload Is A Conflict
    [Tags]    negative    idempotency
    ${first}=    New Offline Event    evt-001
    Sync Events    ${first}
    ${changed}=    New Offline Event    evt-001    user=U-002
    ${r}=    Sync Events    ${changed}
    Should Be Equal    ${r.json()}[results][0][code]    event_id_conflict
    No Extra Reservation Should Exist

SYN-006 Invalid Envelope Rejects Entire Batch Before Applying Events
    [Tags]    negative
    ${valid}=    New Offline Event    evt-001
    &{invalid}=    Create Dictionary    event_id=bad    kind=unknown
    @{events}=    Create List    ${valid}    ${invalid}
    &{body}=    Create Dictionary    events=${events}
    ${r}=    POST On Session    driver    /api/driver/sync    json=${body}    expected_status=422
    Error Should Be    ${r}    invalid_event
    SQL Value Should Be    SELECT COUNT(*) FROM events    0
    SQL Value Should Be    SELECT COUNT(*) FROM reservations WHERE status='boarded'    0

SYN-007 Mixed Batch Records Rejection And Continues Valid Events
    [Tags]    negative
    ${invalid}=    New Offline Event    evt-001    user=U-UNKNOWN
    ${valid}=    New Offline Event    evt-002
    ${r}=    Sync Events    ${invalid}    ${valid}
    Should Be Equal    ${r.json()}[results][0][status]    rejected
    Should Be Equal    ${r.json()}[results][1][status]    accepted
    SQL Value Should Be    SELECT COUNT(*) FROM events    2

SYN-008 Out Of Order Departure Is Rejected Until Explicit New Event
    [Tags]    negative
    ${departure}=    New Offline Event    evt-001    kind=depart
    ${boarding}=    New Offline Event    evt-002
    ${r}=    Sync Events    ${departure}    ${boarding}
    Should Be Equal    ${r.json()}[results][0][code]    no_boarded_passengers
    Should Be Equal    ${r.json()}[results][1][status]    accepted
    ${retry}=    Sync Events    ${departure}
    Should Be Equal    ${retry.json()}[results][0][status]    rejected
    Should Be Equal    ${retry.json()}[results][0][replayed]    ${TRUE}
    ${new}=    New Offline Event    evt-003    kind=depart
    ${r}=    Sync Events    ${new}
    Should Be Equal    ${r.json()}[results][0][status]    accepted

SYN-009 Cancelled Reservation Does Not Bypass FullTrip Capacity
    [Tags]    critical    negative
    POST On Session    owner    /api/reservations/R-001/cancel    json=${{ {} }}    expected_status=200
    Buy Ticket    seat=${1}
    Validate Passenger    user=U-005
    Validate Passenger    user=U-006
    ${event}=    New Offline Event    evt-cancelled    user=U-001
    ${r}=    Sync Events    ${event}
    Should Be Equal    ${r.json()}[results][0][code]    no_seats
    SQL Value Should Be    SELECT status FROM reservations WHERE id='R-001'    cancelled
