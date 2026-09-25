import { HttpClient, HttpParams } from '@angular/common/http';
import { Injectable, inject } from '@angular/core';
import { Observable, map } from 'rxjs';

import { HBH_CONFIG } from '@hbh/shared/config/app-config';
import { Page, Row } from '../api/ops-api';

/**
 * The five reads the console opens a DAY through, and the writes that change
 * what they show.
 *
 * These are not the CRUD resources. A room is a row that is created and
 * edited; an appointment is a row that MOVES - booked, confirmed, checked in,
 * completed - and the move is the whole operation. So this client is separate
 * from OpsApi: same service, different verbs, and putting a `close session`
 * next to a generic `update` would invite somebody to PATCH a status column
 * directly and skip the state machine that exists to stop exactly that.
 */
export type DayResource =
  | 'appointments'
  | 'sessions'
  | 'reports'
  | 'invoices'
  | 'requests'
  | 'enrolments';

/**
 * The filters the service accepts on these six.
 *
 * `date` and `from`/`to` are NOT interchangeable, and the difference is the
 * service's, not a mistake:
 *
 *   appointments and sessions read a DIARY. Their window is a pair of
 *   instants, resolved in the centre's own time zone from the centre's row,
 *   and an empty window means today.
 *
 *   reports, invoices and requests read a LEDGER. Their bounds are days
 *   (YYYY-MM-DD) and an empty bound means no bound - a list of invoices does
 *   not open on one day the way a diary does.
 *
 *   enrolments read a QUEUE, and take no window at all. A family that applied
 *   three weeks ago and has not been called back is the one reception most
 *   needs to see, and a date filter is how they would stop seeing it.
 *
 * Sending an instant where a day is expected is a 400 naming the field, which
 * is how this was found rather than guessed.
 */
export interface DayQuery {
  readonly date?: string;
  readonly from?: string;
  readonly to?: string;
  readonly therapist_id?: number;
  /**
   * "Only the therapist I am." The service resolves who that is from the
   * session; this carries no identifier because it must not be able to.
   * Overrides therapist_id server-side rather than combining with it.
   */
  readonly mine?: boolean;
  readonly room_id?: number;
  readonly service_id?: number;
  readonly child_id?: number;
  readonly status?: string;
  readonly kind?: string;
  readonly archived?: boolean;
  readonly page?: number;
  readonly limit?: number;
}

/**
 * In the centre, or over video.
 *
 * EXTERNAL exists in the schema - a visit somewhere that is neither - and is
 * deliberately absent from the console's picker until somebody asks for it.
 * The type carries it so that a row which already has it reads correctly.
 */
export type DeliveryMode = 'IN_PERSON' | 'ONLINE' | 'EXTERNAL';

/** What `POST /appointments` and `POST /appointments/validate` both take. */
export interface NewAppointment {
  readonly child_id: number;
  readonly therapist_id: number;
  /**
   * OMITTED for a mode that has no room. The service reads absent as "no
   * room" and asks hbh.validate_slot about it; sending 0 would be asking
   * about a room that cannot exist.
   */
  readonly room_id?: number;
  readonly service_id: number;
  /** UTC instants. The picker collects local wall time and converts. */
  readonly starts_at: string;
  readonly ends_at: string;
  readonly note_ar?: string;
  /** Absent means IN_PERSON, which is what this screen booked for years. */
  readonly delivery_mode?: DeliveryMode;
}

/**
 * The answer to "would this booking be accepted?".
 *
 * A refusal arrives as HTTP 200 with `ok:false`, not as an error status, and
 * that is right: a question was asked and answered, and nothing failed. The
 * screen must not treat this as a network problem.
 */
export interface SlotCheck {
  readonly ok: boolean;
  /** A code - SLOT_TAKEN, SLOT_UNAVAILABLE - never a sentence. */
  readonly reason: string;
}

/**
 * One window a booking would be accepted into, and a room that is free then.
 *
 * Every one of these has already been through hbh.validate_slot - the same
 * function the booking itself goes through - so the list can never offer a
 * time the confirm then refuses. The exception is the CHILD, who is chosen
 * after the slot: a family already booked elsewhere at that hour is refused
 * at confirm with CHILD_BUSY.
 */
export interface Slot {
  readonly starts_at: string;
  readonly ends_at: string;
  /**
   * NULL for an online consultation, which has no room and never will.
   * Typed nullable so the compiler makes every reader decide which it is -
   * `room_id: number` would have made "no room" arrive as 0 and be rendered
   * as a room number nobody can walk into.
   */
  readonly room_id: number | null;
  readonly room_name_ar: string | null;
}

@Injectable({ providedIn: 'root' })
export class DayApi {
  private readonly http = inject(HttpClient);
  private readonly base = `${inject(HBH_CONFIG).apiBaseUrl}/api/v1`;

  /**
   * One page of a day. The response wraps its rows in a named key -
   * `{"appointments":[...]}` - and the key is found as the one array in the
   * object, the same way OpsApi does it and for the same reason: a table of
   * resource-to-key names would be a second copy of the service's naming
   * convention, and it is the copy that would go stale.
   */
  /**
   * One row by its id, for the resources the service reads that way:
   * `GET /enrolments/{id}`, `GET /invoices/{id}`, `GET /reports/{id}`.
   * Appointments, sessions and requests have no single-row read - a caller
   * that holds such a row passes it along instead.
   */
  get(resource: DayResource, id: number): Observable<Row> {
    return this.http.get<Row>(`${this.base}/${resource}/${id}`);
  }

  list(resource: DayResource, query: DayQuery = {}): Observable<Page> {
    return this.http
      .get<Record<string, unknown>>(`${this.base}/${resource}`, { params: this.params(query) })
      .pipe(map((body) => {
        const rows = this.unwrap(body);
        return {
          rows,
          total: typeof body?.['total'] === 'number' ? body['total'] as number : rows.length,
          limit: typeof body?.['limit'] === 'number' ? body['limit'] as number : rows.length,
          offset: typeof body?.['offset'] === 'number' ? body['offset'] as number : 0,
        };
      }));
  }

  // ---- appointments ----

  /**
   * Which windows this therapist could be booked into on one day.
   *
   * The reverse of validateSlot, and the question the booking screen
   * actually has. With only the first, finding a gap in a busy day meant
   * proposing a time, being refused, and proposing another - eight times to
   * find the one hour that was free.
   *
   * Needs APPOINTMENT.BOOK. A caller without it gets 403, not an empty list:
   * "you may not ask" and "there is nothing free" are different answers.
   */
  slots(
    therapistId: number, serviceId: number, date: string, roomId?: number,
    mode?: DeliveryMode,
  ): Observable<readonly Slot[]> {
    let params = new HttpParams()
      .set('therapist_id', therapistId)
      .set('service_id', serviceId)
      .set('date', date);
    if (roomId) {
      params = params.set('room_id', roomId);
    }
    // Sent only when it is not the default, so a request for an ordinary
    // in-person day is byte for byte the request this screen always sent.
    if (mode && mode !== 'IN_PERSON') {
      params = params.set('delivery_mode', mode);
    }
    return this.http
      .get<{ slots: readonly Slot[] }>(`${this.base}/appointments/slots`, { params })
      .pipe(map((body) => body?.slots ?? []));
  }

  /**
   * Every (service, therapist) combination the centre can deliver.
   *
   * ONE read for the whole set, so the booking screen can ask a single
   * question instead of two that can contradict each other. Asking per
   * service would be a request per row of a dropdown, and the answers
   * would arrive in whatever order the network chose.
   */
  servicePairs(): Observable<readonly Row[]> {
    return this.http
      .get<Record<string, unknown>>(`${this.base}/service-therapists`)
      .pipe(map((body) => this.unwrap(body)));
  }

  validateSlot(body: NewAppointment): Observable<SlotCheck> {
    return this.http.post<SlotCheck>(`${this.base}/appointments/validate`, body);
  }

  book(body: NewAppointment): Observable<{ appointment_id: number }> {
    return this.http.post<{ appointment_id: number }>(`${this.base}/appointments`, body);
  }

  /**
   * Moves an appointment along its state machine.
   *
   * The service refuses an illegal move with 409 ILLEGAL_TRANSITION, and a
   * move to the status a row already holds is accepted silently - the trigger
   * is not consulted unless the status actually changes - so a screen that
   * retries after a dropped response does not produce a second history row.
   */
  setAppointmentStatus(id: number, status: string, reason = ''): Observable<void> {
    return this.http.patch<void>(
      `${this.base}/appointments/${id}/status`, { status, reason });
  }

  startSession(appointmentId: number): Observable<{ session_id: number }> {
    return this.http.post<{ session_id: number }>(
      `${this.base}/appointments/${appointmentId}/session`, {});
  }

  // ---- sessions ----

  closeSession(id: number, status: string, reason = ''): Observable<void> {
    return this.http.patch<void>(`${this.base}/sessions/${id}/close`, { status, reason });
  }

  /**
   * Writes a clinical note. The service answers with `visibility: INTERNAL`,
   * and it means it: the note does not reach a family until somebody
   * publishes it through the ladder on session_notes. The screen says so
   * rather than letting a therapist assume a parent is reading this.
   */
  writeNote(sessionId: number, bodyAr: string): Observable<{ note_id: number }> {
    return this.http.put<{ note_id: number }>(
      `${this.base}/sessions/${sessionId}/note`, { body_ar: bodyAr });
  }

  // ---- reports, invoices, requests ----

  publishReport(id: number): Observable<void> {
    return this.http.post<void>(`${this.base}/reports/${id}/publish`, {});
  }

  issueInvoice(id: number): Observable<void> {
    return this.http.post<void>(`${this.base}/invoices/${id}/issue`, {});
  }

  /**
   * Creates an empty DRAFT invoice for a child.
   *
   * What the screen does NOT send is the point: the number comes from
   * hbh.next_number (a gapless series that resets yearly), the currency from
   * the centre's row, and the tax rate from a parameter - and the rate is
   * FROZEN onto the invoice at creation, so changing it next month does not
   * silently restate an invoice that already went out.
   *
   * The tables carry no write grant at all; these functions are the only way
   * in, which is why there is no path that could skip any of that.
   */
  createInvoice(
    childId: number, dueDate?: string, noteAr?: string,
  ): Observable<{ invoice_id: number }> {
    return this.http.post<{ invoice_id: number }>(`${this.base}/invoices`, {
      child_id: childId,
      due_date: dueDate || undefined,
      note_ar: noteAr || undefined,
    });
  }

  /**
   * Adds a line. `line_amt` and the invoice total are CALCULATED - send the
   * quantity and the unit price and nothing else.
   *
   * `unit_amt` is a decimal string end to end. JSON's only number type is a
   * float, and the nearest float to 10.10 is not 10.10 - which is a strange
   * thing to discover on an invoice.
   *
   * Refused with 409 once the invoice has left DRAFT: the family has been
   * told a number to pay.
   */
  addInvoiceLine(
    invoiceId: number, descriptionAr: string, qty: string, unitAmt: string,
    serviceId?: number,
  ): Observable<{ line_id: number }> {
    return this.http.post<{ line_id: number }>(`${this.base}/invoices/${invoiceId}/lines`, {
      description_ar: descriptionAr,
      qty,
      unit_amt: unitAmt,
      service_id: serviceId,
    });
  }

  removeInvoiceLine(invoiceId: number, lineId: number): Observable<void> {
    return this.http.delete<void>(`${this.base}/invoices/${invoiceId}/lines/${lineId}`);
  }

  // ---- which services a therapist actually practises ----

  /**
   * Not one of the fourteen CRUD resources, and not by oversight: the table's
   * key is the PAIR (therapist_id, service_id) with no surrogate id, so it
   * cannot be addressed as /{id} the way the others are.
   *
   * Easy to confuse with caseload, and they answer different questions:
   * caseload is therapist-to-CHILD ("may this person run this session"), this
   * is therapist-to-SERVICE ("does he practise speech therapy at all").
   * Booking checks both, and without a row here validate_slot answers
   * THERAPIST_SERVICE_MISMATCH - which is how its absence was found.
   */
  therapistServices(therapistId: number): Observable<readonly Row[]> {
    return this.http
      .get<Record<string, unknown>>(`${this.base}/therapists/${therapistId}/services`)
      .pipe(map((body) => this.unwrap(body)));
  }

  /**
   * The same pair read the other way: who offers this service.
   *
   * This is the direction the BOOKING screen needs. A dropdown of every
   * therapist lets somebody pick one who does not do speech therapy, and
   * validate_slot then answers THERAPIST_SERVICE_MISMATCH - a refusal about
   * a fact the service knew before the choice was made.
   *
   * Active therapists only, because validate_slot refuses the others with
   * THERAPIST_UNAVAILABLE. An empty list is a real answer: nobody in this
   * centre is linked to that service yet, and /therapist-services is where
   * that is fixed.
   */
  serviceTherapists(serviceId: number): Observable<readonly Row[]> {
    return this.http
      .get<Record<string, unknown>>(`${this.base}/services/${serviceId}/therapists`)
      .pipe(map((body) => this.unwrap(body)));
  }

  /** Re-linking a service that was removed is accepted, not refused as a
   *  duplicate: taking a service off a therapist and putting it back is
   *  ordinary, and a unique-key collision with a row the screen cannot see
   *  would be a dead end nobody could act on. */
  linkTherapistService(therapistId: number, serviceId: number): Observable<void> {
    return this.http.post<void>(
      `${this.base}/therapists/${therapistId}/services`, { service_id: serviceId });
  }

  unlinkTherapistService(therapistId: number, serviceId: number): Observable<void> {
    return this.http.delete<void>(
      `${this.base}/therapists/${therapistId}/services/${serviceId}`);
  }

  /**
   * `amount` stays a decimal STRING the whole way. It is the one figure in
   * this system that is summed and compared against a total, and JSON's only
   * number type is a float.
   */
  addPayment(
    invoiceId: number, amount: string, methodCode: string, noteAr = '',
  ): Observable<{ payment_id: number }> {
    return this.http.post<{ payment_id: number }>(
      `${this.base}/invoices/${invoiceId}/payments`,
      { amount, method_code: methodCode, note_ar: noteAr });
  }

  sellPackage(childId: number, packageId: number): Observable<{ child_package_id: number }> {
    return this.http.post<{ child_package_id: number }>(
      `${this.base}/children/${childId}/packages`, { package_id: packageId });
  }

  decideRequest(id: number, status: string, noteAr = ''): Observable<void> {
    return this.http.patch<void>(`${this.base}/requests/${id}`, { status, note_ar: noteAr });
  }

  // ---- enrolment applications ----

  /**
   * Moves an application along its queue.
   *
   * ENROLLED is NOT reachable here - a check constraint ties that status to
   * the converted guardian and child, and only convert() writes both. The
   * screen leaves it out of the dropdown rather than offering a choice the
   * database refuses (verified: PATCH status=ENROLLED answers 409).
   *
   * The contacted timestamp is stamped by the state machine, not sent from
   * here: the moment of a transition is part of the transition.
   */
  setEnrolmentStatus(id: number, status: string, noteAr = '', assessmentAt?: string): Observable<void> {
    return this.http.patch<void>(
      `${this.base}/enrolments/${id}`, { status, note_ar: noteAr, ...(assessmentAt ? { assessment_at: assessmentAt } : {}) });
  }

  /**
   * Turns an application into a real family: a guardian row and a child row,
   * written together, with the application marked as their origin.
   *
   * This is the only path from the quarantine table into the clinical record,
   * it needs ENROLMENT.MANAGE, and it is refused from NEW - somebody has to
   * have spoken to the family first (verified: convert from NEW answers 409).
   */
  convertEnrolment(
    id: number, noteAr = '',
  ): Observable<{ guardian_id: number; child_id: number; child_no: string }> {
    return this.http.post<{ guardian_id: number; child_id: number; child_no: string }>(
      `${this.base}/enrolments/${id}/convert`, { note_ar: noteAr });
  }

  private unwrap(body: Record<string, unknown>): readonly Row[] {
    for (const value of Object.values(body ?? {})) {
      if (Array.isArray(value)) {
        return value as readonly Row[];
      }
    }
    return [];
  }

  private params(query: DayQuery): HttpParams {
    let params = new HttpParams();
    for (const [key, value] of Object.entries(query)) {
      if (value !== undefined && value !== null && value !== '') {
        params = params.set(key, String(value));
      }
    }
    return params;
  }
}
