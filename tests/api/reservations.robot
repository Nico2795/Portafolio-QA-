*** Settings ***
Documentation    Ticket purchase, seat ownership, cancellation and synthetic refunds.
Resource    ../../resources/api.resource
Suite Setup    Start Test Environment
Suite Teardown    Stop Test Environment
Test Setup    Reset Synthetic Data
Test Tags    api    regression

*** Test Cases ***
RES-001 Purchase Persists Assigned Seat And Fare
    [Tags]    smoke    critical    contract    sql
    ${r}=    Buy Ticket
    Reservation Should Match Contract    ${r.json()}
    Should Be Equal As Integers    ${r.json()}[amount]    5000
    SQL Value Should Be    SELECT seat FROM reservations WHERE user_id='U-002'    2
    SQL Value Should Be    SELECT amount FROM reservations WHERE user_id='U-002'    5000

RES-002 Occupied Seat Cannot Be Purchased
    [Tags]    critical    negative
    ${r}=    Buy Ticket    seat=${1}    status=409
    Error Should Be    ${r}    seat_taken
    No Extra Reservation Should Exist

RES-003 Invalid Seat Boundaries And Types
    [Tags]    negative    boundary
    [Template]    Reject Invalid Seat
    ${0}
    ${-1}
    ${4}
    ${1.5}
    ${TRUE}
    two
    ${NONE}

RES-004 Same Purchase Request Is Idempotent
    [Tags]    critical    idempotency
    ${first}=    Buy Ticket
    ${retry}=    Buy Ticket    status=200
    Should Be Equal    ${first.json()}[id]    ${retry.json()}[id]
    SQL Value Should Be    SELECT COUNT(*) FROM reservations WHERE user_id='U-002'    1

RES-005 Reused Purchase Key With Different Seat Is Rejected
    [Tags]    negative    idempotency
    Buy Ticket
    ${r}=    Buy Ticket    seat=${3}    status=409
    Error Should Be    ${r}    idempotency_conflict
    SQL Value Should Be    SELECT seat FROM reservations WHERE user_id='U-002'    2

RES-006 Passenger Cannot Reserve Two Seats On Same Trip
    [Tags]    negative
    Buy Ticket
    ${r}=    Buy Ticket    seat=${3}    request=another-request    status=409
    Error Should Be    ${r}    already_reserved

RES-007 Edit Reservation Releases Previous Seat
    [Tags]    smoke    sql
    &{body}=    Create Dictionary    seat=${3}
    ${r}=    PATCH On Session    owner    /api/reservations/R-001    json=${body}    expected_status=200
    Should Be Equal As Integers    ${r.json()}[seat]    3
    Buy Ticket    seat=${1}
    SQL Value Should Be    SELECT COUNT(*) FROM reservations WHERE trip_id='T-001' AND seat=1 AND status!='cancelled'    1

RES-008 Edit To Occupied Seat Leaves Original Unchanged
    [Tags]    negative
    Buy Ticket
    &{body}=    Create Dictionary    seat=${2}
    ${r}=    PATCH On Session    owner    /api/reservations/R-001    json=${body}    expected_status=409
    Error Should Be    ${r}    seat_taken
    SQL Value Should Be    SELECT seat FROM reservations WHERE id='R-001'    1

RES-009 Cancellation Refunds Once And Releases Seat
    [Tags]    smoke    critical    sql    idempotency
    ${first}=    POST On Session    owner    /api/reservations/R-001/cancel    json=${{ {} }}    expected_status=200
    ${retry}=    POST On Session    owner    /api/reservations/R-001/cancel    json=${{ {} }}    expected_status=200
    Should Be Equal    ${first.json()}[id]    ${retry.json()}[id]
    Should Be Equal As Integers    ${first.json()}[amount]    5000
    SQL Value Should Be    SELECT COUNT(*) FROM refunds WHERE reservation_id='R-001'    1
    SQL Value Should Be    SELECT status FROM reservations WHERE id='R-001'    cancelled
    Buy Ticket    seat=${1}

RES-010 Another User Cannot Cancel Or Edit Reservation
    [Tags]    security    negative
    ${cancel}=    POST On Session    rider    /api/reservations/R-001/cancel    json=${{ {} }}    expected_status=403
    Error Should Be    ${cancel}    not_owner
    ${edit}=    PATCH On Session    rider    /api/reservations/R-001    json=${{ {'seat': 3} }}    expected_status=403
    Error Should Be    ${edit}    not_owner
    SQL Value Should Be    SELECT COUNT(*) FROM refunds    0
    SQL Value Should Be    SELECT seat FROM reservations WHERE id='R-001'    1

RES-011 Boarded Reservation Cannot Be Cancelled Or Edited
    [Tags]    negative
    Validate Passenger
    ${cancel}=    POST On Session    owner    /api/reservations/R-001/cancel    json=${{ {} }}    expected_status=409
    Error Should Be    ${cancel}    reservation_not_cancellable
    ${edit}=    PATCH On Session    owner    /api/reservations/R-001    json=${{ {'seat': 3} }}    expected_status=409
    Error Should Be    ${edit}    reservation_not_editable
    SQL Value Should Be    SELECT COUNT(*) FROM refunds    0

RES-012 Concurrent Purchases Of Same Seat Have One Winner
    [Tags]    concurrency    critical    sql
    Concurrent Seat Purchases Should Have One Winner

RES-013 Purchase After Departure Is Rejected
    [Tags]    negative
    Validate Passenger
    Start Departure
    ${r}=    Buy Ticket    status=409
    Error Should Be    ${r}    trip_departed
    No Extra Reservation Should Exist

*** Keywords ***
Reject Invalid Seat
    [Arguments]    ${seat}
    ${r}=    Buy Ticket    seat=${seat}    status=422
    Error Should Be    ${r}    invalid_seat
    No Extra Reservation Should Exist
