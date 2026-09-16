# Encounter Code-Presence Audit — Operating Prompt

Paste everything below the line into Claude Code. Fill in every `<<FILL IN>>` first —
the run will be wrong if any are left as placeholders.

---

## 0. Parameters to fill in before running

| Parameter | Value |
|---|---|
| Portal URL | `https://portal.medgener.com` |
| Login username | `<<FILL IN>>` |
| Login password | `<<FILL IN — use an env var, do not paste in chat>>` |
| Audit window | From `<<START DATE = run date minus 12 months>>` to `<<RUN DATE>>` |
| Provider 1 | Dr. Adma Tocare (`<<exact name string as it appears on the schedule>>`) |
| Provider 2 | Dr. Angela Richter (`<<exact string>>`) |
| Provider 3 | Josh, PA (`<<exact string>>`) |
| Provider 4 | Beth, NP (`<<exact string>>`) |
| Provider 5 | Dr. Scott Chapeiro (`<<exact string>>`) — schedule ends 2026-01-30, do not look for him after that date |
| Prolia visit-type name | `<<FILL IN — exact text as shown in the Visit Type field>>` |
| Medicare Advantage counts as Medicare? | `<<YES / NO>>` — see §4.1 |
| Output file | `./billing-audit-<<RUN DATE>>.xlsx` |

---

## 1. Your role and hard rules

You are auditing **whether specific CPT/HCPCS codes are present in the Procedures
section of encounter notes**. You are producing a report only.

**Hard rules — violating any of these invalidates the run:**

1. **READ ONLY.** Never click Save, Edit, Update, Add, Delete, Sign, or Submit.
   Never type into any chart field. If a page has no way forward without writing,
   log it as `BLOCKED` and move on.
2. **Never add a code to any encounter.** You are not billing and not correcting.
3. **Never invent data.** If a field is unreadable, blank, or the page fails to
   load, write `UNREADABLE` in that cell. Do not guess a name, DOB, date, or code.
4. **Never skip silently.** Every encounter you could not fully evaluate goes on
   the Exceptions tab with the reason.
5. Keep all output on the local machine. Do not upload the workbook anywhere.

---

## 2. Order of work

Process **one provider at a time, completely, before starting the next.**
Within each provider, process **newest date first, working backward** to the
start of the window.

Order: Tocare → Richter → Josh → Beth → Chapeiro.

Rationale for newest-first: Medicare timely filing is 12 months from date of
service, so the oldest end of the window is the least actionable. If the run has
to be stopped early, the useful findings are already captured.

---

## 3. Checkpointing (required — this run takes days)

Before you start, create `./audit-state.json`:

```json
{ "completed": [], "current_provider": null, "current_date": null, "rows": [], "exceptions": [] }
```

**After every single date you finish**, append that date's rows to `rows`, add
`"<provider>|<date>"` to `completed`, and write the file to disk.

**On startup, always read `audit-state.json` first.** If it exists, skip every
`provider|date` already in `completed` and resume from there. Never restart from
scratch. Never re-scrape a completed date.

If the browser session drops, the portal logs you out, or a page hangs: re-login,
re-read the state file, and continue. Do not treat a crash as a reason to stop.

Write the workbook from `audit-state.json` at the end — and also regenerate it
after each completed provider, so a partial workbook always exists.

---

## 4. Per-day procedure

For each date in the window, for the current provider:

1. Open that provider's schedule for that date.
2. For each appointment on it, capture from the schedule / **Appointment Info
   panel on the left** (no need to open the chart for this):
   - Patient last name, first name, DOB
   - Date of service
   - Visit type (verbatim)
   - **Insurance plan name (verbatim)** — this panel is the insurance source of truth
3. Open the encounter and read the **Procedures** section. Record every code present.
4. Apply the rules in §5. Open chart documents only when a rule requires it.

Skip appointments that are cancelled, no-show, or have no encounter — log them on
the Exceptions tab as `NO_ENCOUNTER`.

### 4.1 Determining Medicare status

Read the plan name verbatim from the Appointment Info panel.

- Names containing `Medicare`, `Medicare Part B`, `Railroad Medicare` → **Medicare**.
- Medicare Advantage style names (e.g. `Humana Gold Plus`, `UHC AARP Medicare
  Advantage`, `Aetna Medicare`) → treat per the parameter in §0.
- Medicare listed as **secondary** also counts as Medicare.
- **Always write the verbatim plan name into the report row**, whatever you decide.
  This lets the reviewer re-filter without a re-run.
- If the plan name is ambiguous, still emit the row and set Confidence = `REVIEW`.

---

## 5. The five rules

### 5.1 — G2211 (Medicare only)

For every encounter where the patient is Medicare (§4.1):
if `G2211` is **not** in Procedures → **flag**.

Evidence to record: the verbatim insurance plan name.

### 5.2 — G0136 (Medicare only, max once per 6 months)

Uses the SDOH form in chart documents → folder **`Insurance/documents`**.

For each Medicare patient:
- Find all SDOH forms in `Insurance/documents` with their dates.
- For each SDOH form dated inside the audit window:
  - Look back 180 days from that form's date across the patient's encounters.
    If `G0136` appears in any of them → **do not flag** (frequency limit already met).
  - Otherwise, check the encounter on/nearest the form's date. If `G0136` is not
    in its Procedures → **flag** on the **Missing Codes** tab.
- If a Medicare patient has an encounter in the window but **no SDOH form at all**
  within the preceding 6 months → put them on the **SDOH Care Gap** tab.
  **Do not put them on the Missing Codes tab.** No form means the assessment was
  not performed; there is nothing to code. This tab is a clinical worklist.

Evidence to record: SDOH form date, or `NO SDOH FORM ON FILE`.

### 5.3 — 95250 (CGM sensor placement — per placement, may recur within a month)

Source of truth: chart documents → folder **`CGM Consent Form`**.

A signed consent form in that folder means a sensor was placed on that date.
Placements repeat (e.g. Dexcom 10-day sensors → up to ~3 placements in a month),
and **each placement is its own event**. Do **not** apply any monthly cap here.

For each consent form dated inside the audit window:
- Find the encounter on that same date.
- If `95250` is not in that encounter's Procedures → **flag**.
- If there is no encounter on that date → Exceptions tab, reason
  `CONSENT WITHOUT ENCOUNTER`.

Not limited to diabetic patients — check every patient's CGM Consent Form folder.

Evidence to record: consent form date.

### 5.4 — 95251 (CGM download/interpretation — max once per rolling 30 days)

Source of truth: chart documents → folder **`Continuous Glucose Monitor Report`**.

Window is **rolling 30 days**, not calendar month.

Process each patient's reports **oldest to newest** so the 30-day clock advances
correctly:

1. Take the earliest report date `D` in the window not yet accounted for.
2. Look across all encounters from `D - 30 days` through `D`. If `95251` appears
   in any of their Procedures → this window is satisfied; advance past it and
   continue from the next report dated after that encounter + 30 days.
3. If `95251` appears nowhere in that window → **flag** against the encounter
   nearest to `D`. Then advance the clock: skip any further reports dated within
   30 days of `D` (they roll into the same window and must not produce a second row).
4. If there is **no encounter** within the window at all but a report exists →
   Exceptions tab, reason `DOWNLOAD WITHOUT ENCOUNTER`. Do not flag it as a
   missing code.

Evidence to record: report PDF date, and the 30-day window evaluated.

### 5.5 — Prolia visits

Identify by **Visit Type** matching the Prolia string from §0. Match
case-insensitively and allow the string to appear as a substring.

Required codes on a Prolia encounter:
- `J0897`
- `96401`
- **Either** `99213` **or** `99214` — either one satisfies it. Only flag the E/M
  if **neither** is present. Never report both as missing.

Emit one row per Prolia encounter listing **exactly which** of these is absent.
If all are present → no row.

Note for the reviewer: J0897 is billed per 1 mg, so a 60 mg dose is 60 units. This
audit only checks whether the code is present — it does not check units.

---

## 6. Output workbook

One `.xlsx` file, with these tabs:

**Tabs 1–5 — one per provider, named for the provider.** Columns:

| Column | Contents |
|---|---|
| Patient Last Name | |
| Patient First Name | |
| DOB | MM/DD/YYYY |
| Date of Service | MM/DD/YYYY |
| Visit Type | verbatim |
| Insurance Plan | verbatim from Appointment Info panel |
| Missing Code(s) | e.g. `G2211` or `J0897, 96401` |
| Why Flagged | the rule, in one line |
| Evidence | consent date / report date / SDOH date / plan name |
| Confidence | `HIGH` or `REVIEW` |

Sort each tab by Date of Service, newest first. One row per encounter per rule —
if an encounter is missing both G2211 and 95250, that is two rows.

Set Confidence = `REVIEW` when: the insurance name is ambiguous, a document date is
unclear, the Procedures section was hard to parse, or two encounters share a date.

**Tab 6 — `SDOH Care Gap`.** Medicare patients with no SDOH form in 6 months.
Columns: Provider, Last Name, First Name, DOB, Most Recent Encounter Date, Last SDOH
Form On File (or `NONE`). Put this note in cell A1:
`NOT A BILLING LIST — no SDOH form means the assessment was not performed. Nothing to code.`

**Tab 7 — `Exceptions`.** Everything you could not evaluate.
Columns: Provider, Date, Patient (if known), Reason, Detail.
Reasons: `NO_ENCOUNTER`, `BLOCKED`, `UNREADABLE`, `CONSENT WITHOUT ENCOUNTER`,
`DOWNLOAD WITHOUT ENCOUNTER`, `PAGE_ERROR`.

**Tab 8 — `Run Log`.** Provider, date range covered, dates completed, dates failed,
total encounters reviewed, total rows flagged, run start/end timestamps.

---

## 7. Pilot before the full run

**Do not start the 12-month sweep on the first attempt.**

Run one provider (Dr. Tocare) for **one month** first. Produce the workbook. Stop
and report:
- How many encounters were reviewed and how long it took
- How many rows were flagged, by code
- Anything ambiguous about the portal's layout or the folder names

Wait for the reviewer to verify those rows against the portal by hand before
running the remaining 11 months. If the false-positive rate is material, the
rules need adjusting, and finding that out after 20,000 encounters is far more
expensive than finding it out after 400.

---

## 8. Reporting back

At the end of each provider, output a short summary: encounters reviewed, rows
flagged by code, exceptions by reason. Do not print patient data into chat beyond
what is needed to explain a problem.

If you hit something the rules do not cover, stop and ask rather than guessing.
