# Vertica Workload Capture & Replay Tool

This repository provides a **single script** `1_save_workload.sh` to **capture and replay query workloads** from a Vertica database. It is intended for performance validation, workload benchmarking, and environment comparison (e.g., Enterprise vs. EON mode).

> ⚠️ **Disclaimer**  
> This script is provided as-is, without any warranty. Use at your own risk and only in test environments. Always validate the output before using in production scenarios.

---

## 📌 What This Script Does

- Extracts recent successful queries from `QUERY_REQUESTS` and `QUERY_CONSUMPTION`.
- Saves each query as a `.sql` file along with metadata (`duration`, `output_rows`, `user`, `resource_pool`).
- Automatically generates a replay script (`2_replay_saved_workload.sh`) to:
  - Replay all queries.
  - Record and compare expected vs actual execution metrics.

All output files are generated at runtime by `1_save_workload.sh`. 

---

## 🧰 Script Overview: `1_save_workload.sh`

### Key Responsibilities:
- Connects to a Vertica database using `vsql`.
- **Creates temporary copies** of `QUERY_REQUESTS` and `QUERY_CONSUMPTION` as regular tables:
  - `MY_QUERY_REQUESTS_REPOSITORY`
  - `MY_QUERY_CONSUMPTION_REPOSITORY`
  > 💡 *This improves performance and avoids repeatedly querying the large system tables.*
- Captures a list of successful user queries using a time window.
- Filters out internal/system queries and those from specific resource pools.
- Extracts SQL text for each query.
- Writes metadata and SQL files into the `SAVED_QUERIES/` directory.
- Creates a replay script that re-runs each query and logs performance.
- Optionally packages all replay files into a `.tar.gz` archive.

### Configuration Parameters:
Edit the following variables in the script before use:

```bash
DB_NAME="YourDatabase"
HOST="VerticaHost"
PORT="5433"
USER="dbadmin"
PASSWORD="your_password"

# Optional tuning:
START_TIME="..."       # Default: 10 minutes ago
END_TIME="..."         # Default: now
QUERIES_LABEL="..."    # Optional label filter
QUERIES_COUNT_LIMIT=50 # Max queries to capture
```

## 🚀 How to Use

1. Edit `1_save_workload.sh` to configure:
   - `DB_NAME`, `HOST`, and Vertica credentials
   - `START_TIME`, `END_TIME`, `QUERIES_COUNT_LIMIT`
2. Run the script:
   ```bash
   ./1_save_workload.sh
   ```
3.	When prompted, confirm deletion of any previous output files.
4.	Run the generated replay script:
```bash
   ./2_replay_saved_workload.sh
```


## 🖥️ Example Output
Below is a sample run demonstrating how the script captures queries, generates the replay script, and compares expected vs. actual performance metrics after replaying the queries.
```bash
$ ./1_save_workload.sh
❓ Delete old files from previous run? (y/n): y
✅ Old files deleted.
🔵 Capturing queries between 2025-05-02 23:17:42 and 2025-05-02 23:27:42 ...
✅ Queries saved to workflow_capture.csv
✅ Saved 6 queries...
✅ Saved 6 queries and metadata into SAVED_QUERIES
✅ Replay script generated successfully.

📦 Do you want to package the saved workload files for transfer to another cluster? (y/n): n
✅ To run all query files located in dir SAVED_QUERIES do:   ./2_replay_saved_workload.sh

$ ./2_replay_saved_workload.sh
✅ Running query 6 ...🏁 All queries replayed.
         QUERY                  | EXPECTED_ELAPSED_MS | CURRENT_ELAPSED_MS | EXPECTED_OUTPUT_ROWS | CURRENT_OUTPUT_ROWS
--------------------------------+---------------------+--------------------+----------------------+---------------------
query_45035996276295685_1_1.sql |                  27 |                 23 |                    5 |                   5
query_45035996276295685_2_2.sql |                1955 |               1974 |              4353372 |             4353372
query_45035996276295685_3_3.sql |                  38 |                 35 |                    4 |                   4
query_45035996276295685_5_5.sql |                 360 |                354 |                61025 |               61025
query_45035996276295685_7_7.sql |                  31 |                 32 |                  152 |                 152
query_45035996276295685_8_8.sql |                  26 |                 28 |                    0 |                   0
(6 rows)
```

