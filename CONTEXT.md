# Growth Dashboard: Context File

Handover file for continuing this work in a new Claude account or session. Updated 12 Nov 2026.

## 1. What this is

- **Growth Dashboard** (earlier names: Sales Capacity Dashboard / Tracker). Built for Harsh's manager and Ajeet (Head of Growth).
- **Live:** https://harshr-code.github.io/Sales-Capacity-Dashboard/
- **Repo:** `harshr-code/Sales-Capacity-Dashboard` (GitHub Pages, root: `index.html`, `capacity.json`, `data/manpower.csv`, `scripts/`, `.github/workflows/refresh.yml`)
- **Local copy:** `C:\capdash\`
- **This is a separate assignment from the BQL Inflow Dashboard** (harshr-code/BQL-Dashboard). Never mix the two, and don't add data requests (for example an SC roster tab) unless Harsh asks. He objected both times this happened.

## 2. Tabs (current order) and agreed layout

Global filters: City (24 cities + PAN India), Month, From / To date (To is capped at the last complete data day, marked "● Data till X"), Sales channel (Field / Inside / Field+Inside). Levers: Meetings per SC per day (default 2) and Days off (defaults to the Mondays in the range, can be overridden). Header buttons: ⓘ Notes, ↻ Refresh.

1. **Overview**: tiles, plus cards for 🚩 Daily flags, Lead sufficiency and Lead utilisation × Channel.
2. **🚩 Daily flags** (Ajeet's ask: the team owns daily lead-utilisation flags). Editable thresholds: Window days 7, MD vs MOP below 85%, Capacity utilisation below 70%, Conversion drop 7pp. Minimum base fixed at 50 (input box removed). Signals:
   - MD below MOP (city × channel, Field+Inside)
   - SC under-utilised (city level; cause lists BQL short, scheduling low, or MS→MD low vs PAN)
   - Funnel leakage (BQL→MS or MS→MD vs the prior 4 weeks)
   - Column "Actual vs benchmark" uses wording specific to each signal. The "Since" column was removed. Red = deep below threshold, or flagged for the full window.
3. **Lead sufficiency & SC utilisation**: City · SC count (Active) · Meeting capacity · MS to date · MS ÷ capacity · MD · MD / SC (= total MD ÷ SC count) · Capacity utilisation (= total MD ÷ capacity) · Actual MS→MD · MS required at current MS→MD · MD→HoTo · BQL→HoTo. Channel and sub-channel filters. Sort options: MS÷capacity low→high (default), MS÷capacity high→low, SC count high→low, SC count low→high.
   - Removed on request: MD by SCs, Target MD/SC, MS gap, In-training filter, % of target.
4. **SC planner**: same table, but the SC count per city is typed in by hand (saved in localStorage, with a Reset button).
5. **Lead utilisation × Channel**: channel rows (works for PAN India). Columns: BQL · LS LRM · MS · MD · HoTo · BQL→LS LRM · LS LRM→MS · BQL→MS · MS→MD · BQL→MD · MD→HoTo · BQL→HoTo. Lead score band chips (multi-select, laid out horizontally). A second table, "Lead utilisation × Lead score band", has a Channel filter. LS LRM is shown for Digital only.
6. **Lead utilisation × City**: city rows. Selecting Digital adds the LRM columns. Other channels show BQL, MS, MD, HoTo, BQL→MS, MS→MD, BQL→MD, MD→HoTo, BQL→HoTo. **No red/green colouring** (removed 22 Oct).
7. **BQL cohort**: rows are cohorts (selected dates, with LMTD below). Each metric is a column group of M0 | by M1 | by M2. BQL sits under M0 only. ▸ BQL→MD expands to BQL→MS and MS→MD. ▸ BQL→MS expands to BQL→LS LRM and LS LRM→MS (Digital). LMTD is shown to date; a summary line gives the same-age comparison.
8. **MOP tracking**: city table of BQL / MS / MD actual vs MOP MTD, and a city × channel table of MS / MD vs MOP.

Style rules: descriptions kept short and placed at the bottom of each section (management doesn't read long text). Plain tables, no busy charts.

## 3. Data definitions (agreed with Harsh)

- **Cities: only these 24.** Delhi, Ghaziabad, Noida, Gurgaon, Faridabad, Ahmedabad, Surat, Bangalore, Hyderabad, Amravati, Nagpur, Aurangabad, Nashik, Pune, Kolhapur, Bhopal, Gwalior, Indore, Jabalpur, Jaipur, Kanpur, Lucknow, Varanasi, Chennai. PAN India = their total. There is no "Other cities" row.
- **Source:** the "Raw Data" tab (gid `1197917477`) of Harsh's Google Sheet, fed by a BigQuery Connected Sheet on `presales-442917.leadcsv.leads_summary_table`. Data runs from 1 Sep 2026.
- **Header expected by the build:** `Lead_ID,LSQ_City,BQL_Flag,Source_Class,Source_Sub_Class,score,First_Sales_Channel,Sales_Channel,Created_On,lead_delivered_to_lrm,First_Meeting_Schedule_Date,First_Meeting_Done_Date,Order_closure_Date,HoTo_Date,SC_Email_Id` (trailing commas are trimmed before the check).
- **BQL** = BQL_Flag = 1, dated by Created_On.
- **LRM (LS LRM)** = lead_delivered_to_lrm date. Digital only.
- **MS** = First_Meeting_Schedule_Date. Harsh chose the first-meeting date over the last-meeting date. About 2% of leads have an MD before their first MS; Harsh said to ignore this.
- **MD** = First_Meeting_Done_Date.
- **HoTo** = HoTo_Date (col N), split by Sales_Channel (col H).
- **Channel split:** BQL, LRM, MS and MD use First_Sales_Channel (col G). HoTo uses Sales_Channel (col H).
- **Channel mapping:** Digital; Referral; Referral with sub-channel BTL → BTL (shown as "BTL Referral"); "BTL Activity" → BTL; SolarPro; everything else → Others. City is LSQ_City.
- **Lead score bands:** Excellent >9, Good >7, Average >5, Poor ≤5, No score.
- **Basis:** the cohort tab uses BQL leads only (cohort view). All other tabs use the effort view. LMTD is a like-for-like comparison.
- Orders are not shown. Order data is kept for later use.
- **As-of rule:** the latest MD date up to yesterday (IST). Then step back while a day's BQL is below 50% of the median of the prior 7 days, so incomplete days are excluded.

### SC count (rule from 19 Oct)
- Comes from the monthly **manpower CSV** that Harsh downloads and shares each month.
- Field sales: Designation SC or Sr SC, Current Status Active. Inside sales: Designation SC, Active.
- Each month uses its own file. An SC does not need to appear in the raw data to be counted.
- Emails are SHA-256 hashed (first 20 hex characters) in `data/manpower.csv`, so no names or plain emails go to the public repo. Harsh said showing names and emails is fine, but hashing was kept anyway.
- Oct file: 594 Active (515 Field + 79 Inside); 456 Field SCs in the 24 cities.

### MOP
- MOP tab, gid `1033353473`: day-wise for the current month, with no month column. Column map (letters):
  - BQL: G | I+J | O+P | L+M | Q
  - MS: T | V+W | AB+AC | Y+Z | AD
  - MD: AH+AI | AK+AL | AQ+AR | AN+AO | AS
  - Order FS: AW | AY+AZ | BE+BF | BB+BC
- Channel order in the build is Digital, Referral, BTL, SolarPro, Others. The build checks the header layout. If the layout changes, it skips MOP with a note instead of failing.

## 4. Pipeline and automation

```
BigQuery (leads_summary_table)
  → Connected Sheet extract "Raw_Data" (cap 250,000 rows)
  → IMPORTRANGE into the "Raw Data" tab
  → Apps Script exportRaw_(): gzip CSV saved to Drive (file id 1CWnk6LVeAJjFjbejWuSRIAM9JOwMhyvw, anyone-with-link view)
  → GitHub Action refresh.yml runs scripts/build-capacity.ps1 (pwsh) → capacity.json
  → commit → GitHub Pages
```

- **build-capacity.ps1** downloads the Drive gz first. If that fails, it falls back to the published-CSV link (retries while the sheet shows Loading / #REF / #N/A).
- **GitHub Action:** cron `30 2-16/2 * * *` (every 2 h, 08:00–22:00 IST) plus workflow_dispatch.
- **Apps Script (bound to the sheet):** `exportRaw_`, `republishSheet_`, `dispatch_` (POSTs a workflow dispatch using script property `GH_TOKEN`), `triggerDashboardRefresh` (hourly trigger, 08:00–22:00 IST), `doGet` (web app used by the ↻ Refresh button, max once per 10 min).
  - Pending: Harsh needs to redeploy the web app as a **New version** so the Refresh button uses `exportRaw_`.
- **Local push:** `& C:\capdash\scripts\push.ps1 -Files @('index.html','capacity.json')`. Uses user env var `CAP_GH_TOKEN` (fine-grained token). Call it with `&`, not `powershell -File`, when passing an array.
- **Local preview:** `scripts/serve.ps1`, launch config "capdash", port 8765.
- **Token hygiene:** never ask Harsh to paste a token in chat. One token was exposed earlier and was regenerated. Tokens expire around early Jan 2027.

### Monthly upkeep
1. **Manpower:** Harsh shares the new month's CSV. Add a line to `$FILES` in `scripts/build-manpower.ps1`, run it, then run build-capacity.ps1, then push `data/manpower.csv` and `capacity.json`.
2. **MOP (from Nov 2026):** Harsh sends a monthly plan CSV ("MOP Plan <Mon>'26 - MOP_Final_New"). It has one row per cluster with monthly totals, not day-wise. Copy it to `data/mop-YYYY-MM.csv` and push it. The build uses this file in place of the MOP tab and spreads each monthly value evenly over the days of the month. Columns: BQL D/E/K/H/N, MS AR/AS/AY/AV/BB, MD BE/BH/BN/BK/BQ. Surat has no row in the Nov file.
3. **Connected Sheet query date cutoff:** move it forward each month to keep the current and previous month (done for Nov: `'2026-10-01'`; on 1 Dec, change it to `'2026-11-01'`).

## 5. Row-cap fix (27 Oct 2026)

- **Problem:** the Connected Sheets extract is capped at 250,000 rows, so the dashboard was stuck at 22 Oct. Harsh cannot split the tab because it comes from a live query.
- **Fix:** an extra WHERE block in the Connected Sheet query. It keeps a row only if BQL_Flag = 1, or any meeting / order / HoTo date is present, or it is a Digital lead with an LRM date. It also orders by `Created_On DESC`. Raw Data then went to **162,916 rows**.
- Dashboard numbers are unaffected: every row used for BQL, Digital LRM, MS, MD and HoTo is kept.
- Query in use:

```sql
SELECT Opportunity_Id, Lead_ID, LSQ_City, First_Meeting_SC_Email, SC_Email_Id, BQL_Flag, Source_Class, Source_Sub_Class, score,
  First_Sales_Channel, Sales_Channel,
  DATE(Created_On) AS Created_On, DATE(lead_delivered_to_lrm) AS lead_delivered_to_lrm,
  DATE(First_Meeting_Schedule_Date) AS First_Meeting_Schedule_Date, DATE(First_Meeting_Done_Date) AS First_Meeting_Done_Date,
  DATE(Order_closure_Date) AS Order_closure_Date, DATE(Approved_by_customer_Date) AS HoTo_Date, DATE(Meeting_Done_Date) AS Meeting_Done_Date
FROM `presales-442917.leadcsv.leads_summary_table`
WHERE (DATE(Created_On) >= '2026-09-01' OR DATE(lead_delivered_to_lrm) >= '2026-09-01' OR DATE(First_Meeting_Schedule_Date) >= '2026-09-01'
       OR DATE(First_Meeting_Done_Date) >= '2026-09-01' OR DATE(Order_closure_Date) >= '2026-09-01'
       OR DATE(Approved_by_customer_Date) >= '2026-09-01' OR DATE(Meeting_Done_Date) >= '2026-09-01')
  AND (SAFE_CAST(BQL_Flag AS INT64) = 1 OR First_Meeting_Schedule_Date IS NOT NULL OR First_Meeting_Done_Date IS NOT NULL
       OR Meeting_Done_Date IS NOT NULL OR Order_closure_Date IS NOT NULL OR Approved_by_customer_Date IS NOT NULL
       OR (lead_delivered_to_lrm IS NOT NULL AND Source_Class = 'Digital'))
ORDER BY Created_On DESC
```

- **Benchmark for 1–22 Oct** (from before the fix; should stay the same after it): BQL 107,339 · LRM 84,435 · MS 42,786 · MD 27,357 · HoTo 6,411 (to 22 Oct).

- **10 Nov 2026 update:** Harsh moved the query cutoff from `'2026-09-01'` to `'2026-10-01'`. Raw Data went to **114,297 rows** (1 Oct onward). After that the dashboard reached as-of 9 Nov. Checks: Oct BQL 64,974 (complete month); 1–9 Nov BQL 15,741 (1,251–2,174/day). **September is now partial** (BQL 3,270), so don't use Sep in the dashboard. On 1 Dec, move the cutoff to `'2026-11-01'`.
- **Raw sheet:** https://docs.google.com/spreadsheets/d/1GE0RunXmtgKBOdx8SHSKFDqt_Uq05ZcT_aTwbwfcKOs/ (Raw Data gid 1197917477). The built-in browser isn't signed in to Harsh's Google account, and the Drive connector can't see this sheet. Check the data via the Drive gz instead: get_file_metadata on `1CWnk6LVeAJjFjbejWuSRIAM9JOwMhyvw` gives modifiedTime, and the build prints the row count and as-of.
- **The publish-to-web CSV link now returns 401** (the backup route in the build). The main route (Drive gz) works.

## 6. Status on 12 Nov 2026 and open items

- **November done (10 Nov):** manpower file added (443 Active Field SCs in 24 cities; 579 Active SCs overall); MOP plan added as `data/mop-2026-11.csv` (24-city totals BQL 60,449 · MS 24,167 · MD 17,505; matches the file).
- **Live capacity.json on 12 Nov:** as-of **9 Nov**, generated 12 Nov 08:05 IST. The build runs, but the source has no complete day after 9 Nov, so it should be 11 Nov.
  - Check whether the Connected Sheet extract (Raw_Data) is refreshing daily. A scheduled refresh around 9–10 am was recommended; not confirmed that Harsh set it.
  - Then check the Drive gz modifiedTime.
- The sheet script (`triggerDashboardRefresh`) runs hourly and rewrites the Drive gz (confirmed 10 Nov). The GitHub Action rebuilds every 2 h.
- December: manpower CSV + MOP plan CSV from Harsh; move the query cutoff on 1 Dec.
- The Apps Script web app still needs redeploying as a New version (for the ↻ Refresh button).
- Ideas raised but not decided: a daily email digest of flags; owner names per city on flags; "New today / Resolved" tiles; removing colouring from other tables; GitHub failure email notifications.
- `C:\capdash\raw\` holds old local CSV snapshots used for testing. They are not needed by the build.

### 17 Nov 2026
- Every Action run failed from 16 Nov 06:34 UTC: the sheet's MOP tab was cleared, the build crashed on it ("Cannot index into a null array", build-capacity.ps1 MOP block). Fix: the MOP tab is now read only when no `data/mop-YYYY-MM.csv` exists for the as-of month, and an empty/unreadable tab is skipped instead of failing. Dashboard went from as-of 9 Nov to 15 Nov.
- November manpower replaced with the updated file `...November Mapping (1).csv`: 450 Active Field SCs in 24 cities (was 443), 77 Inside, 585 Active overall.
- The local `CAP_GH_TOKEN` cannot trigger workflow_dispatch (403); the sheet's Apps Script does that hourly.

## 7. Working style for this project

- English only, short replies, little preamble. Ready-to-paste steps.
- Make surgical edits to `index.html` and the scripts; don't rebuild from scratch.
- Reconcile after every logic change: PAN = sum of cities = raw totals.
- Harsh pushes back on definitions that weren't asked for (for example how MD/SC is defined). Confirm any metric definition before changing it.
