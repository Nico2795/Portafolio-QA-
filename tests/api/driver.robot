*** Settings ***
Documentation    Online boarding and departure rules including walk-in capacity.
Resource    ../../resources/api.resource
Suite Setup    Start Test Environment
Suite Teardown    Stop Test Environment
Test Setup    Reset Synthetic Data
Test Tags    api    driver    regression

*** Test Cases ***
DRV-001 Reserved Passenger Can Board Even When Trip Is Full
    [Tags]    smoke    critical
    ${r}=    Validate Passenger    user=U-003    trip=T-FULL
    Should Be Equal    ${r.json()}[code]    validated
    No Extra Reservation Should Exist
    SQL Value Should Be    SELECT status FROM reservations WHERE id='R-002'    boarded

DRV-002 No Reservation And No Seats Must Be Rejected
    [Tags]    smoke    critical    negative
    ${r}=    Validate Passenger    user=U-002    trip=T-FULL    status=409
    Error Should Be    ${r}    no_seats
    No Extra Reservation Should Exist
    SQL Value Should Be    SELECT COUNT(*) FROM reservations WHERE status='boarded'    0

DRV-003 Walk In Receives Available Seat
    [Tags]    smoke
    ${r}=    Validate Passenger    user=U-002
    Should Be Equal    ${r.json()}[code]    walk_in_validated
    Should Be Equal As Integers    ${r.json()}[seat]    2
    SQL Value Should Be    SELECT amount FROM reservations WHERE user_id='U-002'    0

DRV-004 Same Passenger Cannot Be Validated Twice
    [Tags]    negative
    Validate Passenger
    ${r}=    Validate Passenger    status=409
    Error Should Be    ${r}    already_validated
    No Extra Reservation Should Exist

DRV-005 Unknown Passenger Cannot Board
    [Tags]    negative
    ${r}=    Validate Passenger    user=U-UNKNOWN    status=404
    Error Should Be    ${r}    user_not_found
    No Extra Reservation Should Exist

DRV-006 Departure Requires A Boarded Passenger
    [Tags]    negative
    ${r}=    Start Departure    status=409
    Error Should Be    ${r}    no_boarded_passengers
    SQL Value Should Be    SELECT status FROM trips WHERE id='T-001'    scheduled

DRV-007 Start Departure Online
    [Tags]    smoke
    Validate Passenger
    Start Departure
    SQL Value Should Be    SELECT status FROM trips WHERE id='T-001'    departed

DRV-008 Departure Cannot Start Twice
    [Tags]    negative
    Validate Passenger
    Start Departure
    ${r}=    Start Departure    status=409
    Error Should Be    ${r}    trip_departed

DRV-009 Boarding After Departure Is Rejected
    [Tags]    negative
    Validate Passenger
    Start Departure
    ${r}=    Validate Passenger    user=U-002    status=409
    Error Should Be    ${r}    trip_departed
    No Extra Reservation Should Exist

DRV-010 Rider Cannot Call Driver Endpoints
    [Tags]    security    negative
    ${r}=    POST On Session    rider    /api/driver/validate    json=${{ {'trip_id':'T-FULL','user_id':'U-002'} }}    expected_status=403
    Error Should Be    ${r}    driver_required
    No Extra Reservation Should Exist

DRV-011 Missing Token Is Unauthorized
    [Tags]    security
    ${r}=    GET    ${BASE_URL}/api/trips    expected_status=401    timeout=5
    Error Should Be    ${r}    unauthorized

DRV-012 Malformed JSON Does Not Alter State
    [Tags]    negative
    ${r}=    POST On Session    driver    /api/driver/validate    data=invalid-json    expected_status=400
    Error Should Be    ${r}    invalid_json
    No Extra Reservation Should Exist
