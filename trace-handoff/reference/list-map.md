# SharePoint list map and field legend

Site: `https://<tenant>.sharepoint.com/sites/<site>`

The flows refer to lists by GUID, not by name. The list names below are **inferred** from how each flow uses the list. The only exceptions are `Trace_Workflow`, which the lanes name directly (`getbytitle('Trace_Workflow')`), and the plan's `TRACE_Communication_Batch_Items` and `TRACE_Email_Templates`.
**To confirm a GUID:** open any list → Settings (gear) → List settings. The browser URL ends in `List=%7B<GUID>%7D`.

| GUID | Inferred list name / role | Written by | Read by |
|---|---|---|---|
| `<LIST_STAGING>` | QV_File_Batch_Staging (one row per incoming CSV file) | Archive Intake (`Create_Staging_Record`, `Set_Staging_File_Ready`); Process Ready Batch (`Assign_Run_ID_to_Staging_Record`) | Process Ready Batch (trigger) |
| `<LIST_IMPORT_RUNS>` | Import Run log (one row per RunID) | Process Ready Batch (`Create_Import_Run_Log`); Finalizer; Release flow | Finalizer, Release flow |
| `<LIST_CHUNKS>` | Tracking Processing **Chunks** (100 records each) | Process Ready Batch (`Create_Tracking_Chunk_Record`); Lanes 1–4 | Lanes, Finalizer |
| `<LIST_RESULTS>` | Tracking Processing **Results** (one row per tracking number per run) | Lanes 1–4; Finalizer | Lanes, Finalizer, Release flow (trigger) |
| `<LIST_TRACE_WORKFLOW>` | **Trace_Workflow** (active TRACE cases) | Lanes (HTTP PATCH), Finalizer (`Create_New_Active_TRACE`), Send flow | Lanes, Finalizer, Send flow |
| `<LIST_HISTORICAL>` | Historical TRACE cases | — (not written by any flow in the export) | Lanes |
| `<LIST_CASE_COUNTER>` | Daily **case-number counter** (Title = yyyyMMdd) | Finalizer (`Reserve_Current_Case_Number`, `Create_Today_Case_Counter`) | Finalizer |
| `<LIST_ROUTING_RULES>` | Exception **routing rules** | — | Lanes (`Get_Active_Exception_Routing_Rules`) |
| `<LIST_BATCH_HEADER>` | Communication **Batch header** | Draft batch flow, Send flow | Send flow (trigger) |
| `<LIST_BATCH_ITEMS>` | **TRACE_Communication_Batch_Items** (plan's main list) | Draft batch flow, Send flow | Send flow |
| `<LIST_COMM_LOG>` | Communication **log** (send idempotency, key `COM-<item key>`) | Send flow | Send flow |
| `<LIST_CLAIM_ACTIVITY>` | Claim / case activity log | Send flow (`Create_Claim_Activity`) | — |
| `<LIBRARY_QV_FILES>` | QV Automation Files document library | (files land here) | Archive Intake (trigger), Promote flow |

## Field legend (inferred from usage; confirm each in List settings → click column → URL ends `Field=<internal name>`)

### Chunks (`<LIST_CHUNKS>`)
| Internal | Meaning | Evidence |
|---|---|---|
| Title | `RunID|001` | `Create_Tracking_Chunk_Record` |
| field_1 | RunID | same; finalizer filters on it |
| field_2 | BatchKey | same |
| field_3 | ChunkNumber (1-based) | `add(item(),1)` |
| field_4 | Start index | `mul(item(),100)` |
| field_5 | ExpectedCount | `min(100, …)`; reconciled by lanes and finalizer |
| field_6 | CompletedCount | `Complete_Tracking_Chunk` |
| field_7 | ErrorCount | same |
| field_8 | **Status** (choice: Pending / Processing / Completed / Failed) | lane filter `field_8 eq 'Pending'` |
| field_9 | Payload JSON (array of up to 100 records) | `json(field_9)` |
| field_10 | Started date | Claim |
| field_11 | Last updated | every lane PATCH |
| field_12 | Completed / failed date | |
| field_13 | RetryCount (written, never read) | `Fail_Tracking_Chunk_After_Worker_Error` |
| field_14 | Worker run ID | |
| field_15 | Error message | |
| WorkerLane, LaneSequence, TotalChunkCount, ClaimToken, ClaimedDate | named columns | |

### Results (`<LIST_RESULTS>`)
| Internal | Meaning |
|---|---|
| Title | Result key `RunID|TrackingNumber` (the lane idempotency key) |
| field_1 | RunID |
| field_2 | BatchKey |
| field_3 | TrackingNumber |
| field_4 | **Outcome** (choice; see analysis §2c for all values) |
| field_5 | Trace_Workflow item ID (active or historical) |
| field_6 | Record count (always 1) |
| field_7 | Error text |
| field_8 | Processed date |
| field_9 | CaseNumber |
| ChunkNumber, CaseCreationEligible, CaseCreationReason, CaseReviewDecision, Shipper*/ShipTo*, Carrier*, Exception*, ScheduledDeliveryDate, ShipperLocationKey | named columns |

### Import Runs (`<LIST_IMPORT_RUNS>`)
Named columns: `RunID`, `RunStatus` (Started / Completed / Failed), `FinalizationStatus` (Not Started / Processing / Awaiting Review / Completed / Failed), `FinalizerRunID`, `FinalizationStartedDate`, `FinalizationCompletedDate`, `FinalizationErrorMessage`, `ClassificationReady`, `ClassificationCompletedDate`, `ClassificationRefreshRequested`, `ClassificationRefreshRequestedDa` (truncated internal name of …Date), `EmailBatchReady`, `DashboardRefreshRequested`, `DashboardRefreshRequestedDate`, `DashboardRefreshCompleted`, `RowsRead`, `RowsCreated`, `RowsUpdated`, `RowsSkipped`, `RowsFailed`, `HistoricalMatches`, `DuplicateRows`, `FirstCaseNumberAssigned`, `LastCaseNumberAssigned`, `SourceFileGroup`, `RunDate_x002f_Time`, `RunCompletedDate_x002f_Time`, `FolderType`, `ProcessedFilePath`.

### Case counter (`<LIST_CASE_COUNTER>`)
`Title` (yyyyMMdd, Central time) · `LastSequence` · `LastCaseNumber` · `LastUpdated` · `LastAutomationRunID` · `Notes`.
Case number format: `yyyyMMdd` + `formatNumber(sequence,'000')`, e.g. `20261111007`.

### Communication Batch Items (`<LIST_BATCH_ITEMS>`)
| Internal | Meaning | Evidence |
|---|---|---|
| field_1 | Item key `BTI-yyyyMMddHHmmss-xxxxxxxx` | `Create_Batch_Item`; send key `COM-<field_1>` |
| field_2 | BatchID | send flow filter |
| field_3 | **TraceItemID** (Trace_Workflow item ID) | `Get_Live_Trace_Workflow_Eligibility` |
| field_4 | TraceID (`TRC-<guid>`) | |
| field_5 | CaseNumber | |
| field_6 | TrackingNumber | |
| field_7 | Exception summary | |
| field_8 | **Template key** | "using template" note; `onetrust` check |
| field_10 | **Recipient email** | `emailMessage/To` |
| field_11 | Selection status (Pending Selection …) | |
| field_15 / field_16 | Subject / body (inferred) | copied to the log |
| field_17 | **Response expected** flag → `Trace_Workflow.ResponseStatus = 'Awaiting Response'` | `Update_Trace_Workflow_After_Communication` |
| field_19 | Review status (Needs Review / Ready) | |
| field_21 | Approved / queued flag | `Filter_Ready_Items` |
| field_22 | **SendStatus** (Draft / Queued / Processing / Sent / Failed / Skipped) | |
| field_23 | **SentDate** | all three Sent paths |
| field_25 / field_26 | Created by email / created date | |
| field_37 | Verification method | |
