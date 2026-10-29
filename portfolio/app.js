'use strict';
const cases = {
  capacity: {
    id: 'DRV-002', tag: 'RIESGO CRÍTICO', title: 'Sin reserva. Sin cupos. Sin validación.',
    description: 'Un usuario sin reserva intenta abordar un viaje con todos sus asientos asignados. El sistema debe rechazarlo sin crear una reserva ni marcarlo como abordado.',
    given: 'Viaje T-FULL · 2 de 2 asientos ocupados · U-002 sin reserva.',
    then: 'HTTP 409 · no_seats. La base de datos conserva sus 3 reservas iniciales.',
    code: '${r}=    Validate Passenger    user=U-002\n...    trip=T-FULL    status=409\nError Should Be    ${r}    no_seats\nNo Extra Reservation Should Exist',
    file: 'tests/api/driver.robot'
  },
  offline: {
    id: 'SYN-004 / UI-005', tag: 'CONFLICTO OFFLINE', title: 'El manifiesto local puede quedar atrás.',
    description: 'El conductor registra un pasajero sin reserva mientras está offline. Otros usuarios ocupan los cupos en el servidor antes de la sincronización. La validación local es provisional.',
    given: 'Manifiesto con cupos → operación offline → servidor lleno.',
    then: 'El evento se rechaza con no_seats. El conflicto se muestra en pantalla y la capacidad nunca se supera.',
    code: '${event}=    New Offline Event    evt-stale\n...    user=U-006\n${r}=    Sync Events    ${event}\nShould Be Equal\n...    ${r.json()}[results][0][code]    no_seats',
    file: 'tests/api/synchronization.robot'
  },
  refund: {
    id: 'RES-009', tag: 'IDEMPOTENCIA', title: 'Reintentar no significa reembolsar dos veces.',
    description: 'Una cancelación libera el asiento y registra un reembolso simulado de 5.000 CLP. Si se repite la solicitud, se devuelve el mismo reembolso en lugar de generar otro.',
    given: 'Reserva R-001 confirmada · viaje sin iniciar · dos solicitudes de cancelación.',
    then: 'Mismo ID de reembolso. Un solo registro en SQL. El asiento queda disponible para otra compra.',
    code: 'Should Be Equal\n...    ${first.json()}[id]    ${retry.json()}[id]\nSQL Value Should Be\n...    SELECT COUNT(*) FROM refunds WHERE reservation_id=\'R-001\'\n...    1',
    file: 'tests/api/reservations.robot'
  },
  race: {
    id: 'RES-012', tag: 'CONCURRENCIA', title: 'Un asiento no puede tener dos ganadores.',
    description: 'Dos usuarios intentan comprar simultáneamente el mismo asiento. La comprobación se realiza mediante solicitudes HTTP concurrentes y una consulta independiente a la base de datos.',
    given: 'U-002 y U-005 compiten por el asiento 2 de T-001.',
    then: 'Una respuesta 201 y otra 409. Solo una reserva activa para ese asiento.',
    code: 'Concurrent Seat Purchases Should Have One Winner\n\n# Dos requests concurrentes:\n# sorted(statuses) == [201, 409]\n# SQL: una reserva activa en el asiento 2',
    file: 'libraries/DemoLibrary.py'
  }
};

for (const button of document.querySelectorAll('[data-case]')) {
  button.addEventListener('click', () => {
    const item = cases[button.dataset.case];
    for (const other of document.querySelectorAll('[data-case]')) {
      const selected = other === button;
      other.classList.toggle('active', selected);
      other.setAttribute('aria-pressed', String(selected));
    }
    for (const key of ['id', 'tag', 'title', 'description', 'given', 'then', 'code']) {
      document.getElementById('case-' + key).textContent = item[key];
    }
    document.getElementById('case-source').href = 'https://github.com/Nico2795/Portafolio-QA-/blob/main/' + item.file;
  });
}

fetch('evidence.json').then(response => {
  if (!response.ok) throw new Error('Evidence unavailable');
  return response.json();
}).then(data => {
  if (!Number.isInteger(data.tests) || data.failures !== 0 || data.errors !== 0 || data.skipped !== 0) return;
  document.querySelector('[data-total]').textContent = data.tests;
  const date = new Date(data.generated_at).toLocaleDateString('es-CL', {timeZone:'America/Santiago'});
  document.getElementById('evidence-status').textContent = `${data.tests}/${data.tests} aprobados · ${date} · ${data.environment}`;
}).catch(() => { /* The report link stays usable if metadata cannot load. */ });
