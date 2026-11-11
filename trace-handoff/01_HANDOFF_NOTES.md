# TRACE Lane and Finalizer Redesign: Handoff Notes

| | |
|---|---|
| Prepared | 2026-11-11 |
| Owner | CrawfordTS25 |
| Subject | Redesign of the TRACE tracking lane worker flows and the scheduled finalizer, and how the Communication Follow-Up plan fits in |
| Inputs analysed | `TRACEQVCodeReview20261022_1_0_0_9.zip` (Power Automate solution export, v1.0.0.9, 11 flows) and `TRACE_Communication_Follow_Up_Implementation_Plan.docx`. **Neither is in this repo.** Keep them locally. |
| Redaction | This repo is public, so tenant/site URL, mailbox, list/dataset/file IDs and office street addresses are replaced by placeholders (see `README.md` → *Filling in the placeholders*). The analysis itself is unchanged. |
| Status | **Analysis complete. Nothing has been changed in Power Automate or SharePoint.** Fixes and the redesign are written up but not applied. The reconciliation script has **never been run**. |

---

## 1. Executive summary

1. **The lanes are off.** All four lane flows are in Draft (off) in the export. With the lanes off, no chunk gets processed and no run gets finalized. Find out who turned them off and why before turning them back on.
2. **Three defects block correct operation regardless of design:**
   - The lanes count a chunk's results **by chunk number only, not by run** (`Get_Current_Chunk_Processing_Results`). After about 50 runs, chunk counts break.
   - The finalizer has **four empty "No" branches**. When a check fails, nothing is written, and because it picks the **newest run first**, one stuck run hides every older one.
   - Chunks can be **stranded in `Processing` forever** (bad payload branch, cancelled run, timeout). No retry path exists.
3. **The review loop is broken.** Runs in `Awaiting Review` are re-picked every 10 minutes and trigger a Power BI refresh each time. The release flow compares a count to the text `"01"`, and human "Create TRACE Case" decisions don't match the finalizer's filter.
4. **The intake flow is about 25% dead code.** Process Ready Batch (40 of its actions) never runs, including de-duplication, the "parsed rows = CSV rows" check, and the failure handler.
5. **Nothing in the export marks a new run as eligible for finalization** (`ClassificationReady`). Probably a column default; needs confirming.
6. **Recommendation:** replace the 4 copied lanes with **one worker child flow plus a 5-minute dispatcher** using **ETag claims, leases and retries**. Make the finalizer **oldest-first, event-driven (`Ready`), with a reason written on every block**, and have it balance from per-chunk counts instead of reading every result.
7. **The Communication Follow-Up plan doesn't touch the lanes or the finalizer.** Do follow-up setup in the evaluator, not the send flow (which has three "Sent" paths). Keep tracking `Follow-Up Required` separate (rename it) and link the two through TraceItemID.

---

## 2. What was asked, and how the work went

### 2.1 Original request
> "I need to redesign the lane flows, the finalizer flow with this. But I don't know what makes the most sense based off my notes. Analyze the best way to make this work with these files."

### 2.2 Sharpened request (agreed and used as the brief)
A seven-part brief:
1. What must stay true, and which action enforces it today
2. State machines (import run, chunk, processing result, communication item)
3. Ranked failure modes (retries, overlapping runs, unverified claims, fixed Wait, two-page cap, case-counter race, lane drift)
4. Tracking `Follow-Up Required` vs. communication `FollowUpStatus`
5. One target design (lanes vs. child flow, ETag vs. claim-then-verify, Wait replacement, finalizer paging and numbering, where the plan plugs in)
6. What's missing from the export
7. Reconciliation checks plus failure tests mapped to the plan's launch gate

Rule: ground every claim in the JSON and mark inferences.

### 2.3 Method
1. Unzipped the export and converted every flow's JSON into a readable outline of every action, filter, write and run-after (`reference/flow-outlines/`).
2. Ordered each flow by run-after dependencies, which is how the dead code was found (`reference/run-order/`).
3. Diffed the four lanes (`reference/lane-diffs/`).
4. Read `customizations.xml` for on/off state (`reference/flow-inventory.md`).
5. Mapped list GUIDs and field meanings from usage (`reference/list-map.md`).
6. Searched every flow for writers of the key fields (`ClassificationReady`, the counter list, the chunk list, `Follow-Up Required`, `field_23`).
7. Wrote the analysis (`03_ANALYSIS_REPORT.md`) and the read-only reconciliation script (`scripts/TRACE_Reconciliation.ps1`).
8. Wrote this walkthrough and these notes.

### 2.4 What was NOT done
- No access to the tenant, SharePoint, run history, the Power App or the Office Script.
- The PowerShell script hasn't been executed or syntax-checked (PowerShell wasn't available in the analysis environment).
- No flow has been edited. All fixes are instructions (`02_WALKTHROUGH_GUIDE.md` Part 5).

---

## 3. Deliverables

| File | Purpose | Verified? |
|---|---|---|
| `03_ANALYSIS_REPORT.md` | All seven sections with evidence | Every claim read from the JSON, except items marked ⟨inferred⟩ |
| `02_WALKTHROUGH_GUIDE.md` | Exact steps: setup, data collection, fixes, tests, redesign, follow-up plan | Expressions written against the JSON; **not executed in Power Automate** |
| `scripts/TRACE_Reconciliation.ps1` | Read-only checks R1–R9, C1–C3 | **Not run** |
| `reference/*` | Generated outlines, run order, diffs, inventory, list map | Generated mechanically from the export |
| `tools/*.py` | Regenerate the reference files | Run successfully on this export |

---

## 4. Key findings (cross-reference to the report)

| # | Finding | Evidence (flow → action) | Report |
|---|---|---|---|
| F1 | Lanes 1–4 are off | `customizations.xml` StateCode 0 | §0 |
| F2 | Process Ready Batch creates the chunks; lanes assigned by `mod 4` | `Create_Tracking_Chunk_Record` | §0 |
| F3 | 40 actions of dead code in Process Ready Batch | Both branches of `QV_Batch_Promotion_Succeeded` terminate | §0 |
| F4 | No writer for `ClassificationReady` on new runs | Search of all 11 flows | §0 |
| F5 | Lane drift (Lane 1 escaping, Lane 3 messages) | `reference/lane-diffs/` | §0 |
| FM-1 | Chunk-results query ignores RunID | Lanes `Get_Current_Chunk_Processing_Results` | §3 |
| FM-2 | Empty No branches + newest-first = silent starvation | Finalizer `Candidate_Run_Chunks_Complete`, `Candidate_Run_Results_Balanced`, `Import_Run_Claim_Verified`, `Candidate_Outcome_Distribution_Balanced`; `Get_Candidate_Import_Runs` | §3 |
| FM-3 | Orphaned / terminal chunks | Lanes `Chunk_Payload_Balanced` No branch; no Failed→Pending anywhere | §3 |
| FM-4 | Awaiting Review loop + repeated refresh | Finalizer `Request_TRACE_Dashboard_Refresh_-_No_New_Cases` | §3 |
| FM-5 | Release never fires; human decision mismatch | Release `All_Case_Reviews_Completed` (`"01"`); finalizer `Filter_New_Case_Required_Results` | §3 |
| FM-6 | Duplicate tracking numbers across chunks → chunk Failed | `Compact_Parsed_Outbound_Records` (no de-duplication) + lane count | §1, §3 |
| — | Comm send flow already tracks "awaiting response" | Send `Update_Trace_Workflow_After_Communication` (`ResponseStatus`) | §4 |
| — | Three Sent paths, all write SentDate (`field_23`) | `Mark_Batch_Item_Sent_-_Safe`, `Mark_Retried_Batch_Item_Sent`, `Reconcile_Previously_Sent_Batch_Item` | §5.5 |

What already works well (keep it):
- The finalizer's case-number **reserve-before-create**, plus the `Check_TRACE_Case_Already_Created` idempotency.
- The send flow's **communication log** (`COM-<key>`), which prevents double-sending; the "Pending" state means it holds rather than re-sends.
- The lane idempotency key `Title = RunID|TrackingNumber`, which makes re-processing a chunk safe once Fix 1 is in.
- The finalizer's 250-per-pass case blocks with re-queue.

---

## 5. Decisions and recommendations

| Topic | Recommendation | Status |
|---|---|---|
| Lanes | Replace 4 copies with **1 worker child flow + 1 dispatcher** (5 min, concurrency 1, fan-out 4) | Proposed |
| Claims | **ETag / If-Match** on the chunk claim; keep the finalizer at concurrency 1 and add an ETag as a backstop | Proposed |
| Leases / retries | `LeaseExpires` 30 min; up to 3 retries; then Failed + alert | Proposed |
| Wait | Delete it; query by RunID + ChunkNumber with pagination | Proposed (Fix 1 + Fix 7) |
| Finalizer selection | `FinalizationStatus eq 'Ready'`, **oldest first**; skip Awaiting Review / Blocked | Proposed (Fix 4 interim) |
| Finalizer failures | Every failed check → `Blocked` + reason + alert | Proposed (Fix 3) |
| Finalizer paging | Balance from **per-chunk outcome counts**; query only the rows to act on | Proposed |
| Case numbers | Single writer + reserve-first + ETag + **unique constraint** on CaseNumber/TrackingNumber; 4-digit sequence only if >999/day (business sign-off) | Proposed |
| Follow-Up naming | Rename the tracking outcome to `Carrier Follow-Up Required`; link via TraceItemID | Proposed |
| Follow-up setup | In the **evaluator** (one idempotent sweep), not in the 3 send-flow Sent paths | Proposed (differs from plan §3) |
| Response truth | Tie the plan's `ResponseReceived` to the existing `Trace_Workflow.ResponseStatus` | Needs decision |
| Repo | Package stored on branch `claude/keen-tesla-gckrbv` of a **public** repo, **redacted** (placeholders), without the source files | Done |

---

## 6. Open questions (fill in the Answer column)

| # | Question | Why it matters | How to answer (Walkthrough) | Answer |
|---|---|---|---|---|
| Q1 | What sets `ClassificationReady = Yes` on a new import run? (Column default? App? Another flow?) | Without it, runs are never finalized (F4) | Part 2 step 5 (column default); Part 4.1 | |
| Q2 | Why, and since when, are Lanes 1–4 off? | Turning them back on may resurface a known problem | Part 4.1 | |
| Q3 | Has `Release_Import_Run_After_Reviews` ever succeeded? | Confirms FM-5 | Part 4.1 | |
| Q4 | Have dashboard refresh actions failed? Pro or Premium capacity? | FM-4 severity | Parts 4.1, 4.2 | |
| Q5 | What does the app write on review (`CaseReviewDecision`, `field_4`, `CaseCreationEligible`)? | Whether human-approved cases are ever created | Part 4.5 | |
| Q6 | What does "close case" do (status change or move to the historical list)? | Evaluator suppression (404 handling) | Part 4.5 | |
| Q7 | Does the Office Script de-duplicate? Longest payload length? | FM-6; multi-line text limit | Part 4.6; script R3 prints the max payload length | |
| Q8 | Column types, defaults, unique constraints, indexes, item counts for the 9 lists | FM-1 timing; threshold errors; uniqueness guarantees | Parts 2, 4.3 | |
| Q9 | Which routing rules output `New Case Required` / `Follow-Up Required`? | The only path to automatic case creation | Part 4.4 | |
| Q10 | Peak rows per run, runs per day, new cases per day | Dispatcher concurrency; 10,000 cap; 999/day format | Part 4.7 | |
| Q11 | Is a 4-digit daily case sequence acceptable if ever needed? | Case-number format change | Business owner | |
| Q12 | Which `ResponseStatus` value means "responded"? | Follow-up suppression | Part 4.5 | |

---

## 7. Risks and caveats

1. **The field legend is inferred.** Internal names (`field_N`) were mapped from how the flows use them. Confirm before running the script or applying fixes (Walkthrough Part 2).
2. **The script is unexecuted.** Expect to fix small issues on the first run.
3. **Fix 4 depends on Fix 5.** If the Release flow still doesn't fire, runs that are `Awaiting Review` will never come back. Test T7 must pass before relying on Fix 4 in production.
4. **Fix 5's last step depends on Q5.** Don't change the finalizer's case filter until you know what the app writes.
5. **Dispatcher HTTP PATCH on a choice column:** the REST value format must be confirmed on one item first (Walkthrough 7.3).
6. **Long child-flow calls:** confirm the tenant behaviour (Walkthrough 7.3 step 5), with the fallback in Report §5.1.
7. **Unique constraints** require the column to be indexed, and fail if duplicates already exist. Run R7 first.
8. **The repo is public.** Identifiers are redacted, but the flow logic, list structure and business rules are visible. Don't add the original export, real GUIDs, tenant URLs or mailbox addresses to it. Keep a filled-in copy of the script and list map locally only.

---

## 8. Next steps (checklist)

- [ ] Export a backup of the solution (Walkthrough 1.3)
- [ ] Confirm the field legend and list names (Part 2)
- [ ] Run the reconciliation script on one known-good run (Part 3)
- [ ] Answer Q1–Q12 (Part 4)
- [ ] Add indexes (Part 4.3)
- [ ] Apply Fixes 1, 2, 6, 7 to all lanes (Part 5)
- [ ] Apply Fix 3 (add the `Blocked` choice first), Fix 4 and Fix 5 steps 1–5 (Part 5)
- [ ] Run tests T5, T7, T9, T10 (Part 6)
- [ ] Turn on one lane, then all four (Part 5, end)
- [ ] Build the dispatcher + worker in dev (Part 7.1–7.3); tests T1–T3
- [ ] Process Ready Batch de-duplication and dead-code removal (Part 7.4)
- [ ] Finalizer rework (Part 7.5); cut-over (Part 7.6)
- [ ] Follow-up plan with the adjustments in Part 8
- [ ] Acceptance gate: R1–R9 green for 3 consecutive production runs

Estimated effort ⟨inferred, for planning only⟩: Parts 1–4 about 1 day; Part 5 about 1 day plus testing; Part 7 about 3–5 days plus a parallel run; Part 8 per the plan's checkpoints.

---

## 9. Glossary

| Term | Meaning |
|---|---|
| Import run | One intake batch, identified by RunID (`TRACE-<BatchKey>-HHmmss-xxxxxxxx`) |
| Chunk | 100 outbound tracking records stored as JSON on one row in the Chunks list |
| Lane | One of four copied worker flows; each processes only chunks with its `WorkerLane` number |
| Processing result | One row per tracking number per run, with the outcome and case link |
| Finalizer | Scheduled flow (every 10 min) that checks a run is complete, creates cases, and marks the run Completed or Awaiting Review |
| Release flow | Moves an Awaiting Review run back to Not Started once reviews are done |
| Claim | Marking a work item as owned by one worker |
| ETag / If-Match | SharePoint's built-in version check: the update succeeds only if nobody changed the item since you read it (else HTTP 412) |
| Lease | A time limit on a claim, after which the item can be reclaimed |
| Idempotent | Safe to run twice; the second run changes nothing |
| R1–R9, C1–C3 | Reconciliation checks in the script |
| T1–T10 | Failure tests in Walkthrough Part 6 |
| FM-n | Failure mode n in Report §3 |
| ⟨inferred⟩ | Not read directly from the export; needs confirming |
