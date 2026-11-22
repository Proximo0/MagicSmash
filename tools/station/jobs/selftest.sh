#!/usr/bin/env bash
# A queue `shell` job that does nothing heavy: `kind=shell args=script=selftest` proves a station can run a job file.
# Contract for any jobs/<name>.sh: the last line printed is the summary (start it with PASS, FAIL or INFO); exit non-zero = FAIL;
# files written to $STATION_JOB_ART are published (2 MB cap); $STATION_JOB_SEED is a fresh seed; words after script=NAME arrive as $1...
echo "INFO selftest ok seed=${STATION_JOB_SEED:-0} words=$*"
