# Litebar - SQLite Monitoring for Agents

Litebar is a macOS menubar app that monitors SQLite databases. It lives in the menubar and shows database health, table sizes, activity status, and custom watch expressions. It's built for people running agent systems, personal life operating systems, and mission-control dashboards backed by SQLite.

**You are reading this because a project you're working in uses Litebar for monitoring. You can configure what Litebar monitors by editing its config file.**

## Config Location

```
~/Library/Application Support/Litebar/config.yaml
```

Litebar reloads this file automatically on every refresh cycle (default: 60 seconds). Any changes you write take effect on the next refresh.

## What You Can Configure

### Register a Database

Add your project's SQLite database to the `databases` list so Litebar picks it up:

```yaml
databases:
  - path: /absolute/path/to/your/database.db
    name: Human-Readable Name    # optional, shown in the panel
    group: Project Name           # optional, groups databases visually
```

- `path` is required and must be an absolute path to a `.db`, `.sqlite`, or `.sqlite3` file.
- `name` defaults to the filename if not provided.
- `group` is optional. Databases with the same group are shown together.

### Add Watch Expressions

Watch expressions are custom SQL queries that run on every refresh. Each query must return exactly one value (one row, one column). Results are shown in the Litebar panel next to the database.

```yaml
databases:
  - path: /path/to/db.sqlite
    name: My System
    watches:
      - name: Active Tasks
        query: "SELECT COUNT(*) FROM tasks WHERE status = 'active'"

      - name: Failed Jobs (24h)
        query: "SELECT COUNT(*) FROM jobs WHERE status = 'failed' AND created_at > datetime('now', '-24 hours')"
        warn_above: 0

      - name: Queue Depth
        query: "SELECT COUNT(*) FROM tasks WHERE status = 'pending'"
        warn_above: 20

      - name: Today's Cost
        query: "SELECT ROUND(COALESCE(SUM(cost_usd), 0), 2) FROM session_costs WHERE date(created_at) = date('now')"
        format: dollar
        warn_above: 10.00
```

### Watch Expression Fields

| Field | Required | Description |
|-------|----------|-------------|
| `name` | yes | Label shown in the panel |
| `query` | yes | SQL SELECT returning one value. Use `COALESCE()` to handle NULLs. |
| `warn_above` | no | Trigger alert if value exceeds this number |
| `warn_below` | no | Trigger alert if value drops below this number |
| `format` | no | Display format: `number` (default), `dollar`, `bytes`, `percent`, `text` |

When a threshold is crossed, Litebar fires a macOS notification and shows the value in orange/red in the panel. Notifications only fire on state transitions (normal -> warning), not repeatedly.

### Global Settings

```yaml
refresh_interval: 60              # seconds between refresh cycles
activity_timeout_minutes: 30      # flag database as "quiet" after this many minutes of no writes
```

## What Litebar Monitors Automatically

For each registered database, Litebar tracks:

- **Health**: runs `PRAGMA integrity_check`, checks freelist fragmentation, WAL checkpoint status
- **Activity pulse**: monitors filesystem last-modified time. If no writes happen for `activity_timeout_minutes`, the database is flagged as "quiet" with a visible badge. Useful for detecting crashed agents or stalled pipelines.
- **Table deltas**: tracks row count changes between refreshes. Shows +/- indicators when tables grow or shrink.
- **File size**: total size including WAL and SHM files
- **Metadata**: journal mode, page size, page count, encoding, SQLite version

## Common Watch Patterns for Agent Systems

### Stuck tasks
```yaml
- name: Stuck Tasks
  query: "SELECT COUNT(*) FROM tasks WHERE status = 'in_progress' AND updated_at < datetime('now', '-2 hours')"
  warn_above: 0
```

### Agent heartbeat freshness (minutes since last heartbeat)
```yaml
- name: Last Heartbeat
  query: "SELECT CAST((julianday('now') - julianday(MAX(last_heartbeat))) * 1440 AS INTEGER) FROM agent_sessions"
  format: text
  warn_above: 30
```

### Daily token burn
```yaml
- name: Tokens Today
  query: "SELECT COALESCE(SUM(total_tokens), 0) FROM runs WHERE date(created_at) = date('now')"
  format: number
  warn_above: 500000
```

### Database size
```yaml
- name: DB Size
  query: "SELECT page_count * page_size FROM pragma_page_count(), pragma_page_size()"
  format: bytes
```

### Error rate
```yaml
- name: Error Rate (1h)
  query: "SELECT ROUND(100.0 * COUNT(CASE WHEN status = 'failed' THEN 1 END) / MAX(COUNT(*), 1), 1) FROM runs WHERE created_at > datetime('now', '-1 hour')"
  format: percent
  warn_above: 10
```

## Guidelines for Agents

1. **Read the existing config first** before making changes. Preserve existing databases and watches.
2. **Use `COALESCE()`** in queries to avoid NULL results (e.g., `COALESCE(SUM(x), 0)`).
3. **Queries must return exactly one value** -- one row, one column. Litebar will error on multi-row results.
4. **Use absolute paths** for database paths. Relative paths won't resolve correctly.
5. **Set meaningful thresholds**. `warn_above: 0` on error/failure counts is a common pattern.
6. **Group related databases** using the `group` field for visual organization.
7. **Don't set the refresh interval below 10 seconds** -- it creates unnecessary load.
8. **Test your queries** against the database before adding them to the config. A broken query shows as a red error in the panel but doesn't crash anything.
