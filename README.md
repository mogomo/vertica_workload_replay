# Vertica Workload Capture & Replay Tool

This repository provides a script to **capture and replay real query workloads** from a Vertica database. It is useful for benchmarking, testing, and validating query performance in different environments (e.g., EON vs Enterprise mode).

## 📜 What It Does

- Extracts recent successful queries from `QUERY_REQUESTS` and `QUERY_CONSUMPTION`
- Saves SQL text and metadata for each query
- Generates a replay script that:
  - Re-executes each query
  - Collects runtime metrics
  - Compares with the originally captured execution statistics

## 🧰 Files

- `1_save_workload.sh`: Main script for capturing queries and generating the replay script
- `2_replay_saved_workload.sh`: Auto-generated script to replay queries and log performance results
- `workflow_capture.csv`: Captured query metadata
- `SAVED_QUERIES/`: Directory holding individual query `.sql` files and `.meta` data
- `workload_package_*.tar.gz`: Optional archive for transferring workload data between clusters

## ⚙️ Prerequisites

- Vertica client tools installed (`vsql`)
- User with access to `QUERY_REQUESTS` and `QUERY_CONSUMPTION`
- Bash-compatible shell environment

## 🚀 Usage

### 1. Configure the script

Edit the following variables in `1_save_workload.sh`:

```bash
DB_NAME="Your_DB_name"
HOST="Vertica_Host_IP"
PORT="5433"
USER="dbadmin"
PASSWORD="Your_dbadmin_password"
```

### 2. Run the script to save the required queries 
./1_save_workload.sh

### 3. Run the queries via the generated script:
./2_replay_saved_workload.sh



