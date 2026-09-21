#!/bin/bash
# Elite Diabetes billing audit — one-time setup for macOS.
# Run with:  bash ~/Downloads/elite-audit-setup.sh

set -u

DIR="$HOME/Documents/EliteDiabetes - Billing report"

echo "=============================================="
echo " Elite Diabetes — Billing Audit Setup"
echo "=============================================="
echo

# --- 1. Confirm we are actually on the Mac -------------------------------
if [ "$(uname -s)" != "Darwin" ]; then
  echo "STOP: this is not macOS (found: $(uname -s))."
  echo "You are in a cloud session, not Terminal on your MacBook."
  echo "Open Terminal on the Mac (Cmd+Space, type Terminal) and run this there."
  exit 1
fi
echo "[ok] Running on macOS as $(whoami)"

# --- 2. Check Claude Code is installed ------------------------------------
if ! command -v claude >/dev/null 2>&1; then
  echo "[!] Claude Code is not installed on this Mac."
  if command -v npm >/dev/null 2>&1; then
    echo "    Installing it now..."
    npm install -g @anthropic-ai/claude-code || {
      echo "    Install failed. Try:  sudo npm install -g @anthropic-ai/claude-code"
      exit 1
    }
  else
    echo "    npm is missing too. Install Node.js from https://nodejs.org first,"
    echo "    then run this script again."
    exit 1
  fi
fi
echo "[ok] Claude Code found: $(command -v claude)"

# --- 3. Create the output folder and drop the prompt in it ----------------
mkdir -p "$DIR"
cd "$DIR" || exit 1

cat > AUDIT-PROMPT.md <<'ELITE_AUDIT_PROMPT_EOF'
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

## 2. Architecture — two phases

```
Phase 1  Roster sweep    → who was on the schedule, and when. Read off the grid.
Phase 2  Per-patient pass → one chart open per patient. Everything else happens here.
```

**Phase 2 is patient-centric, and that is the whole design.** A patient's chart
lists *all* their encounters, whoever the provider was. Opening that chart **once**
gives you every rule at the same time: G2211 on each encounter, the G0136 six-month
window, the 95251 thirty-day window, the consent dates, and whether any encounter
was a Prolia visit.

**Never open the same chart twice.** A patient seen in March, May, August and
November is **one** chart open, not four. When the roster reaches that patient again
in a later month, they are already in `completed_patients` — skip them, the answers
are already recorded. Key on the **numeric patient ID** from the chart tab. This is
not an optimization to apply where convenient; reopening charts is the single
biggest way this run wastes days.

Rows are assigned to provider tabs and to monthly workbooks at output time, not
during traversal.

---

## 3. Phase 1 — Roster sweep

Walk the schedule across the 12-month window, **newest month first** (Medicare
timely filing is 12 months from date of service, so the oldest end is least
actionable if the run stops early).

The date does **not** change the URL — navigate by clicking the date picker. Use
the **weekly view**: ~52 screens per provider, ~260 in total.

**Read patient names straight off the grid cells. Do not click into appointments.**
The grid prints the patient name in each cell, and that is all Phase 1 needs:

- patient name
- date of service
- provider

Insurance is **not** collected here — the chart header banner carries it in Phase 2,
and it is more reliable there. Visit type is **not** collected here — Prolia is
detected from the encounter note in Phase 2.

Cancellations and no-shows do not appear — everything listed is a real appointment.

Output: a roster of ~13,000 appointments, deduplicated to roughly 2,000 unique
patients. **The deduplicated list is what Phase 2 consumes.**

If names in the grid cells turn out to be truncated or ambiguous, fall back to
clicking appointments — but report that, because it changes the runtime by an order
of magnitude.

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

## 4. Phase 2 — Per-patient pass

For each unique patient in the roster, open the chart **once** and do all of the
following before moving on. Cache the result in `audit-state.json` so no chart is
opened twice.

Read, in this order:
1. **Chart documents** — the consent and report folders below, with their dates.
2. **The encounter list** — every encounter in the 12-month window, with dates,
   providers, and the codes in each Procedures section.

### 4.0 Reading an encounter

Each encounter offers two documents: a **PDF summary** for faxing out, and an
**editable in-office note**. **Open the editable in-office note.** Never the fax PDF.

Read the **Procedures** section from the main view. Codes appear with descriptions,
e.g. `95250 - Ambulatory continuous glucose monitoring...`. Match the code as a
**whole token at the start of the line**, never as a substring of the whole line, or
digits inside a description will produce false matches.

Unsigned notes **are** audited — mark the row `UNSIGNED NOTE`.

### 4.1 — G2211 · Medicare only · every visit

Only for patients whose Medicare Type is TRADITIONAL or ADVANTAGE. This is the one
rule with no document trigger, so every Medicare encounter in the window must be
opened and checked.

For each such encounter: `G2211` not in Procedures → **flag**.

### 4.2 — G0136 · Medicare only · max once per 6 months

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

### 4.3 — 95250 · CGM placement · per placement, no monthly cap

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

### 4.4 — 95251 · CGM download · max once per rolling 30 days

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

### 4.5 — Prolia · all insurances

An encounter is a **Prolia encounter** when its note records that the patient
received a Prolia injection. The appointment's visit type (`PROLIA INJECTION`) is
corroborating when available, never required — detection happens from the note, in
this same encounter pass.

On a Prolia day the patient does nothing but receive the shot.

Required codes:
- `J0897` — flag if absent
- `96401` — flag if absent
- **either** `99213` **or** `99214` — flag as `99213 or 99214` **only if neither is
  present**. Never report both as missing.

All present → no row. A Medicare patient's Prolia encounter is also subject to
G2211 (§4.1) and will produce that row too.

Reviewer note, not a check: J0897 is per 1 mg, so 60 mg = 60 units. This audit
checks code presence only, never units.

---

## 5. Checkpointing — required

Create `./audit-state.json` before starting:

```json
{ "phase": 1, "completed_weeks": [], "roster": [], "completed_patients": [],
  "rows": [], "exceptions": [] }
```

- Phase 1: after **every week**, append roster entries, add the week key
  (`"2026-08-W3"`) to `completed_weeks`, write to disk.
- Phase 2: after **every patient**, append rows and add the patient ID to
  `completed_patients`, write to disk.
- **Check `completed_patients` before every chart open.** A patient already in it
  is done for the entire 12 months — every rule, every month. Skip them.
- **On startup, read this file first.** Skip completed weeks and completed patients.
  Never restart from scratch. Never re-open a chart already done.
- On logout, hang, or crash: re-login, re-read state, continue. A crash is not a
  reason to stop.
- Regenerate the affected month workbooks after each completed patient batch, so a
  partial file always exists.

~13,000 appointments and ~2,000 charts. This run *will* be interrupted. The state
file is what makes that survivable.

---

## 6. Output

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

## 7. Before the pilot — three checks

### 7.1 Can the roster be read off the grid?

Open one week in Weekly View and confirm patient names are legible in the cells
without clicking. If they are, Phase 1 is ~260 screen reads. If names are truncated
or ambiguous, check whether **Daily View** shows them in full, and only fall back to
clicking each appointment if neither works. Report which path you took — it changes
the runtime by an order of magnitude.

### 7.2 Where the cost actually is

Chart opens are ~2,000, once per unique patient. The volume is in **encounter
opens**: G2211 has no document trigger, so every Medicare encounter in the window
must be read. A Medicare patient seen six times is **one chart open and six
encounters read within it**.

Check whether the `Encounters` list displays the Procedures codes inline. If it
does, those six encounters cost one page load instead of six, and the whole run
gets dramatically cheaper. Report the answer either way, and report chart-open and
encounter-open counts separately.

### 7.3 Check `Reporting` for an export

Open the `Reporting` menu in the top-right, and `Reports` on the schedule screen.
List what is available. If either offers a charge/CPT export or a document index by
date range, **stop and report it** — an export replaces most of Phase 1's ~13,000
clicks with a file, and is both faster and more accurate. Do not start the sweep
before checking.

---

## 8. Pilot first — do not skip

Run **one month, all five providers, both phases.** Produce the workbook, then
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

ELITE_AUDIT_PROMPT_EOF

echo "[ok] Folder ready:  $DIR"
echo "[ok] Prompt written: $DIR/AUDIT-PROMPT.md"

# --- 4. Credentials, read without echoing to screen or history ------------
echo
read -r -p "Medgen username [Josane]: " MU
MEDGEN_USER="${MU:-Josane}"
read -r -s -p "Medgen password (typing is hidden): " MEDGEN_PASS
echo
export MEDGEN_USER MEDGEN_PASS
echo "[ok] Credentials set for this Terminal window only."
echo "     They are not saved to disk or to your shell history."

# --- 5. Launch -------------------------------------------------------------
cat <<'INSTRUCTIONS'

==============================================
 Claude Code is about to start in this folder.
 When it opens, paste exactly this one line:

   Read AUDIT-PROMPT.md in this folder and follow it.
   Run section 7 first and report the three answers
   before starting anything. Then run the section 8
   pilot only - one month, all five providers - and
   stop and report.

 Login with $MEDGEN_USER / $MEDGEN_PASS from the
 environment. Do not type the password into chat.
==============================================

INSTRUCTIONS

if command -v caffeinate >/dev/null 2>&1; then
  exec caffeinate -i claude
else
  exec claude
fi
