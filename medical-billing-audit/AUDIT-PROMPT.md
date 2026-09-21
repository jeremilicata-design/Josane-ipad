# Elite Diabetes — Encounter Code-Presence Audit

Operating prompt for Claude Code. Runs on Jeremi's MacBook Pro against
`portal.medgener.com`. Fill in every `<<FILL IN>>` before running.

---

## 0. Parameters

| Parameter | Value |
|---|---|
| Portal | `https://portal.medgenehr.com/medgenweb/` — Medgen EMR v9.6 |
| Login | `<<FILL IN — username>>` / `<<FILL IN — password via env var, never in this file>>` |
| Audit window | Run date minus 12 months → run date |
| Output folder | `/Users/jeremi/Documents/EliteDiabetes - Billing report/` |
| File naming | `2026-08.xlsx` — one workbook per calendar month |
| Prolia visit type | `PROLIA INJECTION` |

**Providers** — exact strings in the schedule's provider filter, format
`LASTNAME-LASTNAME-FIRSTNAME`:

| Schedule string | Office name | Note |
|---|---|---|
| `SCHEINDLING-TOKAYER-EDNA` | Dr. Tocare | |
| `RICHTER-ANGELA` | Dr. Richter | |
| `BALINT-JOSHUA` | Josh, PA | own NPI |
| `CAMHI-GREENBERG-BETH` | Beth, NP | own NPI |
| `SHAPIRO-SCOTT` | Dr. Shapiro | no appointments after 2026-01-30 |

Provider for a row = whoever saw the patient and wrote that day's note.

**Portal layout, confirmed from screen recordings:**
- Top bar: `Open Chart`, `Schedule`, `Message Center`, `ICD-10`; right side `Support`,
  `Reporting`. Open charts appear as tabs, each showing `Lastname, Fi. [patientID]`.
- Schedule screen: practice dropdown (`ELITE DIABETES`) and provider dropdown; buttons
  `Daily View`, `Weekly View`, `Monthly View`, `Reports`, `Utilities`,
  `Find Available Appointments`, `Refresh`. `Appointment Info` panel bottom-left.
- Right-clicking an appointment gives `Open Chart`, `Open Chart to...`,
  `Lookup Appointments`, and write actions. **Use `Open Chart` only.**
- Chart navigation (left panel): `Summary`, `Patient Information`, **`Encounters`**,
  **`Chart Documents`**, `Inquiry`.
- Chart header banner is always visible and carries name, DOB, age, and
  **`Insurance:`** — e.g. `Insurance: Fl Medicare Part B (j9 First Coast)`.
- **Use the numeric patient ID** from the chart tab as the key, not name + DOB.

---

## 1. Hard rules

1. **READ ONLY.** Never click Save, Edit, Update, Add, Delete, Sign, or Submit.
   Never type into a chart field. If blocked without writing, log `BLOCKED` and move on.
2. **Never add a code to any encounter.** This produces a report. Nothing else.
3. **Never invent data.** Unreadable or missing → `UNREADABLE`. Never guess a name,
   DOB, date, or code.
4. **Never skip silently.** Anything not fully evaluated goes on the Exceptions tab.
5. Output stays in the local folder. Do not upload it anywhere.

---

## 2. Architecture — three phases

Chart documents drive the CGM and SDOH rules. The schedule drives Prolia. Medicare
requires opening every encounter regardless. So:

```
Phase 1  Schedule sweep      → roster of appointments + unique patient list
Phase 2  Prolia encounters   → straight from the schedule, no chart documents
Phase 3  Per-patient pass    → one chart open per patient, everything else
```

**Phase 3 is patient-centric, and that matters.** A patient's chart lists *all*
their encounters, whoever the provider was. Walking that list checks the G0136
six-month window and the 95251 thirty-day window correctly across providers, at no
extra cost. Never reconstruct a patient's history from the schedule.

Rows are assigned to provider tabs at output time, not traversal time.

---

## 3. Phase 1 — Schedule sweep

Walk the schedule across the 12-month window, **newest month first** (Medicare
timely filing is 12 months from date of service, so the oldest end is least
actionable if the run stops early).

The date does **not** change the URL — navigate by clicking the date picker. Use
the **weekly view** to cut this from ~250 clicks per provider to ~52.

For each week, for each of the five providers, click into **every** appointment.
The weekly grid shows neither insurance nor visit type, so each one must be opened.
From the **Appointment Info panel on the left**, record:

- patient last name, first name, DOB
- date of service, provider
- visit type (verbatim)
- **insurance plan name (verbatim)**

Cancellations and no-shows do not appear — everything listed is a real appointment.

Output of this phase: a roster of ~13,000 appointments, and a deduplicated patient
list of roughly 2,000 unique patients.

### 3.1 Medicare status

Read the plan name from the **chart header banner** (`Insurance: ...`), which is
more reliable than the Appointment Info panel. A green Comment Alert reading
`MEDICARE VERIFIED` or `MEDICARE & SUPP` is a corroborating signal when the plan
name is ambiguous — never the primary source.

From the plan name, set **Medicare Type**:
`TRADITIONAL` (Medicare, Medicare Part B, Railroad Medicare), `ADVANTAGE` (Humana
Gold Plus, UHC AARP Medicare Advantage, Aetna Medicare, similar), `COMMERCIAL`, or
`UNCLEAR`. Medicare as **secondary** counts. Always also store the plan name
verbatim. Both TRADITIONAL and ADVANTAGE are treated as Medicare for the rules
below; the reviewer sorts on this column to decide what to act on.

---

## 4. Phase 2 — Prolia

For every roster appointment whose Visit Type contains `PROLIA INJECTION`
(case-insensitive substring):

Go **straight to the encounter**. Do not open chart documents — on a Prolia day the
patient does nothing but receive the shot.

Required codes:
- `J0897` — flag if absent
- `96401` — flag if absent
- **either** `99213` **or** `99214` — flag as `99213 or 99214` **only if neither is
  present**. Never report both as missing.

All present → no row.

A Medicare patient's Prolia visit is also subject to G2211 (§5.1) and will produce
that row too, from Phase 3.

Reviewer note, not a check: J0897 is per 1 mg, so 60 mg = 60 units. This audit
checks code presence only, never units.

---

## 5. Phase 3 — Per-patient pass

For each unique patient in the roster, open the chart **once** and do all of the
following before moving on. Cache the result in `audit-state.json` so no chart is
opened twice.

Read, in this order:
1. **Chart documents** — the three folders below, with their listed dates.
2. **The encounter list** — every encounter in the 12-month window, with dates,
   providers, and the codes in each Procedures section.

### 5.0 Reading an encounter

Each encounter offers two documents: a **PDF summary** for faxing out, and an
**editable in-office note**. **Open the editable in-office note.** Never the fax PDF.

Read the **Procedures** section from the main view. Codes appear with descriptions,
e.g. `95250 - Ambulatory continuous glucose monitoring...`. Match the code as a
**whole token at the start of the line**, never as a substring of the whole line, or
digits inside a description will produce false matches.

Unsigned notes **are** audited — mark the row `UNSIGNED NOTE`.

### 5.1 — G2211 · Medicare only · every visit

Only for patients whose Medicare Type is TRADITIONAL or ADVANTAGE. This is the one
rule with no document trigger, so every Medicare encounter in the window must be
opened and checked.

For each such encounter: `G2211` not in Procedures → **flag**.

### 5.2 — G0136 · Medicare only · max once per 6 months

> **UNRESOLVED — DO NOT RUN THIS RULE YET.** Two charts were inspected and neither
> contained an `Insurance-documents` folder or anything resembling an SDOH form.
> The source for this rule is unconfirmed. Skip G0136 entirely and note it in the
> Run Log until Jeremi identifies where the SDOH form actually lives. Running it
> against a guessed folder would flag every Medicare patient in the practice.

Documents: folder `<<FILL IN — confirmed SDOH folder name>>`, one file per
assessment, date in the filename.

Expect at most **two** G0136 in a 12-month window (one per six months).

For each SDOH file dated in the window:
1. Look back **180 days** across the patient's encounter list, any provider. If
   `G0136` appears in any → **do not flag**; the window is already satisfied.
2. Otherwise check the encounter **on the same date as the SDOH file**. If `G0136`
   is not in its Procedures → **flag**.
3. No encounter on that date → **Exceptions**, reason `SDOH WITHOUT ENCOUNTER`.
   (Upload lag is normal — usually same or next day, occasionally up to a week.
   These go to manual review rather than being matched by guesswork.)

Separately: a Medicare patient with encounters in the window but **no SDOH file in
the preceding 6 months** → **`SDOH Care Gap` tab**, never Missing Codes. No form
means the assessment was not performed; there is nothing to code.

### 5.3 — 95250 · CGM placement · per placement, no monthly cap

Documents: the consent folder. **Folder names are free-typed and vary by patient.**
Match case-insensitively any folder whose name contains `consent` together with
`CGM`, `Libre`, or `Dexcom` — confirmed variants are `CGM CONSENT FORM`,
`Libre consent`, and `dexcom consent`. A patient may have one of these and not the
others. Matching only `CGM CONSENT FORM` silently skips every Libre and Dexcom
patient — this is a confirmed failure mode, not a hypothetical.

Document dates appear **in the filename**, e.g.
`CGM CONSENT FORM (12/05/2024)`. That date is typed by staff and can differ from
the signature date inside the PDF — one confirmed case differs by 16 days. Use the
filename date; mismatches surface as `CONSENT WITHOUT ENCOUNTER` exceptions rather
than being guessed at.

A signed consent means a sensor was placed **in the office, that day**.
Patients who learn to place sensors at home stop generating consents while
continuing to generate reports — so a patient with one consent and twenty reports
is normal and correct, not a data problem. Never infer placements from report count. Placements repeat — Dexcom 10-day
sensors can mean three in a month, and **each is its own event. Apply no cap.**

For each consent file dated in the window:
- Check the encounter **on that same date**. `95250` not in Procedures → **flag**.
- No encounter on that date → **Exceptions**, `CONSENT WITHOUT ENCOUNTER`.

Check **every** patient's folder, not only diabetics — sensors are also placed on
thyroid patients.

### 5.4 — 95251 · CGM download · max once per rolling 30 days

Documents: folder **`CONTINUOUS GLUCOSE MONITOR REPORTS`** (plural). Dates are in
the filenames, e.g. `CONTINUOUS GLUCOSE MONITOR REPORTS (02/14/2026)`. Some entries
carry only a date and no name — treat those in this folder as reports. Rolling 30 days, not
calendar month. 95251 is never coded without a report here, so this folder is the
complete source of truth.

Process the patient's reports **oldest to newest**:
1. Take the earliest report date `D` not yet accounted for.
2. Check the patient's encounters from `D - 30` through `D`, any provider. If
   `95251` appears in any → satisfied; advance past this window.
3. If it appears nowhere in that window → **flag**.
4. **Advance the clock**: skip every later report within 30 days of `D`. They belong
   to the same window and must not produce a second row.

A report with **no encounter** in the window is still **flagged**, not an exception.
The row records patient, DOB, and code regardless. Put `NO ENCOUNTER IN WINDOW` in
Why Flagged, leave Date of Service blank, and assign it to the provider of that
patient's most recent encounter.

---

## 6. Checkpointing — required

Create `./audit-state.json` before starting:

```json
{ "phase": 1, "completed_weeks": [], "roster": [], "completed_patients": [],
  "rows": [], "exceptions": [] }
```

- Phase 1: after **every week**, append roster entries, add the week key
  (`"2026-08-W3"`) to `completed_weeks`, write to disk.
- Phase 3: after **every patient**, append rows and add the patient to
  `completed_patients`, write to disk.
- **On startup, read this file first.** Skip completed weeks and completed patients.
  Never restart from scratch. Never re-open a chart already done.
- On logout, hang, or crash: re-login, re-read state, continue. A crash is not a
  reason to stop.
- Regenerate the affected month workbooks after each completed patient batch, so a
  partial file always exists.

~13,000 appointments and ~2,000 charts. This run *will* be interrupted. The state
file is what makes that survivable.

---

## 7. Output

One `.xlsx` per calendar month in
`/Users/jeremi/Documents/EliteDiabetes - Billing report/`, named `2026-08.xlsx`.
A row lands in the month of its Date of Service (or its document date when there is
no encounter).

**Tabs 1–5, one per provider.** First rows: summary counts, e.g.
`Encounters reviewed: 412 | G2211: 31 | G0136: 4 | 95250: 8 | 95251: 14 | Prolia: 3`

Then the header and data. **One row per missing code** — three missing codes on one
encounter is three rows.

| Column | Contents |
|---|---|
| Last Name | |
| First Name | |
| DOB | MM/DD/YYYY |
| Missing Code | one per row — `G2211`, `95250`, `99213 or 99214` |
| Date of Service | MM/DD/YYYY, blank if no encounter |
| Visit Type | verbatim |
| Insurance Plan | verbatim |
| Medicare Type | `TRADITIONAL` / `ADVANTAGE` / `COMMERCIAL` / `UNCLEAR` |
| Why Flagged | the rule in one line, plus `UNSIGNED NOTE` or `NO ENCOUNTER IN WINDOW` |
| Evidence | consent date / report date / SDOH date / plan name |
| Confidence | `HIGH` or `REVIEW` |

Sorted by Date of Service, newest first. Use `REVIEW` when the insurance name is
ambiguous, a document date is unclear, the Procedures section was hard to parse, or
two encounters share a date.

**`SDOH Care Gap` tab.** Cell A1 must read:
`NOT A BILLING LIST — no SDOH form means the assessment was not performed. Nothing to code.`
Columns: Provider, Last Name, First Name, DOB, Most Recent Encounter, Last SDOH On
File (or `NONE`).

**`Exceptions` tab.** Provider, Date, Patient, DOB, Reason, Detail.
Reasons: `BLOCKED`, `UNREADABLE`, `PAGE_ERROR`, `CONSENT WITHOUT ENCOUNTER`,
`SDOH WITHOUT ENCOUNTER`.

**`Run Log` tab.** Weeks covered, patients processed, failures, rows by code,
start/end timestamps.

---

## 7.5 Before the pilot — check `Reporting`

Open the `Reporting` menu in the top-right, and `Reports` on the schedule screen.
List what is available. If either offers a charge/CPT export or a document index by
date range, **stop and report it** — an export replaces most of Phase 1's ~13,000
clicks with a file, and is both faster and more accurate. Do not start the sweep
before checking.

---

## 8. Pilot first — do not skip

Run **one month, all five providers, all three phases.** Produce the workbook, then
stop and report:
- Appointments swept, charts opened, elapsed time
- Rows flagged, by code
- Anything ambiguous about the portal layout or folder names

Wait for Jeremi to verify those rows by hand before running the remaining eleven
months. A rule defect found after 400 encounters costs a re-run; found after 13,000
it costs the project.

---

## 9. Reporting

After each month: appointments swept, charts opened, rows by code, exceptions by
reason. Keep patient data out of chat beyond what is needed to explain a problem.

If something is not covered by these rules, stop and ask rather than guessing.
