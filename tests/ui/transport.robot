*** Settings ***
Documentation    Real Chrome E2E over the local transport demo, including persistent offline queue.
Resource    ../../resources/api.resource
Library    SeleniumLibrary    timeout=10
Suite Setup    Start Test Environment
Suite Teardown    Stop Test Environment
Test Setup    Open Clean Transport App
Test Teardown    Close Transport App
Test Tags    ui    regression

*** Keywords ***
Open Clean Transport App
    Reset Synthetic Data
    Open Browser    ${BASE_URL}    headlesschrome    options=add_argument("--no-sandbox");add_argument("--disable-dev-shm-usage");add_argument("--window-size=1440,1100")
    Wait Until Element Contains    css:[data-testid="manifest"]    T-001

Close Transport App
    Run Keyword If Test Failed    Capture Page Screenshot
    Close All Browsers

Driver Message Should Contain
    [Arguments]    ${text}
    Wait Until Element Contains    css:[data-testid="driver-message"]    ${text}

Go Offline
    Click Button    css:[data-testid="toggle"]
    Wait Until Element Contains    css:[data-testid="mode"]    offline

Go Online
    Click Button    css:[data-testid="toggle"]
    Wait Until Element Contains    css:[data-testid="mode"]    online

*** Test Cases ***
UI-001 Purchase Edit Cancel And Refund
    [Tags]    smoke    critical
    Click Button    css:[data-testid="buy"]
    Wait Until Element Contains    css:[data-testid="rider-message"]    Compra confirmada
    Input Text    css:[data-testid="seat"]    3
    Click Button    css:[data-testid="edit"]
    Wait Until Element Contains    css:[data-testid="rider-message"]    Reserva editada · asiento 3
    Click Button    css:[data-testid="cancel"]
    Wait Until Element Contains    css:[data-testid="rider-message"]    Reembolso simulado · 5000 CLP
    SQL Value Should Be    SELECT status FROM reservations WHERE user_id='U-002'    cancelled
    SQL Value Should Be    SELECT SUM(amount) FROM refunds    5000

UI-002 Online Full Trip Rejects Passenger Without Reservation
    [Tags]    smoke    critical    negative
    Select From List By Value    css:[data-testid="driver-trip"]    T-FULL
    Wait Until Element Contains    css:[data-testid="manifest"]    T-FULL · 0 asientos libres
    Input Text    css:[data-testid="passenger"]    U-002
    Click Button    css:[data-testid="validate"]
    Driver Message Should Contain    Sin asientos disponibles
    No Extra Reservation Should Exist

UI-003 Offline Full Trip Rejects Locally Without Queueing
    [Tags]    critical    negative    offline
    Select From List By Value    css:[data-testid="driver-trip"]    T-FULL
    Wait Until Element Contains    css:[data-testid="manifest"]    T-FULL · 0 asientos libres
    Go Offline
    Input Text    css:[data-testid="passenger"]    U-002
    Click Button    css:[data-testid="validate"]
    Driver Message Should Contain    Sin asientos disponibles
    Element Text Should Be    css:[data-testid="pending"]    0
    No Extra Reservation Should Exist

UI-004 Offline Boarding And Departure SurviveReload AndSynchronize
    [Tags]    smoke    critical    offline    sync
    Go Offline
    Click Button    css:[data-testid="validate"]
    Driver Message Should Contain    Operación offline pendiente
    Click Button    css:[data-testid="depart"]
    Wait Until Element Contains    css:[data-testid="pending"]    2
    SQL Value Should Be    SELECT status FROM reservations WHERE id='R-001'    confirmed
    SQL Value Should Be    SELECT status FROM trips WHERE id='T-001'    scheduled
    Reload Page
    Wait Until Element Contains    css:[data-testid="mode"]    offline
    Element Text Should Be    css:[data-testid="pending"]    2
    Go Online
    Click Button    css:[data-testid="sync"]
    Driver Message Should Contain    Sincronización completada
    Element Text Should Be    css:[data-testid="pending"]    0
    SQL Value Should Be    SELECT status FROM reservations WHERE id='R-001'    boarded
    SQL Value Should Be    SELECT status FROM trips WHERE id='T-001'    departed
    SQL Value Should Be    SELECT COUNT(*) FROM events    2

UI-005 Stale Offline SeatAssignment ShowsConflict OnSync
    [Tags]    critical    negative    offline    conflict
    Go Offline
    Input Text    css:[data-testid="passenger"]    U-006
    Click Button    css:[data-testid="validate"]
    Driver Message Should Contain    Operación offline pendiente
    Buy Ticket
    Validate Passenger    user=U-005
    Go Online
    Click Button    css:[data-testid="sync"]
    Driver Message Should Contain    Conflictos:
    Driver Message Should Contain    no_seats
    Element Text Should Be    css:[data-testid="pending"]    0
    SQL Value Should Be    SELECT COUNT(*) FROM reservations WHERE user_id='U-006'    0
    SQL Value Should Be    SELECT COUNT(*) FROM reservations WHERE trip_id='T-001' AND status!='cancelled'    3

UI-006 Failed Sync KeepsQueue ForRetry
    [Tags]    offline    resilience
    Go Offline
    Click Button    css:[data-testid="validate"]
    Wait Until Element Contains    css:[data-testid="pending"]    1
    Go Online
    # Simulates a transport failure before acknowledgement; no server mutation.
    Execute Javascript    window.originalFetch=window.fetch;window.fetch=(url,opts)=>String(url).endsWith('/sync')?Promise.reject(new Error('Simulated network failure')):window.originalFetch(url,opts);
    Click Button    css:[data-testid="sync"]
    Driver Message Should Contain    Simulated network failure
    Element Text Should Be    css:[data-testid="pending"]    1
    SQL Value Should Be    SELECT COUNT(*) FROM events    0
    Reload Page
    Wait Until Element Contains    css:[data-testid="pending"]    1
    Click Button    css:[data-testid="sync"]
    Driver Message Should Contain    Sincronización completada
    SQL Value Should Be    SELECT COUNT(*) FROM events    1

UI-007 Start Departure Online
    [Tags]    smoke
    Click Button    css:[data-testid="validate"]
    Driver Message Should Contain    Pasajero validado
    Click Button    css:[data-testid="depart"]
    Driver Message Should Contain    Salida iniciada
    SQL Value Should Be    SELECT status FROM trips WHERE id='T-001'    departed

UI-008 Purchase OfOccupiedSeat ShowsError
    [Tags]    negative
    Input Text    css:[data-testid="seat"]    1
    Click Button    css:[data-testid="buy"]
    Wait Until Element Contains    css:[data-testid="rider-message"]    Asiento ocupado
    No Extra Reservation Should Exist
