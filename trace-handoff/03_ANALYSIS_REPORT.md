# TRACE: Lane and Finalizer Redesign Analysis

Source: solution export `TRACEQVCodeReview20261022` v1.0.0.9 (11 flows) and *TRACE Communication Follow-Up Implementation Plan*.
Every claim cites the flow and action name as it appears in the JSON. **⟨inferred⟩** marks anything not read directly from the export.

---

## 0. Facts about the export that shape everything below

| # | Fact | Evidence |
|---|---|---|
| F1 | **All four lane flows are turned off** in this export. The other seven flows are on. | `customizations.xml`: Lanes 1–4 have `StateCode 0 / StatusCode 1` (Draft). Every other flow is `1 / 2` (Activated). |
| F2 | Chunks are created by **`TRACE - Process Ready Batch - Optimized v3 Chunked`**, not by the lanes. Each chunk holds 100 records, and lanes are assigned round-robin. | `Tracking_Chunk_Count` = `div(add(total,99),100)`; `Create_Tracking_Chunk_Record` writes `WorkerLane = add(mod(item(),4),1)`, `field_5 = min(100, …)`, `field_9 = string(take(skip(...)))`, `field_8 = Pending`. |
| F3 | **About 40 actions in Process Ready Batch are dead code.** Both branches of `QV_Batch_Promotion_Succeeded` end in `Terminate` (`Stop_-_QV_Batch_Published_and_Chunks_Queued` and `Stop_-_QV_Batch_Promotion_Failed`). Everything that runs after it never executes: `Parsed_Outbound_Records_Balanced`, the de-duplication actions (`Unique_Outbound_Tracking_Numbers` …), `Evaluate_Outbound_Tracking_Numbers`, the inline case creation `Create_New_Trace_Cases`, `Scope_-_Finalize_Successful_Batch` and `Scope_-_Handle_Batch_Failure`. | Run-after chain traced from the JSON. |
| F4 | **Nothing in the export sets `ClassificationReady = true` on a new import run.** The finalizer only selects runs where `ClassificationReady eq 1`. The only writers are the finalizer itself and `Release_Import_Run_After_Reviews`, and both act on runs that were already selected. | `Create_Import_Run_Log` does not set the field. A search of all 11 JSON files finds no other writer. ⟨inferred⟩ A column default, the Power App, or a flow outside this solution sets it. |
| F5 | Lanes 1–4 are near copies. **Lane 1** does not escape apostrophes in `Find_Existing_Chunk_Result`. Lanes 2–4 do (`replace(…,'''','''''')`). **Lane 3** uses different error text and boolean literals (`true` instead of `"@true"`). Otherwise the only differences are the lane number and the trigger `startTime`, staggered at :00, :30, :60 and :90 seconds. | JSON diff of the four lane definitions. |

### Field legend (internal names → meaning), ⟨inferred⟩ from how each field is used

**Chunks** (`<LIST_CHUNKS>`): `field_1` RunID · `field_2` BatchKey · `field_3` ChunkNumber · `field_4` StartIndex · `field_5` ExpectedCount · `field_6` CompletedCount · `field_7` ErrorCount · `field_8` Status · `field_9` Payload JSON · `field_10` StartedDate · `field_11` LastUpdated · `field_12` CompletedDate · `field_13` RetryCount · `field_14` WorkerRunID · `field_15` ErrorMessage · plus `ClaimToken`, `ClaimedDate`, `WorkerLane`, `LaneSequence`, `TotalChunkCount`.

**Processing Results** (`<LIST_RESULTS>`): `Title` result key (`RunID|TrackingNumber`) · `field_1` RunID · `field_2` BatchKey · `field_3` TrackingNumber · `field_4` Outcome · `field_5` Trace_Workflow item ID · `field_6` record count · `field_7` error text · `field_8` processed date · `field_9` CaseNumber · plus `ChunkNumber`, `CaseCreationEligible`, `CaseCreationReason`, `CaseReviewDecision`.

**Import Runs** (`<LIST_IMPORT_RUNS>`): `RunID`, `RunStatus`, `FinalizationStatus`, `FinalizerRunID`, `ClassificationReady`, `ClassificationRefreshRequested`, `EmailBatchReady`, `DashboardRefresh*`.

**Case counter** (`<LIST_CASE_COUNTER>`): `Title` (yyyyMMdd) · `LastSequence` · `LastCaseNumber`.

**Communication Batch Items** (`<LIST_BATCH_ITEMS>`): `field_1` item key (`BTI-…`) · `field_2` BatchID · `field_3` TraceItemID · `field_4` TraceID · `field_5` CaseNumber · `field_6` TrackingNumber · `field_8` template key · `field_10` recipient · `field_11` selection · `field_17` response-expected flag · `field_19` review status · `field_21` approved · `field_22` **SendStatus** · `field_23` **SentDate**.

---

## 1. What must stay true, and what enforces it today

### I-1. One result per tracking number per run

| Layer | Enforced by | Strength |
|---|---|---|
| Lane write | `Find_Existing_Chunk_Result` (GetItems `Title eq 'RunID|Tracking'`, `$top 1`) → `Chunk_Result_Does_Not_Exist` → one of three `Write_*_Chunk_Result` PostItems. | **Weak.** This is check-then-insert, so it isn't atomic. `Process_Current_Chunk_Records` runs 4 iterations in parallel. A duplicate tracking number inside one chunk can race. ⟨inferred⟩ Whether `Title` has *Enforce unique values* turned on is unknown. If it doesn't, nothing stops a second row. |
| Source | Nothing. The de-duplication actions (`Unique_Outbound_Tracking_Numbers`, `Valid_Outbound_Tracking_Numbers`) are dead code (F3). `Compact_Parsed_Outbound_Records` is a plain `Select` over the Office Script output, with no de-duplication. | **Not enforced.** |
| Finalizer | Only detected indirectly. `Candidate_Run_Results_Balanced` requires `Actual_Processing_Result_Count == Expected_Processing_Result_Count`. A duplicate row makes the counts disagree, and the run stalls (see I-4). | Detect-only, and it stalls silently. |

**Consequence (read from the JSON):** say a tracking number appears in two different chunks. The second chunk's iteration finds the first chunk's row (same `Title`) and skips writing. But `Filter_Current_Chunk_Results` only counts rows where `ChunkNumber` is this chunk. So the second chunk comes up one short. `Chunk_Results_Balanced` is false, `Fail_Unbalanced_Tracking_Chunk` runs, and the chunk is marked **Failed**. ⟨inferred⟩ This only matters if the outbound file or Office Script can contain duplicate tracking numbers. The old code de-duplicated, which suggests it can.

### I-2. Chunk reconciliation (payload = expected = results)

| Check | Action | Gap |
|---|---|---|
| Payload size equals expected | Lane `Chunk_Payload_Balanced` (`length(json(field_9)) == field_5`) | **The ELSE branch (`Set_Chunk_Unbalanced_Error_Message_`, `Set_Chunk_Unbalanced`) never updates the chunk.** It was already set to `Processing` by `Claim_Tracking_Chunk`, so it stays in **Processing forever**. |
| Results equal expected, with no errors | Lane `Chunk_Results_Balanced` | `Get_Current_Chunk_Processing_Results` filters **`ChunkNumber eq N` only**, with `$top 5000` and no pagination. The RunID is applied afterwards, in memory, by `Filter_Current_Chunk_Results`. Every run has a chunk 1, chunk 2 and so on. After about 50 runs (≤100 rows per chunk number per run), chunk N's history passes 5,000 rows. ⟨inferred⟩ Without `$orderby`, SharePoint returns oldest IDs first, so the *current* run's rows get cut off and the chunk fails. Alternatively, if `ChunkNumber` isn't indexed, the query hits the list-view threshold and fails outright. |
| All chunks of the run exist and are Completed | Finalizer `Candidate_Run_Chunks_Complete` (actual == `TotalChunkCount` == completed, 0 incomplete, 0 failed) | **Its ELSE branch is empty.** A failed or orphaned chunk means the run is never finalized, and no status or error is written. |
| Sum of results equals sum of `field_5` | Finalizer `Sum_Chunk_Expected_Counts` → `Candidate_Run_Results_Balanced` | **Empty ELSE** (same problem). |
| Every result is classified | Finalizer `Candidate_Outcome_Distribution_Balanced` (`Classified_Result_Count == Actual`) | **Empty ELSE** (same problem). |
| Source CSV rows equal parsed rows | `Parsed_Outbound_Records_Balanced` | **Dead code (F3).** Nothing checks that the Office Script returned every outbound row. `Create_Import_Run_Log` writes `RowsRead = 0`, and the action that would update it (`Update_Import_Run_Row_Count`) is also dead. So the reconciliation is self-referential: chunks are checked against chunks, never against the source file. |

### I-3. Unique case numbers

| Mechanism | Action |
|---|---|
| A single writer | Only the finalizer writes the counter list (`Reserve_Current_Case_Number`). The finalizer trigger has `concurrency.runs = 1`. Process Ready Batch also writes the counter, but only from dead code (`Create_New_Trace_Cases`). |
| Reserve before create | `Increment_Current_Case_Sequence` → `Reserve_Current_Case_Number` (PATCH `LastSequence`) → `Create_New_Active_TRACE`. A failure afterwards leaves a gap, never a duplicate. |
| Idempotent re-run | `Check_TRACE_Case_Already_Created` (by TrackingNumber in `Trace_Workflow`), then `Link_Existing_TRACE_Case_to_Result` instead of creating a new case. |
| Sequential loop | `Create_Required_TRACE_Cases` runs at concurrency 1, over `take(…,250)`. |
| **Not enforced** | No ETag on the counter PATCH. ⟨inferred⟩ Unknown whether `Trace_Workflow.CaseNumber` has a unique constraint. Uniqueness depends entirely on there being one writer. The sequence uses `formatNumber(seq,'000')`, so the 1,000th case in a day becomes 4 digits. It stays unique but breaks the fixed width. |

### I-4. Finalization happens exactly once

| Mechanism | Action |
|---|---|
| Single flight | Finalizer trigger `concurrency.runs = 1`. |
| Claim and verify | `Claim_Import_Run_for_Finalization` → `Verify_Import_Run_Finalization_Claim` → `Import_Run_Claim_Verified` (checks both `FinalizationStatus == Processing` and `FinalizerRunID` match). |
| Terminal states | `Complete_Import_Run_Finalization`, `Complete_…_No_New_Cases` (→ `Completed`), `Fail_Final_Reconciliation`, `Mark_Finalization_Failed` (→ `Failed`). The candidate filter excludes only `Completed` and `Failed`. |
| **Actual behaviour: "at least once, mostly idempotent"** | (a) `Awaiting Review` is **not excluded** from `Get_Candidate_Import_Runs`. A run waiting on reviews is re-selected every 10 minutes and re-runs `Request_TRACE_Dashboard_Refresh_-_No_New_Cases` plus `Complete_…_No_New_Cases` each time. (b) Case creation runs 250 cases per activation, then `Release_Import_Run_for_Next_Case_Block` sets the run back to `Not Started`. That is deliberate multi-pass work, and it's safe because of `Check_TRACE_Case_Already_Created`. (c) Selection is `$orderby Created desc, $top 1`, newest first. **A newest run that is stuck (any empty-ELSE case above) blocks every older run from finalizing.** |

---

## 2. State machines

### 2a. Import run (`FinalizationStatus`; `RunStatus` in brackets)

```
                       ProcessReadyBatch.Create_Import_Run_Log
                                     │  RunStatus=Started, FinalizationStatus=(blank), ClassificationReady=(blank)
                                     ▼
                         (blank) ──⟨inferred: unknown writer⟩──► ClassificationReady = true
                                     │
             Finalizer.Get_Candidate_Import_Runs selects it (newest first)
                                     │
                    [chunks incomplete / unbalanced / unclassified] ──► no write; reselected every 10 min  ⚠
                                     │
                Claim_Import_Run_for_Finalization ─► Processing
                                     │
          ┌──────────────────────────┼─────────────────────────────┬──────────────────────────┐
 first pass: Mark_Classification_Ready│                              │                          │
   Processing (RefreshRequested=true) │                              │                          │
                                      ▼                              ▼                          ▼
             Release_Import_Run_for_Next_Case_Block     Complete_Import_Run_Finalization   Fail_Final_Reconciliation
             ► Not Started  [Started]  (>250 cases)     (or …_No_New_Cases)                Mark_Finalization_Failed
                 └─► reselected next poll               ► Completed [Completed] if 0 pending   ► Failed [Failed]  (terminal)
                                                        ► Awaiting Review [Started] if pending>0
                                                                 │  ⚠ still matches candidate filter → re-refresh every 10 min
                                                                 ▼
                                      ReleaseImportRunAfterReviews.Release_Import_Run_After_Reviews
                                      ► Not Started  [Started]   (only if All_Case_Reviews_Completed — see FM-5)
```

Statuses that the JSON writes: `Not Started`, `Processing`, `Awaiting Review`, `Completed`, `Failed`. `RunStatus` values written: `Started`, `Completed`, `Failed`. (Process Ready Batch's `Completed` and `Failed` writes are dead code.)

### 2b. Chunk (`field_8`)

```
ProcessReadyBatch.Create_Tracking_Chunk_Record ► Pending (WorkerLane = i mod 4 + 1)
     │
Lane N.Claim_Tracking_Chunk ► Processing  (no verify, no lease expiry)
     ├─ Complete_Tracking_Chunk ► Completed
     ├─ Fail_Unbalanced_Tracking_Chunk ► Failed            (results ≠ expected)
     ├─ Fail_Tracking_Chunk_After_Worker_Error ► Failed     (Chunk_Results_Balanced Failed/TimedOut/Skipped; RetryCount+1)
     └─ ⚠ stays Processing forever:
          • Chunk_Payload_Balanced = false (ELSE branch never PATCHes the chunk)
          • json(field_9) throws in Current_Chunk_Records (the whole Chunk_Payload_Balanced is skipped)
          • run cancelled / Until timeout PT90M / platform kill mid-chunk
Failed ──► (no transition exists anywhere; field_13 RetryCount is written but never read)
```

### 2c. Processing result (`field_4` Outcome + `CaseReviewDecision`)

```
Lane write (one row per tracking number):
  Active trace found      ► Active Updated              / Auto - Dashboard Only
  Historical trace found  ► Historical Match            / Auto - Dashboard Only
  Otherwise (routing rule field_12, else Current_Default_Outcome):
     New Case Required                 / Auto - Create TRACE Case   (only from a routing rule; the default outcome never produces it)
     Dashboard Only - No Case          / Auto - Dashboard Only
     Reference History - No Action     / Auto - Dashboard Only
     Operational Dashboard - No Action / Auto - Dashboard Only
     Communication Review              / Auto - Dashboard Only
     Follow-Up Required                / Auto - Dashboard Only     (only from a routing rule)
     Manual Classification             / Pending Review
     Needs Case Review                 / Pending Review
Finalizer:
  New Case Required ─Complete_New_Case_Processing_Result─► New Case Created (field_5 = trace ID, field_9 = CaseNumber)
  New Case Required ─Link_Existing_TRACE_Case_to_Result─► Active Updated
Human (Power App, not in the export) ⟨inferred⟩:
  Pending Review ─► Create TRACE Case | Dashboard Only - No Case   (the values ReleaseImportRunAfterReviews checks for)
Never written by any live path: Parsed Record Error, Processing Failed (dead code only), so every error count is always 0.
```

### 2d. Communication batch item (`field_22` SendStatus, with the plan's FollowUpStatus nested under Sent)

```
CreateCompleteDraftBatch.Create_Batch_Item ► Draft (field_19 Needs Review, field_11 Pending Selection, field_21 false)
  ─(Power App ⟨inferred⟩)─► Queued + field_19 Ready + field_21 true
  ─Send flow.Lock_Batch_Item_for_Processing─► Processing
       ├─ Mark_Batch_Item_Sent_-_Safe          ► Sent   (field_23 = utcNow)
       ├─ Mark_Batch_Item_Failed_-_Safe        ► Failed
       ├─ Mark_Ineligible_Batch_Item_Failed    ► Failed (lock/OneTrust check)
       ├─ Reconcile_Previously_Sent_Batch_Item ► Sent   (field_23 = log field_15)
       ├─ Mark_Retried_Batch_Item_Sent         ► Sent   (field_23 = utcNow)
       ├─ Mark_Retried_Batch_Item_Failed       ► Failed
       └─ Hold_Batch_Item_for_Pending_Communication ► Skipped (log stuck Pending ⇒ at-most-once email)
  Missing payload: Blocked_Communication_Payload has no PATCH ⇒ item stays Queued.

Plan, nested under Sent (new):
  Not Required ─init─► Pending ─evaluator─► Due Soon ► Due Today ► Overdue
                                 any ─► Suppressed (response, closed, test, newer send) | Completed | Cancelled (human)
  Prepare Follow-Up ─► new Draft item with PreviousCommunicationItemID = original ID
```

---

## 3. Failure modes, ranked by likelihood × impact

L and I are each rated 1–3. "Score" is L×I.

| Rank | Failure mode | Where | L | I | Score | Notes |
|---|---|---|---|---|---|---|
| 1 | **The chunk-results query ignores RunID.** Once chunk-number history exceeds 5,000 rows (≈50 runs), the current run's rows are truncated or the query hits the threshold, and every chunk fails reconciliation. | Lanes `Get_Current_Chunk_Processing_Results` | 3 | 3 | **9** | A time bomb. ⟨inferred⟩ The ordering and indexing behaviour depends on how the list is configured. |
| 2 | **Silent dead-ends.** Four empty ELSE branches in the finalizer (`Candidate_Run_Chunks_Complete`, `Candidate_Run_Results_Balanced`, `Import_Run_Claim_Verified`, `Candidate_Outcome_Distribution_Balanced`). Add newest-first selection, and one stuck run blocks every older run with no error written. | Finalizer | 3 | 3 | **9** | This turns every other failure into an invisible outage. |
| 3 | **Orphaned or terminal chunks.** The payload-unbalanced ELSE never writes the chunk. A cancel, timeout or JSON error leaves it `Processing`. `Failed` has no retry path. There is no lease expiry. | Lanes, `Chunk_Payload_Balanced` ELSE, `Process_Lane_Until_Empty_or_Limit_Reached` (PT90M) | 2 | 3 | **6** | The "kill a lane mid-chunk" test fails today. |
| 4 | **Awaiting Review loop.** The run is re-selected every 10 minutes, and each pass requests a Power BI refresh. ⟨inferred⟩ Pro capacity allows 8 scheduled/API refreshes per day and Premium 48. A refusal fails the refresh action, which triggers `Mark_Finalization_Failed`, and the run becomes **Failed**. | Finalizer `Request_TRACE_Dashboard_Refresh_-_No_New_Cases` | 3 | 2 | **6** | It also blocks older runs while it waits. |
| 5 | **The review release can't fire, and human decisions don't create cases.** `All_Case_Reviews_Completed` compares `length(...)` to the **string `"01"`**. It only counts outcome `Needs Case Review`, not `Manual Classification` (which the finalizer also treats as pending). The human decision `Create TRACE Case` doesn't match the finalizer's `Filter_New_Case_Required_Results`, which requires `Auto - Create TRACE Case`, `field_4 = New Case Required` and `CaseCreationEligible`. | ReleaseImportRunAfterReviews; Finalizer | 2 | 3 | **6** | ⟨inferred⟩ The exact effect depends on how the runtime treats int-vs-string `equals` and on what the Power App writes. Check run history: has `Release_Import_Run_After_Reviews` ever succeeded? |
| 6 | **Duplicate tracking numbers across chunks** produce a deterministic chunk failure (I-1). | Process Ready Batch (no de-duplication) plus lane counting | 2 | 3 | **6** | ⟨inferred⟩ Depends on whether duplicates exist in the source file. |
| 7 | **No live writer for `ClassificationReady`** (F4). New runs might never be selected. | Process Ready Batch / Finalizer | 2 | 3 | **6** | Could be a column default. Needs the schema to confirm. |
| 8 | **Static lane partitioning.** The `mod 4` assignment can't rebalance, so a stalled or off lane blocks a quarter of every run (all lanes are off right now, F1). Throughput is capped at 10 chunks per 90 minutes per lane, which is 4,000 records per 90 minutes. A new chunk can wait up to 90 minutes before pickup. | Lane triggers, `Initialize_Maximum_Chunks_This_Activation` = 10 | 3 | 2 | **6** | |
| 9 | **No source-completeness check** (dead `Parsed_Outbound_Records_Balanced`; `RowsRead = 0`). | Process Ready Batch | 2 | 2 | 4 | Rows the Office Script drops are lost silently. |
| 10 | **The two-page cap.** The finalizer reads at most 10,000 results (`…_Page_1` plus `…_Page_2`, each 5,000). Above that, `Actual < Expected` and the run hits the empty ELSE with no error. | Finalizer | 1 | 3 | 3 | Becomes 3×3 if volumes grow. |
| 11 | **Process Ready Batch failure handler is dead** (F3). A failure while creating chunks leaves staging `Processing`, the run `Started`, and a partial set of chunks. | Process Ready Batch | 1 | 2 | 2 | `TotalChunkCount` makes the finalizer wait forever rather than finalize a partial run. |
| 12 | **Case-counter race.** It can't happen while the finalizer is the sole writer at concurrency 1. It becomes live if the dead code in Process Ready Batch is re-enabled or the app numbers cases. Overflow past 999 per day. | Finalizer `Reserve_Current_Case_Number` | 1 | 3 | 3 | |
| 13 | **Unverified lane claim, overlapping activations.** Recurrence triggers with no concurrency limit can overlap once a run exceeds 90 minutes. Collisions are only possible in the ~1-second gap between `Get_Pending_Chunk_Source` and `Claim_Tracking_Chunk`. | Lanes | 1 | 2 | 2 | The `Title` idempotency check limits the damage. |
| 14 | **Trigger hygiene.** The Release flow fires on *every* result create or modify (thousands per run, with no trigger condition), and only `first(body/value)` is evaluated. Process Ready Batch is likewise first-item only. | ReleaseImportRunAfterReviews, Process Ready Batch | 3 | 1 | 3 | Burns quota. `maximumWaitingRuns 100` can drop triggers. |
| 15 | **The fixed `Wait_for_Processing_Results_to_Settle` (15 s).** It adds no correctness: the Foreach finishes only after every PostItem has returned. It adds 15 seconds per chunk (25 minutes per 100 chunks). | Lanes | 3 | 1 | 3 | |
| 16 | **Lane drift.** Lane 1 doesn't escape apostrophes (FM: a tracking number containing `'` fails the iteration and the chunk). No lane escapes `Find_Active_Trace_for_Chunk_Record` or `Find_Historical_Trace_for_Chunk_Record`. Lane 3's messages differ. | Lanes | 1 | 2 | 2 | Fixing a bug in one lane leaves it in the other three. |

---

## 4. Tracking "Follow-Up Required" vs. communication `FollowUpStatus`

**Verdict: separate concepts that should be *linked*, not merged.**

| | Tracking `Follow-Up Required` | Communication `FollowUpStatus` (plan) |
|---|---|---|
| Lives on | Processing Result, `field_4` (one row per tracking number per import run) | Batch Item (one row per sent message) |
| Produced by | Only an exception routing rule whose `field_12` = `Follow-Up Required` (lane `Write_Unmatched_Shipment_Chunk_Result`). `Current_Default_Outcome` never produces it. | Plan: the send flow or an evaluator, from the template's `FollowUpRequired` |
| Decision written | Always `Auto - Dashboard Only` (lane `CaseReviewDecision` expression) | n/a |
| Who acts on it | **Nobody.** The finalizer only counts it (`Follow-Up_Required_Count`) so `Classified_Result_Count` balances. | Human queue plus a daily digest |
| Clock | One-time, at the import run | Business days from `SentDate` (`field_23`) |

Why not merge: different grain (carrier event vs. message), different trigger, different owner. Merging would make the lanes create communication work, which the plan explicitly avoids ("Notify and queue; do not auto-send").

**Do this:**
1. **Rename the tracking outcome**, e.g. to `Carrier Follow-Up Required`. That means changing the choice value in the Results `field_4` and routing-rule `field_12` columns, the `Filter_Follow-Up_Required_Results` filter in the finalizer, and any Power BI measures. Otherwise two different things called "Follow-Up" will show up next to each other in the Case Communications app.
2. **Link through fields that already exist:**
   - `Processing Result.field_5` (Trace_Workflow item ID) = `Batch Item.field_3` (TraceItemID) = `Trace_Workflow.ID`
   - `Processing Result.field_3` = `Batch Item.field_6` = `Trace_Workflow.TrackingNumber`
   - `Trace_Workflow.LastSourceUpdateDate` and `LastImportRunID` are **already written by every lane** (`Active_Trace_Patch_Body`). The evaluator can flag "carrier status changed since the message was sent" (`LastSourceUpdateDate > field_23`) and can suppress `Delivery Still Unconfirmed` follow-ups when `Trace_Workflow.CarrierStatus` shows delivery, **with no lane change.**
   - The plan's Trace_Workflow summary fields (`OpenCommunicationFollowUpCount`, `NextCommunicationFollowUpDate`, `CommunicationFollowUpStatus`) are where the two meet in the app and in Power BI.
3. **Don't duplicate "response" truth.** The send flow already writes `Trace_Workflow.ResponseStatus = 'Awaiting Response'` when Batch Item `field_17` is true (`Update_Trace_Workflow_After_Communication`). The plan's `ResponseReceived` and `ResponseReceivedDate` should either be set together with `ResponseStatus` by the same app action, or the evaluator should derive suppression from `ResponseStatus`. ⟨inferred⟩ I don't know which value means "responded"; only `Not Contacted`, `Awaiting Response` and `No Response Needed` appear in the JSON.

---

## 5. Target design (one recommendation)

### 5.1 Replace four lanes with one dispatcher plus one parameterized worker child flow

- **`TRACE - Dispatch Tracking Chunks`**: Recurrence every 5 minutes, trigger concurrency 1.
  1. **Recover orphans:** find chunks in `Processing` whose `ClaimedDate` is older than the lease (30 minutes). If `RetryCount < 3`, set them to `Pending` with `RetryCount + 1`. Otherwise set them to `Failed` and post an alert.
  2. **Pick work:** `field_8 eq 'Pending'`, `$orderby ID asc`, `$top 4`. Don't filter by lane; delete `WorkerLane`.
  3. **Apply to each** at concurrency 4: claim with ETag (5.2), then `Run a Child Flow` → worker(ChunkID, ClaimToken).
- **`TRACE - Process Tracking Chunk`** (child flow): one definition containing the current lane body, parameterized. One copy means one fix, with no drift (FM-16).

Why: chunks are pulled dynamically, so one slow chunk doesn't hold up a quarter of the run (FM-8). Throughput is tuned with one number. Latency drops to about 5 minutes. Orphans recover (FM-3).
⟨inferred⟩ Check your tenant's behaviour for long child-flow calls. If a child running longer than the parent's action timeout is a problem, use the fallback: same dispatcher, but the worker becomes a single flow triggered by a chunk-list "status changed to Claimed" trigger condition.

### 5.2 Claims: use ETag / If-Match, not claim-then-verify

1. `Send an HTTP request to SharePoint` GET `…/items(ID)?$select=…,field_8` with header `Accept: application/json;odata=minimalmetadata`, then read `odata.etag`.
2. PATCH with `IF-MATCH: <etag>`, body `{field_8: 'Processing', ClaimToken, ClaimedDate}`.
3. **412** means someone else won. Skip it, with no error.

Claim-then-verify (which the finalizer uses) **isn't atomic**: A patches, A verifies, B patches, B verifies, and both believe they own the item. It's safe in the finalizer only because the trigger runs at concurrency 1. Keep concurrency 1 there and add the ETag to `Claim_Import_Run_for_Finalization` and `Reserve_Current_Case_Number` as defence in depth.

### 5.3 What replaces the Wait, and the reconciliation fixes in the worker

- **Delete `Wait_for_Processing_Results_to_Settle`.** Change `Get_Current_Chunk_Processing_Results` to filter on **`field_1 eq '<RunID>' and ChunkNumber eq N`** (index both columns), with pagination on. This fixes FM-1.
- Count results for **distinct tracking numbers** in the payload, not payload rows.
- **Every branch writes the chunk.** The payload-unbalanced ELSE must PATCH the chunk to `Failed` with a reason. Wrap the body in Try/Catch scopes, with the Catch setting `Failed` and `RetryCount + 1`.
- Re-processing is already idempotent (`Find_Existing_Chunk_Result` skips rows that exist, and the corrected count includes the earlier attempt's rows). That's what makes automatic retry (5.1 step 1) safe.
- Escape `'` in every OData filter.
- **Source de-duplication in Process Ready Batch:** de-duplicate `Compact_Parsed_Outbound_Records` by TrackingNumber before chunking, and write the duplicate count and parsed-vs-CSV row counts onto the import run (`RowsRead`, `DuplicateRows`). Then **delete the dead code** after `QV_Batch_Promotion_Succeeded` and wire a live failure scope.

### 5.4 Finalizer: paging, selection, numbering

- **Make the run eligible on an event.** When the worker completes a chunk, it checks "count of non-Completed chunks for this RunID = 0". If that's true, it PATCHes the import run to `FinalizationStatus = 'Ready'` (with ETag). This resolves F4.
- **Selection:** `FinalizationStatus eq 'Ready'`, **`$orderby Created asc`**, oldest first. `Awaiting Review` is no longer selectable (fixes FM-4). The Release flow moves it back to `Ready`.
- **No empty ELSE branches.** Every gate that fails writes `FinalizationStatus = 'Blocked'` plus a `FinalizationBlockedReason` (`Chunks incomplete n/m`, `Results x≠y`, `Unclassified k`), and sends one alert. A blocked run no longer hides the runs behind it (FM-2).
- **Paging: stop reading every result.** Have the worker write per-outcome counts onto the chunk row (a small JSON or numeric columns). The finalizer then balances on the sum of chunk rows (hundreds, not tens of thousands) and only queries the rows it must act on: `field_1 eq RunID and field_4 eq 'New Case Required' and CaseCreationEligible eq 1`, `$top 250` (the existing `Get_Remaining_New_Case_Required_Results` pattern). This removes the 10,000 cap (FM-10). If you'd rather keep reading results, replace page 1 and page 2 with a Do-until keyset loop (`ID gt lastID`, 5,000 at a time) that runs until a page comes back short.
- **Case numbering:** keep the single writer (finalizer at concurrency 1), reserve before create, and keep the `Check_TRACE_Case_Already_Created` idempotency. Add: an ETag on the counter PATCH; **Enforce unique values** on `Trace_Workflow.CaseNumber` and `TrackingNumber`, so the list is the last line of defence; `formatNumber(seq,'0000')` if more than 999 cases a day is possible.
- **Human decisions:** the finalizer's case filter must accept the decision values the app actually writes (`Create TRACE Case`). One "pending" definition, `CaseReviewDecision eq 'Pending Review'`, should be used by the finalizer, the Release flow and the app.
- **Dashboard refresh** happens once, when the run reaches `Completed` or `Awaiting Review`, never on each poll.
- **Release flow:** add a trigger condition (only when `CaseReviewDecision` is a final value), turn on split-on, compare `length(...)` to `0` (the integer), and set the run to `Ready`.

### 5.5 Where the plan plugs in, without touching the lanes

The plan touches only the Templates list, Batch Items (`<LIST_BATCH_ITEMS>`), Trace_Workflow summary fields, the app and Power BI. **No lane or finalizer change is needed.**

- **Follow-up initialization:** recommend doing it **in the evaluator**, not in the send flow. The send flow has **three** paths that end in Sent (`Mark_Batch_Item_Sent_-_Safe`, `Mark_Retried_Batch_Item_Sent`, `Reconcile_Previously_Sent_Batch_Item`). All three write `field_23`. Adding initialization to all three is how you end up with zero or two follow-ups. An evaluator sweep is one idempotent code path, and it leaves the working at-most-once send flow alone: "`field_22 = Sent` and `FollowUpStatus` blank or Not Required and the template has `FollowUpRequired` and `FollowUpActive` set → write `Pending`, due date = `field_23` + N business days." Run the sweep hourly. Send the digest once a day, guarded by the date in `FollowUpNotificationDate`.
  - If you must initialize at send time, put it in **one child flow** and call it from all three Sent paths.
- **Suppression lookups:** read Trace_Workflow by `field_3`. ⟨inferred⟩ If closed cases move to the historical list (`<LIST_HISTORICAL>`), the GetItem returns 404. Treat 404 as `Suppressed – case archived`, not as a flow failure.
- "A newer sent communication exists": filter Batch Items on `field_3 eq <TraceItemID> and field_22 eq 'Sent' and field_23 gt <this SentDate>` (index `field_3`).

---

## 6. What I need from you that isn't in the export

1. **Run history (last 30 days)** for all lanes, the finalizer, Release and Process Ready Batch: durations, failed actions, 429s. In particular: has `Release_Import_Run_After_Reviews` ever succeeded? Did `Request_TRACE_Dashboard_Refresh*` ever fail? Why are the lanes off (F1)?
2. **List schemas with internal names** for Chunks, Processing Results, Import Runs, Case Counter, Trace_Workflow, the historical list, Batch Items, Templates and Routing Rules. For each column I need the type, choice values, **default value** (to settle F4), *Enforce unique values*, and whether it's indexed. Also the real display names behind `field_N` so the legend above can be confirmed.
3. **Item counts** for those lists, plus the largest run so far (outbound rows), runs per day, and new cases per day.
4. **Indexes** on: Results `Title`, `field_1`, `ChunkNumber`, `field_4`; Chunks `field_1`, `field_8`; Trace_Workflow `TrackingNumber`, `CaseNumber`; historical `TrackingNumber`; Batch Items `field_2`, `field_3`, `field_22`.
5. **Routing Rules contents:** which rules output `New Case Required` (the *only* path to automatic case creation) and `Follow-Up Required`.
6. **The Power App's writes** on review (values for `CaseReviewDecision` and `field_4`) and on queueing (Draft → Queued), and what "close case" does (status change or move to the historical list).
7. **The Office Script** (`Parse_Outbound_CSV`): does it de-duplicate? What's the longest `field_9` payload you've seen (multi-line text limits)?
8. **Power BI capacity** (Pro or Premium/Fabric), which decides the refresh limit in FM-4.
9. Volume target: the expected maximum number of rows per run, to size the dispatcher's concurrency.

---

## 7. Verification: reconciliation checks and failure tests

`scripts/TRACE_Reconciliation.ps1` (PnP.PowerShell; usage in `02_WALKTHROUGH_GUIDE.md` Part 3) runs R1–R9 against the lists by GUID and internal name. **It has not been run against your tenant.** Confirm the field legend first (item 2 above).

### 7.1 Reconciliation checks (run after every import run, then nightly)

| ID | Check | Pass condition | Invariant |
|---|---|---|---|
| R1 | Results for a RunID, grouped by `Title` and by `(field_1, field_3)` | No group larger than 1 | I-1 |
| R2 | Chunks for a RunID | count = `TotalChunkCount`; all `Completed`; for each chunk, `field_6` = `field_5` and `field_7` = 0 | I-2 |
| R3 | For each chunk: results with `field_1` = RunID and `ChunkNumber` = N | count = distinct tracking numbers in `json(field_9)` | I-2 |
| R4 | Σ chunk `field_5` vs. result count vs. distinct outbound tracking numbers | All three equal | I-1, I-2 |
| R5 | Outcome distribution | Σ every outcome = result count; 0 rows with `New Case Required` when the run is `Completed` | I-2, I-4 |
| R6 | `New Case Created` rows | `field_5` and `field_9` not empty; the referenced Trace_Workflow item exists with the same CaseNumber and TrackingNumber | I-3 |
| R7 | Trace_Workflow `CaseNumber` | Unique across active + historical; for each day, max sequence ≤ counter `LastSequence` | I-3 |
| R8 | Import runs | None in `Processing` for more than 30 minutes; none `Ready` or `Blocked` for more than 2 hours without an alert; `Completed` ⇒ R2–R5 pass | I-4 |
| R9 | Chunks in `Processing` with `ClaimedDate` older than 30 minutes | 0 | I-2 |
| C1 | Sent items whose template requires follow-up | Exactly 1 with `FollowUpStatus` ≠ Not Required | Plan gate 1 |
| C2 | Sent items whose template doesn't require follow-up | 0 with `FollowUpStatus` ≠ Not Required | Plan gate 2 |
| C3 | Queue count (Pending, Due Soon, Due Today, Overdue, excluding test records and closed cases) | = digest totals = Power BI alert-strip totals | Plan gate 4 |
| C4 | Follow-up drafts | Every item with `PreviousCommunicationItemID` points to a Sent original whose `Modified` didn't change after the follow-up draft was created | Plan gate 7 |

### 7.2 Failure tests (in a test site or with `IsTestRecord` data)

| ID | Test | How | Pass condition | Fails today? |
|---|---|---|---|---|
| T1 | Kill a worker mid-chunk | Start a run of about 300 rows and cancel the worker run during `Process_Current_Chunk_Records` | Within lease plus one dispatch interval, the chunk returns to `Pending` with `RetryCount = 1`, then `Completed`. R1–R4 pass and no duplicate results exist. | **Yes.** The chunk stays `Processing` and the run never finalizes. |
| T2 | Two workers on the same chunk | Fire two worker runs with the same ChunkID at the same time | Exactly one gets past the ETag claim; the other gets a 412 and exits cleanly. R1 passes. | Possible duplicates; no 412 path exists |
| T3 | A run over 5,000 results | Feed 12,000 outbound rows | Run reaches `Completed`; R2–R7 pass; finalizer duration recorded | **Yes**, above 10,000 (FM-10). Also FM-1 once history grows. |
| T4 | Duplicate tracking number in different chunks | Put the same number at rows 5 and 150 | `DuplicateRows = 1` on the import run; one result; run `Completed` | **Yes** ⟨inferred⟩ (FM-6) |
| T5 | Payload mismatch | Manually set one chunk's `field_5` to 99 while it contains 100 records | Chunk → `Failed` with a reason; run → `Blocked` with a reason; alert sent | **Yes.** It stays `Processing` and nothing is reported. |
| T6 | History growth | Seed more than 5,000 historical results with `ChunkNumber = 1` | The current run's chunk 1 reconciles | **Yes** (FM-1) |
| T7 | Pending reviews | A run with 1 `Manual Classification` and 1 `Needs Case Review` | `Awaiting Review`, exactly 1 dashboard refresh. Completing both decisions moves the run to `Ready` and then `Completed`; a "Create TRACE Case" decision produces a case. | **Yes** (FM-4, FM-5) |
| T8 | More than 250 new cases | 600 rows that route to `New Case Required` | 3 passes, 600 unique contiguous case numbers, R6 and R7 pass | Should pass today; keep as a regression test |
| T9 | Apostrophe in a tracking number | Inject `1Z'TEST` | Processed in one chunk without error | Lane 1 fails; Lanes 2–4 partially |
| T10 | Stuck newest run | Leave the newest run `Blocked` and add an older `Ready` run | The older run finalizes | **Yes** (newest-first selection) |

### 7.3 Mapping to the plan's launch gate

| Plan launch gate | Covered by |
|---|---|
| A sent template requiring follow-up creates exactly one pending item | C1, plus a test that sends via each of the 3 Sent paths (normal, retry, reconcile) |
| A template without follow-up creates none | C2 |
| Due dates skip Saturday and Sunday | A unit test of the evaluator's date expression: Fri + 1 business day = Mon; Fri + 3 = Wed |
| Queue totals equal digest totals | C3 |
| Closed, responded, replaced, failed-send and test records are suppressed | Plan's validation table, plus the 404-on-archived case (5.5) |
| Selecting an alert opens the correct TraceItemID | Manual UI test |
| Follow-up creates a new history item and preserves the original | C4 |
| No automation sends an external follow-up without human review | Static check: no `SendEmail` action in the evaluator JSON |
| **Proposed tracking-side launch gate** (add it): R1–R9 green for 3 consecutive production runs, and T1, T2, T3, T5, T7 and T10 passed | — |

---

## Suggested order of work

1. **Stop the bleeding.** Add RunID to the lane result filter (FM-1). Write status on every finalizer ELSE branch (FM-2). Exclude `Awaiting Review` from selection and select oldest first (FM-4, T10). Make the payload ELSE write `Failed` (FM-3, T5). These are small edits to existing flows.
2. **Answer section 6.** The schema, defaults and run history settle F4, FM-5 and FM-6.
3. **Build the dispatcher and worker** with ETag claims, a lease, retries and chunk-level outcome counts. Retire Lanes 1–4.
4. **Rework the finalizer:** `Ready` event, keyset paging or chunk aggregates, unique constraints. Fix the Release flow.
5. **Then the communication follow-up plan**, built on top of a stable pipeline. It doesn't depend on steps 3–4, so it can run in parallel once step 1 is done.
