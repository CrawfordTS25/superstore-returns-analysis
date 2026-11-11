# TRACE Redesign: Step-by-Step Walkthrough Guide

Follow the parts in order. Each step says **where to click, what to type, and what you should see**.
Anything marked ⚠ can change production behaviour. Do it in a dev/test copy first, or right after exporting a backup (Part 1.3).

- Analysis behind every step: `03_ANALYSIS_REPORT.md`
- Column meanings: `reference/list-map.md`

---

## Part 0: Getting this package onto your computer

### 0.1 Download from GitHub (no tools needed)
1. Go to GitHub (sign-in not needed; the repo is public).
2. Go to `https://github.com/CrawfordTS25/superstore-returns-analysis`.
3. **Switch branch.** Click the branch dropdown (top left, it shows `main`) and select **`claude/keen-tesla-gckrbv`**. The `trace-handoff` folder only exists on this branch.
4. Click the green **Code** button → **Download ZIP**.
5. Unzip it. Everything is in the `trace-handoff/` folder.

### 0.2 Or clone with git
```bash
git clone -b claude/keen-tesla-gckrbv https://github.com/CrawfordTS25/superstore-returns-analysis.git
cd superstore-returns-analysis/trace-handoff
```

### 0.3 What is in the folder
| Path | What it is | When you use it |
|---|---|---|
| `README.md` | Index | First |
| `01_HANDOFF_NOTES.md` | Status, decisions, open questions, next steps | Before starting, and when handing to someone else |
| `02_WALKTHROUGH_GUIDE.md` | This file | Doing the work |
| `03_ANALYSIS_REPORT.md` | Full 7-section analysis with evidence | Looking up *why* |
| `scripts/TRACE_Reconciliation.ps1` | Read-only checks R1–R9, C1–C3 | Parts 3 and 6 |
| `reference/list-map.md` | List GUIDs → names, field legend | Parts 2 and 5 |
| `reference/flow-inventory.md` | Every flow: on/off, trigger, concurrency | Part 1 |
| `reference/flow-outlines/*.txt` | Every action with its inputs, filters and writes | Finding an action in the designer |
| `reference/run-order/*.order.txt` | Actions in execution order per container, with `[YES]`/`[NO]` branches | Understanding control flow |
| `reference/lane-diffs/*.diff` | Exact differences between Lane 1 and Lanes 2/3/4 | Part 5, Fix 6 |
| `tools/*.py` | Python scripts that regenerate `reference/` from the export | Part 9 |

### 0.4 Placeholders (this copy is redacted)
This public copy replaces identifiers with placeholders (`<tenant>`, `<site>`, `<LIST_CHUNKS>`, `<shared-mailbox@company.com>`, `<ADDRESS-A>`, `Location A` …). The table in `README.md` → *Filling in the placeholders* says where each real value lives.
- Wherever this guide shows a placeholder in a URL or expression, type the real value.
- Before Part 3, fill in the `$L` block at the top of `scripts/TRACE_Reconciliation.ps1`. The script stops with a clear error if any placeholder is left.
- Keep the **original solution export zip and plan .docx** on your computer. They aren't in the repo. Part 9 regenerates the reference files from the zip.
- **Never commit** real GUIDs, URLs or the export back into this public repo.

---

## Part 1: Get oriented (about 30 minutes)

### 1.1 Read in this order
1. `01_HANDOFF_NOTES.md` → *Executive summary* and *Open questions*.
2. `03_ANALYSIS_REPORT.md` → §0 (facts), then §3 (ranked failure modes).
3. `reference/flow-inventory.md`. Note that **Lanes 1–4 are OFF** in this export.

### 1.2 Confirm the export matches production
The analysis is of solution **TRACEQVCodeReview20261022 v1.0.0.9**. If production has changed since then:
1. Go to make.powerautomate.com → **Solutions** → open the TRACE solution.
2. Check the version number (top right of the solution page).
3. If it's newer than 1.0.0.9, export a fresh copy (1.3) and re-run the tools (Part 9) so the outlines match what you're editing.

### 1.3 ⚠ Back up before changing anything
1. make.powerautomate.com → **Solutions** → select the TRACE solution → **Export solution**.
2. **Publish all changes** → Next → **Unmanaged** → Export.
3. Save the `.zip` with today's date in its name. This is your rollback.
4. Rollback = Solutions → **Import solution** → choose the zip → overwrite customizations.

---

## Part 2: Confirm the field legend (about 20 minutes, required before Part 3)

The script and fixes use **internal column names** like `field_5`. These were inferred from the flow JSON and need confirming.

For each list in `reference/list-map.md`:
1. Open the SharePoint site → open the list.
2. Click the **gear** → **List settings**.
3. Check that the browser URL contains the GUID from the list map (`List=%7B<GUID>%7D`). Write the list's display name next to the GUID in the list map.
4. Under **Columns**, click each column you care about. The URL ends in `&Field=<internal name>`. Compare it with the legend.
5. On the same column page, note:
   - Column type (Choice / Number / Text / Multiple lines …)
   - **Default value** (most important for `ClassificationReady` on the Import Runs list; see Handoff open question Q1)
   - **Enforce unique values** (Yes/No)
   - For Choice columns: the exact list of choices
6. Back on List settings → **Indexed columns**: write down every indexed column.
7. List settings top section: note the **item count**.

**Minimum needed before running the script:** confirm Chunks `field_1, field_3, field_5, field_6, field_7, field_8, field_9`, Results `Title, field_1, field_3, field_4, field_5, field_9, ChunkNumber`, Import Runs `RunID, FinalizationStatus`.
If any differ, edit the names in `scripts/TRACE_Reconciliation.ps1` (search for the old name and replace it).

---

## Part 3: Run the reconciliation script (about 30 minutes the first time)

The script only **reads**. It never writes to SharePoint.

### 3.1 One-time install
1. Install **PowerShell 7**. In Windows Terminal or cmd:
   ```
   winget install Microsoft.PowerShell
   ```
   Then open **PowerShell 7** (the black-icon "pwsh", not the blue Windows PowerShell 5.1).
2. Install the PnP module:
   ```powershell
   Install-Module PnP.PowerShell -Scope CurrentUser
   ```
   Answer **Y** if it asks about an untrusted repository.
3. Get a **Client ID**. PnP needs an Entra ID app registration to sign in.
   - **Option A:** ask your M365 / SharePoint admin for an existing PnP app Client ID.
   - **Option B:** if you're allowed to register apps:
     ```powershell
     Register-PnPEntraIDAppForInteractiveLogin -ApplicationName "TRACE Recon" -Tenant <tenant>.onmicrosoft.com -Interactive
     ```
     Copy the **Client ID** it prints. An admin may need to grant consent. The app only needs SharePoint delegated read (`AllSites.Read`).

### 3.2 Pick a run to check
1. Open the **Import Runs** list (`<LIST_IMPORT_RUNS>`).
2. Copy the `RunID` of a run, e.g. `TRACE-<BatchKey>-143012-a1b2c3d4`.
3. **For the first run, choose one you believe finished correctly.** If everything passes, the field mapping is right. If something fails on a known-good run, suspect the mapping first.

### 3.3 Run it
```powershell
cd <path>\trace-handoff\scripts
Unblock-File .\TRACE_Reconciliation.ps1          # only needed once, if Windows blocks downloaded scripts
.\TRACE_Reconciliation.ps1 `
  -SiteUrl  "https://<tenant>.sharepoint.com/sites/<site>" `
  -ClientId "<your-client-id>" `
  -RunId    "TRACE-...." `
  -SkipCommunication
```
- A browser sign-in window opens. Sign in with your normal work account.
- Keep **`-SkipCommunication`** until the follow-up plan's columns (`FollowUpRequired`, `FollowUpStatus`, `IsTestRecord`) exist on Batch Items.
- Optional: `-LeaseMinutes 30` (default) sets how long a chunk may sit in `Processing` before R9 counts it as orphaned.

### 3.4 Read the output
```
RunID TRACE-... : 12 chunk(s), 1150 result(s), 1 import-run row(s)
[PASS] R1  duplicate keys: 0; duplicate tracking numbers: 0
[FAIL] R2  chunks 12/12; not Completed: 1 [#7=Processing]; count-unbalanced: 0
...
1 CHECK(S) FAILED
```
| Check | PASS means | If it FAILS, look at |
|---|---|---|
| R1 | One result per tracking number per run | Report §1 I-1, FM-6 (duplicates across chunks) |
| R2 | All chunks exist, are Completed, counts match | FM-3 (orphaned chunks), FM-1 (count query) |
| R3 | Each chunk's results = distinct tracking numbers in its payload. Also prints the longest payload length. | FM-1, FM-6 |
| R4 | Σ expected = results = distinct tracking numbers | I-1, I-2 |
| R5 | Only known outcomes; no `New Case Required` left on a Completed run | FM-5 |
| R6 | Every "New Case Created" points to a real case with a matching number | I-3 |
| R7 | Case numbers unique; counter not behind | I-3, FM-12 |
| R8 | Run not stuck in Processing more than 30 minutes; not Completed while other checks fail | FM-2, FM-4 |
| R9 | No chunk (any run) stuck in Processing beyond the lease | FM-3 |

- **Exit code** = number of failed checks (`$LASTEXITCODE` after the run).
- R7 reads every item in both case lists, so it can take several minutes.
- Save the console output: `.\TRACE_Reconciliation.ps1 ... *> recon_<RunID>.txt`.

### 3.5 Common errors
| Error | Fix |
|---|---|
| `Connect-PnPOnline: ... ClientId` | You need a Client ID (3.1 step 3) |
| `AADSTS65001` consent error | Admin must grant consent to the app |
| `The attempted operation is prohibited because it exceeds the list view threshold` | The filtered column isn't indexed. Add the index (Part 4.3) or ask the site owner. **This is the same failure the flows will hit (FM-1).** |
| `Column 'field_X' does not exist` | Field legend mismatch. Fix the name (Part 2). |
| The script errors on a line | It has never been executed (no PowerShell where it was written). Send the error text back for a fix. |

---

## Part 4: Collect the missing information (Report §6)

Do these and record the answers in `01_HANDOFF_NOTES.md` → *Open questions* (fill in the "Answer" column).

### 4.1 Run history (last 30 days)
For each flow: **Lanes 1–4, Finalizer, Release Import Run After Reviews, Process Ready Batch**:
1. make.powerautomate.com → **My flows** (or **Solutions** → the solution → the flow).
2. Open the flow → **28-day run history** → **All runs**.
3. Click **Download CSV** (the "⋯" or the export icon above the list).
4. In the CSV, note: number of runs, number Failed, longest duration.
5. For each **Failed** run: open it, find the red action, and note its name and error message.

Answer these specifically:
- Has **`Release_Import_Run_After_Reviews`** ever run? (Open a Release flow run where `Review_Decision_Is_Complete` was YES and expand `All_Case_Reviews_Completed`.) This settles FM-5.
- Have **`Request_TRACE_Dashboard_Refresh*`** actions ever failed? Error text mentioning a refresh limit confirms FM-4.
- **Why are the lanes off?** Who turned them off, and when?

### 4.2 Power BI capacity
1. app.powerbi.com → the workspace that holds the TRACE dataset (group `<PBI_WORKSPACE_ID>`).
2. Workspace settings → **License info**: Pro, Premium per user, Premium/Fabric capacity.
3. Dataset → ⋯ → **Refresh history**: count refreshes per day.

### 4.3 Indexes ⚠ (low risk, but makes a schema change)
Recommended indexes (List settings → **Indexed columns** → **Create a new index**):
| List | Column(s) |
|---|---|
| Results `<LIST_RESULTS>` | `field_1` (RunID), `ChunkNumber`, `Title`, `field_4` |
| Chunks `<LIST_CHUNKS>` | `field_1`, `field_8` |
| Trace_Workflow `<LIST_TRACE_WORKFLOW>` | `TrackingNumber`, `CaseNumber` |
| Historical `<LIST_HISTORICAL>` | `TrackingNumber` |
| Batch Items `<LIST_BATCH_ITEMS>` | `field_2`, `field_3`, `field_22` |

A list can have at most 20 indexes. Lists over 20,000 items may need the index created during off-hours.

### 4.4 Routing rules
Open the routing rules list (`<LIST_ROUTING_RULES>`). Export to Excel (**Export → Export to CSV**). Note:
- Which active rules output **`New Case Required`**. These are the *only* path to automatic case creation.
- Which output **`Follow-Up Required`**.

### 4.5 Power App behaviour
Open the TRACE Power App in edit mode (make.powerapps.com → Apps → ⋯ → Edit). Find:
- The screen or control where a reviewer decides on a pending result. What does it `Patch` into `CaseReviewDecision` and `field_4`? (Needed for FM-5.)
- The button that moves a communication item from Draft to Queued. Which fields does it set?
- The "close case" action. Does it change `TraceWorkflowStatus` or move the item to the historical list?

### 4.6 The Office Script
In Excel Online, open the workbook used by `Parse_Outbound_CSV` (Automate tab → **All scripts**). Check whether it de-duplicates tracking numbers. (FM-6)

### 4.7 Volumes
From the Import Runs list: largest `RowsRead` or outbound count, runs per day, new cases per day (counter list `LastSequence`).

---

## Part 5: Stop-the-bleeding fixes (small edits to existing flows) ⚠

Do these in order, in a dev copy if you have one. After each fix: **Save** → **Flow checker** (no errors) → test (Part 6).

> **Editing tip:** to copy an existing action, open its **⋯** menu → **Copy to my clipboard**. To paste it, click **+** → **Add an action** → **My clipboard**. Copying keeps all the required fields (Title etc.) that the SharePoint *Update item* action needs.

### Fix 1: Lanes count by RunID **and** chunk number (fixes FM-1) — every lane, or the single worker later
1. Open **TRACE - Process Tracking Lane 1 - Self Drain** → Edit.
2. Find **`Get_Current_Chunk_Processing_Results`**. It's inside `Process_Lane_Until_Empty_or_Limit_Reached` → `Pending_Chunk_Found` (YES) → `Chunk_Is_Pending` (YES) → `Chunk_Payload_Balanced` (YES).
3. **Filter Query** currently:
   ```
   @concat('ChunkNumber eq ', string(outputs('Get_Triggered_Chunk_Record')?['body/field_3']))
   ```
   Replace it with (switch the field to expression mode):
   ```
   concat('field_1 eq ''', replace(outputs('Get_Triggered_Chunk_Record')?['body/field_1'], '''', ''''''), ''' and ChunkNumber eq ', string(outputs('Get_Triggered_Chunk_Record')?['body/field_3']))
   ```
4. **Top Count** stays `5000`.
5. ⋯ → **Settings** → turn **Pagination** On, Threshold `5000` → Done.
6. Requires indexes on Results `field_1` and `ChunkNumber` (4.3).
7. Repeat for Lanes 2, 3 and 4. The action has the same name in each.

### Fix 2: A bad payload marks the chunk Failed instead of leaving it stuck in Processing (fixes part of FM-3)
1. Same lane. Find **`Chunk_Payload_Balanced`** → its **No** branch. It contains `Set_Chunk_Unbalanced_Error_Message_` and `Set_Chunk_Unbalanced`.
2. Copy **`Fail_Tracking_Chunk_After_Worker_Error`** (in the YES branch) to the clipboard.
3. Paste it as the **first** action in the **No** branch. Rename it `Fail_Payload_Unbalanced_Tracking_Chunk`.
4. In the pasted action change:
   - `field_7` (ErrorCount) → `0`
   - `field_13` (RetryCount) → expression `int(coalesce(outputs('Get_Triggered_Chunk_Record')?['body/field_13'], 0))` (don't add 1; this isn't a worker error)
   - `field_15` (ErrorMessage) → expression
     ```
     concat('Payload count did not match ExpectedCount. Chunk ', string(outputs('Get_Triggered_Chunk_Record')?['body/field_3']), ' expected ', string(outputs('Get_Triggered_Chunk_Record')?['body/field_5']), ' record(s), payload contained ', string(outputs('Current_Chunk_Record_Count')), '.')
     ```
5. Make `Set_Chunk_Unbalanced_Error_Message_` run after the new action. Open its ⋯ → **Configure run after** → select the new action → **is successful**.
6. Repeat in Lanes 2–4.

### Fix 3: Finalizer writes a reason instead of failing silently (fixes FM-2)
**Prerequisite (SharePoint):** Import Runs list → `FinalizationStatus` column → add the choice **`Blocked`**.

1. Open **TRACE - Finalize Completed Tracking Runs - Scheduled** → Edit.
2. Copy **`Mark_Finalization_Failed`** (root level, near the bottom) to the clipboard. It already has every required field.
3. **Gate A: `Candidate_Run_Chunks_Complete` → No branch** (currently empty):
   - Add **Condition** `Chunks_Failed_Or_Missing`, expression:
     `or(greater(outputs('Failed_Chunk_Count'), 0), not(equals(outputs('Actual_Chunk_Count'), outputs('Expected_Chunk_Count'))))` is equal to `true`
     - Expected ≠ actual only *after* creation has finished. A run whose chunks are still being processed has `Failed = 0` and actual = expected, so it is left alone and re-checked in 10 minutes. That's correct.
   - **Yes** branch: paste the clipboard action, rename it `Block_Run_Chunks_Failed`, and set:
     - `FinalizationStatus` → `Blocked`
     - `RunStatus` → leave as the current value (`outputs('Current_Candidate_Import_Run')?['RunStatus']?['Value']`)
     - `FinalizationErrorMessage` → `concat('Blocked: chunks failed=', string(outputs('Failed_Chunk_Count')), ', present=', string(outputs('Actual_Chunk_Count')), ' of ', string(outputs('Expected_Chunk_Count')), '. Review the chunk list for this RunID, then set failed chunks back to Pending to retry.')`
     - Any field in the pasted action that references `Verify_Import_Run_Finalization_Claim` → change it to `Current_Candidate_Import_Run` (the verify action hasn't run at this point)
4. **Gate B: `Candidate_Run_Results_Balanced` → No branch:** paste again, rename it `Block_Run_Results_Unbalanced`, `FinalizationStatus` = `Blocked`, message:
   `concat('Blocked: results ', string(outputs('Actual_Processing_Result_Count')), ' vs expected ', string(outputs('Expected_Processing_Result_Count')), ', errors ', string(outputs('Processing_Error_Result_Count')), '. Run TRACE_Reconciliation.ps1 R1-R4 for this RunID.')`
   - The same `Verify_…` → `Current_Candidate_Import_Run` substitution applies.
   - ⚠ If the run has more than 10,000 results it will now show Blocked here instead of hanging silently. That's intended (FM-10).
5. **Gate C: `Candidate_Outcome_Distribution_Balanced` → No branch:** paste, rename it `Block_Run_Unclassified`, message:
   `concat('Blocked: ', string(outputs('Unclassified_Result_Count')), ' result(s) have an outcome the finalizer does not recognise.')`
   Here `Verify_Import_Run_Finalization_Claim` has run, so its references can stay.
6. **Gate D: `Import_Run_Claim_Verified` → No branch:** leave it empty. A lost claim means another run owns the item.
7. **Save.**

### Fix 4: Finalizer picks the oldest eligible run and skips Awaiting Review and Blocked (fixes FM-4 and the starvation in FM-2)
1. Same flow → **`Get_Candidate_Import_Runs`**.
2. **Filter Query** → replace it with:
   ```
   ClassificationReady eq 1 and FinalizationStatus ne 'Completed' and FinalizationStatus ne 'Failed' and FinalizationStatus ne 'Awaiting Review' and FinalizationStatus ne 'Blocked'
   ```
3. **Order By** → `Created asc`.
4. Top Count stays `1`.
5. **Effect:** a run waiting on reviews is no longer re-picked every 10 minutes, so there are no repeated dashboard refreshes. The Release flow (Fix 5) returns it to `Not Started` when reviews are done.
   - ⚠ This depends on Fix 5 working. Otherwise `Awaiting Review` runs never come back. Check: Part 6 test T7.

### Fix 5: Release flow actually releases (fixes FM-5)
1. Open **TRACE - Release Import Run After Reviews** → Edit.
2. **`Get_Remaining_Case_Reviews`** → Filter Query → replace it with the same "pending" definition the finalizer uses:
   ```
   concat('field_1 eq ''', outputs('Current_Review_RunID'), ''' and CaseReviewDecision eq ''Pending Review''')
   ```
   This assumes the app sets `CaseReviewDecision` to a final value when a reviewer decides. Confirm via 4.5.
3. **`All_Case_Reviews_Completed`** → the right-hand value is `01` (text). Change it to the expression `0`. Click the field → Expression tab → type `0` → OK.
4. **Trigger condition** (stops the flow running thousands of times per import run):
   - Trigger ⋯ → **Settings** → **Trigger conditions** → **+ Add**:
     ```
     @not(empty(string(first(triggerBody()?['value'])?['CaseReviewDecision']?['Value'])))
     ```
   - Make sure **Split on** stays **Off**. The flow reads `first(triggerOutputs()?['body/value'])`, and this condition matches that.
5. **Save.**
6. **Human-approved case creation** (FM-5, second half) needs the answer from 4.5. If the app writes `Create TRACE Case` but doesn't change `field_4` to `New Case Required` or `CaseCreationEligible` to true, then the finalizer's `Filter_New_Case_Required_Results` must also accept it. Change its `where` to:
   ```
   @and(
     equals(item()?['field_4']?['Value'], 'New Case Required'),
     equals(item()?['CaseCreationEligible'], true),
     or(
       equals(item()?['CaseReviewDecision']?['Value'], 'Auto - Create TRACE Case'),
       equals(item()?['CaseReviewDecision']?['Value'], 'Create TRACE Case')
     )
   )
   ```
   Also make sure the app sets `field_4 = New Case Required` and `CaseCreationEligible = Yes` when the reviewer picks "Create TRACE Case". Otherwise the classified-count check fails (Gate C will now report this).
   **Don't make this change until 4.5 is answered.**

### Fix 6: Remove lane drift (fixes FM-16)
1. Open `reference/lane-diffs/lane1_vs_lane2.diff`. The only intended differences are the lane number and `startTime`.
2. **Lane 1:** `Find_Existing_Chunk_Result` → Filter Query → use the escaped form from Lanes 2–4:
   ```
   concat('Title eq ''', replace(outputs('Current_Result_Key'), '''', ''''''), '''')
   ```
3. **All lanes:** do the same `replace(..., '''', '''''')` in `Find_Active_Trace_for_Chunk_Record` and `Find_Historical_Trace_for_Chunk_Record`.
4. This drift problem disappears for good with the single worker (Part 7).

### Fix 7: Remove the fixed wait (FM-15). Only after Fix 1.
- Delete **`Wait_for_Processing_Results_to_Settle`** in each lane.
- Then set **`Get_Current_Chunk_Processing_Results`** → Configure run after → **`Process_Current_Chunk_Records` is successful**.

### Turning the lanes back on
Only after Fixes 1, 2, 6 and 7 are in all four lanes, and after you know why they were turned off (4.1):
1. Turn on **one** lane. Watch one full activation.
2. Run the script for that RunID (expect R2 to show other lanes' chunks still Pending).
3. Turn on the remaining lanes.

---

## Part 6: Testing (Report §7.2)

Use a **test batch**: copy a small real outbound file, change the tracking numbers to fake ones (e.g. prefix `1ZTEST`), and drop it in the intake library the usual way. Run the script after each test.

| Test | How (exact) | Pass condition | Before fixes |
|---|---|---|---|
| T1: kill worker mid-chunk | Start a batch of ~300 rows. While a lane run shows `Process_Current_Chunk_Records` running, open the run → **Cancel**. | After the redesign (Part 7): the chunk is Pending again within the lease plus 5 minutes, then Completed; R1–R4 pass. After Part 5 only: the chunk stays Processing (known gap). R9 must report it. | Chunk stuck forever, no report |
| T2: two workers, one chunk | After Part 7: call the worker child flow twice by hand with the same ChunkID | One proceeds; the other gets HTTP 412 and exits Succeeded; R1 passes | n/a |
| T3: >5,000 results | Test batch of 12,000 rows (dev only) | Run Completed (after Part 7), or Blocked with a clear message (after Part 5). Never silent. | Silent hang above 10,000 |
| T4: duplicate tracking number | Put the same number on rows 5 and 150 of the test file | One result; `DuplicateRows = 1`; run Completed (after source de-duplication, Part 7) | Chunk Failed |
| T5: payload mismatch | In the Chunks list, edit one **Pending** chunk's `field_5` from 100 to 99 before a lane picks it up | Chunk Failed with the payload message (Fix 2); run Blocked (Fix 3) | Chunk stuck Processing |
| T6: history growth | Dev only: bulk-add 5,001 dummy results with `ChunkNumber = 1` and another RunID | The new run's chunk 1 reconciles (Fix 1) | Chunk 1 Failed |
| T7: pending reviews | Include rows that route to `Manual Classification` and `Needs Case Review` | Run → Awaiting Review, **one** dashboard refresh. Decide both in the app → within 10 minutes the run is Not Started, then Completed. A "Create TRACE Case" decision creates a case. | Refresh every 10 minutes; never released |
| T8: >250 new cases | 600 rows routed to `New Case Required` (dev) | 3 finalizer passes; 600 unique, contiguous case numbers; R6 and R7 pass | Should already pass |
| T9: apostrophe | A tracking number `1ZTEST'01` | Processed without error in every lane | Lane 1 fails |
| T10: stuck run doesn't block | Leave a run Blocked (T5), then submit a new batch | The new batch finalizes | Newest-first starvation |

**Proposed acceptance gate:** R1–R9 green for 3 consecutive production runs, plus T5, T7, T9 and T10 passed (after Part 5), and T1–T3 passed (after Part 7).

---

## Part 7: Build the target design (Report §5)

Build in dev. Run old and new side by side on copies of real batches before switching over.

### 7.1 Schema additions
| List | Add | Type |
|---|---|---|
| Chunks | `LeaseExpires` | Date/time |
| Chunks | `OutcomeCountsJson` | Multiple lines of text (plain) |
| Import Runs | `FinalizationBlockedReason` | Multiple lines of text (or reuse `FinalizationErrorMessage`) |
| Import Runs, `FinalizationStatus` | Choices `Ready`, `Blocked` | Choice |
| Trace_Workflow | **Enforce unique values** on `CaseNumber` and `TrackingNumber` (requires indexing first) | Setting |

### 7.2 Worker child flow: "TRACE - Process Tracking Chunk"
1. **New** → Instant cloud flow → trigger **Manually trigger a flow** (inside the solution, so it can be called as a child flow). Inputs: `ChunkID` (number), `ClaimToken` (text).
2. Copy the body of Lane 2 (the cleanest copy), from `Generate_Worker_Run_ID` down. Use `Get_Triggered_Chunk_Record` with `Id = ChunkID`.
3. Remove `Claim_Tracking_Chunk` (the dispatcher claims). Instead, check that `ClaimToken` on the item equals the input; if not, Respond and stop.
4. Apply Fixes 1, 2, 6 and 7.
5. Wrap the processing in **Scope Try** + **Scope Catch** (Catch runs after Try *has failed / has timed out*). Catch: chunk → `Failed`, `field_13 + 1`, message = `result('Try')` summary.
6. After `Complete_Tracking_Chunk`, write `OutcomeCountsJson`: a JSON object with one count per outcome in this chunk.
7. **Completion check:** GetItems on Chunks with `field_1 eq '<RunID>' and field_8 ne 'Completed'`, Top 1. If there are none, PATCH the import run: `FinalizationStatus = Ready`, `ClassificationReady = true`.
8. End with **Respond to a PowerApp or flow** (`status` = Completed/Failed). Child flows *must* end with this action.
9. Flow ⋯ → Details → **Run only users** → set the connections to **Use this connection** (not "Provided by run-only user"). Child flows need this.

### 7.3 Dispatcher: "TRACE - Dispatch Tracking Chunks"
1. **Scheduled cloud flow**, every **5 minutes**. Trigger ⋯ → Settings → Concurrency **On, 1**.
2. **Recover orphans:** Get items on Chunks, filter `field_8 eq 'Processing' and LeaseExpires lt '<utcNow>'`. For each:
   - if `field_13 < 3`: PATCH `field_8 = Pending`, `field_13 + 1`
   - else: PATCH `field_8 = Failed`, `field_15 = 'Lease expired 3 times'`, and send an alert email
3. **Pick work:** Get items, filter `field_8 eq 'Pending'`, order by `ID asc`, top `4`.
4. **Apply to each** → Settings → Concurrency **On, 4**. Inside:
   1. **Send an HTTP request to SharePoint**, GET:
      `_api/web/lists(guid'<LIST_CHUNKS>')/items(<ID>)?$select=Id,field_8`
      Headers: `Accept: application/json;odata=minimalmetadata`
   2. Compose the ETag: `body('<GET action>')?['odata.etag']`
   3. **Send an HTTP request to SharePoint**, POST (PATCH via header):
      URI `_api/web/lists(guid'<LIST_CHUNKS>')/items(<ID>)`
      Headers:
      ```
      Accept: application/json;odata=nometadata
      Content-Type: application/json;odata=nometadata
      IF-MATCH: <etag>
      X-HTTP-Method: MERGE
      ```
      Body: `{"field_8":"Processing","ClaimToken":"<guid>","ClaimedDate":"<utcNow>","LeaseExpires":"<utcNow + 30 min>"}`
      - Status 412 means someone else claimed it → **skip**. Configure the next action to run after *failed*, and check `outputs('<PATCH>')?['statusCode']` equals 412 → do nothing.
      - ⚠ A **choice** column written by REST may need a different value format depending on the column. Test this one call alone first.
   4. **Run a Child Flow** → TRACE - Process Tracking Chunk → `ChunkID`, `ClaimToken`.
5. Test that a child running longer than about 2 minutes still returns correctly in your tenant. If it doesn't, use the fallback in Report §5.1.

### 7.4 Process Ready Batch changes
1. After `Compact_Parsed_Outbound_Records`, de-duplicate by TrackingNumber. Use a Select of tracking numbers → `union(x,x)` → for each unique number take the first matching record (Filter array + `first()`). Write the duplicate count to the import run's `DuplicateRows`, and the parsed and CSV row counts to `RowsRead`.
2. Remove `WorkerLane` and `LaneSequence` from `Create_Tracking_Chunk_Record`.
3. **Delete the dead code** after `QV_Batch_Promotion_Succeeded`. In `reference/run-order/ProcessReadyBatch.order.txt`, section `[ROOT > Batch_Is_Unclaimed [YES]]`, that's items **34 (`Parsed_Outbound_Record_Count`) through 73 (`Scope_-_Handle_Batch_Failure`)** — 40 actions, with everything nested inside them. Delete from the bottom up: the designer won't delete an action that another action's run-after still points to. Keep a backup (Part 1.3).
4. Add a Catch scope around chunk creation that marks the staging rows and the import run `Failed`.

### 7.5 Finalizer changes
1. `Get_Candidate_Import_Runs` → `FinalizationStatus eq 'Ready'`, `Created asc`, Top 1.
2. Replace the page 1 / page 2 result reads with: Get the chunks (already done), then sum `OutcomeCountsJson` across chunks for the balance checks. Query only `New Case Required` rows (existing `Get_Remaining_New_Case_Required_Results` pattern, top 250).
3. Dashboard refresh: only when entering `Completed` or `Awaiting Review`.
4. Counter PATCH with ETag (same pattern as 7.3), and `formatNumber(seq,'0000')` if more than 999 cases per day is possible. **Changing to 4 digits changes the case-number format.** Agree that with the business first.
5. Every gate's failure branch → `Blocked` + reason (Fix 3 is already in place).

### 7.6 Cut-over
1. Turn off Lanes 1–4.
2. Turn on the dispatcher.
3. Process 3 production batches; R1–R9 green each time.
4. Delete Lanes 1–4 from the solution after 2 clean weeks.

---

## Part 8: The communication follow-up plan (plan .docx), adjusted

The plan's content stands. These adjustments come from the analysis (Report §4 and §5.5):

1. **Columns:** add them exactly as the plan's §2 says. **Also** decide how `ResponseReceived` relates to the existing `Trace_Workflow.ResponseStatus` (already set to `Awaiting Response` by the send flow when item `field_17` is true). Recommended: the app's "Mark Response Received" sets both.
2. **Don't edit the send flow** (plan §3) unless you have to. It has three Sent paths (`Mark_Batch_Item_Sent_-_Safe`, `Mark_Retried_Batch_Item_Sent`, `Reconcile_Previously_Sent_Batch_Item`). Instead, give the evaluator an **initialize** step:
   - Get Batch Items: `field_22 eq 'Sent' and FollowUpStatus eq 'Not Required'` (or empty), where `field_23` is within the last 30 days.
   - For each: look up the template by `field_8`. If `FollowUpRequired` and `FollowUpActive` are set, set `FollowUpRequired = Yes`, `FollowUpStatus = Pending`, `FollowUpDueDate = field_23 + N business days`, plus reason, template key and source.
3. **Business-day calculation** (Saturdays and Sundays skipped): the Copilot prompt in the plan doesn't give the formula. Use a Do-until loop: a `DueDate` variable that starts at SentDate (Central time) and a counter of days added. Repeat until the counter = N: add 1 day; if `dayOfWeek(DueDate)` is not 0 or 6, increment the counter.
4. **Schedule:** run the evaluator hourly for initialize plus status. Send the digest only on the first run after 7:15 Central, guarded by a "digest already sent today" check.
5. **Closed cases:** if the Trace_Workflow GetItem by `field_3` fails with 404 (case moved to the historical list), set `Suppressed`. Configure the next step to run after *has failed* and check the status code.
6. **Carrier signal (optional, no lane change):** if `Trace_Workflow.LastSourceUpdateDate > field_23`, flag "carrier update since sent" in the queue and digest.
7. **Rename** the tracking outcome `Follow-Up Required` to `Carrier Follow-Up Required`. Change it in the Results `field_4` choices, the routing-rule `field_12` choices, the finalizer's `Filter_Follow-Up_Required_Results`, and Power BI.
8. **Validation:** the plan's §8 table, plus script checks C1–C3 (run without `-SkipCommunication` once the columns exist).

---

## Part 9: Regenerating the reference files (optional)

If you export a newer version of the solution, regenerate the outlines so they match.

⚠ **Regenerated files contain the real tenant URL, IDs and addresses.** Keep them on your computer, not in this public repo, unless you redact them first.
Requires Python 3.

```bash
mkdir work && cd work
unzip <path-to-your-local-export>.zip -d export     # the original export is not in the repo
python3 -I ../tools/dump.py      ../reference/flow-outlines  export/Workflows/*.json
python3 -I ../tools/order_all.py ../reference/run-order      export/Workflows/*.json
python3 -I ../tools/summ.py export/Workflows/*Lane1* export/Workflows/*Finalize*   # quick tree to the console
```
The lane diffs were generated by a short inline script. Its logic: sort-keys JSON dump of each lane's `properties.definition`, then `difflib.unified_diff` of Lane 1 against each other lane.
