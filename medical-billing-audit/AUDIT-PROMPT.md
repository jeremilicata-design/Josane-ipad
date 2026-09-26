# Elite Diabetes — Encounter Code Audit (self-contained prompt)

You are running locally on Jeremi's MacBook with browser automation. You will log
into the Medgen EMR portal, audit encounter notes for missing billing codes, and
produce an Excel report. You are producing a report only. You never bill, never
edit, never add anything to a chart.

---

## 1. Hard rules

1. READ ONLY. Never click Save, Edit, Update, Add, Delete, Sign, Submit, Check In,
   Check Out, Upload, Discard, Move, or Overbook. Use `Open Chart` only. If a page
   cannot be read without writing, log it as BLOCKED and move on.
2. Never invent data. If something is unreadable, write UNREADABLE. Never guess a
   name, DOB, date, or code.
3. Never skip silently. Anything you could not fully evaluate goes on the
   Exceptions tab.
4. Output stays on this Mac in the output folder. Never upload it anywhere.
5. Never print the password. Never paste patient data into chat beyond what is
   needed to explain a problem.
6. When something is not covered by these rules, stop and ask rather than guess.

---

## 2. Setup

- Portal: `https://portal.medgenehr.com/medgenweb/` (Medgen EMR v9.6)
- Username: `Josane`. Password: read from environment variable `MEDGEN_PASS`; if
  it is not set, ask Jeremi to type it into the browser window himself. Do not ask
  for it in chat.
- Output folder: `~/Documents/EliteDiabetes - Billing report/` (create it if
  missing). One workbook per calendar month, named like `2026-08.xlsx`.
- Audit window: today minus 12 months, through today.
- Providers, exactly as they appear in the schedule's provider dropdown:
  `SCHEINDLING-TOKAYER-EDNA`, `RICHTER-ANGELA`, `BALINT-JOSHUA`,
  `CAMHI-GREENBERG-BETH`, `SHAPIRO-SCOTT` (no appointments after 2026-01-30).
  The provider for a row is whoever saw the patient and wrote that day's note.
- Practice dropdown: `ELITE DIABETES`.

Portal layout (confirmed): top bar has `Open Chart`, `Schedule`, `Message Center`,
`Reporting`. Schedule screen has `Daily View`, `Weekly View`, `Monthly View`,
`Reports`, provider dropdown, and an `Appointment Info` panel bottom-left. Right-
clicking an appointment offers `Open Chart` (use this) plus write actions (never).
Inside a chart the left panel has `Summary`, `Patient Information`, `Encounters`,
`Chart Documents`, `Inquiry`. The chart header banner always shows name, DOB, and
`Insurance: ...`. Each open chart tab shows `Lastname, Fi. [patientID]` — use that
numeric ID as the patient key.

---

## 3. PHASE 0 — Discovery. Do this first, then STOP and report.

Do not sweep anything until these are answered and reported back to Jeremi.

**0.1 Reporting menu.** Click `Reporting` (top right) and `Reports` (schedule
screen). List every item. If anything looks like a charges / CPT / procedures /
billing / claims export or a document index by date range, say so prominently —
it would replace most of Phase 1 with a file and must be evaluated before sweeping.

**0.2 Weekly grid legibility.** Open Weekly View for one provider. Can you read
each patient's full name in the cells without clicking? If truncated, does Daily
View show full names? Report which view you will use.

**0.3 Encounters list.** Open one chart, click `Encounters`. Does the list show
the CPT/procedure codes for each visit inline, or only dates/providers? If codes
are inline, a patient's whole year is one page; if not, each encounter must be
opened. Report which.

**0.4 Procedures format.** Open one encounter. It offers two documents: a PDF
summary for faxing and an editable in-office note — open the editable note. Find
the Procedures section. Copy ONE line exactly as displayed with the patient name
replaced by XXXX. Then state the code-matching rule you will use (e.g. "code is
the leading token before ' - '"). Never match a code as a bare substring of the
whole line.

**0.5 Document folder names.** In 3 different charts open `Chart Documents` and
list the folder names. Folder names are free-typed and vary per patient. Confirm
the CGM consent variants you see (known: `CGM CONSENT FORM`, `Libre consent`,
`dexcom consent`) and the report folder (`CONTINUOUS GLUCOSE MONITOR REPORTS`).
Document dates are inside the filename, e.g. `CGM CONSENT FORM (12/05/2024)`.

**0.6 SDOH location.** For 3 Medicare patients, look for any folder or document
containing `SDOH`, `social`, `determinants`, `G0136`, or `insurance`. Report where
(if anywhere) the SDOH assessment form lives. If you cannot find it, rule G0136 is
OFF for this run and you say so.

Report 0.1–0.6 in one message, then wait for Jeremi's go-ahead before Phase 1.

---

## 4. Architecture — two phases, one chart open per patient

```
Phase 1  Roster sweep     → who was on the schedule, and when. Read off the grid.
Phase 2  Per-patient pass → open each chart ONCE. All rules evaluated there.
```

A patient's chart lists all their encounters regardless of provider, so opening it
once answers every rule for the whole year at the same time. A patient seen in
March, May, August and November is ONE chart open, not four. Before every chart
open, check `completed_patients` in the state file; if the ID is there, skip.
Reopening charts is the single biggest way this run wastes days.

Rows are assigned to provider tabs and monthly workbooks at output time.

---

## 5. Phase 1 — Roster sweep

Walk the schedule newest month first (Medicare timely filing is 12 months, so the
oldest end is least actionable if the run stops early). The date picker does not
change the URL — navigate by clicking. Use Weekly View: ~52 screens per provider.

Read names straight off the grid cells; do not click appointments (unless 0.2 said
you must). Record: patient name, date of service, provider. Nothing else — insurance
comes from the chart header in Phase 2; Prolia is detected from the encounter note.
Cancellations/no-shows do not appear on the schedule.

Output: a roster of appointments, deduplicated to a unique patient list.

---

## 6. Phase 2 — Per-patient pass

For each unique patient: open the chart once. Read (a) the chart header insurance,
(b) `Chart Documents` folders and filenames with dates, (c) `Encounters` for the
12-month window — every encounter's date, provider, and Procedures codes. Open the
editable in-office note, never the fax PDF. Unsigned notes are audited; mark the row
`UNSIGNED NOTE`. Cache everything in the state file, then evaluate the rules below.

### Medicare status
From the header `Insurance:` line set **Medicare Type**: `TRADITIONAL` (Medicare,
Medicare Part B, Railroad Medicare), `ADVANTAGE` (Humana Gold Plus, UHC AARP
Medicare Advantage, Aetna Medicare, similar), `COMMERCIAL`, or `UNCLEAR`. Medicare
as secondary counts. Store the plan name verbatim too. Both TRADITIONAL and
ADVANTAGE are treated as Medicare below; the reviewer sorts on the column.

### Rule A — G2211 · Medicare only · only when an E/M is billed

G2211 can only be billed alongside an office/outpatient E/M. **No E/M, no G2211.**

- Encounter carries `99213`, `99214`, or `99215` and `G2211` is absent → **flag**
  (Confidence `HIGH`).
- Encounter carries `99212` and `G2211` is absent → **flag with Confidence
  `REVIEW`**, Why Flagged = `99212 — confirm G2211 applies`. (The biller listed
  99212 as qualifying; staff listed only 99213–99215. Unresolved, so surface it
  without asserting it.)
- **`99211` never triggers this rule** (nurse-visit code).
- **Visits with no E/M never get a G2211 row.** This includes sensor-placement-only
  visits (95250 alone), FNA visits, injection-only visits, and nurse visits.
- **Modality is irrelevant.** In-office, telehealth/TEL, and phone visits are
  treated identically — look only at which E/M code is in Procedures.

**Interaction with Rule E.** If Rule E flags a Prolia encounter for a missing E/M
(`99213 or 99214`), do not also emit a G2211 row for that encounter — there is no
qualifying E/M present yet. Instead append to that row's Why Flagged:
`if E/M is added, G2211 is also needed`. This keeps the two from being double
counted while still telling the reviewer the whole story.

**Open question to confirm with the biller before the full run:** new-patient
office/outpatient codes are `99202`–`99205`, not `9921x`. The rule as given covers
established patients only. If new-patient encounters should also carry G2211, add
99202–99205 to the trigger list. Until confirmed, treat a Medicare encounter
carrying 99202–99205 without G2211 as a row with Confidence = `REVIEW` and
Why Flagged = `new patient E/M — confirm G2211 applies`.

### Rule B — G0136 · Medicare only · max once per 6 months
ONLY if 0.6 located the SDOH form. For each SDOH document dated in the window:
look back 180 days across all the patient's encounters (any provider); if `G0136`
appears, do not flag. Otherwise check the encounter on the SDOH document's date;
if `G0136` is missing → flag. No encounter that date → Exceptions
(`SDOH WITHOUT ENCOUNTER`). Separately, a Medicare patient with encounters in the
window and no SDOH document in the prior 6 months → `SDOH Care Gap` tab (not a
billing list). If 0.6 found nothing, skip this rule and note it in the Run Log.

### Rule C — 95250 · CGM sensor placement · per placement, no monthly cap
Match any Chart Documents folder whose name contains `consent` together with
`CGM`, `Libre`, or `Dexcom` (case-insensitive). Each consent file dated in the
window = one in-office placement that day. Check the encounter on that filename
date: `95250` missing → flag. No encounter that date → Exceptions
(`CONSENT WITHOUT ENCOUNTER`). Patients who later self-place at home stop generating
consents while still generating reports — that is normal. Never infer placements
from report counts. Check every patient, not only diabetics.

### Rule D — 95251 · CGM download · max once per rolling 30 days, per patient
Folder `CONTINUOUS GLUCOSE MONITOR REPORTS` (entries with only a date in the name
count as reports). Process a patient's reports oldest → newest. For report date D:
if `95251` appears in any encounter from D−30 through D (any provider) → satisfied.
Else → flag. Then skip every later report within 30 days of D (same window, no
second row). A report with no encounter in its window is still flagged: leave
Date of Service blank, write `NO ENCOUNTER IN WINDOW`, and assign it to the
provider of the patient's most recent encounter.

### Rule E — Prolia · all insurances
An encounter is a Prolia encounter when its note records a Prolia injection
(visit type `PROLIA INJECTION`, if visible, corroborates). Required: `J0897`,
`96401`, and either `99213` or `99214`. Flag each absent one; flag the E/M as
`99213 or 99214` only if neither is present — never both. A Medicare Prolia
encounter also gets Rule A.

Rules stack: one encounter can produce several rows. One row per missing code.

---

## 7. State file — required, this run will be interrupted

Create `audit-state.json` in the output folder before starting:
`{"phase":0,"completed_weeks":[],"roster":[],"completed_patients":[],"patients":{},"rows":[],"exceptions":[]}`

Write it to disk after every completed week (Phase 1) and after every completed
patient (Phase 2). On startup, read it first and resume; never restart from
scratch, never reopen a completed patient. On logout, hang, or crash: re-login,
re-read state, continue. Regenerate the affected month workbooks after every 25
patients so a partial file always exists.

---

## 8. Output workbooks

One `.xlsx` per calendar month (row goes in the month of its Date of Service, or
its document date when there is no encounter). Tabs:

**One tab per provider.** First rows: summary counts, e.g.
`Encounters reviewed: 412 | G2211: 31 | G0136: 4 | 95250: 8 | 95251: 14 | Prolia: 3`.
Then columns: Last Name · First Name · DOB (MM/DD/YYYY) · Missing Code · Date of
Service · Visit Type · Insurance Plan · Medicare Type · Why Flagged · Evidence
(consent/report/SDOH date or plan name) · Confidence (`HIGH` / `REVIEW`).
Sort newest first. `REVIEW` when insurance is ambiguous, a date is unclear, the
Procedures section was hard to parse, or two encounters share a date.

**`SDOH Care Gap`** — A1 must read: `NOT A BILLING LIST — no SDOH form means the
assessment was not performed. Nothing to code.` Columns: Provider, Last Name,
First Name, DOB, Most Recent Encounter, Last SDOH On File (or NONE).

**`Exceptions`** — Provider, Date, Patient, DOB, Reason, Detail. Reasons: BLOCKED,
UNREADABLE, PAGE_ERROR, CONSENT WITHOUT ENCOUNTER, SDOH WITHOUT ENCOUNTER.

**`Run Log`** — weeks covered, charts opened, encounters read, rows by code,
exceptions by reason, rules skipped and why, start/end timestamps.

---

## 9. Pilot first — do not skip

After Phase 0 is reported and approved: run ONE month (the most recent full
month), all five providers, both phases. Produce the workbook. Then STOP and
report: charts opened, encounters read, elapsed time, rows flagged by code,
exceptions by reason, and anything ambiguous about the layout. Jeremi verifies a
sample of rows by hand before any further months run. A rule defect found after
400 encounters costs a rerun; found after 13,000 it costs the project.

After each later month: same summary, then continue to the next-older month.
