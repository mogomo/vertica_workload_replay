#!/bin/bash
# 1_save_workload.sh    Query collector and replay script generator
# Usage:                ./1_save_workload.sh
# Author:               Moshe
#
# BEFORE RUNNING:
# 1. Adjust the database connection settings below as needed:
#    DB_NAME     - Name of your Vertica database
#    HOST        - Hostname or IP of the Vertica server
#    PORT        - Port (default: 5433)
#    USER        - User with access to system tables
#    PASSWORD    - Corresponding password
#
# 2. (Optional) Change these parameters to fine-tune query selection:
#    START_TIME / END_TIME - Time window to filter queries
#    QUERIES_LABEL         - If set, filters only queries with this label
#    QUERIES_COUNT_LIMIT   - Max number of queries to collect


# CONFIGURATION
DB_NAME="Your_DB_name"
VSQL="/opt/vertica/bin/vsql"
USER="dbadmin"
PASSWORD="Your_dbadmin_password"
HOST="10.10.10.10"
PORT="5433"

# Conditions for choosing which queries to save and run again
# The below default time window is 10 minutes backwards and queries with no specific Label definition
# QUERIES_COUNT_LIMIT sets the maximum number of queries to save for replay later
END_TIME=$(date '+%Y-%m-%d %H:%M:%S')
START_TIME=$(date -d '-10 minutes' '+%Y-%m-%d %H:%M:%S')
QUERIES_LABEL=""
QUERIES_COUNT_LIMIT=50

# Seting files and dir names
COLLECT_FILE="workflow_capture.csv"
REPLAY_SCRIPT="2_replay_saved_workload.sh"
QUERY_DIR="SAVED_QUERIES"

# Cleanup old files
if [[ -f "$COLLECT_FILE" || -f "$REPLAY_SCRIPT" || -d "$QUERY_DIR" || $(ls workload_package_*.tar.gz 2>/dev/null | wc -l) -gt 0 ]]; then
  read -p "❓ Delete old files from previous run? (y/n): " CONFIRM
  if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
    rm -f "$COLLECT_FILE" "$REPLAY_SCRIPT"
    rm -rf "$QUERY_DIR"
    rm -f workload_package_*.tar.gz
    echo "✅ Old files deleted."
  else
    echo "🛑 Operation aborted due to existing files."
    exit 1
  fi
fi

mkdir -p "$QUERY_DIR"

[[ -z "$START_TIME" || -z "$END_TIME" ]] && { echo "❌ Error: START_TIME and END_TIME must both be defined."; exit 1; } || echo "🔵 Capturing queries between $START_TIME and $END_TIME ..."
[[ -n "$QUERIES_LABEL" ]] && echo "🔵 Capturing queries with LABEL $QUERIES_LABEL ..."

# Creating simple tables repository of Vertica system tables for faster response
$VSQL -h "$HOST" -d "$DB_NAME" -U "$USER" -w "$PASSWORD" -Xf - <<-EOF
DROP TABLE IF EXISTS MY_QUERY_REQUESTS_REPOSITORY CASCADE;
DROP TABLE IF EXISTS MY_QUERY_CONSUMPTION_REPOSITORY CASCADE;

CREATE TABLE MY_QUERY_REQUESTS_REPOSITORY AS
SELECT * FROM QUERY_REQUESTS
WHERE START_TIMESTAMP BETWEEN '$START_TIME' AND '$END_TIME';

CREATE TABLE MY_QUERY_CONSUMPTION_REPOSITORY AS
SELECT * FROM QUERY_CONSUMPTION
WHERE START_TIME BETWEEN '$START_TIME' AND '$END_TIME';
EOF

# Step 1: Collect successful query handles with their consumption metrics in one query
SQL_QUERY=$(cat <<EOF
SELECT
    qr.TRANSACTION_ID,
    qr.STATEMENT_ID,
    qr.REQUEST_ID,
    TO_CHAR(qr.END_TIMESTAMP, 'YYYY-MM-DD HH24:MI:SS.US TZ') as END_TS,
    qr.REQUEST_DURATION_MS as ELAPSED,
    qr.USER_NAME,
    qc.DURATION_MS,
    qc.OUTPUT_ROWS,
    qc.RESOURCE_POOL
FROM MY_QUERY_REQUESTS_REPOSITORY qr
JOIN MY_QUERY_CONSUMPTION_REPOSITORY qc
    ON qr.TRANSACTION_ID = qc.TRANSACTION_ID
    AND qr.STATEMENT_ID = qc.STATEMENT_ID
WHERE qr.REQUEST_TYPE = 'QUERY'
    AND qr.SUCCESS = true
    AND qr.END_TIMESTAMP IS NOT NULL
    AND qc.RESOURCE_POOL NOT IN ('dbd','jvm','metadata','recovery','refresh','sysquery','tm')
EOF
)

[[ -n "$QUERIES_LABEL" ]] && SQL_QUERY+=" AND qr.REQUEST_LABEL = '$QUERIES_LABEL'"
[[ -n "$START_TIME" && -n "$END_TIME" ]] && SQL_QUERY+=" AND qr.START_TIMESTAMP BETWEEN '$START_TIME' AND '$END_TIME'"
SQL_QUERY+=" ORDER BY qr.END_TIMESTAMP LIMIT ${QUERIES_COUNT_LIMIT};"

# Step 2: Execute the query and write to file
$VSQL -h "$HOST" -d "$DB_NAME" -U "$USER" -w "$PASSWORD" \
  -F'|' -P null='NULL' -AXtnqc "$SQL_QUERY" > "$COLLECT_FILE"

# Step 3: Validate results
[[ $? -ne 0 ]] && echo "❌ Failed to collect workload." && exit 1
[[ ! -s "$COLLECT_FILE" ]] && echo "🛑 Didn't find any queries qualified for the replay conditions." && exit 0

echo "✅ Queries saved to $COLLECT_FILE"

# Step 4: Process each query and create metadata files
count=0
while IFS='|' read -r TXN_ID STMT_ID REQ_ID END_TS ELAPSED USERNAME DURATION_MS OUTPUT_ROWS RESOURCE_POOL; do
  [[ -z "$TXN_ID" || -z "$STMT_ID" || -z "$REQ_ID" || -z "$USERNAME" ]] && continue

  BASE_NAME="query_${TXN_ID}_${STMT_ID}_${REQ_ID}"
  META_FILE="${QUERY_DIR}/${BASE_NAME}.meta"
  SQL_FILE="${QUERY_DIR}/${BASE_NAME}.sql"

  # Handle null values with defaults
  [[ -z "$DURATION_MS" ]] && DURATION_MS="$ELAPSED"
  [[ -z "$OUTPUT_ROWS" ]] && OUTPUT_ROWS=0
  [[ -z "$RESOURCE_POOL" ]] && RESOURCE_POOL="general"

  # Write .meta
  cat <<EOF > "$META_FILE"
end_timestamp=$END_TS
expected_elapsed_ms=$DURATION_MS
expected_output_rows=$OUTPUT_ROWS
resource_pool=$RESOURCE_POOL
user_name=$USERNAME
EOF

  # Save SQL
  $VSQL -h "$HOST" -d "$DB_NAME" -U "$USER" -w "$PASSWORD" -AXtqc "
    SELECT REQUEST
    FROM MY_QUERY_REQUESTS_REPOSITORY
    WHERE TRANSACTION_ID = $TXN_ID AND STATEMENT_ID = $STMT_ID AND REQUEST_ID = $REQ_ID;" > "$SQL_FILE"

  echo "SET SESSION RESOURCE_POOL = '$RESOURCE_POOL';" | cat - "$SQL_FILE" > "$SQL_FILE.tmp" && mv "$SQL_FILE.tmp" "$SQL_FILE"

  count=$((count + 1))
  printf "\r✅ Saved %d queries..." "$count"
done < "$COLLECT_FILE"

printf "\n✅ Saved %d queries and metadata into %s\n" "$count" "$QUERY_DIR"

# Step 5: Generate aligned replay script
cat <<EOF1 > "$REPLAY_SCRIPT"
#!/bin/bash
DB_NAME="${DB_NAME}"
VSQL="${VSQL}"
USER="${USER}"
PASSWORD="${PASSWORD}"
HOST="${HOST}"
PORT="${PORT}"
QUERY_DIR="${QUERY_DIR}"
EOF1

cat <<'EOF2' >> "$REPLAY_SCRIPT"
#!/bin/bash

$VSQL -h "$HOST" -d "$DB_NAME" -U "$USER" -w "$PASSWORD" -AXtqc "DROP TABLE IF EXISTS my_workload_log_ezer_table CASCADE; "
$VSQL -h "$HOST" -d "$DB_NAME" -U "$USER" -w "$PASSWORD" -AXtqc "CREATE TABLE my_workload_log_ezer_table ( QUERY varchar(200), EXPECTED_ELAPSED_MS INT, CURRENT_ELAPSED_MS INT, EXPECTED_OUTPUT_ROWS INT, CURRENT_OUTPUT_ROWS INT, CURRENT_TRANSACTION_ID INT, CURRENT_STATEMENT_ID INT ); "

count=0
for QUERY_FILE in $QUERY_DIR/*.sql; do
  BASE_NAME="${QUERY_FILE%.sql}"
  META_FILE="${BASE_NAME}.meta"
  OUT_FILE="${BASE_NAME}.out"

  saved_end_ts=$(grep '^end_timestamp=' "$META_FILE" | cut -d= -f2-)
  expected_elapsed_ms=$(grep '^expected_elapsed_ms=' "$META_FILE" | cut -d= -f2)
  expected_output_rows=$(grep '^expected_output_rows=' "$META_FILE" | cut -d= -f2)
  user_name=$(grep '^user_name=' "$META_FILE" | cut -d= -f2)

  echo >> $QUERY_FILE
  echo "INSERT INTO my_workload_log_ezer_table
        SELECT '${QUERY_FILE}' as QUERY, ${expected_elapsed_ms} as EXPECTED_ELAPSED_MS, DURATION_MS as CURRENT_ELAPSED_MS,
               ${expected_output_rows} as EXPECTED_OUTPUT_ROWS, OUTPUT_ROWS as CURRENT_OUTPUT_ROWS,
               current_trans_id() as CURRENT_TRANSACTION_ID, current_statement()-1 as CURRENT_STATEMENT_ID
        FROM QUERY_CONSUMPTION
        WHERE transaction_id=current_trans_id() AND (statement_id = current_statement()-1) ;
        COMMIT;" >> $QUERY_FILE

  count=$((count + 1))
  printf "\r✅ Running query %d ..." "$count"
  $VSQL -h "$HOST" -d "$DB_NAME" -U "$USER" -w "$PASSWORD" -f "$QUERY_FILE" -o "$OUT_FILE" 2>/dev/null
done

echo "🏁 All queries replayed."
$VSQL -h "$HOST" -d "$DB_NAME" -U "$USER" -w "$PASSWORD" -Xc "SELECT QUERY,EXPECTED_ELAPSED_MS,CURRENT_ELAPSED_MS,EXPECTED_OUTPUT_ROWS,CURRENT_OUTPUT_ROWS FROM my_workload_log_ezer_table ORDER BY 1;"
EOF2

chmod +x "$REPLAY_SCRIPT"
echo "✅ Replay script generated successfully."
echo
read -p "📦 Do you want to package the saved workload files for transfer to another cluster? (y/n): " PACK_CONFIRM
if [[ "$PACK_CONFIRM" =~ ^[Yy]$ ]]; then
  PACKAGE_NAME="workload_package_$(date +%Y%m%d_%H%M%S).tar.gz"
  THIS_SCRIPT="$0"
  cp ${THIS_SCRIPT} ${THIS_SCRIPT}_backup
  tar -czf "$PACKAGE_NAME" \
    "$THIS_SCRIPT" \
    "$REPLAY_SCRIPT" \
    "$COLLECT_FILE" \
    "$QUERY_DIR"
  echo "✅ All files packaged into $PACKAGE_NAME"
  echo "📤 Transfer it to the target cluster and extract using: tar -xzf $PACKAGE_NAME"
  echo "   And run:   ./$REPLAY_SCRIPT"
else
  echo "✅ To run all query files located in dir ${QUERY_DIR} do:   ./$REPLAY_SCRIPT"
fi

