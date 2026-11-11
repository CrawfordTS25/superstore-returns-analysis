# TRACE Handoff Package

Analysis and redesign plan for the TRACE tracking **lane** flows and the **finalizer**, plus how the **Communication Follow-Up** plan fits in.

> **This is the redacted public copy.** Tenant and site URL, mailbox address, list / dataset / file IDs and office street addresses have been replaced with placeholders such as `<tenant>`, `<LIST_CHUNKS>`, `<ADDRESS-A>`, `Location A`. The original solution export and plan document are **not** in this repo; keep them locally. See **"Filling in the placeholders"** below.
> It is unrelated to the Superstore returns analysis in the rest of the repo.

## Start here
1. **`01_HANDOFF_NOTES.md`**: what was done, findings, decisions, open questions, next-step checklist.
2. **`02_WALKTHROUGH_GUIDE.md`**: step-by-step instructions (setup → data collection → fixes → tests → redesign → follow-up plan).
3. **`03_ANALYSIS_REPORT.md`**: full seven-section analysis with evidence for every claim.

## Folder contents
```
trace-handoff/
├── README.md                          this file
├── 01_HANDOFF_NOTES.md                status, decisions, open questions, checklist
├── 02_WALKTHROUGH_GUIDE.md            detailed step-by-step guide
├── 03_ANALYSIS_REPORT.md              the analysis (invariants, state machines, failure modes, design, tests)
├── scripts/
│   └── TRACE_Reconciliation.ps1       read-only SharePoint checks R1–R9, C1–C3 (PnP.PowerShell; not yet run)
├── reference/
│   ├── flow-inventory.md              every flow: on/off, trigger, schedule, concurrency, action count
│   ├── list-map.md                    list GUIDs → names, internal field legend
│   ├── flow-outlines/*.txt            every action with inputs, filters and field writes (one file per flow)
│   ├── run-order/*.order.txt          actions in execution order per container, with [YES]/[NO] branches
│   └── lane-diffs/*.diff              Lane 1 vs. Lanes 2, 3, 4
└── tools/
    ├── dump.py        regenerates flow-outlines
    ├── order_all.py   regenerates run-order
    ├── order.py       single-container run-order (used during analysis)
    └── summ.py        quick tree printout of a flow
```

## Filling in the placeholders
| Placeholder | Where to get the real value |
|---|---|
| `<tenant>`, `<site>` | Your SharePoint site address: `https://<tenant>.sharepoint.com/sites/<site>` |
| `<LIST_…>`, `<LIBRARY_QV_FILES>` | Open the list → gear → **List settings** → the URL ends in `List=%7B<GUID>%7D`. `reference/list-map.md` says which list each placeholder is. Or search your local copy of the export zip (`Workflows/*.json`) for the `table` value next to the same action name. |
| `<PBI_WORKSPACE_ID>`, `<PBI_DATASET_ID>` | Power BI → the TRACE workspace / dataset → the IDs in the browser URL |
| `<shared-mailbox@company.com>` | The shared Package Tracking mailbox used by the send flow |
| `<ADDRESS-A/B/C>`, `Location A/B/C` | The office street keys and location names in the lanes' `Current_Operational_Location` / `Current_Return_Outreach_Destination` expressions (A = the main campus, B = the second site, C = the third, outreach-only location) |
| `<M365_GROUP_ID>`, `<DRIVE_ID>`, `<WORKBOOK_FILE_ID>`, `<OFFICE_SCRIPT_ID>` | The `Parse_Outbound_CSV` action in Process Ready Batch |
| `<GUID>` | Any other ID (only cosmetic, in the outlines) |

**Only the script needs real values to run:** fill in the `$L` block at the top of `scripts/TRACE_Reconciliation.ps1`. The script refuses to run while placeholders remain.

## Download
Branch **`claude/keen-tesla-gckrbv`**. On GitHub, switch to that branch, then **Code → Download ZIP**, or:
```bash
git clone -b claude/keen-tesla-gckrbv https://github.com/CrawfordTS25/superstore-returns-analysis.git
```

## Status (2026-11-11)
The analysis is complete. **No changes have been made to Power Automate or SharePoint.** The script has not been executed. See `01_HANDOFF_NOTES.md` §2.4 and §7.
