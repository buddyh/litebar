# Litebar Runtime Agent Guide

Litebar is an agent-operated SQLite observability panel. Your job is to keep `config.yaml` in this folder accurate and useful for the human operator.

## Directory Contract

- `config.yaml`: source of truth for what Litebar monitors.
- `AGENTS.md`: this guide. Keep it present for future agents.
- `backups/`: optional output location for manual backups triggered in the app UI.
- Use absolute database paths.

## Config Schema

```yaml
refresh_interval: 60
activity_timeout_minutes: 30
databases:
  - path: /absolute/path/to/app.sqlite
    name: Optional Display Name
    group: Optional Group Name
    watches:
      - name: Label
        query: "SELECT COUNT(*) FROM table_name"
        warn_above: 100
        warn_below: 5
        format: number
```

## Field Semantics

- `refresh_interval`: seconds between refresh cycles (must be >= 10).
- `activity_timeout_minutes`: database is marked quiet when no writes occur in this window.
- `databases[].path`: absolute SQLite path.
- `databases[].name`: optional display label.
- `databases[].group`: optional grouping label.
- `watches[]`: optional list of single-value SQL checks.

## Watch Rules

- Query must return exactly one value (one row, one column).
- Use `COALESCE()` for aggregates that may return `NULL`.
- Supported formats: `number`, `dollar`, `bytes`, `percent`, `text`.
- Thresholds:
  - `warn_above`: warning when value is greater than threshold.
  - `warn_below`: warning when value is less than threshold.

## Capabilities Litebar Computes Automatically

- Database health checks (integrity, fragmentation, WAL pressure signal)
- Last write activity and quiet detection
- Full table list and row counts
- Table row-count deltas between refreshes
- DB + WAL + SHM total size
- SQLite metadata (journal mode, page size/count, encoding, version)

## Agent Guidance

- Optimize for signal quality, not query count.
- Prefer short, deterministic watch names.
- Set thresholds that map to clear operator action.
- Preserve existing intent when editing config.
- Avoid expensive full-table scans in frequent watches when alternatives exist.

## Example Watch Patterns

```yaml
- name: Failed Jobs (1h)
  query: "SELECT COUNT(*) FROM jobs WHERE status = 'failed' AND created_at > datetime('now', '-1 hour')"
  warn_above: 0

- name: Last Heartbeat Minutes
  query: "SELECT CAST((julianday('now') - julianday(MAX(last_heartbeat))) * 1440 AS INTEGER) FROM worker_heartbeats"
  warn_above: 15

- name: Queue Depth
  query: "SELECT COUNT(*) FROM work_queue WHERE status = 'pending'"
  warn_above: 50
```

## Example Use Cases

- Agent mission-control SQLite systems (runs, costs, queue depth, failures)
- Personal automation state stores
- Local-first app telemetry stores
- Any SQLite workflow requiring passive operational visibility
