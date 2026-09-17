# Elite Diabetes — Encounter Code-Presence Audit

Operating prompt for Claude Code. Run on Jeremi's MacBook Pro.
Fill in every `<<FILL IN>>` before running.

---

## 0. Parameters

| Parameter | Value |
|---|---|
| Portal | `https://portal.medgener.com` |
| Login | `<<FILL IN — username>>` / `<<FILL IN — password, via env var>>` |
| Audit window | Run date minus 12 months → run date |
| Output folder | `/Users/jeremi/Documents/EliteDiabetes - Billing report/` |
| File naming | `2026-08.xlsx` (one workbook per calendar month) |
| Prolia visit type | `PROLIA INJECTION` |

**Providers** (exact strings as they appear in the schedule's provider filter):

| Schedule name | Known in office as | Notes |
|---|---|---|
| `SCHEINDLING-TOKAYER-EDNA` | Dr. Tocare | |
| `RICHTER-ANGELA` | Dr. Richter | |
| `BALINT-JOSHUA` | Josh, PA | own NPI |
| `CAMHI-GREENBERG-BETH` | Beth, NP | own NPI |
| `SHAPIRO-SCOTT` | Dr. Shapiro | no appointments after 2026-01-30 |

Format is `LASTNAME-LASTNAME-FIRSTNAME`. Whoever saw the patient and wrote the
note is the provider for that encounter.

---

## 1. Hard rules

1. **READ ONLY.** Never click Save, Edit, Update, Add, Delete, Sign, or Submit.
   Never type into a chart field. Blocked without writing → log `BLOCKED`, move on.
2. **Never add a code to any encounter.** This produces a report. Nothing else.
3. **Never invent data.** Unreadable or missing → write `UNREADABLE`. Never guess a
   name, DOB, date, or code.
4. **Never skip silently.** Anything not fully evaluated goes on the Exceptions tab.
5. All output stays in the local folder. Do not upload it anywhere.

---

## 2. Traversal order — week by week, all providers together

- Work **one calendar month at a time, newest month first.**
- Within a month, use the **weekly schedule view**, one week at a time.
- Within a week, cover **all five providers** before advancing.
- One workbook per month, with a tab per provider.

Newest-first matters: Medicare timely filing is 12 months from date of service, so
the oldest end of the window is the least actionable if the run stops early.

The schedule's date does **not** change the URL — navigation is by clicking the
date picker. Use the weekly view to cut this from ~250 clicks per provider to ~52.

### 2.1 Lookback scope for the frequency rules

G0136 (6 months) and 95251 (30 days) are **per patient**, not per provider. A code
entered by one provider satisfies the window for all of them.

Two lookback scopes, with different costs:

| Scope | What it checks | Cost | Setting |
|---|---|---|---|
| **In-run** | every encounter already scraped in this run, any provider, any week | free — data is already collected | **ON** |
| **Chart history** | encounters from before this run's start date | requires opening each patient's chart history | **OFF** |

**In-run lookback is ON.** Because all five providers are scraped for the same
weeks, another provider's codes are already in `audit-state.json` when a patient is
evaluated. Checking them costs no extra page loads. Never filter the lookback by
provider.

**Chart-history lookback is OFF** for now. When a rule's window reaches back before
the run's start date, evaluate what is available and add `LOOKBACK LIMITED` to the
Why Flagged column, so the reviewer knows that row was judged on a partial window.

Each flagged row also carries an **Also Seen By** column naming any other provider
who saw that patient in the same month. This measures how much cross-provider
overlap actually exists — if it turns out to be negligible, the in-run lookback can
be dropped later; if it is large, chart-history lookback should be turned on.

---

## 3. Checkpointing — required

Create `./audit-state.json` before starting:

```json
{ "completed_weeks": [], "rows": [], "exceptions": [], "patient_cache": {} }
```

- After **every week** you finish: append rows, add the week key
  (`"2026-08-W3"`) to `completed_weeks`, write the file to disk.
- **On startup, read this file first.** Skip any week already in `completed_weeks`.
  Never restart from scratch.
- `patient_cache` holds each patient's encounter/code history once looked up, so
  the §5 lookbacks don't re-scrape the same chart repeatedly.
- On logout, hang, or crash: re-login, re-read the state file, continue. A crash is
  not a reason to stop.
- Write the month's workbook after each completed week, so a partial file always
  exists.

This run is roughly 13,000 encounters. It will be interrupted. The state file is
what makes that survivable.

---

## 4. Per-appointment procedure

For each appointment in the weekly view:

1. Click into it. The weekly grid does not show insurance or visit type — you must
   open each one.
2. From the **Appointment Info panel on the left**, capture:
   patient last name, first name, DOB, date of service, visit type (verbatim),
   **insurance plan name (verbatim)**.
3. Open the encounter. It offers two documents: a **PDF summary** meant for faxing
   out, and an **editable in-office note**. **Open the editable in-office note.**
   Never the fax PDF.
4. Read the **Procedures** section from the main view and record every code.
5. Apply §5.

Notes: cancellations and no-shows do not appear on the schedule — everything listed
is a real appointment. Unsigned notes **are** audited; mark the row
`UNSIGNED NOTE` in the Why Flagged column.

### 4.1 Code matching

Codes appear with descriptions, e.g. `95250 - Ambulatory continuous glucose
monitoring...`. Match the code as a **whole token at the start of the line** — not
as a substring of the whole line, or digits inside a description will produce false
matches.

### 4.2 Medicare status

Read the plan name verbatim from the Appointment Info panel. Record two columns:

- **Insurance Plan** — verbatim, always.
- **Medicare Type** — `TRADITIONAL` (name contains Medicare / Medicare Part B /
  Railroad Medicare), `ADVANTAGE` (Humana Gold Plus, UHC AARP Medicare Advantage,
  Aetna Medicare, and similar), `COMMERCIAL`, or `UNCLEAR`.

**Flag both TRADITIONAL and ADVANTAGE** for the Medicare-only rules. The reviewer
sorts on the Medicare Type column to decide what to act on. Medicare as **secondary**
also counts. When unsure, use `UNCLEAR` and still emit the row.

---

## 5. The five rules

Rules stack. One encounter can produce several rows — a Medicare patient with a
sensor on a Prolia visit can trigger G2211, 95250, and the Prolia set all at once.
**One row per missing code.** Three missing codes = three rows.

### 5.1 — G2211 (Medicare only, every visit)

Medicare patient (§4.2) and `G2211` not in Procedures → **flag**.
Applies to Prolia visits too.

### 5.2 — G0136 (Medicare only, max once per 6 months)

Source: chart documents → folder **`Insurance-documents`** (no sub-folder; contains
one SDOH file per assessment). The list view shows the **upload date**.

For each Medicare patient, for each SDOH file dated in the window:
1. Look back **180 days** across that patient's encounters, **any provider**,
   using the lookback scope in §2.1. If `G0136` appears in any → **do not flag**
   (frequency already met). If the 180 days reach before the run's start date, mark
   the row `LOOKBACK LIMITED`.
2. Otherwise find the encounter **on the same date as the SDOH file**. If `G0136`
   is not in its Procedures → **flag**.
3. No encounter on that date → **Exceptions**, reason `SDOH WITHOUT ENCOUNTER`.

Separately: a Medicare patient with an encounter in the window and **no SDOH file
in the preceding 6 months** → **`SDOH Care Gap` tab**, never the Missing Codes tab.
No form means the assessment was not performed; there is nothing to code.

### 5.3 — 95250 (CGM placement — per placement, no monthly cap)

Source: chart documents → folder **`CGM Consent Form`**.

A signed consent means a sensor was placed. Placements repeat — Dexcom 10-day
sensors can mean three placements in a month, and **each is its own billable event.
Apply no monthly cap.**

For each consent file dated in the window:
- Find the encounter on **that same date**. If `95250` is not in its Procedures →
  **flag**.
- No encounter on that date → **Exceptions**, reason `CONSENT WITHOUT ENCOUNTER`.
  (Upload lag is normal — most are same day or next day, occasionally up to a week.
  These land here for manual review rather than being matched by guesswork.)

Check **every** patient's CGM Consent Form folder, not just diabetics — sensors are
also placed on thyroid patients.

### 5.4 — 95251 (CGM download — max once per rolling 30 days, per patient)

Source: chart documents → folder **`Continuous Glucose Monitor Report`**.
Window is **rolling 30 days**, not calendar month. Clock is **per patient across all
providers**.

Process each patient's reports **oldest to newest**:
1. Take the earliest report date `D` not yet accounted for.
2. Look across that patient's encounters from `D - 30` through `D`, **any
   provider**, using the lookback scope in §2.1. If `95251` appears in any →
   satisfied; advance past this window. If the window reaches before the run's
   start date, mark the row `LOOKBACK LIMITED`.
3. If it appears nowhere in that window → **flag** (patient, DOB, `95251`).
4. Then **advance the clock**: skip every later report dated within 30 days of `D`.
   They belong to the same window and must not produce a second row.

A report with no encounter in the window is still **flagged**, not an exception —
the row records the patient, DOB, and code regardless of whether an encounter
exists. Put `NO ENCOUNTER IN WINDOW` in Why Flagged and leave Date of Service blank.

95251 is never coded without a report in this folder, so the folder is the complete
source of truth.

### 5.5 — Prolia visits (all insurances)

Identify by Visit Type containing `PROLIA INJECTION`, case-insensitive substring.

Required: `J0897`, `96401`, and **either** `99213` **or** `99214`.
- Flag `J0897` if absent.
- Flag `96401` if absent.
- Flag the E/M **only if neither** 99213 nor 99214 is present. Write it as
  `99213 or 99214`. **Never report both as missing.**

All present → no row.

Note for the reviewer, not a check: J0897 is per 1 mg, so 60 mg = 60 units. This
audit checks code presence only, never units.

---

## 6. Output

One `.xlsx` per calendar month at
`/Users/jeremi/Documents/EliteDiabetes - Billing report/2026-08.xlsx`.

**Tabs 1–5, one per provider.** Provider = whoever saw the patient and wrote the
note that day.

Rows 1–3 of each tab: summary counts, e.g.
`Encounters reviewed: 412 | G2211: 31 | G0136: 4 | 95250: 8 | 95251: 14 | Prolia: 3`
`Patients seen by more than one provider this month: 18`

Then the header row and data:

| Column | Contents |
|---|---|
| Last Name | |
| First Name | |
| DOB | MM/DD/YYYY |
| Missing Code | one code per row — `G2211`, `95250`, `99213 or 99214` |
| Date of Service | MM/DD/YYYY, blank if no encounter |
| Visit Type | verbatim |
| Insurance Plan | verbatim |
| Medicare Type | `TRADITIONAL` / `ADVANTAGE` / `COMMERCIAL` / `UNCLEAR` |
| Also Seen By | other providers who saw this patient this month, or blank |
| Why Flagged | one line — the rule, plus `UNSIGNED NOTE`, `NO ENCOUNTER IN WINDOW`, or `LOOKBACK LIMITED` |
| Evidence | consent date / report date / SDOH date / plan name |
| Confidence | `HIGH` or `REVIEW` |

Sorted by Date of Service, newest first.

Set `REVIEW` when: insurance name is ambiguous, a document date is unclear, the
Procedures section was hard to parse, or two encounters share a date.

**`SDOH Care Gap` tab.** Medicare patients with no SDOH form in 6 months.
Columns: Provider, Last Name, First Name, DOB, Most Recent Encounter, Last SDOH On
File (or `NONE`). Cell A1 must read:
`NOT A BILLING LIST — no SDOH form means the assessment was not performed. Nothing to code.`

**`Exceptions` tab.** Everything not fully evaluated.
Columns: Provider, Date, Patient, DOB, Reason, Detail.
Reasons: `BLOCKED`, `UNREADABLE`, `PAGE_ERROR`, `CONSENT WITHOUT ENCOUNTER`,
`SDOH WITHOUT ENCOUNTER`.

**`Run Log` tab.** Weeks covered, weeks failed, encounters reviewed, rows flagged
by code, start/end timestamps.

---

## 7. Pilot first — do not skip

Run **one month, all five providers**. Produce the workbook. Stop and report:
- Encounters reviewed and elapsed time
- Rows flagged, by code
- Anything ambiguous about the portal layout or folder names

Wait for Jeremi to verify those rows by hand before running the remaining eleven
months. Finding a rule defect after 400 encounters costs a re-run; finding it after
13,000 costs the project.

---

## 8. Reporting

After each month, output: encounters reviewed, rows by code, exceptions by reason.
Keep patient data out of chat beyond what's needed to explain a problem.

If something isn't covered by these rules, stop and ask rather than guessing.
