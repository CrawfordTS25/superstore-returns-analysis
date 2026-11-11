# Flow inventory (from solution export v1.0.0.9)

State is read from `customizations.xml` (StateCode 1 = Activated, 0 = Draft).

| Flow | State | Trigger | Polling / schedule | Trigger concurrency | Split-on | Actions |
|---|---|---|---|---|---|---|
| TRACE - Archive Intake and Batch Classification | ON (Activated) | OpenApiConnection GetOnNewFileItems <LIBRARY_QV_FILES> | every 1 Minute | `{"runs": 1}` | split-on: yes | 32 |
| TRACE - Create Complete Draft Batch | ON (Activated) | Request   |  | `"default (off)"` | split-on: no | 5 |
| TRACE - Finalize Completed Tracking Runs - Scheduled | ON (Activated) | Recurrence   | every 10 Minute | `{"runs": 1}` | split-on: no | 110 |
| TRACE - Process Ready Batch - Optimized v3 Chunked | ON (Activated) | OpenApiConnection GetOnUpdatedItems <LIST_STAGING> | every 1 Minute | `{"runs": 1, "maximumWaitingRuns": 100}` | split-on: no | 167 |
| TRACE - Process Submitted Communication Batch | ON (Activated) | OpenApiConnection GetOnUpdatedItems <LIST_BATCH_HEADER> | every 1 Minute | `{"runs": 1}` | split-on: yes | 57 |
| TRACE - Process Tracking Lane 1 - Self Drain | OFF (Draft) | Recurrence   | every 90 Minute | `"default (off)"` | split-on: no | 70 |
| TRACE - Process Tracking Lane 2 - Self Drain | OFF (Draft) | Recurrence   | every 90 Minute | `"default (off)"` | split-on: no | 70 |
| TRACE - Process Tracking Lane 3 - Self Drain | OFF (Draft) | Recurrence   | every 90 Minute | `"default (off)"` | split-on: no | 70 |
| TRACE - Process Tracking Lane 4 - Self Drain | OFF (Draft) | Recurrence   | every 90 Minute | `"default (off)"` | split-on: no | 70 |
| TRACE - Promote Validated QV Batch | ON (Activated) | Request   |  | `"default (off)"` | split-on: no | 49 |
| TRACE - Release Import Run After Reviews | ON (Activated) | OpenApiConnection GetOnUpdatedItems <LIST_RESULTS> | every 1 Minute | `{"runs": 1, "maximumWaitingRuns": 100}` | split-on: no | 10 |
