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
