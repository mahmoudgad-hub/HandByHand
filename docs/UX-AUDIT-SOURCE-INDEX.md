# UX Audit — source evidence index

2026-09-14. فهرس مصادر مكمل للتحليل؛ ليس ادعاء تجربة كل فعل حيًا. الأسطر من النسخة المفحوصة. لا بيانات أسر أو أسرار. يشمل النماذج المتولدة التي لا يكتشفها جرد ملفات HTML وحده.

## web/ops/src/app/core/resource/resource-spec.ts

### CHILDREN_SPEC

| Source | Resource | Form fields | Keys (columns/actions) | Permissions |
| --- | --- | --- | --- | --- |
| web/ops/src/app/core/resource/resource-spec.ts:207 | children | full_name_ar, child_no, birth_date, gender |  |  |

### THERAPISTS_SPEC

| Source | Resource | Form fields | Keys (columns/actions) | Permissions |
| --- | --- | --- | --- | --- |
| web/ops/src/app/core/resource/resource-spec.ts:233 | therapists | full_name_ar, title_ar, mobile, status |  |  |

### WORKING_HOURS_SPEC

| Source | Resource | Form fields | Keys (columns/actions) | Permissions |
| --- | --- | --- | --- | --- |
| web/ops/src/app/core/resource/resource-spec.ts:256 | working-hours | therapist_id, weekday, start_time, end_time |  |  |

### CASELOAD_SPEC

| Source | Resource | Form fields | Keys (columns/actions) | Permissions |
| --- | --- | --- | --- | --- |
| web/ops/src/app/core/resource/resource-spec.ts:282 | caseload | therapist_id, child_id, service_id |  |  |

### ROOMS_SPEC

| Source | Resource | Form fields | Keys (columns/actions) | Permissions |
| --- | --- | --- | --- | --- |
| web/ops/src/app/core/resource/resource-spec.ts:299 | rooms | name_ar, code, notes_ar |  |  |

### CAMERAS_SPEC

| Source | Resource | Form fields | Keys (columns/actions) | Permissions |
| --- | --- | --- | --- | --- |
| web/ops/src/app/core/resource/resource-spec.ts:324 | cameras | name_ar, room_id |  |  |

### SERVICES_SPEC

| Source | Resource | Form fields | Keys (columns/actions) | Permissions |
| --- | --- | --- | --- | --- |
| web/ops/src/app/core/resource/resource-spec.ts:337 | services | name_ar, code, kind_code, default_duration_min, creates_session_flg, needs_caseload_flg |  |  |

### PACKAGES_SPEC

| Source | Resource | Form fields | Keys (columns/actions) | Permissions |
| --- | --- | --- | --- | --- |
| web/ops/src/app/core/resource/resource-spec.ts:384 | service-packages | name_ar, service_id, sessions_cnt, price_amt |  |  |

### ACTIVITY_LIBRARY_SPEC

| Source | Resource | Form fields | Keys (columns/actions) | Permissions |
| --- | --- | --- | --- | --- |
| web/ops/src/app/core/resource/resource-spec.ts:401 | activity-library | title_ar, code, how_to_ar |  |  |

### PLANS_SPEC

| Source | Resource | Form fields | Keys (columns/actions) | Permissions |
| --- | --- | --- | --- | --- |
| web/ops/src/app/core/resource/resource-spec.ts:448 | plans | title_ar, child_id, service_id, therapist_id, start_date, end_date |  |  |

### GOALS_SPEC

| Source | Resource | Form fields | Keys (columns/actions) | Permissions |
| --- | --- | --- | --- | --- |
| web/ops/src/app/core/resource/resource-spec.ts:467 | goals | plan_id, title_ar, description_ar, baseline_pct, target_pct, status, sort_order |  |  |

### MEASUREMENTS_SPEC

| Source | Resource | Form fields | Keys (columns/actions) | Permissions |
| --- | --- | --- | --- | --- |
| web/ops/src/app/core/resource/resource-spec.ts:490 | measurements | goal_id, measured_on, value_pct, trials_cnt, session_id, note_ar |  |  |

### CHILD_ACTIVITIES_SPEC

| Source | Resource | Form fields | Keys (columns/actions) | Permissions |
| --- | --- | --- | --- | --- |
| web/ops/src/app/core/resource/resource-spec.ts:510 | child-activities | child_id, activity_id, plan_id, goal_id, times_per_week, minutes_each, instructions_ar, start_date, end_date |  |  |

### NPS_SURVEYS_SPEC

| Source | Resource | Form fields | Keys (columns/actions) | Permissions |
| --- | --- | --- | --- | --- |
| web/ops/src/app/core/resource/resource-spec.ts:562 | nps-surveys | code, name_ar, question_ar, followup_question_ar, audience, trigger_kind, action_code, period_days, cooldown_days, starts_on, ends_on |  |  |

### GUARDIANS_SPEC

| Source | Resource | Form fields | Keys (columns/actions) | Permissions |
| --- | --- | --- | --- | --- |
| web/ops/src/app/core/resource/resource-spec.ts:596 | guardians | full_name_ar, mobile, email, city, relationship, national_id |  |  |

### SITE_CONTACT_SPEC

| Source | Resource | Form fields | Keys (columns/actions) | Permissions |
| --- | --- | --- | --- | --- |
| web/ops/src/app/core/resource/resource-spec.ts:652 | site-contact | phone, landline, whatsapp, email, address_ar, address_en, map_url, arrival_ar, arrival_en, hours_ar, hours_en, weekend_ar, weekend_en, status |  |  |

### SITE_TEXTS_SPEC

| Source | Resource | Form fields | Keys (columns/actions) | Permissions |
| --- | --- | --- | --- | --- |
| web/ops/src/app/core/resource/resource-spec.ts:730 | site-texts | text_key, text_ar, text_en, status |  |  |

### SITE_FAQ_SPEC

| Source | Resource | Form fields | Keys (columns/actions) | Permissions |
| --- | --- | --- | --- | --- |
| web/ops/src/app/core/resource/resource-spec.ts:755 | site-faq | question_ar, answer_ar, question_en, answer_en, sort_order, status |  |  |

### SITE_TEAM_SPEC

| Source | Resource | Form fields | Keys (columns/actions) | Permissions |
| --- | --- | --- | --- | --- |
| web/ops/src/app/core/resource/resource-spec.ts:781 | site-team | name_ar, role_ar, name_en, role_en, sort_order, status |  |  |

### SITE_REVIEWS_SPEC

| Source | Resource | Form fields | Keys (columns/actions) | Permissions |
| --- | --- | --- | --- | --- |
| web/ops/src/app/core/resource/resource-spec.ts:800 | site-reviews | display_name, body_ar, body_en, guardian_id, sort_order, status |  |  |

### SITE_SERVICES_SPEC

| Source | Resource | Form fields | Keys (columns/actions) | Permissions |
| --- | --- | --- | --- | --- |
| web/ops/src/app/core/resource/resource-spec.ts:841 | site-services | service_id, blurb_ar, blurb_en, icon_key, sort_order, status |  |  |

### SITE_SECTIONS_SPEC

| Source | Resource | Form fields | Keys (columns/actions) | Permissions |
| --- | --- | --- | --- | --- |
| web/ops/src/app/core/resource/resource-spec.ts:906 | site-sections | code, visible_flg |  |  |

### SITE_PROGRAMS_SPEC

| Source | Resource | Form fields | Keys (columns/actions) | Permissions |
| --- | --- | --- | --- | --- |
| web/ops/src/app/core/resource/resource-spec.ts:925 | site-programs | title_ar, desc_ar, detail_ar, title_en, desc_en, detail_en, icon_key, sort_order, status |  |  |

### SITE_TEAM_FACTS_SPEC

| Source | Resource | Form fields | Keys (columns/actions) | Permissions |
| --- | --- | --- | --- | --- |
| web/ops/src/app/core/resource/resource-spec.ts:955 | site-team-facts | member_id, text_ar, text_en, sort_order |  |  |

### SITE_CERTIFICATES_SPEC

| Source | Resource | Form fields | Keys (columns/actions) | Permissions |
| --- | --- | --- | --- | --- |
| web/ops/src/app/core/resource/resource-spec.ts:989 | site-team-certificates | member_id, path, caption_ar, caption_en, consent_given_at, redaction_checked_at, sort_order, status |  |  |

## web/ops/src/app/core/ops/day-spec.ts

### APPOINTMENTS_SPEC

| Source | Resource | Form fields | Keys (columns/actions) | Permissions |
| --- | --- | --- | --- | --- |
| web/ops/src/app/core/ops/day-spec.ts:356 | appointments | child_id, service_therapist, service_id, therapist_id, delivery_mode, slot, starts_at, ends_at, room_id, note_ar, status | time, child, childNo, service, therapist, room, book, status, start | APPOINTMENT.BOOK, SESSION.START |

### SESSIONS_SPEC

| Source | Resource | Form fields | Keys (columns/actions) | Permissions |
| --- | --- | --- | --- | --- |
| web/ops/src/app/core/ops/day-spec.ts:661 | sessions | body_ar, status | started, ended, child, service, therapist, room, watch, note, close | LIVE.VIEW, SESSION.NOTES.EDIT, SESSION.COMPLETE |

### REPORTS_SPEC

| Source | Resource | Form fields | Keys (columns/actions) | Permissions |
| --- | --- | --- | --- | --- |
| web/ops/src/app/core/ops/day-spec.ts:773 | reports |  | no, title, child, period, publishedAt, publish | REPORT.PUBLISH |

### INVOICES_SPEC

| Source | Resource | Form fields | Keys (columns/actions) | Permissions |
| --- | --- | --- | --- | --- |
| web/ops/src/app/core/ops/day-spec.ts:837 | invoices | child_id, due_date, note_ar, child_id, package_id, description_ar, qty, unit_amt, amount, method_code, note_ar | no, child, issue, due, total, paid, newInvoice, sell, addLine, issue, pay | BILLING.MANAGE |

### REQUESTS_SPEC

| Source | Resource | Form fields | Keys (columns/actions) | Permissions |
| --- | --- | --- | --- | --- |
| web/ops/src/app/core/ops/day-spec.ts:1026 | requests | status, note_ar | no, kind, child, guardian, guardianMobile, body, preferred, created, decide | REQUEST.MANAGE |

### ENROLMENTS_SPEC

| Source | Resource | Form fields | Keys (columns/actions) | Permissions |
| --- | --- | --- | --- | --- |
| web/ops/src/app/core/ops/day-spec.ts:1132 | enrolments | status, note_ar, note_ar | no, submitted, parent, mobile, childName, age, concern, source, open, status, convert | ENROLMENT.MANAGE |

## Forms / dialogs / actions / tabs / calls

الموضع مؤشر تتبع لا عداد أزرار؛ @for قد يولد عدة أفعال. FORM جرد تقني يتبع حاوية PAGE/MODAL في التصنيف. راجع required/when/run في موضع التعريف لمعرفة التحقق والتنفيذ.

| Kind | Source | Declaration |
| --- | --- | --- |
| TAB | web/ops/src/app/app.routes.ts:187 | extraTabs: [{ |
| TAB | web/ops/src/app/app.routes.ts:258 | extraTabs: [{ |
| TAB | web/ops/src/app/app.routes.ts:422 | extraTabs: [{ |
| API CALL | web/ops/src/app/core/api/child-api.ts:47 | return this.http.get<Row>(`${this.base}/children/${childId}`); |
| API CALL | web/ops/src/app/core/api/child-api.ts:75 | return this.http.get<Balance>(`${this.base}/children/${childId}/balance`); |
| API CALL | web/ops/src/app/core/api/child-api.ts:91 | return this.http.post(`${this.base}/guardians/${guardianId}/consent`, |
| API CALL | web/ops/src/app/core/api/child-api.ts:114 | return this.http.post<void>(`${this.base}/notes/${noteId}/publish`, {}); |
| API CALL | web/ops/src/app/core/api/child-api.ts:134 | return this.http.post<{ report_id: number; version: string }>(`${this.base}/reports`, input); |
| API CALL | web/ops/src/app/core/api/child-api.ts:150 | return this.http.patch<{ version: string }>(`${this.base}/reports/${reportId}`, patch); |
| API CALL | web/ops/src/app/core/api/child-api.ts:154 | return this.http.get<Row>(`${this.base}/reports/${reportId}`); |
| API CALL | web/ops/src/app/core/api/child-api.ts:158 | return this.http.post<void>(`${this.base}/reports/${reportId}/publish`, {}); |
| API CALL | web/ops/src/app/core/api/inbox-api.ts:61 | return this.http.get<FeedResponse>(`${this.base}/notifications`, { |
| API CALL | web/ops/src/app/core/api/inbox-api.ts:79 | return this.http.post(`${this.base}/notifications/${id}/read`, {}); |
| API CALL | web/ops/src/app/core/api/live-api.ts:51 | return this.http.post<StreamGrant>( |
| API CALL | web/ops/src/app/core/api/live-api.ts:63 | return this.http.post<void>( |
| API CALL | web/ops/src/app/core/api/ops-api.ts:135 | return this.http.get<Row>(`${this.base}/${resource}/${id}`); |
| API CALL | web/ops/src/app/core/api/ops-api.ts:139 | return this.http.post<Row>(`${this.base}/${resource}`, body); |
| API CALL | web/ops/src/app/core/api/ops-api.ts:143 | return this.http.patch<Row>(`${this.base}/${resource}/${id}`, body); |
| API CALL | web/ops/src/app/core/api/ops-api.ts:152 | return this.http.delete<void>(`${this.base}/${resource}/${id}`); |
| API CALL | web/ops/src/app/core/api/ops-api.ts:156 | return this.http.post<void>(`${this.base}/${resource}/${id}/restore`, {}); |
| API CALL | web/ops/src/app/core/api/ops-api.ts:173 | return this.http.post<UploadResult>(`${this.base}/site-media`, form); |
| API CALL | web/ops/src/app/core/api/therapist-profile-api.ts:47 | return this.http.patch<void>(`${this.base}/therapists/${therapistId}/profile`, edit); |
| API CALL | web/ops/src/app/core/api/therapist-profile-api.ts:72 | return this.http.put<void>(`${this.base}/therapists/${therapistId}/languages`, { |
| API CALL | web/ops/src/app/core/api/therapist-profile-api.ts:81 | return this.http.delete<void>( |
| API CALL | web/ops/src/app/core/api/therapist-profile-api.ts:92 | return this.http.post<{ certificate_id: number }>( |
| API CALL | web/ops/src/app/core/api/therapist-profile-api.ts:110 | return this.http.patch<void>( |
| API CALL | web/ops/src/app/core/api/therapist-profile-api.ts:124 | return this.http.post<void>(`${this.base}/therapists/${therapistId}/consent`, {}); |
| API CALL | web/ops/src/app/core/api/therapist-profile-api.ts:133 | return this.http.delete<void>(`${this.base}/therapists/${therapistId}/consent`); |
| API CALL | web/ops/src/app/core/api/therapist-profile-api.ts:143 | return this.http.post<void>(`${this.base}/therapists/${therapistId}/publish`, {}); |
| API CALL | web/ops/src/app/core/api/therapist-profile-api.ts:147 | return this.http.get<Record<string, unknown>>(url).pipe(map((body) => { |
| API CALL | web/ops/src/app/core/auth/ops-auth.service.ts:108 | return this.http.get<MeResponse>(`${this.base}/me`).pipe( |
| API CALL | web/ops/src/app/core/auth/ops-auth.service.ts:146 | this.http.post(`${this.base}/auth/logout`, {}).subscribe({ |
| MODAL | web/ops/src/app/core/ops/action-dialog.service.ts:36 | export class ActionDialogService { |
| API CALL | web/ops/src/app/core/ops/action-dialog.service.ts:72 | ? this.day.get(request.entityType, request.entityId).pipe(catchError(() => of(null))) |
| API CALL | web/ops/src/app/core/ops/action-dialog.service.ts:104 | ? this.crud.get(request.resource, request.entityId).pipe(catchError(() => of(null))) |
| API CALL | web/ops/src/app/core/ops/day-api.ts:151 | return this.http.get<Row>(`${this.base}/${resource}/${id}`); |
| API CALL | web/ops/src/app/core/ops/day-api.ts:217 | return this.http.post<SlotCheck>(`${this.base}/appointments/validate`, body); |
| API CALL | web/ops/src/app/core/ops/day-api.ts:221 | return this.http.post<{ appointment_id: number }>(`${this.base}/appointments`, body); |
| API CALL | web/ops/src/app/core/ops/day-api.ts:233 | return this.http.patch<void>( |
| API CALL | web/ops/src/app/core/ops/day-api.ts:238 | return this.http.post<{ session_id: number }>( |
| API CALL | web/ops/src/app/core/ops/day-api.ts:245 | return this.http.patch<void>(`${this.base}/sessions/${id}/close`, { status, reason }); |
| API CALL | web/ops/src/app/core/ops/day-api.ts:255 | return this.http.put<{ note_id: number }>( |
| API CALL | web/ops/src/app/core/ops/day-api.ts:262 | return this.http.post<void>(`${this.base}/reports/${id}/publish`, {}); |
| API CALL | web/ops/src/app/core/ops/day-api.ts:266 | return this.http.post<void>(`${this.base}/invoices/${id}/issue`, {}); |
| API CALL | web/ops/src/app/core/ops/day-api.ts:284 | return this.http.post<{ invoice_id: number }>(`${this.base}/invoices`, { |
| API CALL | web/ops/src/app/core/ops/day-api.ts:306 | return this.http.post<{ line_id: number }>(`${this.base}/invoices/${invoiceId}/lines`, { |
| API CALL | web/ops/src/app/core/ops/day-api.ts:315 | return this.http.delete<void>(`${this.base}/invoices/${invoiceId}/lines/${lineId}`); |
| API CALL | web/ops/src/app/core/ops/day-api.ts:361 | return this.http.post<void>( |
| API CALL | web/ops/src/app/core/ops/day-api.ts:366 | return this.http.delete<void>( |
| API CALL | web/ops/src/app/core/ops/day-api.ts:378 | return this.http.post<{ payment_id: number }>( |
| API CALL | web/ops/src/app/core/ops/day-api.ts:384 | return this.http.post<{ child_package_id: number }>( |
| API CALL | web/ops/src/app/core/ops/day-api.ts:389 | return this.http.patch<void>(`${this.base}/requests/${id}`, { status, note_ar: noteAr }); |
| API CALL | web/ops/src/app/core/ops/day-api.ts:406 | return this.http.patch<void>( |
| API CALL | web/ops/src/app/core/ops/day-api.ts:421 | return this.http.post<{ guardian_id: number; child_id: number; child_no: string }>( |
| MODAL | web/ops/src/app/core/ops/record-drawer.ts:16 | * action set (day-spec.ts), opened through ActionDialogService with the |
| ACTION | web/ops/src/app/features/access/access.html:10 | <button class="hbh-btn hbh-btn--primary" type="button" (click)="startAddUser()"> |
| ACTION | web/ops/src/app/features/access/access.html:15 | <button class="hbh-btn hbh-btn--ghost" type="button" (click)="load()"> |
| TAB | web/ops/src/app/features/access/access.html:22 | <div class="hbh-tabbar" role="tablist"> |
| ACTION | web/ops/src/app/features/access/access.html:23 | <button class="hbh-tabbar__item" type="button" role="tab" |
| ACTION | web/ops/src/app/features/access/access.html:25 | [attr.aria-selected]="tab() === 'people'" (click)="showTab('people')"> |
| ACTION | web/ops/src/app/features/access/access.html:28 | <button class="hbh-tabbar__item" type="button" role="tab" |
| ACTION | web/ops/src/app/features/access/access.html:30 | [attr.aria-selected]="tab() === 'roles'" (click)="showTab('roles')"> |
| ACTION | web/ops/src/app/features/access/access.html:33 | <button class="hbh-tabbar__item" type="button" role="tab" |
| ACTION | web/ops/src/app/features/access/access.html:35 | [attr.aria-selected]="tab() === 'screens'" (click)="showTab('screens')"> |
| ACTION | web/ops/src/app/features/access/access.html:58 | <button class="hbh-btn hbh-btn--ghost hbh-acc__search" type="button" |
| ACTION | web/ops/src/app/features/access/access.html:59 | [attr.aria-pressed]="showArchived()" (click)="toggleArchived()"> |
| ACTION | web/ops/src/app/features/access/access.html:66 | <button class="hbh-btn hbh-btn--ghost hbh-acc__search" type="button" |
| ACTION | web/ops/src/app/features/access/access.html:67 | [attr.aria-pressed]="onlyInactive()" (click)="toggleOnlyInactive()"> |
| ACTION | web/ops/src/app/features/access/access.html:72 | <button class="hbh-md__item" type="button" |
| ACTION | web/ops/src/app/features/access/access.html:75 | (click)="selectUser(user)"> |
| ACTION | web/ops/src/app/features/access/access.html:106 | <button class="hbh-btn hbh-btn--ghost" type="button" (click)="cancelRoles()"> |
| ACTION | web/ops/src/app/features/access/access.html:109 | <button class="hbh-btn hbh-btn--primary" type="button" |
| ACTION | web/ops/src/app/features/access/access.html:110 | [disabled]="saving()" (click)="saveRoles()"> |
| ACTION | web/ops/src/app/features/access/access.html:146 | <button class="hbh-btn hbh-btn--ghost" type="button" |
| ACTION | web/ops/src/app/features/access/access.html:147 | (click)="dismissSetupCode()"> |
| ACTION | web/ops/src/app/features/access/access.html:154 | <button class="hbh-btn hbh-btn--ghost" type="button" |
| ACTION | web/ops/src/app/features/access/access.html:155 | [disabled]="issuing()" (click)="issueSetupCode()"> |
| ACTION | web/ops/src/app/features/access/access.html:163 | <button class="hbh-btn hbh-btn--ghost" type="button" |
| ACTION | web/ops/src/app/features/access/access.html:164 | (click)="archiveUser(user, true)"> |
| ACTION | web/ops/src/app/features/access/access.html:169 | <button class="hbh-btn hbh-btn--ghost" type="button" |
| ACTION | web/ops/src/app/features/access/access.html:170 | (click)="setStatus(user, 'SUSPENDED')"> |
| ACTION | web/ops/src/app/features/access/access.html:174 | <button class="hbh-btn hbh-btn--ghost" type="button" |
| ACTION | web/ops/src/app/features/access/access.html:175 | (click)="setStatus(user, 'ACTIVE')"> |
| ACTION | web/ops/src/app/features/access/access.html:181 | <button class="hbh-btn hbh-btn--ghost" type="button" |
| ACTION | web/ops/src/app/features/access/access.html:182 | (click)="archiveUser(user, false)"> |
| ACTION | web/ops/src/app/features/access/access.html:198 | <button class="hbh-btn hbh-btn--ghost hbh-md__add" type="button" |
| ACTION | web/ops/src/app/features/access/access.html:199 | (click)="togglePasswordForm()"> |
| ACTION | web/ops/src/app/features/access/access.html:226 | <button class="hbh-btn hbh-btn--primary" type="button" |
| ACTION | web/ops/src/app/features/access/access.html:227 | [disabled]="pwBusy()" (click)="changePassword()"> |
| ACTION | web/ops/src/app/features/access/access.html:247 | <button class="hbh-btn hbh-btn--ghost" type="button" (click)="cancelPii()"> |
| ACTION | web/ops/src/app/features/access/access.html:250 | <button class="hbh-btn hbh-btn--primary" type="button" |
| ACTION | web/ops/src/app/features/access/access.html:251 | [disabled]="saving()" (click)="savePii()"> |
| ACTION | web/ops/src/app/features/access/access.html:284 | <button class="hbh-btn hbh-btn--ghost" type="button" |
| ACTION | web/ops/src/app/features/access/access.html:285 | (click)="removeStaffPhoto()"> |
| ACTION | web/ops/src/app/features/access/access.html:351 | <button class="hbh-link hbh-acc__docLink" type="button" |
| ACTION | web/ops/src/app/features/access/access.html:352 | (click)="openDocument(doc)"> |
| ACTION | web/ops/src/app/features/access/access.html:356 | <button class="hbh-iconbtn" type="button" |
| ACTION | web/ops/src/app/features/access/access.html:358 | (click)="archiveDocument(doc)"> |
| ACTION | web/ops/src/app/features/access/access.html:455 | <button class="hbh-btn hbh-btn--ghost hbh-md__add" type="button" |
| ACTION | web/ops/src/app/features/access/access.html:456 | (click)="startEditRole(role)"> |
| ACTION | web/ops/src/app/features/access/access.html:499 | <button class="hbh-btn hbh-btn--ghost" type="button" (click)="cancelEditRole()"> |
| ACTION | web/ops/src/app/features/access/access.html:502 | <button class="hbh-btn hbh-btn--primary" type="button" |
| ACTION | web/ops/src/app/features/access/access.html:503 | [disabled]="saving()  /  /  !roleDirty()" (click)="saveRolePerms()"> |
| MODAL | web/ops/src/app/features/access/access.html:599 | <dialog class="hbh-sheet" hbhModal (dismissed)="cancelAddUser()" |
| FORM | web/ops/src/app/features/access/access.html:601 | <form class="hbh-sheet__box hbh-sheet__box--editor" (submit)="saveUser($event)"> |
| ACTION | web/ops/src/app/features/access/access.html:604 | <button class="hbh-iconbtn" type="button" [attr.aria-label]="'action.cancel'  /  t" |
| ACTION | web/ops/src/app/features/access/access.html:605 | (click)="cancelAddUser()"> |
| ACTION | web/ops/src/app/features/access/access.html:654 | <button class="hbh-btn hbh-btn--ghost" type="button" (click)="cancelAddUser()"> |
| ACTION | web/ops/src/app/features/access/access.html:657 | <button class="hbh-btn hbh-btn--primary" type="submit" [disabled]="saving()"> |
| TAB | web/ops/src/app/features/access/access.ts:60 | type Tab = 'people'  /  'roles'  /  'screens'; |
| FORM | web/ops/src/app/features/access/access.ts:117 | protected readonly search = new FormControl('', { nonNullable: true }); |
| API CALL | web/ops/src/app/features/access/access.ts:275 | this.http.get<{ roles?: readonly RoleRow[] }>(`${this.base}/roles`) |
| API CALL | web/ops/src/app/features/access/access.ts:283 | this.http.get<{ permissions?: readonly { code: string }[] }>(`${this.base}/permissions`) |
| API CALL | web/ops/src/app/features/access/access.ts:315 | this.http.get<{ users?: readonly UserRow[] }>(`${this.base}/users${query}`) |
| API CALL | web/ops/src/app/features/access/access.ts:350 | profiles: this.http.get<Record<string, unknown>>(`${this.base}/staff-profiles`), |
| API CALL | web/ops/src/app/features/access/access.ts:351 | documents: this.http.get<Record<string, unknown>>(`${this.base}/staff-documents`), |
| API CALL | web/ops/src/app/features/access/access.ts:413 | this.http.put(`${this.base}/users/${user.user_id}/roles`, |
| FORM | web/ops/src/app/features/access/access.ts:446 | protected readonly pwCurrent = new FormControl('', { nonNullable: true }); |
| FORM | web/ops/src/app/features/access/access.ts:447 | protected readonly pwNext = new FormControl('', { nonNullable: true }); |
| API CALL | web/ops/src/app/features/access/access.ts:469 | this.http.post(`${this.base}/auth/password`, |
| API CALL | web/ops/src/app/features/access/access.ts:511 | this.http.post<{ setup_code: string }>( |
| FORM | web/ops/src/app/features/access/access.ts:574 | controls[name] = new FormControl(value, { nonNullable: true }); |
| API CALL | web/ops/src/app/features/access/access.ts:652 | ? this.http.patch(`${this.base}/staff-profiles/${existing['profile_id']}`, body) |
| API CALL | web/ops/src/app/features/access/access.ts:653 | : this.http.post(`${this.base}/staff-profiles`, { ...body, user_id: user.user_id }); |
| API CALL | web/ops/src/app/features/access/access.ts:694 | this.http.post(`${this.base}/users/${user.user_id}/documents`, form) |
| API CALL | web/ops/src/app/features/access/access.ts:710 | this.http.delete(`${this.base}/staff-documents/${doc['document_id']}`) |
| API CALL | web/ops/src/app/features/access/access.ts:736 | this.http.get(`${this.base}/staff-documents/${doc['document_id']}/file`, |
| API CALL | web/ops/src/app/features/access/access.ts:772 | this.http.get(`${this.base}/users/${user.user_id}/photo`, { responseType: 'blob' }) |
| API CALL | web/ops/src/app/features/access/access.ts:806 | this.http.post(`${this.base}/users/${user.user_id}/photo`, form) |
| API CALL | web/ops/src/app/features/access/access.ts:828 | this.http.patch(`${this.base}/staff-profiles/${existing['profile_id']}`, |
| FORM | web/ops/src/app/features/access/access.ts:860 | username: new FormControl('', { nonNullable: true }), |
| FORM | web/ops/src/app/features/access/access.ts:861 | full_name_ar: new FormControl('', { nonNullable: true }), |
| FORM | web/ops/src/app/features/access/access.ts:862 | user_type: new FormControl('STAFF', { nonNullable: true }), |
| FORM | web/ops/src/app/features/access/access.ts:863 | mobile: new FormControl('', { nonNullable: true }), |
| API CALL | web/ops/src/app/features/access/access.ts:898 | this.http.post<{ user_id: number }>(`${this.base}/users`, { |
| API CALL | web/ops/src/app/features/access/access.ts:930 | this.http.patch(`${this.base}/users/${user.user_id}`, { status }) |
| API CALL | web/ops/src/app/features/access/access.ts:945 | this.http.delete(url) |
| API CALL | web/ops/src/app/features/access/access.ts:1025 | this.http.put(`${this.base}/roles/${encodeURIComponent(code)}/permissions`, |
| ACTION | web/ops/src/app/features/child/child-profile.html:5 | <p class="cp__center"><button class="hbh-btn hbh-btn--ghost" type="button" (click)="back()">{{ 'child.backToList'  /  t }}</button></p> |
| ACTION | web/ops/src/app/features/child/child-profile.html:8 | <p class="cp__center"><button class="hbh-btn hbh-btn--ghost" type="button" (click)="back()">{{ 'child.backToList'  /  t }}</button></p> |
| ACTION | web/ops/src/app/features/child/child-profile.html:16 | <button class="hbh-iconbtn" type="button" [attr.aria-label]="'action.back'  /  t" (click)="back()"> |
| ACTION | web/ops/src/app/features/child/child-profile.html:63 | @if (nextAppointment(); as next) { <button type="button" class="cp__linkbtn" (click)="openAppointment(next)"><span dir="ltr">{{ when(t(next, 'starts_at')) }}</span> · {{ r(next, 'service', 'name_ar') }}</button> } |
| ACTION | web/ops/src/app/features/child/child-profile.html:74 | <button class="hbh-btn hbh-btn--primary" type="button" (click)="book()"><hbh-icon name="ic-cal-plus" /> {{ 'appointments.book'  /  t }}</button> |
| ACTION | web/ops/src/app/features/child/child-profile.html:77 | <button class="hbh-btn hbh-btn--ghost" type="button" (click)="assignTherapist()"><hbh-icon name="ic-user-check" /> {{ 'child.assignTherapist'  /  t }}</button> |
| ACTION | web/ops/src/app/features/child/child-profile.html:80 | <button class="hbh-btn hbh-btn--ghost" type="button" (click)="newPlan()"><hbh-icon name="ic-target" /> {{ 'child.newPlan'  /  t }}</button> |
| TAB | web/ops/src/app/features/child/child-profile.html:113 | <div class="hbh-tabbar cp__tabs" role="tablist"> |
| ACTION | web/ops/src/app/features/child/child-profile.html:116 | <button class="hbh-tabbar__item" type="button" role="tab" |
| ACTION | web/ops/src/app/features/child/child-profile.html:117 | [class.is-active]="tab() === item" [attr.aria-selected]="tab() === item" (click)="selectTab(item)"> |
| ACTION | web/ops/src/app/features/child/child-profile.html:145 | @if (canAssign()) { <button type="button" class="hbh-btn hbh-btn--ghost" (click)="assignTherapist()">{{ 'child.assignTherapist'  /  t }}</button> } |
| ACTION | web/ops/src/app/features/child/child-profile.html:154 | <button type="button" class="hbh-btn hbh-btn--ghost" (click)="selectTab('plans')">{{ 'child.showAll'  /  t }}</button> |
| ACTION | web/ops/src/app/features/child/child-profile.html:159 | <article><button type="button" class="cp__linkbtn" (click)="openAppointment(row)"><strong dir="ltr">{{ when(t(row, 'starts_at')) }}</strong></button><p>{{ r(row, 'service', 'name_ar') }} · {{ r(row, 'therapist', 'full_name_ar') }} · <span class="hbh-badge" [class]="'hbh-badge ' + apptTone(row)">{{ apptStatusKey(row)  /  t }}</span></p></article> |
| ACTION | web/ops/src/app/features/child/child-profile.html:164 | <button type="button" class="hbh-btn hbh-btn--ghost" (click)="selectTab('appointments')">{{ 'child.showAll'  /  t }}</button> |
| ACTION | web/ops/src/app/features/child/child-profile.html:165 | @if (canBook()) { <button type="button" class="hbh-btn hbh-btn--primary" (click)="book()">{{ 'appointments.book'  /  t }}</button> } |
| ACTION | web/ops/src/app/features/child/child-profile.html:186 | <button type="button" class="hbh-btn hbh-btn--sm hbh-btn--ghost" [disabled]="publishing() === n(g, 'guardian_id')" (click)="toggleLiveConsent(g)"> |
| ACTION | web/ops/src/app/features/child/child-profile.html:201 | @if (canBook()) { <button class="hbh-btn hbh-btn--primary" type="button" (click)="book()"><hbh-icon name="ic-cal-plus" /> {{ 'appointments.book'  /  t }}</button> } |
| ACTION | web/ops/src/app/features/child/child-profile.html:226 | <button class="hbh-btn hbh-btn--sm hbh-btn--ghost" type="button" (click)="openAppointment(row)"><hbh-icon name="ic-eye" /> {{ 'action.open'  /  t }}</button> |
| ACTION | web/ops/src/app/features/child/child-profile.html:227 | @if (canRow('appointments', 'start', row)) { <button class="hbh-btn hbh-btn--sm hbh-btn--primary" type="button" (click)="rowAction('appointments', 'start', row)">{{ 'sessions.start'  /  t }}</button> } |
| ACTION | web/ops/src/app/features/child/child-profile.html:228 | @if (canRow('appointments', 'status', row)) { <button class="hbh-btn hbh-btn--sm hbh-btn--ghost" type="button" (click)="rowAction('appointments', 'status', row)">{{ 'appointments.changeStatus'  /  t }}</button> } |
| ACTION | web/ops/src/app/features/child/child-profile.html:253 | @if (canRow('sessions', 'note', row)) { <button class="hbh-btn hbh-btn--sm hbh-btn--ghost" type="button" (click)="rowAction('sessions', 'note', row)">{{ 'sessions.note'  /  t }}</button> } |
| ACTION | web/ops/src/app/features/child/child-profile.html:254 | @if (canRow('sessions', 'close', row)) { <button class="hbh-btn hbh-btn--sm hbh-btn--primary" type="button" (click)="rowAction('sessions', 'close', row)">{{ 'sessions.close'  /  t }}</button> } |
| ACTION | web/ops/src/app/features/child/child-profile.html:272 | @if (canPlan()) { <button class="hbh-btn hbh-btn--primary" type="button" (click)="newPlan()"><hbh-icon name="ic-target" /> {{ 'child.newPlan'  /  t }}</button> } |
| ACTION | web/ops/src/app/features/child/child-profile.html:287 | @if (canGoal()) { <button class="hbh-btn hbh-btn--sm hbh-btn--ghost" type="button" (click)="addGoal(plan)">{{ 'child.addGoal'  /  t }}</button> } |
| ACTION | web/ops/src/app/features/child/child-profile.html:288 | @if (canPlan()) { <button class="hbh-btn hbh-btn--sm hbh-btn--ghost" type="button" (click)="editPlan(plan)">{{ 'action.edit'  /  t }}</button> } |
| ACTION | web/ops/src/app/features/child/child-profile.html:320 | @if (canMeasure()) { <button class="hbh-btn hbh-btn--sm hbh-btn--primary" type="button" (click)="addMeasurement(goal)">{{ 'child.addMeasurement'  /  t }}</button> } |
| ACTION | web/ops/src/app/features/child/child-profile.html:321 | @if (canGoal()) { <button class="hbh-btn hbh-btn--sm hbh-btn--ghost" type="button" (click)="editGoal(goal)">{{ 'action.edit'  /  t }}</button> } |
| ACTION | web/ops/src/app/features/child/child-profile.html:368 | @if (canRow('reports', 'publish', row)) { <button class="hbh-btn hbh-btn--sm hbh-btn--primary" type="button" (click)="rowAction('reports', 'publish', row)">{{ 'reports.publish'  /  t }}</button> } |
| ACTION | web/ops/src/app/features/child/child-profile.html:405 | <td><button class="hbh-btn hbh-btn--sm hbh-btn--ghost" type="button" (click)="openInvoice(row)"><hbh-icon name="ic-eye" /> {{ 'action.open'  /  t }}</button></td></tr> |
| ACTION | web/ops/src/app/features/child/child-profile.html:425 | <button type="button" class="hbh-btn hbh-btn--sm" [disabled]="publishing() === n(row, 'note_id')" (click)="publishNote(row)">{{ 'notes.publish'  /  t }}</button> |
| MODAL | web/ops/src/app/features/child/child-profile.ts:21 | import { ActionDialogService } from '../../core/ops/action-dialog.service'; |
| TAB | web/ops/src/app/features/child/child-profile.ts:26 | type Tab = 'overview'  /  'family'  /  'appointments'  /  'sessions'  /  'assessments'  /  'plans'  /  'goals' |
| TAB | web/ops/src/app/features/child/child-profile.ts:29 | const TABS: readonly Tab[] = [ |
| MODAL | web/ops/src/app/features/child/child-profile.ts:66 | * drawn here through ActionDialogService: the same dialog, the same |
| MODAL | web/ops/src/app/features/child/child-profile.ts:88 | private readonly dialogs = inject(ActionDialogService); |
| TAB | web/ops/src/app/features/child/child-profile.ts:104 | protected readonly tabs = TABS; |
| API CALL | web/ops/src/app/features/child/child-profile.ts:282 | this.api.balance(this.childId) |
| API CALL | web/ops/src/app/features/child/child-profile.ts:293 | child: this.api.child(this.childId), |
| API CALL | web/ops/src/app/features/child/child-profile.ts:294 | balance: this.api.balance(this.childId).pipe(catchError(() => of(null))), |
| API CALL | web/ops/src/app/features/child/child-profile.ts:324 | this.api.list(this.childId, part) |
| API CALL | web/ops/src/app/features/child/child-profile.ts:360 | caseload: this.crud.list('caseload', { limit: 200 }).pipe(map((page) => page.rows)), |
| API CALL | web/ops/src/app/features/child/child-profile.ts:361 | therapists: this.crud.list('therapists', { limit: 200 }).pipe(map((page) => page.rows), catchError(() => of([] as readonly Row[]))), |
| API CALL | web/ops/src/app/features/child/child-profile.ts:362 | services: this.crud.list('services', { limit: 200 }).pipe(map((page) => page.rows), catchError(() => of([] as readonly Row[]))), |
| API CALL | web/ops/src/app/features/child/child-profile.ts:394 | this.crud.list('measurements', { limit: 200 }) |
| API CALL | web/ops/src/app/features/child/child-profile.ts:559 | this.api.publishNote(id) |
| API CALL | web/ops/src/app/features/child/child-profile.ts:574 | ? this.api.withdrawConsent(guardian, 'LIVE_VIEW', this.childId) |
| API CALL | web/ops/src/app/features/child/child-profile.ts:575 | : this.api.grantConsent(guardian, 'LIVE_VIEW', this.childId); |
| ACTION | web/ops/src/app/features/child-card/child-card.html:12 | <button class="hbh-iconbtn" type="button" |
| ACTION | web/ops/src/app/features/child-card/child-card.html:13 | [attr.aria-label]="'action.back'  /  t" (click)="back()"> |
| ACTION | web/ops/src/app/features/child-card/child-card.html:22 | <button class="hbh-btn hbh-btn--ghost" type="button" (click)="printOne()"> |
| ACTION | web/ops/src/app/features/child-card/child-card.html:26 | <button class="hbh-btn hbh-btn--primary" type="button" (click)="printSheet()"> |
| API CALL | web/ops/src/app/features/child-card/child-card.ts:106 | this.http.get(`${this.base}/children/${this.childId}/photo`, { responseType: 'blob' }) |
| ACTION | web/ops/src/app/features/dashboard/dashboard.html:12 | <button class="hbh-iconbtn toolbar-bell" type="button" aria-label="الإشعارات" title="الإشعارات" [attr.aria-expanded]="toolbarPanel() === 'alerts'" aria-controls="dashboard-toolbar-panel" (click)="toggleToolbar('alerts')"><hbh-icon name="ic-check-circle" />@if(tasks.count()){<span class="toolbar-count">{{ tasks.count() }}</span>}</button> |
| ACTION | web/ops/src/app/features/dashboard/dashboard.html:13 | <button class="hbh-iconbtn" type="button" aria-label="المساعدة" title="المساعدة" [attr.aria-expanded]="toolbarPanel() === 'help'" aria-controls="dashboard-toolbar-panel" (click)="toggleToolbar('help')"><hbh-icon name="ic-help" /></button> |
| ACTION | web/ops/src/app/features/dashboard/dashboard.html:14 | @if(toolbarPanel()) { <section id="dashboard-toolbar-panel" class="toolbar-panel" aria-live="polite"><div class="toolbar-panel-head"><strong>{{ toolbarPanel() === 'alerts' ? 'الإشعارات والمتابعة' : 'مساعدة لوحة التحكم' }}</strong><button class="hbh-iconbtn" type="button" aria-label="إغلاق" (click)="toolbarPanel.set(null)"><hbh-icon name="ic-x" /></button></div> |
| ACTION | web/ops/src/app/features/dashboard/dashboard.html:15 | @if(toolbarPanel() === 'alerts') { @for(task of taskPreview();track task.id){@if(task.primaryAction.drawer){<button type="button" (click)="openTask(task)">{{ task.titleKey  /  t }} · {{ task.entityDisplayName }}</button>}@else{<a [routerLink]="task.primaryAction.link" [queryParams]="task.primaryAction.query ?? null">{{ task.titleKey  /  t }} · {{ task.entityDisplayName }}</a>}} @empty {<p>{{ 'dash.noTasks'  /  t }}</p>} <a routerLink="/tasks">{{ 'dash.allTasks'  /  t }}</a> } |
| ACTION | web/ops/src/app/features/dashboard/dashboard.html:19 | <button class="hbh-btn hbh-btn--ghost" type="button" (click)="load()"> |
| ACTION | web/ops/src/app/features/dashboard/dashboard.html:69 | @if(canStart(row)){<button class="hbh-btn hbh-btn--primary my-day__go" type="button" [disabled]="starting() !== null" (click)="startNow(row)"><hbh-icon name="ic-play"/>{{ 'sessions.start'  /  t }}</button>} |
| ACTION | web/ops/src/app/features/dashboard/dashboard.html:95 | <section class="dash-panel"><h2>{{ 'dash.tasksPreview'  /  t }} @if(tasks.loadedAt() && tasks.count()){<span class="hbh-badge hbh-badge--progress">{{ tasks.count() }}</span>}</h2><div class="dashboard-alerts">@for(task of taskPreview();track task.id){@if(task.primaryAction.drawer){<button type="button" class="dashboard-alerts__task" (click)="openTask(task)" [class.is-urgent]="task.priority === 'urgent'"><hbh-icon [name]="taskIcon(task)"/><span>{{ task.titleKey  /  t }} · {{ task.entityDisplayName }} |
| API CALL | web/ops/src/app/features/dashboard/dashboard.ts:249 | this.http.get(this.config.apiBaseUrl+'/api/v1/dashboard/metrics').pipe(takeUntilDestroyed(this.destroyRef)).subscribe({next:m=>this.metrics.set(m),error:()=>this.metrics.set(null)}); |
| API CALL | web/ops/src/app/features/dashboard/dashboard.ts:251 | if (this.auth.can('CATALOG.MANAGE')) this.crud.list('rooms',{limit:6}).pipe(takeUntilDestroyed(this.destroyRef)).subscribe({next:p=>{this.rooms.set(p.rows);this.roomsState.set('ready')},error:()=>this.roomsState.set('failed')}); |
| API CALL | web/ops/src/app/features/dashboard/dashboard.ts:261 | this.day.list('appointments', { therapist_id: mine, date: this.format.today(), limit: 50 }) |
| API CALL | web/ops/src/app/features/dashboard/dashboard.ts:272 | if(this.auth.can('APPOINTMENT.BOOK')) for(const part of this.agendaParts) this.day.list('appointments',{status:part.key,limit:1}).pipe(takeUntilDestroyed(this.destroyRef)).subscribe({next:p=>this.agenda.update(a=>({...a,[part.key]:p.total})),error:()=>this.agendaFailed.set(true)}); |
| API CALL | web/ops/src/app/features/dashboard/dashboard.ts:279 | ? this.crud.list('children', { limit: 1 }) |
| API CALL | web/ops/src/app/features/dashboard/dashboard.ts:280 | : this.day.list(tile.resource, { ...tile.query, limit: 1 }); |
| MODAL | web/ops/src/app/features/day/action-dialog-host.ts:9 | import { ActionDialogService } from '../../core/ops/action-dialog.service'; |
| MODAL | web/ops/src/app/features/day/action-dialog-host.ts:39 | private readonly svc = inject(ActionDialogService); |
| FORM | web/ops/src/app/features/day/billing-ledger.ts:7 | <section class="ledger"><form (submit)="$event.preventDefault();page.set(1);load()"><input aria-label="البحث بالاسم أو البيان" type="search" placeholder="ابحث بالاسم أو البيان" maxlength="100" [value]="query()" (input)="query.set($any($event.target).value)"><button class="hbh-btn" type="submit">بحث</button></form> |
| ACTION | web/ops/src/app/features/day/billing-ledger.ts:8 | @if(loading()){<p>جارٍ التحميل…</p>}@else if(failed()){<p role="alert">تعذر تحميل البيانات.</p><button class="hbh-btn" (click)="load()">إعادة المحاولة</button>}@else{ |
| ACTION | web/ops/src/app/features/day/billing-ledger.ts:10 | <footer><span>{{total()}} نتيجة · صفحة {{page()}}</span><button class="hbh-btn" [disabled]="page()===1" (click)="move(-1)">السابق</button><button class="hbh-btn" [disabled]="page()*25>=total()" (click)="move(1)">التالي</button></footer>} |
| API CALL | web/ops/src/app/features/day/billing-ledger.ts:19 | protected load(){const version=++this.version;this.loading.set(true);this.failed.set(false);this.http.get<{rows:Record<string,unknown>[];total:number}>(this.base+'/api/v1/billing/ledger',{params:new HttpParams().set('kind',this.kind).set('q',this.query().trim()).set('page',this.page())}).pipe(takeUntilDestroyed(this.destroy)).subscribe({next:r=>{if(version!==this.version)return;this.rows.set(r.rows);this.total.set(r.total);this.loading.set(false)},error:()=>{if(version!==this.version)return;this |
| ACTION | web/ops/src/app/features/day/billing-overview.ts:8 | <section class="summary"><header><div><h2>الملخص المالي</h2><p>الفواتير الصادرة والمدفوعة · التحصيل من بداية الشهر</p></div><button class="hbh-btn hbh-btn--ghost" type="button" (click)="load()">تحديث الملخص</button></header> |
| API CALL | web/ops/src/app/features/day/billing-overview.ts:20 | protected load(){this.loading.set(true);this.failed.set(false);this.http.get<{currencies:Summary[]}>(this.base+'/api/v1/billing/summary').pipe(takeUntilDestroyed(this.destroy)).subscribe({next:r=>{this.rows.set(r.currencies);this.loading.set(false)},error:()=>{this.failed.set(true);this.loading.set(false)}})} |
| ACTION | web/ops/src/app/features/day/day-screen.html:11 | <button class="hbh-btn" |
| ACTION | web/ops/src/app/features/day/day-screen.html:14 | type="button" (click)="startCreate(item)"> |
| ACTION | web/ops/src/app/features/day/day-screen.html:23 | <nav class="hbh-filters" aria-label="أقسام الفواتير">@for(tab of [{key:'invoices',label:'الفواتير'},{key:'payments',label:'المدفوعات'},{key:'packages',label:'الباقات والأسعار'},{key:'balances',label:'أرصدة الجلسات'}];track tab.key){<button type="button" class="hbh-btn" [class.hbh-btn--primary]="billingTab()===tab.key" [attr.aria-pressed]="billingTab()===tab.key" (click)="billingTab.set(tab.key)">{{tab.label}}</button>}</nav> |
| ACTION | web/ops/src/app/features/day/day-screen.html:28 | @if(spec.resource === 'invoices'){<button type="button" class="hbh-btn hbh-btn--ghost" [disabled]="exporting()  /  /  loading()  /  /  failed()" (click)="exportInvoices()">{{exporting() ? 'جارٍ التصدير…' : 'تصدير كل النتائج CSV'}}</button>} |
| ACTION | web/ops/src/app/features/day/day-screen.html:45 | @if(filtersFailed()){<button type="button" class="hbh-btn" (click)="loadFilterOptions()">تعذر تحميل الفلاتر — إعادة المحاولة</button>} |
| ACTION | web/ops/src/app/features/day/day-screen.html:48 | @if (spec.resource === 'enrolments') {<button type="button" class="hbh-btn hbh-btn--ghost" [attr.aria-pressed]="boardView()" (click)="toggleBoard()">{{ boardView() ? 'عرض الجدول' : 'عرض مراحل المتابعة' }}</button>} |
| ACTION | web/ops/src/app/features/day/day-screen.html:49 | @if (spec.resource === 'reports') {<button type="button" class="hbh-btn hbh-btn--ghost" [disabled]="loading()  /  /  failed()  /  /  !rows().length" (click)="exportPage()">تصدير الصفحة الحالية CSV</button>} |
| ACTION | web/ops/src/app/features/day/day-screen.html:51 | <button class="hbh-btn hbh-btn--ghost" type="button" [attr.aria-pressed]="calendarView()" (click)="toggleCalendar()"> |
| ACTION | web/ops/src/app/features/day/day-screen.html:58 | <button class="hbh-iconbtn" type="button" |
| ACTION | web/ops/src/app/features/day/day-screen.html:59 | [attr.aria-label]="calendarView() ? 'الأسبوع السابق' : ('action.previousDay'  /  t)" (click)="shiftDay(calendarView() ? -7 : -1)"> |
| ACTION | web/ops/src/app/features/day/day-screen.html:80 | <button class="hbh-iconbtn" type="button" |
| ACTION | web/ops/src/app/features/day/day-screen.html:81 | [attr.aria-label]="calendarView() ? 'الأسبوع التالي' : ('action.nextDay'  /  t)" (click)="shiftDay(calendarView() ? 7 : 1)"> |
| ACTION | web/ops/src/app/features/day/day-screen.html:84 | <button class="hbh-btn hbh-btn--ghost" type="button" (click)="setToday()"> |
| ACTION | web/ops/src/app/features/day/day-screen.html:111 | <button class="hbh-btn hbh-btn--ghost" type="button" (click)="toggleArchived()" |
| ACTION | web/ops/src/app/features/day/day-screen.html:156 | <button class="invoice-status" type="button" [class.is-selected]="status() === stage" (click)="setStatus(stage)"><span>{{ spec.statusPrefix + stage  /  t }}</span><strong>{{ invoiceCounts()[stage] ?? '—' }}</strong></button> |
| ACTION | web/ops/src/app/features/day/day-screen.html:163 | <details><summary>{{ 'appointments.pendingConfirm'  /  t }} ({{pendingAppointments().length}})</summary>@for(row of pendingAppointments();track rowKey(row)){<article><strong>{{appointmentName(row)}}</strong> · {{format.time($any(row['starts_at']))}}<div class="week-actions"><button class="hbh-btn hbh-btn--sm hbh-btn--ghost" type="button" (click)="openRecord(row)">{{ 'action.open'  /  t }}</button>@for(action of actionsFor(row);track action.key){<button class="hbh-btn hbh-btn--sm" type="button" (clic |
| ACTION | web/ops/src/app/features/day/day-screen.html:178 | <div class="week-actions">@for (action of actionsFor(row); track action.key) {<button type="button" class="hbh-btn hbh-btn--sm" (click)="startAction(action, row)">{{ action.labelKey  /  t }}</button>}</div> |
| ACTION | web/ops/src/app/features/day/day-screen.html:189 | @if(creates().length){<details class="hour-booking"><summary>حجز بساعة محددة</summary><p>يتم التحقق من التوافر قبل تأكيد الحجز.</p><div>@for(hour of bookingHours;track hour){<button type="button" class="hbh-btn hbh-btn--sm" (click)="bookHour(day.date,hour)">{{hour}}:00 · حجز</button>}</div></details>} |
| ACTION | web/ops/src/app/features/day/day-screen.html:203 | <button type="button" class="hbh-btn hbh-btn--sm" (click)="startAction(action, row)">{{ action.labelKey  /  t }}</button> |
| ACTION | web/ops/src/app/features/day/day-screen.html:252 | <button class="hbh-btn hbh-btn--sm hbh-btn--ghost" type="button" (click)="openRecord(row)"> |
| ACTION | web/ops/src/app/features/day/day-screen.html:270 | <button class="hbh-btn hbh-btn--sm" |
| ACTION | web/ops/src/app/features/day/day-screen.html:273 | type="button" (click)="startAction(action, row)"> |
| ACTION | web/ops/src/app/features/day/day-screen.html:296 | <button class="hbh-btn hbh-btn--ghost" type="button" |
| ACTION | web/ops/src/app/features/day/day-screen.html:297 | [disabled]="page() <= 1" (click)="goToPage(page() - 1)"> |
| ACTION | web/ops/src/app/features/day/day-screen.html:305 | <button class="hbh-btn hbh-btn--ghost" type="button" |
| ACTION | web/ops/src/app/features/day/day-screen.html:306 | [disabled]="page() >= pageCount()" (click)="goToPage(page() + 1)"> |
| MODAL | web/ops/src/app/features/day/day-screen.html:319 | <dialog class="hbh-sheet" hbhModal (dismissed)="close()" aria-labelledby="dayDialogTitle"> |
| FORM | web/ops/src/app/features/day/day-screen.html:320 | <form class="hbh-sheet__box" (submit)="submit($event)"> |
| ACTION | web/ops/src/app/features/day/day-screen.html:323 | <button class="hbh-iconbtn" type="button" |
| ACTION | web/ops/src/app/features/day/day-screen.html:324 | [attr.aria-label]="'action.cancel'  /  t" (click)="close()"> |
| ACTION | web/ops/src/app/features/day/day-screen.html:412 | <button type="button" class="childpick__one" |
| ACTION | web/ops/src/app/features/day/day-screen.html:414 | (click)="pickChild(field, hit)"> |
| ACTION | web/ops/src/app/features/day/day-screen.html:454 | <button type="button" class="slotpick__one" |
| ACTION | web/ops/src/app/features/day/day-screen.html:457 | (click)="pickSlot(slot)"> |
| ACTION | web/ops/src/app/features/day/day-screen.html:547 | <button class="hbh-btn hbh-btn--ghost hbh-sheet__more" type="button" |
| ACTION | web/ops/src/app/features/day/day-screen.html:548 | [attr.aria-expanded]="advancedOpen()" (click)="toggleAdvanced()"> |
| ACTION | web/ops/src/app/features/day/day-screen.html:607 | <button class="hbh-btn hbh-btn--primary" type="submit" |
| ACTION | web/ops/src/app/features/day/day-screen.html:620 | <button class="hbh-btn hbh-btn--ghost" type="button" |
| ACTION | web/ops/src/app/features/day/day-screen.html:622 | (click)="check()"> |
| ACTION | web/ops/src/app/features/day/day-screen.html:627 | <button class="hbh-btn hbh-btn--ghost" type="button" |
| ACTION | web/ops/src/app/features/day/day-screen.html:628 | [disabled]="saving()" (click)="close()"> |
| MODAL | web/ops/src/app/features/day/day-screen.ts:80 | * caller elsewhere (ActionDialogHost, through ActionDialogService). No |
| API CALL | web/ops/src/app/features/day/day-screen.ts:303 | this.api.servicePairs() |
| API CALL | web/ops/src/app/features/day/day-screen.ts:436 | return this.crud.list('children', { q, limit: 8 }) |
| API CALL | web/ops/src/app/features/day/day-screen.ts:508 | for (const name of names) this.crud.list(name, {limit: 100}).pipe(switchMap(first => { |
| API CALL | web/ops/src/app/features/day/day-screen.ts:510 | return (count > 1 ? forkJoin(Array.from({length: count - 1}, (_, n) => this.crud.list(name, {limit: 100, page: n + 2}))) : of([])) |
| API CALL | web/ops/src/app/features/day/day-screen.ts:543 | this.api.list('invoices', query).pipe(switchMap(first => { |
| API CALL | web/ops/src/app/features/day/day-screen.ts:545 | return (count > 1 ? forkJoin(Array.from({length: count - 1}, (_, n) => this.api.list('invoices', {...query, page: n + 2}))) : of([])) |
| API CALL | web/ops/src/app/features/day/day-screen.ts:573 | this.api.list('appointments',query).pipe(switchMap(first=>{ |
| API CALL | web/ops/src/app/features/day/day-screen.ts:575 | return (count>1?forkJoin(Array.from({length:count-1},(_,n)=>this.api.list('appointments',{...query,page:n+2}))):of([])).pipe(map(rest=>[first,...rest].flatMap(p=>p.rows))); |
| API CALL | web/ops/src/app/features/day/day-screen.ts:589 | this.api.list('invoices', {status, from: from  /  /  undefined, to: to  /  /  undefined, limit: 1}) |
| API CALL | web/ops/src/app/features/day/day-screen.ts:633 | return this.api.list('appointments', query).pipe(switchMap(first => { |
| API CALL | web/ops/src/app/features/day/day-screen.ts:636 | this.api.list('appointments', {...query, page: n + 2}))) : of([])).pipe( |
| API CALL | web/ops/src/app/features/day/day-screen.ts:677 | this.api.list(this.spec.resource, query) |
| API CALL | web/ops/src/app/features/day/day-screen.ts:681 | return (pages > 1 ? forkJoin(Array.from({length: pages - 1}, (_, n) => this.api.list(this.spec.resource, {...query, page: n + 2}))) : of([])) |
| API CALL | web/ops/src/app/features/day/day-screen.ts:1089 | switchMap((id) => this.api.serviceTherapists(id).pipe( |
| API CALL | web/ops/src/app/features/day/day-screen.ts:1286 | switchMap((q) => this.api.slots(q.therapistId, q.serviceId, q.date, undefined, q.mode).pipe( |
| API CALL | web/ops/src/app/features/day/day-screen.ts:1387 | this.crud.list(name, { limit: 200 }) |
| ACTION | web/ops/src/app/features/drawer/appointment-panel.html:6 | <button class="hbh-btn" type="button" |
| ACTION | web/ops/src/app/features/drawer/appointment-panel.html:8 | (click)="act.emit(offer.step)"> |
| MODAL | web/ops/src/app/features/drawer/appointment-panel.ts:9 | import { ActionDialogService } from '../../core/ops/action-dialog.service'; |
| MODAL | web/ops/src/app/features/drawer/appointment-panel.ts:33 | * action, opened by the host through ActionDialogService. |
| MODAL | web/ops/src/app/features/drawer/appointment-panel.ts:56 | private readonly dialogs = inject(ActionDialogService); |
| ACTION | web/ops/src/app/features/drawer/invoice-panel.html:4 | <button class="hbh-btn" type="button" |
| ACTION | web/ops/src/app/features/drawer/invoice-panel.html:6 | (click)="act.emit(offer.step)"> |
| MODAL | web/ops/src/app/features/drawer/invoice-panel.ts:9 | import { ActionDialogService } from '../../core/ops/action-dialog.service'; |
| MODAL | web/ops/src/app/features/drawer/invoice-panel.ts:48 | private readonly dialogs = inject(ActionDialogService); |
| MODAL | web/ops/src/app/features/drawer/record-drawer-host.html:2 | <!-- A real <dialog>: focus is contained, Escape closes it, the page |
| MODAL | web/ops/src/app/features/drawer/record-drawer-host.html:6 | <dialog class="hbh-drawer" hbhModal (dismissed)="close()" aria-labelledby="rdTitle"> |
| ACTION | web/ops/src/app/features/drawer/record-drawer-host.html:18 | <button class="hbh-iconbtn" type="button" [attr.aria-label]="'action.close'  /  t" (click)="close()"> |
| ACTION | web/ops/src/app/features/drawer/record-drawer-host.html:60 | <button class="hbh-btn hbh-btn--ghost" type="button" (click)="close()"> |
| MODAL | web/ops/src/app/features/drawer/record-drawer-host.ts:18 | import { ActionDialogService } from '../../core/ops/action-dialog.service'; |
| MODAL | web/ops/src/app/features/drawer/record-drawer-host.ts:41 | * an invoice - as a `<dialog>` at the side of the page. The page behind |
| MODAL | web/ops/src/app/features/drawer/record-drawer-host.ts:55 | * actions; this host asks ActionDialogService to open it, exactly as the |
| MODAL | web/ops/src/app/features/drawer/record-drawer-host.ts:68 | private readonly dialogs = inject(ActionDialogService); |
| API CALL | web/ops/src/app/features/drawer/record-drawer-host.ts:221 | return this.day.get('invoices', id).pipe(switchMap((detail) => { |
| API CALL | web/ops/src/app/features/drawer/record-drawer-host.ts:231 | return this.day.list('invoices', { status: readText(detail, 'status')  /  /  undefined, limit: 100 }).pipe( |
| API CALL | web/ops/src/app/features/drawer/record-drawer-host.ts:259 | return this.day.list('appointments', { |
| ACTION | web/ops/src/app/features/enrolment/enrolment-detail.html:5 | <p class="enr__center"><button class="hbh-btn hbh-btn--ghost" type="button" (click)="back()">{{ 'enrolment.backToList'  /  t }}</button></p> |
| ACTION | web/ops/src/app/features/enrolment/enrolment-detail.html:8 | <p class="enr__center"><button class="hbh-btn hbh-btn--ghost" type="button" (click)="back()">{{ 'enrolment.backToList'  /  t }}</button></p> |
| ACTION | web/ops/src/app/features/enrolment/enrolment-detail.html:16 | <button class="hbh-btn hbh-btn--ghost hbh-btn--sm" type="button" (click)="back()"> |
| ACTION | web/ops/src/app/features/enrolment/enrolment-detail.html:56 | <button class="hbh-btn hbh-btn--primary" type="button" (click)="act()">{{ step.ctaKey  /  t }}</button> |
| ACTION | web/ops/src/app/features/enrolment/enrolment-detail.html:61 | <button class="hbh-btn hbh-btn--ghost" type="button" (click)="changeStatus()"> |
| ACTION | web/ops/src/app/features/enrolment/enrolment-detail.html:66 | <button class="hbh-btn hbh-btn--ghost" type="button" (click)="convert()"> |
| ACTION | web/ops/src/app/features/enrolment/enrolment-detail.html:99 | <button class="hbh-btn hbh-btn--primary" type="button" (click)="act()">{{ step.ctaKey  /  t }}</button> |
| TAB | web/ops/src/app/features/enrolment/enrolment-detail.html:110 | <div class="hbh-tabbar enr__tabs" role="tablist"> |
| ACTION | web/ops/src/app/features/enrolment/enrolment-detail.html:112 | <button class="hbh-tabbar__item" type="button" role="tab" |
| ACTION | web/ops/src/app/features/enrolment/enrolment-detail.html:114 | (click)="selectTab(item)"> |
| MODAL | web/ops/src/app/features/enrolment/enrolment-detail.ts:19 | import { ActionDialogService } from '../../core/ops/action-dialog.service'; |
| TAB | web/ops/src/app/features/enrolment/enrolment-detail.ts:27 | type Tab = 'overview'  /  'beneficiary'  /  'family'  /  'appointments'  /  'assessment' |
| TAB | web/ops/src/app/features/enrolment/enrolment-detail.ts:30 | const TABS: readonly Tab[] = [ |
| MODAL | web/ops/src/app/features/enrolment/enrolment-detail.ts:39 | * the same actions from ENROLMENTS_SPEC, drawn through ActionDialogService |
| MODAL | web/ops/src/app/features/enrolment/enrolment-detail.ts:61 | private readonly dialogs = inject(ActionDialogService); |
| TAB | web/ops/src/app/features/enrolment/enrolment-detail.ts:74 | protected readonly tabs = TABS; |
| API CALL | web/ops/src/app/features/enrolment/enrolment-detail.ts:146 | this.day.get('enrolments', this.id) |
| ACTION | web/ops/src/app/features/guardian/guardian-detail.html:5 | <p class="gd__center"><button class="hbh-btn hbh-btn--ghost" type="button" (click)="back()">{{ 'guardian.backToList'  /  t }}</button></p> |
| ACTION | web/ops/src/app/features/guardian/guardian-detail.html:8 | <p class="gd__center"><button class="hbh-btn hbh-btn--ghost" type="button" (click)="back()">{{ 'guardian.backToList'  /  t }}</button></p> |
| ACTION | web/ops/src/app/features/guardian/guardian-detail.html:15 | <button class="hbh-btn hbh-btn--ghost hbh-btn--sm" type="button" (click)="back()"> |
| ACTION | web/ops/src/app/features/guardian/guardian-detail.html:43 | @if (canEdit()) { <button class="hbh-btn hbh-btn--ghost" type="button" (click)="edit()"><hbh-icon name="ic-edit" /> {{ 'guardian.edit'  /  t }}</button> } |
| TAB | web/ops/src/app/features/guardian/guardian-detail.html:57 | <div class="hbh-tabbar gd__tabs" role="tablist"> |
| ACTION | web/ops/src/app/features/guardian/guardian-detail.html:60 | <button class="hbh-tabbar__item" type="button" role="tab" |
| ACTION | web/ops/src/app/features/guardian/guardian-detail.html:61 | [class.is-active]="tab() === item" [attr.aria-selected]="tab() === item" (click)="selectTab(item)"> |
| ACTION | web/ops/src/app/features/guardian/guardian-detail.html:107 | <button class="hbh-btn hbh-btn--ghost hbh-btn--sm" type="button" (click)="loadAppointments()">{{ 'guardian.loadAppointments'  /  t }}</button> |
| ACTION | web/ops/src/app/features/guardian/guardian-detail.html:120 | @else { <button class="hbh-btn hbh-btn--ghost hbh-btn--sm" type="button" (click)="loadBalances()">{{ 'guardian.loadFinance'  /  t }}</button> } |
| ACTION | web/ops/src/app/features/guardian/guardian-detail.html:188 | <td><button class="hbh-btn hbh-btn--ghost hbh-btn--sm" type="button" (click)="openAppointment(item)"><hbh-icon name="ic-eye" /> {{ 'action.open'  /  t }}</button></td> |
| ACTION | web/ops/src/app/features/guardian/guardian-detail.html:232 | <td><button class="hbh-btn hbh-btn--ghost hbh-btn--sm" type="button" (click)="openInvoice(item)"><hbh-icon name="ic-eye" /> {{ 'action.open'  /  t }}</button></td> |
| MODAL | web/ops/src/app/features/guardian/guardian-detail.ts:19 | import { ActionDialogService } from '../../core/ops/action-dialog.service'; |
| TAB | web/ops/src/app/features/guardian/guardian-detail.ts:29 | type Tab = 'overview'  /  'beneficiaries'  /  'applications'  /  'appointments'  /  'finance'  /  'communication'  /  'activity'; |
| MODAL | web/ops/src/app/features/guardian/guardian-detail.ts:43 | * by ActionDialogService. Nothing is written from this file. |
| MODAL | web/ops/src/app/features/guardian/guardian-detail.ts:58 | private readonly dialogs = inject(ActionDialogService); |
| TAB | web/ops/src/app/features/guardian/guardian-detail.ts:71 | protected readonly tabs: readonly Tab[] = [ |
| API CALL | web/ops/src/app/features/guardian/guardian-detail.ts:171 | this.crud.get('guardians', this.id) |
| API CALL | web/ops/src/app/features/guardian/guardian-detail.ts:190 | children: this.crud.list('children', { guardian_id: this.id, limit: 100 }) |
| API CALL | web/ops/src/app/features/guardian/guardian-detail.ts:193 | ? this.day.list('enrolments', { limit: 100 }) |
| API CALL | web/ops/src/app/features/guardian/guardian-detail.ts:197 | ? this.day.list('requests', { limit: 100 }) |
| ACTION | web/ops/src/app/features/inbox/inbox.html:10 | <button class="hbh-btn hbh-btn--ghost" type="button" |
| ACTION | web/ops/src/app/features/inbox/inbox.html:11 | [attr.aria-pressed]="unreadOnly()" (click)="toggleUnread()"> |
| ACTION | web/ops/src/app/features/inbox/inbox.html:17 | <button class="hbh-btn hbh-btn--ghost" type="button" |
| ACTION | web/ops/src/app/features/inbox/inbox.html:18 | [disabled]="loading()" (click)="load()"> |
| ACTION | web/ops/src/app/features/inbox/inbox.html:45 | <button class="inbox__row" type="button" (click)="open(item)"> |
| ACTION | web/ops/src/app/features/inbox/inbox.html:63 | <button class="hbh-btn hbh-btn--ghost" type="button" (click)="markRead(item)"> |
| API CALL | web/ops/src/app/features/inbox/inbox.ts:75 | this.api.list(50) |
| API CALL | web/ops/src/app/features/inbox/inbox.ts:133 | this.api.markRead(item.id) |
| ACTION | web/ops/src/app/features/live/live-view.html:3 | <button class="hbh-iconbtn" type="button" |
| ACTION | web/ops/src/app/features/live/live-view.html:4 | [attr.aria-label]="'action.back'  /  t" (click)="back()"> |
| FORM | web/ops/src/app/features/live/live-view.html:42 | <form class="hbh-live__mark" (submit)="mark($event)"> |
| ACTION | web/ops/src/app/features/live/live-view.html:49 | <button class="hbh-btn hbh-btn--primary hbh-btn--block" type="submit" |
| API CALL | web/ops/src/app/features/live/live-view.ts:83 | this.api.close().subscribe({ next: () => undefined, error: () => undefined }); |
| API CALL | web/ops/src/app/features/live/live-view.ts:89 | this.api.open(this.sessionId) |
| FORM | web/ops/src/app/features/login/login.html:9 | <form class="hbh-signin__box" (submit)="submit($event)"> |
| ACTION | web/ops/src/app/features/login/login.html:43 | <button class="hbh-signin__peek" type="button" |
| ACTION | web/ops/src/app/features/login/login.html:46 | (click)="togglePeek()"> |
| ACTION | web/ops/src/app/features/login/login.html:60 | <button class="hbh-btn hbh-btn--primary hbh-btn--block" type="submit" |
| ACTION | web/ops/src/app/features/login/login.html:79 | <button class="hbh-signin__demoBtn" type="button" |
| ACTION | web/ops/src/app/features/login/login.html:84 | (click)="useDevAccount(account)"> |
| ACTION | web/ops/src/app/features/login/login.html:107 | <button class="hbh-link hbh-acc__docLink" type="button" |
| ACTION | web/ops/src/app/features/login/login.html:108 | (click)="toggleSetup()"> |
| ACTION | web/ops/src/app/features/login/login.html:134 | <button class="hbh-btn hbh-btn--primary" type="button" |
| ACTION | web/ops/src/app/features/login/login.html:135 | [disabled]="setupBusy()" (click)="redeemSetup()"> |
| FORM | web/ops/src/app/features/login/login.ts:46 | protected readonly setupCode = new FormControl('', { nonNullable: true }); |
| FORM | web/ops/src/app/features/login/login.ts:47 | protected readonly setupPassword = new FormControl('', { nonNullable: true }); |
| API CALL | web/ops/src/app/features/login/login.ts:71 | this.http.post(`${this.config.apiBaseUrl}/api/v1/auth/password-setup`, |
| FORM | web/ops/src/app/features/login/login.ts:92 | protected readonly username = new FormControl('', { |
| FORM | web/ops/src/app/features/login/login.ts:95 | protected readonly password = new FormControl('', { |
| ACTION | web/ops/src/app/features/ops-log/ops-log.html:9 | <button class="hbh-btn hbh-btn--ghost" type="button" (click)="load()"> |
| TAB | web/ops/src/app/features/ops-log/ops-log.html:16 | <div class="hbh-tabbar" role="tablist"> |
| ACTION | web/ops/src/app/features/ops-log/ops-log.html:18 | <button class="hbh-tabbar__item" type="button" role="tab" |
| ACTION | web/ops/src/app/features/ops-log/ops-log.html:21 | (click)="select(i)"> |
| API CALL | web/ops/src/app/features/ops-log/ops-log.ts:141 | this.http.get<Record<string, unknown>>(`${this.base}/${this.view().key}`) |
| ACTION | web/ops/src/app/features/report-editor/report-editor.html:3 | <button type="button" class="hbh-btn hbh-btn--ghost" (click)="back()"> |
| ACTION | web/ops/src/app/features/report-editor/report-editor.html:21 | <button type="button" class="hbh-btn hbh-btn--ghost" (click)="togglePreview()"> |
| ACTION | web/ops/src/app/features/report-editor/report-editor.html:25 | <button type="button" class="hbh-btn" [disabled]="saving()  /  /  changed()" (click)="save()"> |
| ACTION | web/ops/src/app/features/report-editor/report-editor.html:29 | <button type="button" class="hbh-btn hbh-btn--primary" |
| ACTION | web/ops/src/app/features/report-editor/report-editor.html:30 | [disabled]="publishing()  /  /  dirty()" (click)="publish()"> |
| ACTION | web/ops/src/app/features/report-editor/report-editor.html:50 | <button type="button" class="hbh-btn report-error__act" (click)="loadLatest()"> |
| FORM | web/ops/src/app/features/report-editor/report-editor.html:90 | <form class="report-form" (ngSubmit)="save()"> |
| FORM | web/ops/src/app/features/report-editor/report-editor.ts:84 | protected readonly title = new FormControl('', { nonNullable: true }); |
| FORM | web/ops/src/app/features/report-editor/report-editor.ts:85 | protected readonly summary = new FormControl('', { nonNullable: true }); |
| FORM | web/ops/src/app/features/report-editor/report-editor.ts:86 | protected readonly from = new FormControl('', { nonNullable: true }); |
| FORM | web/ops/src/app/features/report-editor/report-editor.ts:87 | protected readonly to = new FormControl('', { nonNullable: true }); |
| API CALL | web/ops/src/app/features/report-editor/report-editor.ts:188 | this.api.child(this.childId).pipe(takeUntilDestroyed(this.destroyRef)).subscribe({ |
| API CALL | web/ops/src/app/features/report-editor/report-editor.ts:207 | this.api.report(id).pipe(takeUntilDestroyed(this.destroyRef)).subscribe({ |
| API CALL | web/ops/src/app/features/report-editor/report-editor.ts:262 | this.api.updateReport(id, { |
| API CALL | web/ops/src/app/features/report-editor/report-editor.ts:274 | this.api.createReport({ |
| API CALL | web/ops/src/app/features/report-editor/report-editor.ts:300 | this.api.publishReport(id).pipe(takeUntilDestroyed(this.destroyRef)).subscribe({ |
| TAB | web/ops/src/app/features/resource/resource-screen.html:8 | <div class="hbh-tabbar" role="tablist"> |
| ACTION | web/ops/src/app/features/resource/resource-screen.html:10 | <button class="hbh-tabbar__item" type="button" role="tab" |
| ACTION | web/ops/src/app/features/resource/resource-screen.html:13 | (click)="selectTab(i)"> |
| ACTION | web/ops/src/app/features/resource/resource-screen.html:21 | <div class="family-top"><div class="family-title"><h1><hbh-icon name="ic-users" /> أولياء الأمور</h1><p>إدارة بيانات أولياء الأمور والبحث عنهم واختيار أحدهم لعرض التفاصيل</p><button type="button" class="hbh-btn hbh-btn--primary" (click)="startCreate()" [disabled]="!canWrite()"><hbh-icon name="ic-plus" /> إضافة ولي أمر جديد</button></div> |
| ACTION | web/ops/src/app/features/resource/resource-screen.html:22 | <div class="family-tools"><div class="hbh-filters"><div class="hbh-field hbh-field--grow"><hbh-icon name="ic-search" /><input type="search" [attr.aria-label]="'search.guardians'  /  t" [attr.placeholder]="'search.guardians'  /  t" [formControl]="search" (keyup.enter)="searchNow()"></div><button type="button" class="hbh-btn hbh-btn--ghost" (click)="search.setValue(''); searchNow()">مسح <hbh-icon name="ic-refresh" /></button><button type="button" class="hbh-btn hbh-btn--ghost" (click)="searchNow()">بح |
| ACTION | web/ops/src/app/features/resource/resource-screen.html:23 | <div class="family-filterline"><label><hbh-icon name="ic-filter" /><select aria-label="السجلات المعروضة" [value]="showArchived() ? 'all' : 'active'" (change)="toggleArchived()"><option value="active">السجلات النشطة</option><option value="all">تضمين المؤرشف</option></select></label><button class="hbh-btn hbh-btn--ghost" type="button" (click)="selectTab(1)"><hbh-icon name="ic-users" /> عرض كل الأطفال</button></div></div></div> |
| ACTION | web/ops/src/app/features/resource/resource-screen.html:34 | <button class="hbh-btn hbh-btn--ghost" type="button" (click)="load()" [disabled]="loading()">تحديث</button> |
| ACTION | web/ops/src/app/features/resource/resource-screen.html:35 | <button class="hbh-btn hbh-btn--ghost" type="button" (click)="roomCards.set(!roomCards())">عرض الكروت / الجدول</button> |
| ACTION | web/ops/src/app/features/resource/resource-screen.html:38 | <button class="hbh-btn hbh-btn--ghost" type="button" (click)="toggleArchived()" |
| ACTION | web/ops/src/app/features/resource/resource-screen.html:47 | <button class="hbh-btn hbh-btn--primary" type="button" (click)="startCreate()"> |
| TAB | web/ops/src/app/features/resource/resource-screen.html:60 | <div class="hbh-tabbar" role="tablist"> |
| ACTION | web/ops/src/app/features/resource/resource-screen.html:62 | <button class="hbh-tabbar__item" type="button" role="tab" |
| ACTION | web/ops/src/app/features/resource/resource-screen.html:65 | (click)="selectTab(i)"> |
| ACTION | web/ops/src/app/features/resource/resource-screen.html:83 | <button class="hbh-btn hbh-btn--ghost" type="button" (click)="searchNow()"> |
| ACTION | web/ops/src/app/features/resource/resource-screen.html:103 | <button type="button" class="hbh-btn hbh-btn--ghost" |
| ACTION | web/ops/src/app/features/resource/resource-screen.html:104 | (click)="search.setValue(''); searchNow()"> |
| ACTION | web/ops/src/app/features/resource/resource-screen.html:126 | @if (canWrite() && !isArchived(row)) {<button class="hbh-btn hbh-btn--ghost" type="button" (click)="startEdit(row)"><hbh-icon name="ic-edit" /> تعديل البيانات</button>} |
| ACTION | web/ops/src/app/features/resource/resource-screen.html:132 | @for (row of rows(); track row['guardian_id']; let i=$index) {<tr [class.family-selected]="selectedGuardian()?.['guardian_id'] === row['guardian_id']"><td>{{ (page()-1)*limit()+i+1 }}</td><td><a class="family-name" [routerLink]="['/guardians', row['guardian_id']]">{{ cell(row,'full_name_ar') }}</a></td><td dir="ltr">{{ cell(row,'national_id')  /  /  '—' }}</td><td dir="ltr">{{ cell(row,'mobile')  /  /  '—' }}</td><td>{{ cell(row,'email')  /  /  '—' }}</td><td>{{ cell(row,'relationship')  /  /  '—' }}</td><td>{{ |
| ACTION | web/ops/src/app/features/resource/resource-screen.html:154 | <button type="button" class="hbh-btn hbh-btn--ghost" (click)="openGuardian(row)">{{ display(row, field) }} <hbh-icon name="ic-chevron" /></button> |
| ACTION | web/ops/src/app/features/resource/resource-screen.html:174 | <button class="hbh-iconbtn" type="button" |
| ACTION | web/ops/src/app/features/resource/resource-screen.html:175 | [attr.aria-label]="'action.edit'  /  t" (click)="startEdit(row)"> |
| ACTION | web/ops/src/app/features/resource/resource-screen.html:187 | <button class="hbh-iconbtn" type="button" |
| ACTION | web/ops/src/app/features/resource/resource-screen.html:188 | [attr.aria-label]="'action.restore'  /  t" (click)="restore(row)"> |
| ACTION | web/ops/src/app/features/resource/resource-screen.html:193 | <button class="hbh-iconbtn" type="button" |
| ACTION | web/ops/src/app/features/resource/resource-screen.html:194 | [attr.aria-label]="'action.archive'  /  t" (click)="archive(row)"> |
| ACTION | web/ops/src/app/features/resource/resource-screen.html:219 | <button class="hbh-btn hbh-btn--ghost" type="button" |
| ACTION | web/ops/src/app/features/resource/resource-screen.html:220 | [disabled]="page() <= 1" (click)="goToPage(page() - 1)"> |
| ACTION | web/ops/src/app/features/resource/resource-screen.html:228 | <button class="hbh-btn hbh-btn--ghost" type="button" |
| ACTION | web/ops/src/app/features/resource/resource-screen.html:229 | [disabled]="page() >= pageCount()" (click)="goToPage(page() + 1)"> |
| ACTION | web/ops/src/app/features/resource/resource-screen.html:243 | <button type="button" class="hbh-btn hbh-btn--ghost" (click)="loadFamily(1)">بحث</button> |
| ACTION | web/ops/src/app/features/resource/resource-screen.html:255 | <button class="hbh-btn hbh-btn--ghost" type="button" [disabled]="familyPage() <= 1" (click)="loadFamily(familyPage()-1)">السابق</button> |
| ACTION | web/ops/src/app/features/resource/resource-screen.html:257 | <button class="hbh-btn hbh-btn--ghost" type="button" [disabled]="familyPage()*familyLimit() >= familyTotal()" (click)="loadFamily(familyPage()+1)">التالي</button> |
| MODAL | web/ops/src/app/features/resource/resource-screen.html:270 | <dialog class="hbh-sheet" hbhModal (dismissed)="cancel()" aria-labelledby="editorTitle"> |
| FORM | web/ops/src/app/features/resource/resource-screen.html:271 | <form class="hbh-sheet__box hbh-sheet__box--editor" (submit)="save($event)"> |
| ACTION | web/ops/src/app/features/resource/resource-screen.html:276 | <button class="hbh-iconbtn" type="button" |
| ACTION | web/ops/src/app/features/resource/resource-screen.html:277 | [attr.aria-label]="'action.cancel'  /  t" (click)="cancel()"> |
| ACTION | web/ops/src/app/features/resource/resource-screen.html:364 | <button class="hbh-btn hbh-btn--primary" type="submit" |
| ACTION | web/ops/src/app/features/resource/resource-screen.html:368 | <button class="hbh-btn hbh-btn--ghost" type="button" |
| ACTION | web/ops/src/app/features/resource/resource-screen.html:369 | [disabled]="saving()" (click)="cancel()"> |
| TAB | web/ops/src/app/features/resource/resource-screen.ts:28 | /** A tab drawn by a component of its own, declared in the route's `extraTabs`. */ |
| TAB | web/ops/src/app/features/resource/resource-screen.ts:119 | protected readonly extraTabs: readonly ExtraTab[] = |
| TAB | web/ops/src/app/features/resource/resource-screen.ts:120 | (this.route.snapshot.data['extraTabs'] as ExtraTab[]  /  undefined) ?? []; |
| TAB | web/ops/src/app/features/resource/resource-screen.ts:123 | protected readonly tabs: readonly TabRef[] = [ |
| TAB | web/ops/src/app/features/resource/resource-screen.ts:125 | ...this.extraTabs.map((e) => ({ key: e.key, titleKey: e.titleKey, permission: e.permission })), |
| FORM | web/ops/src/app/features/resource/resource-screen.ts:136 | protected readonly familySearch = new FormControl('', { nonNullable: true }); |
| API CALL | web/ops/src/app/features/resource/resource-screen.ts:150 | this.familyRequest = this.api.list('children', { |
| TAB | web/ops/src/app/features/resource/resource-screen.ts:206 | () => this.extraTabs[this.tabIndex() - this.specs.length] ?? null); |
| API CALL | web/ops/src/app/features/resource/resource-screen.ts:233 | this.api.list(ref.resource, { limit: 200 }) |
| FORM | web/ops/src/app/features/resource/resource-screen.ts:260 | protected readonly search = new FormControl('', { nonNullable: true }); |
| MODAL | web/ops/src/app/features/resource/resource-screen.ts:322 | * elsewhere (ActionDialogHost, through ActionDialogService.openResource): |
| API CALL | web/ops/src/app/features/resource/resource-screen.ts:394 | this.api.list(this.spec().resource, { |
| API CALL | web/ops/src/app/features/resource/resource-screen.ts:410 | this.api.list('children', {guardian_id: Number(guardian['guardian_id'])}).pipe(takeUntilDestroyed(this.destroyRef)).subscribe({next: children => this.guardianCounts.update(counts => ({...counts, [String(guardian['guardian_id'])]: children.total})), error: () => {}}); |
| API CALL | web/ops/src/app/features/resource/resource-screen.ts:630 | ? this.api.create(this.spec().resource, body) |
| API CALL | web/ops/src/app/features/resource/resource-screen.ts:631 | : this.api.update(this.spec().resource, id, body); |
| API CALL | web/ops/src/app/features/resource/resource-screen.ts:657 | this.write(this.api.archive(this.spec().resource, this.idOf(row)), 'crud.archived'); |
| API CALL | web/ops/src/app/features/resource/resource-screen.ts:661 | this.write(this.api.restore(this.spec().resource, this.idOf(row)), 'crud.restored'); |
| FORM | web/ops/src/app/features/resource/resource-screen.ts:709 | controls[field.name] = new FormControl(initial, { nonNullable: true }); |
| ACTION | web/ops/src/app/features/satisfaction/satisfaction.html:9 | <button class="hbh-btn hbh-btn--ghost" type="button" (click)="load()"> |
| ACTION | web/ops/src/app/features/settings/settings.html:45 | <button class="hbh-rowbtn" type="button" |
| ACTION | web/ops/src/app/features/settings/settings.html:46 | [attr.aria-label]="'action.edit'  /  t" (click)="startEditCentre(row)"> |
| MODAL | web/ops/src/app/features/settings/settings.html:64 | <dialog class="hbh-sheet" hbhModal (dismissed)="cancelCentre()" aria-labelledby="centreTitle"> |
| FORM | web/ops/src/app/features/settings/settings.html:65 | <form class="hbh-sheet__box" (submit)="saveCentre($event)"> |
| ACTION | web/ops/src/app/features/settings/settings.html:68 | <button class="hbh-iconbtn" type="button" |
| ACTION | web/ops/src/app/features/settings/settings.html:69 | [attr.aria-label]="'action.cancel'  /  t" (click)="cancelCentre()"> |
| ACTION | web/ops/src/app/features/settings/settings.html:141 | <button class="hbh-btn hbh-btn--primary" type="submit" [disabled]="saving()"> |
| ACTION | web/ops/src/app/features/settings/settings.html:144 | <button class="hbh-btn hbh-btn--ghost" type="button" |
| ACTION | web/ops/src/app/features/settings/settings.html:145 | [disabled]="saving()" (click)="cancelCentre()"> |
| ACTION | web/ops/src/app/features/settings/settings.html:202 | <button class="hbh-rowbtn" type="button" |
| ACTION | web/ops/src/app/features/settings/settings.html:203 | [attr.aria-label]="'action.edit'  /  t" (click)="startEdit(p)"> |
| ACTION | web/ops/src/app/features/settings/settings.html:210 | <button class="hbh-rowbtn" type="button" |
| ACTION | web/ops/src/app/features/settings/settings.html:214 | (click)="clear(p)"> |
| MODAL | web/ops/src/app/features/settings/settings.html:238 | <dialog class="hbh-sheet" hbhModal (dismissed)="cancel()" aria-labelledby="paramTitle"> |
| FORM | web/ops/src/app/features/settings/settings.html:239 | <form class="hbh-sheet__box" (submit)="save($event)"> |
| ACTION | web/ops/src/app/features/settings/settings.html:242 | <button class="hbh-iconbtn" type="button" |
| ACTION | web/ops/src/app/features/settings/settings.html:243 | [attr.aria-label]="'action.cancel'  /  t" (click)="cancel()"> |
| ACTION | web/ops/src/app/features/settings/settings.html:270 | <button class="hbh-btn hbh-btn--primary" type="submit" [disabled]="saving()"> |
| ACTION | web/ops/src/app/features/settings/settings.html:273 | <button class="hbh-btn hbh-btn--ghost" type="button" |
| ACTION | web/ops/src/app/features/settings/settings.html:274 | [disabled]="saving()" (click)="cancel()"> |
| API CALL | web/ops/src/app/features/settings/settings.ts:163 | this.http.get<{ params?: readonly CenterParam[] }>(this.base) |
| API CALL | web/ops/src/app/features/settings/settings.ts:207 | this.http.patch<{ code: string; value: string }>( |
| API CALL | web/ops/src/app/features/settings/settings.ts:244 | this.http.delete<{ code: string; value: string }>( |
| API CALL | web/ops/src/app/features/settings/settings.ts:291 | this.http.get<{ zones?: readonly TimeZone[] }>(`${this.settingsBase}/time-zones`) |
| API CALL | web/ops/src/app/features/settings/settings.ts:368 | this.http.patch(`${this.centreBase}`, body) |
| ACTION | web/ops/src/app/features/tasks/task-card.ts:77 | <button class="hbh-btn hbh-btn--primary hbh-btn--sm" type="button" (click)="openDrawer(target)"> |
| ACTION | web/ops/src/app/features/tasks/task-card.ts:88 | <button class="hbh-btn hbh-btn--ghost hbh-btn--sm" type="button" (click)="openDrawer(target)"> |
| ACTION | web/ops/src/app/features/tasks/tasks.html:13 | <button class="hbh-btn hbh-btn--ghost" type="button" [disabled]="svc.loading()" (click)="load()"> |
| TAB | web/ops/src/app/features/tasks/tasks.html:24 | <div class="tasks__scopes" role="tablist"> |
| ACTION | web/ops/src/app/features/tasks/tasks.html:27 | <button class="hbh-chip" type="button" role="tab" |
| ACTION | web/ops/src/app/features/tasks/tasks.html:30 | (click)="setScope(item)"> |
| ACTION | web/ops/src/app/features/tasks/tasks.html:76 | <p class="tasks__clear"><button class="hbh-btn hbh-btn--ghost" type="button" (click)="clearFilters()">{{ 'tasks.clearFilters'  /  t }}</button></p> |
| MODAL | web/ops/src/app/features/team/portrait-crop.ts:4 | <dialog class="hbh-sheet" hbhModal (dismissed)="cancel.emit()" aria-labelledby="cropTitle"> |
| ACTION | web/ops/src/app/features/team/portrait-crop.ts:5 | <div class="hbh-sheet__box"><div class="hbh-sheet__head"><h2 id="cropTitle" class="hbh-card-title">ضبط صورة العضو</h2><button type="button" class="hbh-iconbtn" aria-label="إغلاق" (click)="cancel.emit()">×</button></div> |
| ACTION | web/ops/src/app/features/team/portrait-crop.ts:11 | <p role="alert">{{error}}</p></div><div class="hbh-sheet__foot"><button type="button" class="hbh-btn hbh-btn--ghost" (click)="cancel.emit()">إلغاء</button><button type="button" class="hbh-btn hbh-btn--primary" [disabled]="!ready  /  /  saving" (click)="save()">اعتماد الصورة</button></div></div></dialog>`,styles:[` |
| ACTION | web/ops/src/app/features/team/team-screen.html:10 | <button class="hbh-btn hbh-btn--primary" type="button" (click)="startAddMember()"> |
| ACTION | web/ops/src/app/features/team/team-screen.html:15 | <button class="hbh-btn hbh-btn--ghost" type="button" (click)="load()"> |
| ACTION | web/ops/src/app/features/team/team-screen.html:35 | <button class="hbh-md__item" type="button" |
| ACTION | web/ops/src/app/features/team/team-screen.html:38 | (click)="select(member)"> |
| ACTION | web/ops/src/app/features/team/team-screen.html:68 | <button class="hbh-btn hbh-btn--ghost" type="button" (click)="cancelProfile()"> |
| ACTION | web/ops/src/app/features/team/team-screen.html:72 | <button class="hbh-btn hbh-btn--primary" type="button" |
| ACTION | web/ops/src/app/features/team/team-screen.html:73 | [disabled]="savingProfile()" (click)="saveProfile()"> |
| TAB | web/ops/src/app/features/team/team-screen.html:95 | <div class="hbh-tabbar" role="tablist"> |
| ACTION | web/ops/src/app/features/team/team-screen.html:96 | <button class="hbh-tabbar__item" type="button" role="tab" |
| ACTION | web/ops/src/app/features/team/team-screen.html:98 | [attr.aria-selected]="tab() === 'profile'" (click)="showTab('profile')"> |
| ACTION | web/ops/src/app/features/team/team-screen.html:101 | <button class="hbh-tabbar__item" type="button" role="tab" |
| ACTION | web/ops/src/app/features/team/team-screen.html:103 | [attr.aria-selected]="tab() === 'facts'" (click)="showTab('facts')"> |
| ACTION | web/ops/src/app/features/team/team-screen.html:106 | <button class="hbh-tabbar__item" type="button" role="tab" |
| ACTION | web/ops/src/app/features/team/team-screen.html:108 | [attr.aria-selected]="tab() === 'videos'" (click)="showTab('videos')"> |
| ACTION | web/ops/src/app/features/team/team-screen.html:111 | <button class="hbh-tabbar__item" type="button" role="tab" |
| ACTION | web/ops/src/app/features/team/team-screen.html:113 | [attr.aria-selected]="tab() === 'certificates'" (click)="showTab('certificates')"> |
| ACTION | web/ops/src/app/features/team/team-screen.html:116 | <button class="hbh-tabbar__item" type="button" role="tab" |
| ACTION | web/ops/src/app/features/team/team-screen.html:118 | [attr.aria-selected]="tab() === 'photos'" (click)="showTab('photos')"> |
| ACTION | web/ops/src/app/features/team/team-screen.html:149 | <button class="hbh-btn hbh-btn--ghost" type="button" (click)="removePortrait()"> |
| ACTION | web/ops/src/app/features/team/team-screen.html:193 | <button type="button" class="hbh-md__chipX" |
| ACTION | web/ops/src/app/features/team/team-screen.html:195 | (click)="removeSpecialty(item)">×</button> |
| FORM | web/ops/src/app/features/team/team-screen.html:201 | <form class="hbh-md__chipAdd" (submit)="addSpecialty($event)"> |
| ACTION | web/ops/src/app/features/team/team-screen.html:204 | <button class="hbh-btn hbh-btn--ghost" type="submit"> |
| ACTION | web/ops/src/app/features/team/team-screen.html:223 | <button class="hbh-btn hbh-btn--primary hbh-md__add" type="button" |
| ACTION | web/ops/src/app/features/team/team-screen.html:224 | (click)="showList('facts'); startAdd()"> |
| ACTION | web/ops/src/app/features/team/team-screen.html:251 | <button class="hbh-iconbtn" type="button" |
| ACTION | web/ops/src/app/features/team/team-screen.html:253 | (click)="startEditRow(fact, 'facts')"> |
| ACTION | web/ops/src/app/features/team/team-screen.html:256 | <button class="hbh-iconbtn" type="button" |
| ACTION | web/ops/src/app/features/team/team-screen.html:258 | (click)="archiveRow(fact, 'facts')"> |
| ACTION | web/ops/src/app/features/team/team-screen.html:262 | <button class="hbh-iconbtn" type="button" |
| ACTION | web/ops/src/app/features/team/team-screen.html:264 | (click)="restoreRow(fact, 'facts')"> |
| ACTION | web/ops/src/app/features/team/team-screen.html:328 | <button class="hbh-iconbtn" type="button" |
| ACTION | web/ops/src/app/features/team/team-screen.html:330 | (click)="consentMedia(item)"> |
| ACTION | web/ops/src/app/features/team/team-screen.html:334 | <button class="hbh-iconbtn" type="button" |
| ACTION | web/ops/src/app/features/team/team-screen.html:336 | (click)="removeMedia(item)"> |
| ACTION | web/ops/src/app/features/team/team-screen.html:352 | <button class="hbh-btn hbh-btn--primary hbh-md__add" type="button" |
| ACTION | web/ops/src/app/features/team/team-screen.html:353 | (click)="showList('certificates'); startAdd()"> |
| ACTION | web/ops/src/app/features/team/team-screen.html:380 | <button class="hbh-iconbtn" type="button" |
| ACTION | web/ops/src/app/features/team/team-screen.html:382 | (click)="startEditRow(cert, 'certificates')"> |
| ACTION | web/ops/src/app/features/team/team-screen.html:385 | <button class="hbh-iconbtn" type="button" |
| ACTION | web/ops/src/app/features/team/team-screen.html:387 | (click)="archiveRow(cert, 'certificates')"> |
| MODAL | web/ops/src/app/features/team/team-screen.html:408 | <dialog class="hbh-sheet" hbhModal (dismissed)="cancelAddMember()" |
| FORM | web/ops/src/app/features/team/team-screen.html:410 | <form class="hbh-sheet__box hbh-sheet__box--editor" (submit)="saveMember($event)"> |
| ACTION | web/ops/src/app/features/team/team-screen.html:413 | <button class="hbh-iconbtn" type="button" [attr.aria-label]="'action.cancel'  /  t" |
| ACTION | web/ops/src/app/features/team/team-screen.html:414 | (click)="cancelAddMember()"> |
| ACTION | web/ops/src/app/features/team/team-screen.html:439 | <button class="hbh-btn hbh-btn--ghost" type="button" (click)="cancelAddMember()"> |
| ACTION | web/ops/src/app/features/team/team-screen.html:442 | <button class="hbh-btn hbh-btn--primary" type="submit" [disabled]="saving()"> |
| MODAL | web/ops/src/app/features/team/team-screen.html:454 | <dialog class="hbh-sheet" hbhModal (dismissed)="cancelEdit()" |
| FORM | web/ops/src/app/features/team/team-screen.html:456 | <form class="hbh-sheet__box hbh-sheet__box--editor" (submit)="saveRow($event)"> |
| ACTION | web/ops/src/app/features/team/team-screen.html:462 | <button class="hbh-iconbtn" type="button" [attr.aria-label]="'action.cancel'  /  t" |
| ACTION | web/ops/src/app/features/team/team-screen.html:463 | (click)="cancelEdit()"> |
| ACTION | web/ops/src/app/features/team/team-screen.html:507 | <button class="hbh-btn hbh-btn--ghost" type="button" (click)="cancelEdit()"> |
| ACTION | web/ops/src/app/features/team/team-screen.html:510 | <button class="hbh-btn hbh-btn--primary" type="submit" [disabled]="saving()"> |
| TAB | web/ops/src/app/features/team/team-screen.ts:70 | type Tab = 'profile'  /  'facts'  /  'videos'  /  'certificates'  /  'photos'; |
| FORM | web/ops/src/app/features/team/team-screen.ts:184 | protected readonly specialtyInput = new FormControl('', { nonNullable: true }); |
| API CALL | web/ops/src/app/features/team/team-screen.ts:246 | members: this.api.list('site-team'), |
| API CALL | web/ops/src/app/features/team/team-screen.ts:247 | facts: this.api.list('site-team-facts'), |
| API CALL | web/ops/src/app/features/team/team-screen.ts:248 | certificates: this.api.list('site-team-certificates'), |
| API CALL | web/ops/src/app/features/team/team-screen.ts:249 | media: this.api.list('site-team-media'), |
| API CALL | web/ops/src/app/features/team/team-screen.ts:250 | specialties: this.api.list('site-team-specialties'), |
| FORM | web/ops/src/app/features/team/team-screen.ts:350 | controls[name] = new FormControl(member ? text(member, name) : '', |
| API CALL | web/ops/src/app/features/team/team-screen.ts:384 | this.api.update('site-team', idOf(member, 'member_id'), body) |
| FORM | web/ops/src/app/features/team/team-screen.ts:405 | controls[name] = new FormControl('', { nonNullable: true }); |
| API CALL | web/ops/src/app/features/team/team-screen.ts:428 | this.api.create('site-team', { name_ar: name, role_ar: role }) |
| API CALL | web/ops/src/app/features/team/team-screen.ts:454 | this.api.create('site-team-specialties', { |
| API CALL | web/ops/src/app/features/team/team-screen.ts:471 | this.api.archive('site-team-specialties', idOf(row, 'specialty_id')) |
| API CALL | web/ops/src/app/features/team/team-screen.ts:500 | this.api.upload(file).pipe(takeUntilDestroyed(this.destroyRef)).subscribe({ |
| API CALL | web/ops/src/app/features/team/team-screen.ts:502 | this.api.update('site-team', idOf(member, 'member_id'), { photo_path: result.path }) |
| API CALL | web/ops/src/app/features/team/team-screen.ts:542 | this.api.upload(file).pipe(takeUntilDestroyed(this.destroyRef)).subscribe({ |
| API CALL | web/ops/src/app/features/team/team-screen.ts:556 | this.api.create('site-team-media', body) |
| API CALL | web/ops/src/app/features/team/team-screen.ts:571 | this.api.archive('site-team-media', idOf(row, 'media_id')) |
| API CALL | web/ops/src/app/features/team/team-screen.ts:585 | this.api.update('site-team', idOf(member, 'member_id'), { photo_path: null }) |
| API CALL | web/ops/src/app/features/team/team-screen.ts:600 | this.api.update('site-team-media', idOf(row, 'media_id'), { consent_given_at: today }) |
| API CALL | web/ops/src/app/features/team/team-screen.ts:683 | ? this.api.create(resource, body) |
| API CALL | web/ops/src/app/features/team/team-screen.ts:684 | : this.api.update(resource, id, body); |
| API CALL | web/ops/src/app/features/team/team-screen.ts:706 | this.api.archive(resource, id) |
| API CALL | web/ops/src/app/features/team/team-screen.ts:719 | this.api.restore(resource, id) |
| API CALL | web/ops/src/app/features/team/team-screen.ts:736 | this.api.upload(file).pipe(takeUntilDestroyed(this.destroyRef)).subscribe({ |
| FORM | web/ops/src/app/features/team/team-screen.ts:759 | controls[field.name] = new FormControl(value, { nonNullable: true }); |
| ACTION | web/ops/src/app/features/therapist-profile/therapist-profile.html:10 | <button class="hbh-iconbtn" type="button" |
| ACTION | web/ops/src/app/features/therapist-profile/therapist-profile.html:11 | [attr.aria-label]="'action.back'  /  t" (click)="back()"> |
| ACTION | web/ops/src/app/features/therapist-profile/therapist-profile.html:42 | <button class="hbh-btn hbh-btn--ghost" type="button" |
| ACTION | web/ops/src/app/features/therapist-profile/therapist-profile.html:43 | [disabled]="saving()" (click)="withdrawConsent()"> |
| ACTION | web/ops/src/app/features/therapist-profile/therapist-profile.html:47 | <button class="hbh-btn hbh-btn--primary" type="button" |
| ACTION | web/ops/src/app/features/therapist-profile/therapist-profile.html:48 | [disabled]="saving()" (click)="giveConsent()"> |
| ACTION | web/ops/src/app/features/therapist-profile/therapist-profile.html:58 | <button class="hbh-btn hbh-btn--primary" type="button" |
| ACTION | web/ops/src/app/features/therapist-profile/therapist-profile.html:59 | [disabled]="saving()" (click)="publish()"> |
| ACTION | web/ops/src/app/features/therapist-profile/therapist-profile.html:109 | <button class="hbh-btn hbh-btn--primary" type="button" |
| ACTION | web/ops/src/app/features/therapist-profile/therapist-profile.html:110 | [class.is-busy]="saving()" [disabled]="saving()" (click)="saveProfile()"> |
| ACTION | web/ops/src/app/features/therapist-profile/therapist-profile.html:146 | <button class="hbh-iconbtn" type="button" [disabled]="saving()" |
| ACTION | web/ops/src/app/features/therapist-profile/therapist-profile.html:148 | (click)="removeLanguage(text(lang, 'lang_code'))"> |
| ACTION | web/ops/src/app/features/therapist-profile/therapist-profile.html:193 | <button class="hbh-btn hbh-btn--ghost" type="button" |
| ACTION | web/ops/src/app/features/therapist-profile/therapist-profile.html:194 | [disabled]="saving()" (click)="addLanguage()"> |
| ACTION | web/ops/src/app/features/therapist-profile/therapist-profile.html:227 | <button class="hbh-btn hbh-btn--sm" |
| ACTION | web/ops/src/app/features/therapist-profile/therapist-profile.html:231 | (click)="toggleImage(cert)"> |
| ACTION | web/ops/src/app/features/therapist-profile/therapist-profile.html:263 | <button class="hbh-btn hbh-btn--ghost" type="button" |
| ACTION | web/ops/src/app/features/therapist-profile/therapist-profile.html:264 | [disabled]="saving()" (click)="addCertificate()"> |
| API CALL | web/ops/src/app/features/therapist-profile/therapist-profile.ts:115 | person: this.crud.get('therapists', this.therapistId), |
| API CALL | web/ops/src/app/features/therapist-profile/therapist-profile.ts:116 | languages: this.api.languages(this.therapistId), |
| API CALL | web/ops/src/app/features/therapist-profile/therapist-profile.ts:117 | certificates: this.api.certificates(this.therapistId), |
| API CALL | web/ops/src/app/features/therapist-profile/therapist-profile.ts:179 | this.write(this.api.patchProfile(this.therapistId, edit), 'tprofile.saved'); |
| API CALL | web/ops/src/app/features/therapist-profile/therapist-profile.ts:188 | this.api.putLanguage( |
| API CALL | web/ops/src/app/features/therapist-profile/therapist-profile.ts:195 | this.write(this.api.removeLanguage(this.therapistId, code), 'tprofile.languageRemoved'); |
| API CALL | web/ops/src/app/features/therapist-profile/therapist-profile.ts:205 | this.api.addCertificate(this.therapistId, { |
| API CALL | web/ops/src/app/features/therapist-profile/therapist-profile.ts:231 | this.api.setImagePublic(id, next), |
| API CALL | web/ops/src/app/features/therapist-profile/therapist-profile.ts:237 | this.write(this.api.giveConsent(this.therapistId), 'tprofile.consentGiven'); |
| API CALL | web/ops/src/app/features/therapist-profile/therapist-profile.ts:241 | this.write(this.api.withdrawConsent(this.therapistId), 'tprofile.consentWithdrawn'); |
| API CALL | web/ops/src/app/features/therapist-profile/therapist-profile.ts:245 | this.write(this.api.publish(this.therapistId), 'tprofile.published'); |
| ACTION | web/ops/src/app/features/therapist-services/therapist-services.html:50 | <button class="hbh-tick" type="button" |
| ACTION | web/ops/src/app/features/therapist-services/therapist-services.html:56 | (click)="toggle(therapistId(therapist), serviceId(service))"> |
| API CALL | web/ops/src/app/features/therapist-services/therapist-services.ts:70 | this.crud.list('therapists', { limit: 200 }) |
| API CALL | web/ops/src/app/features/therapist-services/therapist-services.ts:85 | this.crud.list('services', { limit: 200 }) |
| ACTION | web/ops/src/app/layout/shell/shell.html:50 | <button class="hbh-side__out" type="button" |
| ACTION | web/ops/src/app/layout/shell/shell.html:51 | [attr.aria-label]="'action.signOut'  /  t" (click)="signOut()"> |
| ACTION | web/ops/src/app/layout/shell/shell.html:58 | <button class="hbh-side__signout" type="button" (click)="signOut()"> |
| MODAL | web/ops/src/app/layout/shell/shell.html:69 | page is drawn. Empty until ActionDialogService is asked. --> |
| API CALL | web/portal/src/app/core/api/enrolment.api.ts:58 | return this.http.post<{ application_no: string }>( |
| API CALL | web/portal/src/app/core/api/http-portal-api.ts:76 | return this.http.get<MeResponse>(`${this.base}/me`); |
| API CALL | web/portal/src/app/core/api/http-portal-api.ts:159 | child: this.http.get<ChildRow>(`${this.base}/children/${id}`), |
| API CALL | web/portal/src/app/core/api/http-portal-api.ts:346 | return this.http.post<void>( |
| API CALL | web/portal/src/app/core/api/http-portal-api.ts:488 | return this.http.get<BalanceRow>(`${this.base}/children/${id}/balance`); |
| API CALL | web/portal/src/app/core/api/http-portal-api.ts:516 | return this.http.post<RequestRow>( |
| API CALL | web/portal/src/app/core/api/http-portal-api.ts:552 | person: this.http.get<TherapistRow>(`${this.base}/therapists/${id}`), |
| API CALL | web/portal/src/app/core/api/http-portal-api.ts:705 | return this.http.get<GuardianContact>(`${this.base}/me/contact`); |
| API CALL | web/portal/src/app/core/api/http-portal-api.ts:712 | return this.http.patch<GuardianContact>(`${this.base}/me/contact`, { |
| API CALL | web/portal/src/app/core/api/http-portal-api.ts:725 | child: this.http.get<ChildRow>(`${this.base}/children/${id}`), |
| API CALL | web/portal/src/app/core/api/http-portal-api.ts:817 | return this.http.post<void>(`${this.base}/notifications/${id}/read`, {}); |
| API CALL | web/portal/src/app/core/api/nps-api.ts:34 | return this.http.get<{ survey: DueSurvey  /  null }>(`${this.base}/due`); |
| API CALL | web/portal/src/app/core/api/nps-api.ts:59 | return this.http.post<void>(`${this.base}/${surveyId}/response`, { |
| API CALL | web/portal/src/app/core/api/nps-api.ts:74 | return this.http.post<void>(`${this.base}/${surveyId}/skip`, {}); |
| API CALL | web/portal/src/app/core/auth/auth.service.ts:73 | return this.api.requestOtp(mobile).pipe( |
| API CALL | web/portal/src/app/core/auth/auth.service.ts:117 | return this.api.verifyOtp(mobile, code).pipe( |
| API CALL | web/portal/src/app/core/auth/auth.service.ts:143 | this.api.logout().subscribe({ |
| API CALL | web/portal/src/app/core/auth/http-auth-api.ts:35 | return this.http.post<OtpRequestResponse>(`${this.base}/otp/request`, { mobile }) |
| API CALL | web/portal/src/app/core/auth/http-auth-api.ts:54 | return this.http.post<OtpVerifyResponse>(`${this.base}/otp/verify`, { mobile, code }) |
| API CALL | web/portal/src/app/core/auth/http-auth-api.ts:62 | return this.http.post<void>(`${this.base}/logout`, {}); |
| ACTION | web/portal/src/app/features/activities/activities.html:81 | <button class="hbh-btn hbh-btn--primary activity-record" type="button" |
| ACTION | web/portal/src/app/features/activities/activities.html:82 | [disabled]="isSaving(activity)  /  /  activity.completedAt !== null" (click)="toggle(activity)"> |
| API CALL | web/portal/src/app/features/activities/activities.ts:83 | this.api.homeProgramme(this.childContext.requireId()) |
| API CALL | web/portal/src/app/features/activities/activities.ts:113 | this.api.setActivityDone(this.childContext.requireId(), activity.id, done) |
| ACTION | web/portal/src/app/features/apply/apply.html:2 | @if(applicationNo();as reference){<section class="success"><div class="success-icon">✓</div><h2>تم إرسال طلب الالتحاق بنجاح</h2><p>{{'apply.doneNote' / t}}</p><strong>{{reference}}</strong><p>احتفظ برقم الطلب للمتابعة مع المركز.</p><div class="success-steps"><div><b>١. مراجعة الطلب</b>مراجعة البيانات الأولية</div><div><b>٢. التواصل</b>تحديد التخصص المناسب</div><div><b>٣. حجز التقييم</b>اختيار موعد مناسب</div></div>@for(item of references();track item){<p>{{item}}</p>}<button type="button" class="b |
| FORM | web/portal/src/app/features/apply/apply.html:5 | <form (submit)="$event.preventDefault();nextStep()" novalidate> |
| ACTION | web/portal/src/app/features/apply/apply.html:23 | <div class="section"><div class="section-title"><span>كيف تعرفتم علينا؟</span><span class="sicon">⌕</span></div><div class="chips">@for(source of sources;track source){<button type="button" class="chip" [class.active]="extra()['source']===source" [attr.aria-pressed]="extra()['source']===source" (click)="setExtra('source',source)">{{source}}</button>}</div></div></section> |
| ACTION | web/portal/src/app/features/apply/apply.html:24 | <section class="panel" [class.active]="step()===1"><div class="section"><div class="section-title"><span>الحالة الصحية</span><span class="sicon">♡</span></div><div class="grid"><div class="field full"><label>هل توجد حالة صحية أو دواء منتظم يجب أن نعرف عنه؟</label><div class="choices">@for(answer of ['لا','نعم'];track answer){<button class="chip" type="button" [class.active]="extra()['health']===answer" [attr.aria-pressed]="extra()['health']===answer" (click)="setExtra('health',answer)">{{answer} |
| ACTION | web/portal/src/app/features/apply/apply.html:25 | <div class="section"><div class="section-title"><span>سبب الزيارة</span><span class="sicon">✦</span></div><div class="chips">@for(reason of reasons;track reason){<button type="button" class="chip" [class.active]="selectedReasons().includes(reason)" [attr.aria-pressed]="selectedReasons().includes(reason)" (click)="toggleReason(reason)">{{reason}}</button>}</div><div class="grid" style="margin-top:12px"><div class="field full"><label for="a-main_concern_ar">احكيلنا باختصار ما الذي تلاحظه؟ *</label |
| ACTION | web/portal/src/app/features/apply/apply.html:26 | <section class="panel" [class.active]="step()===2"><div class="section"><div class="section-title"><span>الخدمات السابقة</span><span class="sicon">↻</span></div><div class="choices">@for(answer of ['لا، هذه أول مرة','نعم'];track answer){<button class="chip" type="button" [class.active]="extra()['previous']===answer" (click)="setExtra('previous',answer)">{{answer}}</button>}</div><div class="grid" style="margin-top:12px"><div class="field full"><label for="a-previous_therapy_ar">نوع الخدمة السابق |
| ACTION | web/portal/src/app/features/apply/apply.html:27 | <div class="section"><div class="section-title"><span>أهداف الأسرة خلال ٣–٦ أشهر</span><span class="sicon">◎</span></div><div class="note">اكتب أهم هدفين أو ثلاثة، وسيقوم الفريق بتفصيل الخطة بعد التقييم.</div><div class="goals">@for(goal of goals();track $index){<div class="goal"><span>{{$index+1}}</span><input [attr.aria-label]="'الهدف '+($index+1)" maxlength="200" [value]="goal" (input)="setGoal($index,$any($event.target).value)"><button class="remove" type="button" [disabled]="goals().length= |
| ACTION | web/portal/src/app/features/apply/apply.html:29 | @if(flowError()){<p class="error" role="alert">{{flowError()}}</p>}@if(formErr()){<p class="error" role="alert">{{formErr() / t}}</p>}@if(draftNotice()){<p class="draft-note" role="status">{{draftNotice()}}</p><button class="btn soft" type="button" (click)="clearDraft()">مسح المسودة المحفوظة</button>} |
| ACTION | web/portal/src/app/features/apply/apply.html:30 | <div class="actions"><button class="btn secondary" type="button" [disabled]="busy() /  / step()===0" (click)="previousStep()">السابق</button><div class="actions-right"><button class="btn soft" type="button" [disabled]="busy()" (click)="saveDraft()">حفظ واستكمال لاحقًا</button><button class="btn primary" type="submit" [disabled]="busy()">{{busy()?'جارٍ الإرسال…':step()===3?'إرسال طلب الالتحاق':'التالي'}}</button></div></div></form>} |
| API CALL | web/portal/src/app/features/apply/apply.ts:290 | this.api.submit(body) |
| ACTION | web/portal/src/app/features/billing/billing.html:26 | <button class="hbh-btn hbh-btn--ghost" type="button" |
| ACTION | web/portal/src/app/features/billing/billing.html:27 | [disabled]="retrying() === 'balance'" (click)="retry('balance')"> |
| ACTION | web/portal/src/app/features/billing/billing.html:31 | <button class="hbh-btn hbh-btn--primary" type="button" |
| ACTION | web/portal/src/app/features/billing/billing.html:32 | (click)="askAboutPayment()"> |
| API CALL | web/portal/src/app/features/billing/billing.ts:73 | this.api.billing(new Set([section])) |
| API CALL | web/portal/src/app/features/billing/billing.ts:90 | this.api.billing() |
| ACTION | web/portal/src/app/features/consultation/consultation.html:27 | <button class="hbh-btn hbh-btn--ghost hbh-btn--block" type="button" |
| ACTION | web/portal/src/app/features/consultation/consultation.html:28 | (click)="leave()"> |
| ACTION | web/portal/src/app/features/consultation/consultation.html:66 | <button class="hbh-btn hbh-btn--ghost hbh-btn--block" type="button" |
| ACTION | web/portal/src/app/features/consultation/consultation.html:67 | (click)="enter()"> |
| ACTION | web/portal/src/app/features/consultation/consultation.html:114 | <button class="hbh-btn hbh-btn--primary hbh-btn--block" type="button" |
| ACTION | web/portal/src/app/features/consultation/consultation.html:115 | (click)="enter()"> |
| ACTION | web/portal/src/app/features/consultation/consultation.html:126 | <button class="hbh-btn hbh-btn--ghost hbh-btn--block" type="button" |
| ACTION | web/portal/src/app/features/consultation/consultation.html:127 | (click)="enter()"> |
| API CALL | web/portal/src/app/features/consultation/consultation.ts:228 | this.api.enterConsultation(appointmentId) |
| API CALL | web/portal/src/app/features/home/home.ts:81 | this.api.home(wanted) |
| ACTION | web/portal/src/app/features/live/live.html:43 | <button class="player__btn" type="button" [disabled]="!playing()" |
| ACTION | web/portal/src/app/features/live/live.html:46 | (click)="toggleMute()"> |
| ACTION | web/portal/src/app/features/live/live.html:49 | <button class="player__mark" type="button" [disabled]="!playing()" |
| ACTION | web/portal/src/app/features/live/live.html:50 | (click)="markMoment()"> |
| ACTION | web/portal/src/app/features/live/live.html:54 | <button class="player__btn" type="button" [disabled]="!playing()" |
| ACTION | web/portal/src/app/features/live/live.html:56 | (click)="toggleFullscreen(player)"> |
| API CALL | web/portal/src/app/features/live/live.ts:116 | this.api.liveSession(this.childContext.requireId()) |
| API CALL | web/portal/src/app/features/live/live.ts:140 | this.api.requestStreamTicket(session.sessionId) |
| API CALL | web/portal/src/app/features/live/live.ts:182 | this.api.markMoment(session.sessionId, this.i18n.translate('live.momentNote')) |
| FORM | web/portal/src/app/features/login/login.html:13 | <form class="hbh-signin__box" (submit)="submit($event)"> |
| ACTION | web/portal/src/app/features/login/login.html:96 | <button class="hbh-btn hbh-btn--primary hbh-btn--block" type="submit" |
| ACTION | web/portal/src/app/features/login/login.html:109 | <button class="hbh-signin__join" type="button" (click)="goToApply()"> |
| FORM | web/portal/src/app/features/login/login.ts:63 | protected readonly phone = new FormControl('', { |
| ACTION | web/portal/src/app/features/notifications/notifications.html:43 | <button class="row nrow" type="button" |
| ACTION | web/portal/src/app/features/notifications/notifications.html:45 | (click)="open(item)"> |
| API CALL | web/portal/src/app/features/notifications/notifications.ts:75 | this.api.notifications(50) |
| API CALL | web/portal/src/app/features/notifications/notifications.ts:124 | this.api.markNotificationRead(item.id) |
| ACTION | web/portal/src/app/features/nps/nps-card.ts:45 | <div class="nps-modal" (click)="skip()"> |
| MODAL | web/portal/src/app/features/nps/nps-card.ts:46 | <div #dialog class="nps" role="dialog" aria-modal="true" aria-labelledby="nps-q" |
| ACTION | web/portal/src/app/features/nps/nps-card.ts:47 | tabindex="-1" (click)="$event.stopPropagation()"> |
| ACTION | web/portal/src/app/features/nps/nps-card.ts:50 | <button class="nps__x" type="button" |
| ACTION | web/portal/src/app/features/nps/nps-card.ts:51 | [attr.aria-label]="'nps.dismiss'  /  t" (click)="skip()"> |
| ACTION | web/portal/src/app/features/nps/nps-card.ts:60 | <button class="nps__s" type="button" |
| ACTION | web/portal/src/app/features/nps/nps-card.ts:63 | (click)="answer(value)">{{ value }}</button> |
| ACTION | web/portal/src/app/features/nps/nps-card.ts:81 | <button class="hbh-btn hbh-btn--primary hbh-btn--block" type="button" |
| ACTION | web/portal/src/app/features/nps/nps-card.ts:83 | [class.is-busy]="busy()" [disabled]="busy()" (click)="send()"> |
| API CALL | web/portal/src/app/features/nps/nps-card.ts:125 | this.api.due() |
| API CALL | web/portal/src/app/features/nps/nps-card.ts:150 | this.api.respond(due.survey_id, score, this.comment(), due.context_kind, due.context_id) |
| API CALL | web/portal/src/app/features/nps/nps-card.ts:186 | this.api.skip(due.survey_id) |
| MODAL | web/portal/src/app/features/otp/otp.html:1 | <dialog #dialog class="otp-modal" aria-labelledby="otp-title" aria-describedby="otp-description" (cancel)="cancel($event)"> |
| ACTION | web/portal/src/app/features/otp/otp.html:2 | <button class="otp-close" type="button" [disabled]="busy()" [attr.aria-label]="'action.close'  /  t" (click)="restart()"><hbh-icon name="ic-x" /></button> |
| ACTION | web/portal/src/app/features/otp/otp.html:25 | <button class="hbh-btn hbh-btn--ghost hbh-btn--block" type="button" |
| ACTION | web/portal/src/app/features/otp/otp.html:26 | style="margin-top:14px" (click)="restart()"> |
| ACTION | web/portal/src/app/features/otp/otp.html:70 | <button class="otp__dev" type="button" (click)="useDevCode()"> |
| ACTION | web/portal/src/app/features/otp/otp.html:77 | <button class="hbh-link" type="button" (click)="restart()"> |
| ACTION | web/portal/src/app/features/otp/otp.html:86 | <button class="hbh-link" type="button" (click)="restart()"> |
| ACTION | web/portal/src/app/features/otp/otp.html:92 | <button class="hbh-btn hbh-btn--primary hbh-btn--block" type="button" |
| ACTION | web/portal/src/app/features/otp/otp.html:95 | (click)="submit()"> |
| ACTION | web/portal/src/app/features/profile/profile.html:104 | <button class="btn primary" type="button" |
| ACTION | web/portal/src/app/features/profile/profile.html:105 | [disabled]="savingContact()" (click)="saveContact()"> |
| ACTION | web/portal/src/app/features/profile/profile.html:108 | <button class="btn secondary" type="button" |
| ACTION | web/portal/src/app/features/profile/profile.html:109 | [disabled]="savingContact()" (click)="cancelContact()"> |
| ACTION | web/portal/src/app/features/profile/profile.html:121 | <button class="opt" type="button" (click)="openChild(child)"> |
| ACTION | web/portal/src/app/features/profile/profile.html:159 | <button class="sw" type="button" |
| ACTION | web/portal/src/app/features/profile/profile.html:166 | (click)="toggleConsent(consent)"></button> |
| ACTION | web/portal/src/app/features/profile/profile.html:184 | <button class="opt" type="button" (click)="signOut()"> |
| API CALL | web/portal/src/app/features/profile/profile.ts:106 | this.api.setContact({ |
| API CALL | web/portal/src/app/features/profile/profile.ts:149 | welcome: this.api.family(), |
| API CALL | web/portal/src/app/features/profile/profile.ts:150 | consents: this.api.consents(), |
| API CALL | web/portal/src/app/features/profile/profile.ts:155 | contact: this.api.contact().pipe( |
| API CALL | web/portal/src/app/features/profile/profile.ts:160 | centre: this.api.centreContact(), |
| API CALL | web/portal/src/app/features/profile/profile.ts:205 | this.api.setConsent(consent.key, granted) |
| API CALL | web/portal/src/app/features/progress/progress.ts:64 | this.api.progress(this.childContext.requireId()) |
| API CALL | web/portal/src/app/features/report/report.ts:66 | this.api.report(id) |
| TAB | web/portal/src/app/features/reports/reports.html:3 | <div class="seg" role="tablist"> |
| ACTION | web/portal/src/app/features/reports/reports.html:4 | <button class="seg__i" type="button" role="tab" |
| ACTION | web/portal/src/app/features/reports/reports.html:7 | (click)="select('reports')"> |
| ACTION | web/portal/src/app/features/reports/reports.html:10 | <button class="seg__i" type="button" role="tab" |
| ACTION | web/portal/src/app/features/reports/reports.html:13 | (click)="select('notes')"> |
| ACTION | web/portal/src/app/features/reports/reports.html:37 | <button class="row" type="button" (click)="open(report)"> |
| API CALL | web/portal/src/app/features/reports/reports.ts:68 | this.api.reports(this.childContext.requireId(), this.scope()) |
| ACTION | web/portal/src/app/features/requests/requests.html:7 | <button class="request-toggle" type="button" [disabled]="sending()" |
| ACTION | web/portal/src/app/features/requests/requests.html:9 | [attr.aria-controls]="'panel-' + option.kind" (click)="startDraft(option.kind)"> |
| ACTION | web/portal/src/app/features/requests/requests.html:44 | <div class="req__actions"><button class="hbh-btn hbh-btn--primary" type="button" [class.is-busy]="sending()" [disabled]="!validDraft()" (click)="submit()"><hbh-icon name="ic-send" />{{ (sending() ? 'requests.sending' : 'requests.send')  /  t }}</button><button class="hbh-btn hbh-btn--ghost" type="button" [disabled]="sending()" (click)="cancelDraft()">{{ 'action.cancel'  /  t }}</button></div> |
| FORM | web/portal/src/app/features/requests/requests.ts:71 | protected readonly note = new FormControl('', { nonNullable: true, validators: [Validators.maxLength(500)] }); |
| FORM | web/portal/src/app/features/requests/requests.ts:75 | protected readonly appointmentId = new FormControl('', { nonNullable: true }); |
| FORM | web/portal/src/app/features/requests/requests.ts:76 | protected readonly alternativeDate = new FormControl('', { nonNullable: true }); |
| FORM | web/portal/src/app/features/requests/requests.ts:77 | protected readonly alternativeTime = new FormControl('', { nonNullable: true }); |
| API CALL | web/portal/src/app/features/requests/requests.ts:100 | this.api.appointments(this.childContext.requireId(), 'upcoming') |
| API CALL | web/portal/src/app/features/requests/requests.ts:138 | this.api.requests() |
| API CALL | web/portal/src/app/features/requests/requests.ts:176 | this.api.submitRequest({ |
| TAB | web/portal/src/app/features/schedule/schedule.html:3 | <div class="seg" role="tablist"> |
| ACTION | web/portal/src/app/features/schedule/schedule.html:4 | <button class="seg__i" type="button" role="tab" |
| ACTION | web/portal/src/app/features/schedule/schedule.html:7 | (click)="select('upcoming')"> |
| ACTION | web/portal/src/app/features/schedule/schedule.html:10 | <button class="seg__i" type="button" role="tab" |
| ACTION | web/portal/src/app/features/schedule/schedule.html:13 | (click)="select('past')"> |
| API CALL | web/portal/src/app/features/schedule/schedule.ts:104 | this.api.appointments(this.childContext.requireId(), this.scope()) |
| ACTION | web/portal/src/app/features/therapist/therapist.html:11 | <button class="hbh-crumb" type="button" (click)="back()"> |
| API CALL | web/portal/src/app/features/therapist/therapist.ts:104 | this.api.therapist(id) |
| ACTION | web/portal/src/app/features/welcome/welcome.html:17 | <button class="cbar__sw" type="button" (click)="signOut()"> |
| ACTION | web/portal/src/app/features/welcome/welcome.html:53 | <button class="row" type="button" (click)="openAttention(item)"> |
| ACTION | web/portal/src/app/features/welcome/welcome.html:83 | <button class="kid" type="button" |
| ACTION | web/portal/src/app/features/welcome/welcome.html:85 | (click)="open(child)"> |
| API CALL | web/portal/src/app/features/welcome/welcome.ts:75 | this.api.welcome().pipe(takeUntilDestroyed(this.destroyRef)).subscribe({ |
| TAB | web/portal/src/app/layout/shell/shell.ts:62 | protected readonly tabs = [ |
| API CALL | web/portal/src/app/layout/shell/shell.ts:117 | this.api.profile() |
| API CALL | web/portal/src/app/layout/shell/shell.ts:155 | this.api.notifications(1) |
| ACTION | web/portal/src/app/shared/ui/appointment-row.ts:37 | (click)="openTherapist($event)" |
| ACTION | web/shared/src/ui/error-note.ts:28 | <button class="hbh-btn hbh-btn--ghost hbh-btn--block" type="button" |
| ACTION | web/shared/src/ui/error-note.ts:29 | style="margin-top:10px" (click)="retry.emit()"> |
| ACTION | web/shared/src/ui/family-messages.ts:11 | @if(contacts().some(canManage)){<button type="button" (click)="bulk.set(!bulk())" [disabled]="sending()">{{bulk()?'إغلاق الرسالة الجماعية':'رسالة جماعية'}}</button>} |
| ACTION | web/shared/src/ui/family-messages.ts:15 | <p>{{recipients().length}} مستلم</p><button type="button" [disabled]="sending() /  / !recipients().length /  / !bulkBody().trim()" (click)="sendBulk()">إرسال إلى الأسر المحددة</button><p role="status">{{bulkStatus()}}</p></section>} |
| FORM | web/shared/src/ui/family-messages.ts:16 | <div class="comms-grid"><aside><form (submit)="$event.preventDefault();search()"><label for="family-search">البحث بالاسم أو الجوال</label><div class="search"><input id="family-search" type="search" [value]="query()" (input)="query.set($any($event.target).value)" maxlength="100"><button type="submit">بحث</button></div></form> |
| ACTION | web/shared/src/ui/family-messages.ts:17 | @if(contactsLoading()){<p>جارٍ تحميل الأسر…</p>} @else { @for(contact of contacts();track contact.guardian_id){<button class="contact" type="button" [class.selected]="selected()?.guardian_id===contact.guardian_id" [disabled]="sending()" (click)="select(contact)">{{contact.name}} @if(contact.unread){<b class="unread">{{contact.unread}}</b>}<small>{{contact.last_message  /  /  (contact.can_send?'فتح المحادثة':'ليس لديه حساب بوابة')}}</small>@if(contact.last_at){<small>{{format.shortDate(contact.last_a |
| ACTION | web/shared/src/ui/family-messages.ts:20 | @if(selected();as contact){<header><h2>{{contact.name}}</h2><button type="button" (click)="load()" [disabled]="loading()  /  /  sending()">تحديث الرسائل</button></header> |
| ACTION | web/shared/src/ui/family-messages.ts:23 | @if(more()){<button type="button" [disabled]="loading()" (click)="load(true)">رسائل أقدم</button>} |
| FORM | web/shared/src/ui/family-messages.ts:26 | @if(contact.can_send){<form class="compose" (submit)="$event.preventDefault();send()"><label for="message-body">الرسالة</label>@if(contact.can_manage){<select aria-label="قالب رسالة" [disabled]="sending()" (change)="useTemplate($any($event.target).value);$any($event.target).value='' "><option value="">إدراج قالب رسالة…</option>@for(t of templates;track t.title){<option [value]="t.body">{{t.title}}</option>}</select>}<textarea id="message-body" rows="3" maxlength="4000" [disabled]="sending()" [va |
| API CALL | web/shared/src/ui/family-messages.ts:43 | forkJoin(ids.map(id=>{let attempt=this.bulkAttempts.get(id);if(!attempt /  / attempt.body!==body){attempt={body,id:crypto.randomUUID()};this.bulkAttempts.set(id,attempt)}return this.http.post(this.base+'/family-messages/'+id,{body,request_id:attempt.id}).pipe(map(()=>({id,ok:true})),catchError(()=>of({id,ok:false})))})).pipe(takeUntilDestroyed(this.destroy)).subscribe(results=>{const failed=results.filter(r=>!r.ok).map(r=>r.id);for(const r of results)if(r.ok)this.bulkAttempts.delete(r.id);this.recip |
| API CALL | web/shared/src/ui/family-messages.ts:46 | protected search(quiet=false){const version=++this.contactVersion;if(!quiet){this.contactsLoading.set(true);this.error.set('');}this.http.get<{rows:Contact[];more:boolean}>(this.base+'/family-contacts',{params:new HttpParams().set('q',this.query().trim())}).pipe(takeUntilDestroyed(this.destroy)).subscribe({next:r=>{if(version!==this.contactVersion)return;this.contacts.set(r.rows);this.moreContacts.set(r.more);this.contactsLoading.set(false);if(!this.selected() && r.rows.length===1)this.select(r. |
| API CALL | web/shared/src/ui/family-messages.ts:49 | this.http.get<{rows:Message[];more:boolean}>(this.base+'/family-messages/'+contact.guardian_id,{params}).pipe(takeUntilDestroyed(this.destroy)).subscribe({next:r=>{if(version!==this.version)return;const rows=[...r.rows].reverse();this.messages.set(older?[...rows,...this.messages()]:rows);this.more.set(r.more);this.loading.set(false);if(!older&&rows.length&&document.visibilityState==='visible')this.http.post(this.base+'/family-messages/'+contact.guardian_id+'/read',{message_id:rows[rows.length-1] |
| API CALL | web/shared/src/ui/family-messages.ts:50 | protected send(){const contact=this.selected(),body=this.draft().trim();if(!contact?.can_send /  / !body /  / this.sending())return;if(!this.attempt /  / this.attempt.body!==body /  / this.attempt.guardian!==contact.guardian_id)this.attempt={guardian:contact.guardian_id,body,id:crypto.randomUUID()};this.sending.set(true);this.error.set('');this.http.post(this.base+'/family-messages/'+contact.guardian_id,{body,request_id:this.attempt.id}).pipe(takeUntilDestroyed(this.destroy)).subscribe({next:()=>{this.sending.s |

## Explicit HTTP routes

| Method | Pattern | Source |
| --- | --- | --- |
| GET | /healthz | api/internal/http/server.go:70 |
| GET | /readyz | api/internal/http/server.go:71 |
| POST | /api/v1/auth/otp/request | api/internal/http/server.go:75 |
| POST | /api/v1/auth/otp/verify | api/internal/http/server.go:76 |
| POST | /api/v1/auth/staff/login | api/internal/http/server.go:77 |
| POST | /api/v1/auth/password-setup | api/internal/http/server.go:81 |
| POST | /api/v1/auth/logout | api/internal/http/server.go:82 |
| POST | /api/v1/auth/password | api/internal/http/server.go:83 |
| GET | /api/v1/me | api/internal/http/server.go:85 |
| GET | /api/v1/me/contact | api/internal/http/server.go:92 |
| PATCH | /api/v1/me/contact | api/internal/http/server.go:93 |
| GET | /api/v1/children | api/internal/http/server.go:94 |
| GET | /api/v1/children/{child_id} | api/internal/http/server.go:95 |
| GET | /api/v1/children/{child_id}/profile | api/internal/http/server.go:98 |
| GET | /api/v1/children/{child_id}/guardians | api/internal/http/server.go:103 |
| GET | /api/v1/children/{child_id}/appointments | api/internal/http/server.go:104 |
| GET | /api/v1/children/{child_id}/sessions | api/internal/http/server.go:105 |
| GET | /api/v1/children/{child_id}/plans | api/internal/http/server.go:106 |
| GET | /api/v1/children/{child_id}/reports | api/internal/http/server.go:107 |
| GET | /api/v1/children/{child_id}/notes | api/internal/http/server.go:108 |
| GET | /api/v1/reports/{report_id} | api/internal/http/server.go:113 |
| GET | /api/v1/children/{child_id}/activities | api/internal/http/server.go:116 |
| GET | /api/v1/children/{child_id}/activity-log | api/internal/http/server.go:117 |
| POST | /api/v1/children/{child_id}/activities/{child_activity_id}/log | api/internal/http/server.go:118 |
| GET | /api/v1/children/{child_id}/requests | api/internal/http/server.go:119 |
| POST | /api/v1/children/{child_id}/requests | api/internal/http/server.go:120 |
| GET | /api/v1/children/{child_id}/invoices | api/internal/http/server.go:123 |
| GET | /api/v1/children/{child_id}/packages | api/internal/http/server.go:124 |
| GET | /api/v1/children/{child_id}/balance | api/internal/http/server.go:125 |
| GET | /api/v1/invoices/{invoice_id} | api/internal/http/server.go:126 |
| POST | /api/v1/appointments/{appointment_id}/consultation | api/internal/http/server.go:131 |
| POST | /api/v1/sessions/{session_id}/stream | api/internal/http/server.go:134 |
| POST | /api/v1/stream/close | api/internal/http/server.go:135 |
| GET | /api/v1/appointments | api/internal/http/server.go:146 |
| GET | /api/v1/sessions | api/internal/http/server.go:147 |
| GET | /api/v1/reports | api/internal/http/server.go:148 |
| GET | /api/v1/invoices | api/internal/http/server.go:149 |
| GET | /api/v1/requests | api/internal/http/server.go:150 |
| POST | /api/v1/appointments/validate | api/internal/http/server.go:155 |
| GET | /api/v1/appointments/slots | api/internal/http/server.go:161 |
| POST | /api/v1/appointments | api/internal/http/server.go:162 |
| PATCH | /api/v1/appointments/{appointment_id}/status | api/internal/http/server.go:163 |
| POST | /api/v1/appointments/{appointment_id}/session | api/internal/http/server.go:166 |
| PATCH | /api/v1/sessions/{session_id}/close | api/internal/http/server.go:167 |
| PUT | /api/v1/sessions/{session_id}/note | api/internal/http/server.go:168 |
| POST | /api/v1/reports | api/internal/http/server.go:176 |
| PATCH | /api/v1/reports/{report_id} | api/internal/http/server.go:177 |
| POST | /api/v1/reports/{report_id}/publish | api/internal/http/server.go:178 |
| POST | /api/v1/notes/{note_id}/publish | api/internal/http/server.go:181 |
| POST | /api/v1/guardians/{guardian_id}/consent | api/internal/http/server.go:185 |
| DELETE | /api/v1/guardians/{guardian_id}/consent | api/internal/http/server.go:186 |
| POST | /api/v1/children/{child_id}/photo | api/internal/http/server.go:192 |
| GET | /api/v1/children/{child_id}/photo | api/internal/http/server.go:193 |
| POST | /api/v1/invoices | api/internal/http/server.go:194 |
| POST | /api/v1/invoices/{invoice_id}/lines | api/internal/http/server.go:195 |
| DELETE | /api/v1/invoices/{invoice_id}/lines/{line_id} | api/internal/http/server.go:196 |
| POST | /api/v1/invoices/{invoice_id}/issue | api/internal/http/server.go:197 |
| POST | /api/v1/invoices/{invoice_id}/payments | api/internal/http/server.go:198 |
| POST | /api/v1/children/{child_id}/packages | api/internal/http/server.go:199 |
| PATCH | /api/v1/requests/{request_id} | api/internal/http/server.go:202 |
| POST | /api/v1/enrolments | api/internal/http/server.go:209 |
| GET | /api/v1/enrolments | api/internal/http/server.go:210 |
| GET | /api/v1/enrolments/{application_id} | api/internal/http/server.go:211 |
| PATCH | /api/v1/enrolments/{application_id} | api/internal/http/server.go:212 |
| POST | /api/v1/enrolments/{application_id}/convert | api/internal/http/server.go:213 |
| GET | /api/v1/notifications | api/internal/http/server.go:219 |
| POST | /api/v1/notifications/{notification_id}/read | api/internal/http/server.go:220 |
| GET | /api/v1/nps/due | api/internal/http/server.go:224 |
| POST | /api/v1/nps/{survey_id}/response | api/internal/http/server.go:225 |
| POST | /api/v1/nps/{survey_id}/skip | api/internal/http/server.go:226 |
| GET | /api/v1/nps/summary | api/internal/http/server.go:227 |
| POST | /api/v1/family-messages/{guardian_id}/read | api/internal/http/server.go:231 |
| GET | /api/v1/family-contacts | api/internal/http/server.go:232 |
| GET | /api/v1/family-messages/{guardian_id} | api/internal/http/server.go:233 |
| POST | /api/v1/family-messages/{guardian_id} | api/internal/http/server.go:234 |
| GET | /api/v1/billing/ledger | api/internal/http/server.go:235 |
| GET | /api/v1/billing/summary | api/internal/http/server.go:236 |
| GET | /api/v1/dashboard/metrics | api/internal/http/server.go:237 |
| GET | /api/v1/ops/health | api/internal/http/server.go:238 |
| GET | /api/v1/ops/errors | api/internal/http/server.go:239 |
| GET | /api/v1/settings/params | api/internal/http/server.go:245 |
| PATCH | /api/v1/settings/params/{code} | api/internal/http/server.go:246 |
| DELETE | /api/v1/settings/params/{code} | api/internal/http/server.go:247 |
| PATCH | /api/v1/settings/center | api/internal/http/server.go:248 |
| GET | /api/v1/settings/time-zones | api/internal/http/server.go:249 |
| GET | /api/v1/ops/activity | api/internal/http/server.go:250 |
| GET | /api/v1/therapists/{therapist_id}/services | api/internal/http/server.go:257 |
| GET | /api/v1/services/{service_id}/therapists | api/internal/http/server.go:263 |
| GET | /api/v1/service-therapists | api/internal/http/server.go:269 |
| POST | /api/v1/therapists/{therapist_id}/services | api/internal/http/server.go:270 |
| DELETE | /api/v1/therapists/{therapist_id}/services/{service_id} | api/internal/http/server.go:271 |
| PATCH | /api/v1/therapists/{therapist_id}/profile | api/internal/http/server.go:280 |
| GET | /api/v1/therapists/{therapist_id}/languages | api/internal/http/server.go:281 |
| PUT | /api/v1/therapists/{therapist_id}/languages | api/internal/http/server.go:282 |
| DELETE | /api/v1/therapists/{therapist_id}/languages/{lang_code} | api/internal/http/server.go:283 |
| GET | /api/v1/therapists/{therapist_id}/certificates | api/internal/http/server.go:285 |
| POST | /api/v1/therapists/{therapist_id}/certificates | api/internal/http/server.go:286 |
| PATCH | /api/v1/certificates/{certificate_id}/image | api/internal/http/server.go:287 |
| POST | /api/v1/therapists/{therapist_id}/consent | api/internal/http/server.go:289 |
| DELETE | /api/v1/therapists/{therapist_id}/consent | api/internal/http/server.go:290 |
| POST | /api/v1/therapists/{therapist_id}/publish | api/internal/http/server.go:291 |
| GET | /api/v1/users | api/internal/http/server.go:296 |
| POST | /api/v1/users | api/internal/http/server.go:297 |
| PATCH | /api/v1/users/{user_id} | api/internal/http/server.go:298 |
| DELETE | /api/v1/users/{user_id} | api/internal/http/server.go:299 |
| PUT | /api/v1/users/{user_id}/roles | api/internal/http/server.go:300 |
| POST | /api/v1/users/{user_id}/password-setup | api/internal/http/server.go:301 |
| GET | /api/v1/roles | api/internal/http/server.go:302 |
| PUT | /api/v1/roles/{code}/permissions | api/internal/http/server.go:303 |
| POST | /api/v1/users/{user_id}/documents | api/internal/http/server.go:312 |
| GET | /api/v1/staff-documents/{document_id}/file | api/internal/http/server.go:313 |
| POST | /api/v1/users/{user_id}/photo | api/internal/http/server.go:314 |
| GET | /api/v1/users/{user_id}/photo | api/internal/http/server.go:315 |
| GET | /api/v1/permissions | api/internal/http/server.go:316 |
| POST | /api/v1/site-media | api/internal/http/server.go:322 |
| GET | /api/v1/site-media/{name} | api/internal/http/server.go:345 |

## Generic CRUD API resources

registerCRUD في api/internal/http/crud_handlers.go يضيف GET list/get، POST create، PATCH update، DELETE archive، POST restore؛ children قراءة مسجلة مسبقًا. لذلك عدد explicit routes وحده ناقص.

| Source | Resource declaration |
| --- | --- |
| api/internal/store/crud.go:145 | Name: "services", Param: "service_id", table: "hbh.services", pk: "service_id", |
| api/internal/store/crud.go:165 | Name: "rooms", Param: "room_id", table: "hbh.rooms", pk: "room_id", |
| api/internal/store/crud.go:176 | Name: "cameras", Param: "camera_id", table: "hbh.cameras", pk: "camera_id", |
| api/internal/store/crud.go:183 | Name: "activity-library", Param: "activity_id", table: "hbh.activity_library", pk: "activity_id", |
| api/internal/store/crud.go:190 | Name: "service-packages", Param: "package_id", table: "hbh.service_packages", pk: "package_id", |
| api/internal/store/crud.go:202 | Name: "therapists", Param: "therapist_id", table: "hbh.therapists", pk: "therapist_id", |
| api/internal/store/crud.go:248 | Name: "working-hours", Param: "working_hour_id", table: "hbh.therapist_working_hours", pk: "working_hour_id", |
| api/internal/store/crud.go:260 | Name: "caseload", Param: "caseload_id", table: "hbh.caseload", pk: "caseload_id", |
| api/internal/store/crud.go:266 | Name: "children", Param: "child_id", table: "hbh.children", pk: "child_id", |
| api/internal/store/crud.go:281 | Name: "guardians", Param: "guardian_id", table: "hbh.guardians", pk: "guardian_id", |
| api/internal/store/crud.go:288 | Name: "plans", Param: "plan_id", table: "hbh.treatment_plans", pk: "plan_id", |
| api/internal/store/crud.go:294 | Name: "goals", Param: "goal_id", table: "hbh.plan_goals", pk: "goal_id", |
| api/internal/store/crud.go:300 | Name: "child-activities", Param: "child_activity_id", table: "hbh.child_activities", pk: "child_activity_id", |
| api/internal/store/crud.go:306 | Name: "measurements", Param: "measurement_id", table: "hbh.goal_measurements", pk: "measurement_id", |
| api/internal/store/crud.go:316 | Name: "therapist-qualifications", Param: "qualification_id", |
| api/internal/store/crud.go:342 | Name: "nps-surveys", Param: "survey_id", table: "hbh.nps_surveys", pk: "survey_id", |
| api/internal/store/crud.go:380 | Name: "site-contact", Param: "contact_id", table: "hbh.site_contact", pk: "contact_id", |
| api/internal/store/crud.go:404 | Name: "site-texts", Param: "text_id", table: "hbh.site_texts", pk: "text_id", |
| api/internal/store/crud.go:424 | Name: "site-faq", Param: "faq_id", table: "hbh.site_faq", pk: "faq_id", |
| api/internal/store/crud.go:430 | Name: "site-team", Param: "member_id", table: "hbh.site_team", pk: "member_id", |
| api/internal/store/crud.go:451 | Name: "staff-profiles", Param: "profile_id", |
| api/internal/store/crud.go:466 | Name: "staff-documents", Param: "document_id", |
| api/internal/store/crud.go:482 | Name: "site-team-media", Param: "media_id", table: "hbh.site_team_media", pk: "media_id", |
| api/internal/store/crud.go:491 | Name: "site-team-specialties", Param: "specialty_id", |
| api/internal/store/crud.go:498 | Name: "site-reviews", Param: "review_id", table: "hbh.site_reviews", pk: "review_id", |
| api/internal/store/crud.go:520 | Name: "site-team-certificates", Param: "certificate_id", |
| api/internal/store/crud.go:534 | Name: "site-team-facts", Param: "fact_id", table: "hbh.site_team_facts", pk: "fact_id", |
| api/internal/store/crud.go:545 | Name: "site-services", Param: "site_service_id", table: "hbh.site_services", pk: "site_service_id", |
| api/internal/store/crud.go:556 | Name: "site-programs", Param: "program_id", table: "hbh.site_programs", pk: "program_id", |
| api/internal/store/crud.go:586 | Name: "site-sections", Param: "section_id", table: "hbh.site_sections", pk: "section_id", |

## Entities from migration declarations

الجدول لا يثبت API أو workflow مكتملًا؛ استخدم خريطة الرحلة للتمييز.

| Entity table | Migration |
| --- | --- |
| schema_migrations | db/migrations/0001_foundation.up.sql:35 |
| centers | db/migrations/0001_foundation.up.sql:182 |
| branches | db/migrations/0001_foundation.up.sql:208 |
| sys_params | db/migrations/0001_foundation.up.sql:242 |
| lookup_types | db/migrations/0001_foundation.up.sql:267 |
| lookup_values | db/migrations/0001_foundation.up.sql:283 |
| users | db/migrations/0001_foundation.up.sql:316 |
| audit_log | db/migrations/0001_foundation.up.sql:359 |
| number_series | db/migrations/0002_auth_and_children.up.sql:37 |
| permissions | db/migrations/0002_auth_and_children.up.sql:105 |
| roles | db/migrations/0002_auth_and_children.up.sql:121 |
| role_permissions | db/migrations/0002_auth_and_children.up.sql:141 |
| user_roles | db/migrations/0002_auth_and_children.up.sql:159 |
| children | db/migrations/0002_auth_and_children.up.sql:178 |
| guardians | db/migrations/0002_auth_and_children.up.sql:226 |
| guardian_children | db/migrations/0002_auth_and_children.up.sql:264 |
| otp_codes | db/migrations/0002_auth_and_children.up.sql:295 |
| auth_sessions | db/migrations/0002_auth_and_children.up.sql:317 |
| convention_exemptions | db/migrations/0003_convention_exemptions.up.sql:34 |
| activity_library | db/migrations/0007_home_programme.up.sql:46 |
| child_activities | db/migrations/0007_home_programme.up.sql:79 |
| activity_log | db/migrations/0007_home_programme.up.sql:125 |
| parent_requests | db/migrations/0007_home_programme.up.sql:166 |
| service_packages | db/migrations/0008_billing.up.sql:50 |
| child_packages | db/migrations/0008_billing.up.sql:77 |
| package_ledger | db/migrations/0008_billing.up.sql:116 |
| invoices | db/migrations/0008_billing.up.sql:146 |
| invoice_lines | db/migrations/0008_billing.up.sql:194 |
| payments | db/migrations/0008_billing.up.sql:231 |
| cameras | db/migrations/0009_live_stream.up.sql:66 |
| stream_tokens | db/migrations/0009_live_stream.up.sql:109 |
| stream_views | db/migrations/0009_live_stream.up.sql:144 |
| schedule_blocks | db/migrations/0010_schedule_blocks.up.sql:39 |
| maintenance_runs | db/migrations/0011_staff_auth_and_maintenance.up.sql:199 |
| consents | db/migrations/0015_consents_and_notifications.up.sql:59 |
| consent_events | db/migrations/0015_consents_and_notifications.up.sql:105 |
| notifications | db/migrations/0015_consents_and_notifications.up.sql:338 |
| enrolment_applications | db/migrations/0018_enrolment_applications.up.sql:51 |
| nps_surveys | db/migrations/0019_nps.up.sql:48 |
| nps_responses | db/migrations/0019_nps.up.sql:104 |
| request_log | db/migrations/0020_request_log.up.sql:51 |
| waiting_list | db/migrations/0022_waiting_list_and_recurrence.up.sql:190 |
| assessment_instruments | db/migrations/0023_assessments.up.sql:52 |
| assessment_items | db/migrations/0023_assessments.up.sql:84 |
| assessments | db/migrations/0023_assessments.up.sql:111 |
| assessment_item_scores | db/migrations/0023_assessments.up.sql:164 |
| attachments | db/migrations/0024_attachments.up.sql:49 |
| audit_log_archive | db/migrations/0025_audit_archive_and_backup.up.sql:50 |
| backup_runs | db/migrations/0025_audit_archive_and_backup.up.sql:164 |
| therapist_languages | db/migrations/0033_therapist_profile.up.sql:139 |
| therapist_qualifications | db/migrations/0033_therapist_profile.up.sql:172 |
| therapist_certificates | db/migrations/0033_therapist_profile.up.sql:197 |
| site_sections | db/migrations/0040_site_content.up.sql:64 |
| site_contact | db/migrations/0040_site_content.up.sql:93 |
| site_faq | db/migrations/0040_site_content.up.sql:143 |
| site_team | db/migrations/0040_site_content.up.sql:190 |
| site_reviews | db/migrations/0040_site_content.up.sql:258 |
| site_team_facts | db/migrations/0045_site_content_real.up.sql:94 |
| site_programs | db/migrations/0045_site_content_real.up.sql:131 |
| site_services | db/migrations/0047_site_services.up.sql:36 |
| site_team_certificates | db/migrations/0048_site_team_certificates.up.sql:49 |
| site_team_media | db/migrations/0061_site_team_profile.up.sql:69 |
| site_team_specialties | db/migrations/0061_site_team_profile.up.sql:164 |
| staff_profiles | db/migrations/0067_staff_profiles.up.sql:54 |
| staff_documents | db/migrations/0067_staff_profiles.up.sql:117 |
| password_setups | db/migrations/0068_password_setup.up.sql:43 |
| family_messages | db/migrations/0079_family_messages.up.sql:2 |
| family_message_reads | db/migrations/0080_family_message_reads.up.sql:2 |
| site_texts | db/migrations/0092_site_texts.up.sql:54 |
| sms_outbox | db/migrations/0094_sms_delivery.up.sql:79 |
| country_dial_codes | db/migrations/0112_international_mobiles.up.sql:126 |
| meetings | db/migrations/0120_meetings_and_tokens.up.sql:124 |
| meeting_tokens | db/migrations/0120_meetings_and_tokens.up.sql:225 |
| mobile_verifications | db/migrations/0131_mobile_verification.up.sql:86 |
| profile_field_rules | db/migrations/0133_record_completeness_from_rules.up.sql:76 |
| service_prices | db/migrations/0135_service_prices.up.sql:108 |
| payment_plans | db/migrations/0142_payment_plans.up.sql:101 |
| payment_plan_installments | db/migrations/0142_payment_plans.up.sql:128 |
| invoice_installments | db/migrations/0142_payment_plans.up.sql:367 |
| invoice_installment_status_history | db/migrations/0142_payment_plans.up.sql:417 |

## حدود القراءة

- تعذرت قراءة db/migrations/0005_scheduling.up.sql
- تعذرت قراءة db/migrations/0006_plans_and_notes.up.sql

المراجعة الحية للدخول والداشبورد والمهام بحساب المدير فقط. باقي الواجهات جرد وتحليل ساكن، لا ادعاء اختبار بصري شامل. لا تعد حالات/ميزات fixture تشغيلًا حقيقيًا.

## Expanded form fields and permissions

تفصيل حقول النماذج المتولدة؛ القيم أدناه من التعريف الفعلي ولا تضيف حقلاً لعقد الخادم.

| Source | Field | Kind | Required | Reference/lookup | Options |
| --- | --- | --- | --- | --- | --- |
| web/ops/src/app/core/resource/resource-spec.ts:226 | 'full_name_ar' | 'text' | true | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:227 | 'child_no' | 'text' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:228 | 'birth_date' | 'date' | true | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:229 | 'gender' | 'select' | true | — | GENDER |
| web/ops/src/app/core/resource/resource-spec.ts:249 | 'full_name_ar' | 'text' | true | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:250 | 'title_ar' | 'text' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:251 | 'mobile' | 'text' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:252 | 'status' | 'select' | غير مصرح | — | THERAPIST_STATUS |
| web/ops/src/app/core/resource/resource-spec.ts:264 | 'therapist_id' | 'ref' | true | { resource: 'therapists', idColumn: 'therapist_id', labelColumn: 'full_name_ar' } | — |
| web/ops/src/app/core/resource/resource-spec.ts:267 | 'weekday' | 'number' | true | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:268 | 'start_time' | 'time' | true | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:269 | 'end_time' | 'time' | true | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:290 | 'therapist_id' | 'ref' | true | { resource: 'therapists', idColumn: 'therapist_id', labelColumn: 'full_name_ar' } | — |
| web/ops/src/app/core/resource/resource-spec.ts:291 | 'child_id' | 'ref' | true | { resource: 'children', idColumn: 'child_id', labelColumn: 'full_name_ar' } | — |
| web/ops/src/app/core/resource/resource-spec.ts:295 | 'service_id' | 'ref' | true | { resource: 'services', idColumn: 'service_id', labelColumn: 'name_ar' } | — |
| web/ops/src/app/core/resource/resource-spec.ts:309 | 'name_ar' | 'text' | true | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:310 | 'code' | 'text' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:314 | 'notes_ar' | 'text' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:332 | 'name_ar' | 'text' | true | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:333 | 'room_id' | 'ref' | true | { resource: 'rooms', idColumn: 'room_id', labelColumn: 'name_ar' } | — |
| web/ops/src/app/core/resource/resource-spec.ts:347 | 'name_ar' | 'text' | true | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:348 | 'code' | 'text' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:349 | 'kind_code' | 'text' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:358 | 'default_duration_min' | 'number' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:378 | 'creates_session_flg' | 'switch' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:380 | 'needs_caseload_flg' | 'switch' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:392 | 'name_ar' | 'text' | true | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:393 | 'service_id' | 'ref' | true | { resource: 'services', idColumn: 'service_id', labelColumn: 'name_ar' } | — |
| web/ops/src/app/core/resource/resource-spec.ts:394 | 'sessions_cnt' | 'number' | true | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:397 | 'price_amt' | 'text' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:411 | 'title_ar' | 'text' | true | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:412 | 'code' | 'text' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:413 | 'how_to_ar' | 'text' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:458 | 'title_ar' | 'text' | true | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:459 | 'child_id' | 'ref' | true | { resource: 'children', idColumn: 'child_id', labelColumn: 'full_name_ar' } | — |
| web/ops/src/app/core/resource/resource-spec.ts:460 | 'service_id' | 'ref' | true | { resource: 'services', idColumn: 'service_id', labelColumn: 'name_ar' } | — |
| web/ops/src/app/core/resource/resource-spec.ts:461 | 'therapist_id' | 'ref' | true | { resource: 'therapists', idColumn: 'therapist_id', labelColumn: 'full_name_ar' } | — |
| web/ops/src/app/core/resource/resource-spec.ts:462 | 'start_date' | 'date' | true | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:463 | 'end_date' | 'date' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:477 | 'plan_id' | 'ref' | true | { resource: 'plans', idColumn: 'plan_id', labelColumn: 'title_ar' } | — |
| web/ops/src/app/core/resource/resource-spec.ts:478 | 'title_ar' | 'text' | true | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:479 | 'description_ar' | 'text' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:483 | 'baseline_pct' | 'number' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:484 | 'target_pct' | 'number' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:485 | 'status' | 'select' | غير مصرح | — | GOAL_STATUS |
| web/ops/src/app/core/resource/resource-spec.ts:486 | 'sort_order' | 'number' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:498 | 'goal_id' | 'ref' | true | { resource: 'goals', idColumn: 'goal_id', labelColumn: 'title_ar' } | — |
| web/ops/src/app/core/resource/resource-spec.ts:499 | 'measured_on' | 'date' | true | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:500 | 'value_pct' | 'number' | true | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:501 | 'trials_cnt' | 'number' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:505 | 'session_id' | 'number' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:506 | 'note_ar' | 'text' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:518 | 'child_id' | 'ref' | true | { resource: 'children', idColumn: 'child_id', labelColumn: 'full_name_ar' } | — |
| web/ops/src/app/core/resource/resource-spec.ts:519 | 'activity_id' | 'ref' | true | { resource: 'activity-library', idColumn: 'activity_id', labelColumn: 'title_ar' } | — |
| web/ops/src/app/core/resource/resource-spec.ts:520 | 'plan_id' | 'number' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:521 | 'goal_id' | 'number' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:522 | 'times_per_week' | 'number' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:523 | 'minutes_each' | 'number' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:524 | 'instructions_ar' | 'text' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:525 | 'start_date' | 'date' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:526 | 'end_date' | 'date' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:572 | 'code' | 'text' | true | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:573 | 'name_ar' | 'text' | true | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:574 | 'question_ar' | 'text' | true | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:575 | 'followup_question_ar' | 'text' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:576 | 'audience' | 'select' | غير مصرح | — | NPS_AUDIENCE |
| web/ops/src/app/core/resource/resource-spec.ts:577 | 'trigger_kind' | 'select' | غير مصرح | — | NPS_TRIGGER |
| web/ops/src/app/core/resource/resource-spec.ts:580 | 'action_code' | 'select' | غير مصرح | — | NPS_ACTION |
| web/ops/src/app/core/resource/resource-spec.ts:584 | 'period_days' | 'number' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:590 | 'cooldown_days' | 'number' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:591 | 'starts_on' | 'date' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:592 | 'ends_on' | 'date' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:606 | 'full_name_ar' | 'text' | true | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:607 | 'mobile' | 'text' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:608 | 'email' | 'text' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:609 | 'city' | 'text' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:610 | 'relationship' | 'select' | غير مصرح | — | [       { value: '', labelKey: 'guardian.unspecified' },       { value: 'الأب', labelKey: 'relationship.FATHER' },       { value: 'الأم', labelKey: 'relationship.MOTHER' },       { value: 'وليّ أمر', labelKey: 'relationship.GUARDIAN' },     ] |
| web/ops/src/app/core/resource/resource-spec.ts:616 | 'national_id' | 'text' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:663 | 'phone' | 'text' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:668 | 'landline' | 'text' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:669 | 'whatsapp' | 'text' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:670 | 'email' | 'text' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:671 | 'address_ar' | 'text' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:674 | 'address_en' | 'text' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:678 | 'map_url' | 'text' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:682 | 'arrival_ar' | 'textarea' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:683 | 'arrival_en' | 'textarea' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:684 | 'hours_ar' | 'text' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:685 | 'hours_en' | 'text' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:688 | 'weekend_ar' | 'text' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:689 | 'weekend_en' | 'text' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:690 | 'status' | 'select' | غير مصرح | — | SITE_STATUS |
| web/ops/src/app/core/resource/resource-spec.ts:742 | 'text_key' | 'text' | true | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:743 | 'text_ar' | 'textarea' | true | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:750 | 'text_en' | 'textarea' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:751 | 'status' | 'select' | غير مصرح | — | SITE_STATUS |
| web/ops/src/app/core/resource/resource-spec.ts:765 | 'question_ar' | 'text' | true | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:766 | 'answer_ar' | 'text' | true | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:771 | 'question_en' | 'text' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:772 | 'answer_en' | 'text' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:776 | 'sort_order' | 'number' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:777 | 'status' | 'select' | غير مصرح | — | SITE_STATUS |
| web/ops/src/app/core/resource/resource-spec.ts:791 | 'name_ar' | 'text' | true | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:792 | 'role_ar' | 'text' | true | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:793 | 'name_en' | 'text' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:794 | 'role_en' | 'text' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:795 | 'sort_order' | 'number' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:796 | 'status' | 'select' | غير مصرح | — | SITE_STATUS |
| web/ops/src/app/core/resource/resource-spec.ts:815 | 'display_name' | 'text' | true | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:816 | 'body_ar' | 'text' | true | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:817 | 'body_en' | 'text' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:821 | 'guardian_id' | 'number' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:822 | 'sort_order' | 'number' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:823 | 'status' | 'select' | غير مصرح | — | SITE_STATUS |
| web/ops/src/app/core/resource/resource-spec.ts:851 | 'service_id' | 'number' | true | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:852 | 'blurb_ar' | 'text' | true | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:853 | 'blurb_en' | 'text' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:854 | 'icon_key' | 'select' | غير مصرح | — | SITE_ICON |
| web/ops/src/app/core/resource/resource-spec.ts:855 | 'sort_order' | 'number' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:856 | 'status' | 'select' | غير مصرح | — | SITE_STATUS |
| web/ops/src/app/core/resource/resource-spec.ts:919 | 'code' | 'select' | غير مصرح | — | SITE_SECTION_CODE |
| web/ops/src/app/core/resource/resource-spec.ts:921 | 'visible_flg' | 'switch' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:935 | 'title_ar' | 'text' | true | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:936 | 'desc_ar' | 'text' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:937 | 'detail_ar' | 'text' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:938 | 'title_en' | 'text' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:939 | 'desc_en' | 'text' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:940 | 'detail_en' | 'text' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:941 | 'icon_key' | 'select' | غير مصرح | — | SITE_ICON |
| web/ops/src/app/core/resource/resource-spec.ts:942 | 'sort_order' | 'number' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:943 | 'status' | 'select' | غير مصرح | — | SITE_STATUS |
| web/ops/src/app/core/resource/resource-spec.ts:963 | 'member_id' | 'number' | true | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:964 | 'text_ar' | 'text' | true | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:965 | 'text_en' | 'text' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:966 | 'sort_order' | 'number' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:999 | 'member_id' | 'number' | true | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:1002 | 'path' | 'text' | true | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:1006 | 'caption_ar' | 'text' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:1007 | 'caption_en' | 'text' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:1008 | 'consent_given_at' | 'date' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:1009 | 'redaction_checked_at' | 'date' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:1010 | 'sort_order' | 'number' | غير مصرح | — | — |
| web/ops/src/app/core/resource/resource-spec.ts:1011 | 'status' | 'select' | غير مصرح | — | SITE_STATUS |

| Source | Field | Kind | Required | Reference/lookup | Options |
| --- | --- | --- | --- | --- | --- |
| web/ops/src/app/core/ops/day-spec.ts:345 | 'reason' | 'text' | غير مصرح | — | — |
| web/ops/src/app/core/ops/day-spec.ts:429 | 'child_id' | 'search' | true | 'children' | — |
| web/ops/src/app/core/ops/day-spec.ts:463 | 'service_therapist' | 'pair' | true | — | — |
| web/ops/src/app/core/ops/day-spec.ts:468 | 'service_id' | 'lookup' | true | 'services' | — |
| web/ops/src/app/core/ops/day-spec.ts:482 | 'therapist_id' | 'lookup' | true | 'therapists' | — |
| web/ops/src/app/core/ops/day-spec.ts:520 | 'delivery_mode' | 'select' | true | — | [           { value: 'IN_PERSON', labelKey: 'delivery.IN_PERSON' },           { value: 'ONLINE', labelKey: 'delivery.ONLINE' },         ] |
| web/ops/src/app/core/ops/day-spec.ts:528 | 'slot' | 'slots' | غير مصرح | — | — |
| web/ops/src/app/core/ops/day-spec.ts:546 | 'starts_at' | 'datetime' | true | — | — |
| web/ops/src/app/core/ops/day-spec.ts:551 | 'ends_at' | 'datetime' | true | — | — |
| web/ops/src/app/core/ops/day-spec.ts:556 | 'room_id' | 'lookup' | true | 'rooms' | — |
| web/ops/src/app/core/ops/day-spec.ts:574 | 'note_ar' | 'textarea' | غير مصرح | — | — |
| web/ops/src/app/core/ops/day-spec.ts:594 | 'status' | 'select' | true | — | — |
| web/ops/src/app/core/ops/day-spec.ts:735 | 'body_ar' | 'textarea' | true | — | — |
| web/ops/src/app/core/ops/day-spec.ts:748 | 'status' | 'select' | true | — | — |
| web/ops/src/app/core/ops/day-spec.ts:913 | 'child_id' | 'search' | true | 'children' | — |
| web/ops/src/app/core/ops/day-spec.ts:917 | 'due_date' | 'datetime' | غير مصرح | — | — |
| web/ops/src/app/core/ops/day-spec.ts:918 | 'note_ar' | 'text' | غير مصرح | — | — |
| web/ops/src/app/core/ops/day-spec.ts:933 | 'child_id' | 'search' | true | 'children' | — |
| web/ops/src/app/core/ops/day-spec.ts:937 | 'package_id' | 'lookup' | true | 'service-packages' | — |
| web/ops/src/app/core/ops/day-spec.ts:962 | 'description_ar' | 'text' | true | — | — |
| web/ops/src/app/core/ops/day-spec.ts:963 | 'qty' | 'money' | true | — | — |
| web/ops/src/app/core/ops/day-spec.ts:964 | 'unit_amt' | 'money' | true | — | — |
| web/ops/src/app/core/ops/day-spec.ts:992 | 'amount' | 'money' | true | — | — |
| web/ops/src/app/core/ops/day-spec.ts:996 | 'method_code' | 'select' | true | — | [             { value: 'CASH', labelKey: 'pay.CASH' },             { value: 'CARD', labelKey: 'pay.CARD' },             { value: 'TRANSFER', labelKey: 'pay.TRANSFER' },             { value: 'WALLET', labelKey: 'pay.WALLET' },             { value: 'OTHER', labelKey: 'pay.OTHER' },           ] |
| web/ops/src/app/core/ops/day-spec.ts:1012 | 'note_ar' | 'text' | غير مصرح | — | — |
| web/ops/src/app/core/ops/day-spec.ts:1092 | 'status' | 'select' | true | — | [             { value: 'ACCEPTED', labelKey: 'status.request.ACCEPTED' },             { value: 'REJECTED', labelKey: 'status.request.REJECTED' },           ] |
| web/ops/src/app/core/ops/day-spec.ts:1106 | 'note_ar' | 'textarea' | غير مصرح | — | — |
| web/ops/src/app/core/ops/day-spec.ts:1209 | 'status' | 'select' | true | — | — |
| web/ops/src/app/core/ops/day-spec.ts:1219 | 'note_ar' | 'textarea' | غير مصرح | — | — |
| web/ops/src/app/core/ops/day-spec.ts:1238 | 'note_ar' | 'textarea' | غير مصرح | — | — |

## Permission codes referenced by seed/migrations

هذه قائمة الرموز المستعملة/المذكورة؛ لا تعني أنها ممنوحة لكل دور أو مفعلة في البيئة الحية. /me هو المرجع الفعلي.

| Permission | First source |
| --- | --- |
| APPOINTMENT.BOOK | db/seed/0002_rbac.sql:13 |
| APPOINTMENT.CANCEL | db/seed/0002_rbac.sql:14 |
| ASSESSMENT.PUBLISH | db/seed/0002_rbac.sql:256 |
| ASSESSMENT.RECORD | db/seed/0002_rbac.sql:255 |
| ATTACHMENT.PUBLISH | db/seed/0002_rbac.sql:275 |
| ATTACHMENT.UPLOAD | db/seed/0002_rbac.sql:274 |
| BILLING.HOLD_EXTEND | db/seed/0002_rbac.sql:409 |
| BILLING.MANAGE | db/seed/0002_rbac.sql:22 |
| BILLING.PRICE_EDIT | db/seed/0002_rbac.sql:406 |
| BILLING.PRICE_OVERRIDE | db/seed/0002_rbac.sql:407 |
| BILLING.RECEIPT_REVIEW | db/seed/0002_rbac.sql:408 |
| BILLING.SCHEDULE_OVERRIDE | db/seed/0002_rbac.sql:466 |
| BILLING.VIEW | db/seed/0002_rbac.sql:21 |
| CATALOG.MANAGE | db/seed/0002_rbac.sql:192 |
| CATALOG.PUBLISH | db/seed/0002_rbac.sql:405 |
| CHILD.CREATE | db/seed/0002_rbac.sql:10 |
| CHILD.EDIT | db/seed/0002_rbac.sql:11 |
| CHILD.VIEW_ALL | db/seed/0002_rbac.sql:9 |
| ENROLMENT.MANAGE | db/seed/0002_rbac.sql:213 |
| GOAL.MEASURE | db/seed/0002_rbac.sql:141 |
| GUARDIAN.MANAGE | db/seed/0002_rbac.sql:12 |
| LIVE.VIEW | db/seed/0002_rbac.sql:20 |
| NOTE.PUBLISH | db/seed/0002_rbac.sql:142 |
| NPS.MANAGE | db/seed/0002_rbac.sql:214 |
| OPS.VIEW | db/seed/0002_rbac.sql:215 |
| PACKAGE.MAKEUP_OVERRIDE | db/seed/0002_rbac.sql:410 |
| PLAN.MANAGE | db/seed/0002_rbac.sql:140 |
| PORTAL.VIEW | db/seed/0002_rbac.sql:8 |
| REPORT.PUBLISH | db/seed/0002_rbac.sql:19 |
| REPORT.VIEW | db/seed/0002_rbac.sql:18 |
| REPORT.WRITE | db/migrations/0091_report_authoring.up.sql:76 |
| REQUEST.MANAGE | db/seed/0002_rbac.sql:24 |
| REQUEST.SUBMIT | db/seed/0002_rbac.sql:23 |
| SESSION.COMPLETE | db/seed/0002_rbac.sql:16 |
| SESSION.START | db/seed/0002_rbac.sql:15 |
| SETTINGS.MANAGE | db/seed/0002_rbac.sql:338 |
| SITE.EDIT | db/seed/0002_rbac.sql:310 |
| SITE.PUBLISH | db/seed/0002_rbac.sql:311 |
| STAFF.MANAGE | db/seed/0002_rbac.sql:193 |
| STAFF.PII | db/seed/0002_rbac.sql:360 |
| USER.MANAGE | db/seed/0002_rbac.sql:168 |
