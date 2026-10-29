*** Settings ***
Library    RequestsLibrary
Library    Collections
Library    libraries.DemoLibrary.DemoLibrary

*** Keywords ***
Start Test Environment
    ${url}=    Start Demo
    Set Suite Variable    ${BASE_URL}    ${url}
    &{driver}=    Create Dictionary    Authorization=Bearer demo-driver-001
    &{rider}=    Create Dictionary    Authorization=Bearer demo-rider-U-002
    &{owner}=    Create Dictionary    Authorization=Bearer demo-rider-U-001
    Create Session    driver    ${BASE_URL}    headers=${driver}    timeout=5    max_retries=0
    Create Session    rider    ${BASE_URL}    headers=${rider}    timeout=5    max_retries=0
    Create Session    owner    ${BASE_URL}    headers=${owner}    timeout=5    max_retries=0

Stop Test Environment
    Delete All Sessions
    Stop Demo

Buy Ticket
    [Arguments]    ${seat}=${2}    ${trip}=T-001    ${request}=purchase-001    ${status}=201
    &{body}=    Create Dictionary    trip_id=${trip}    seat=${seat}    request_id=${request}
    ${r}=    POST On Session    rider    /api/reservations    json=${body}    expected_status=${status}
    RETURN    ${r}

Validate Passenger
    [Arguments]    ${user}=U-001    ${trip}=T-001    ${status}=200
    &{body}=    Create Dictionary    trip_id=${trip}    user_id=${user}
    ${r}=    POST On Session    driver    /api/driver/validate    json=${body}    expected_status=${status}
    RETURN    ${r}

Start Departure
    [Arguments]    ${trip}=T-001    ${status}=200
    &{body}=    Create Dictionary    trip_id=${trip}
    ${r}=    POST On Session    driver    /api/driver/depart    json=${body}    expected_status=${status}
    RETURN    ${r}

New Offline Event
    [Arguments]    ${id}    ${kind}=validate    ${user}=U-001    ${trip}=T-001
    &{event}=    Create Dictionary    event_id=${id}    kind=${kind}    user_id=${user}    trip_id=${trip}
    RETURN    ${event}

Sync Events
    [Arguments]    @{events}
    &{body}=    Create Dictionary    events=${events}
    ${r}=    POST On Session    driver    /api/driver/sync    json=${body}    expected_status=200
    RETURN    ${r}

Error Should Be
    [Arguments]    ${response}    ${error}
    Should Be Equal    ${response.json()}[error]    ${error}

No Extra Reservation Should Exist
    SQL Value Should Be    SELECT COUNT(*) FROM reservations    3
