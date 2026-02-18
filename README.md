# Litebar

Menu bar observability for SQLite-backed systems.

Litebar is a macOS menubar app for people running systems that rely on SQLite as an operational datastore. It is built for agent-operated workflows: agents maintain monitor configuration, and humans use Litebar for fast, passive situational awareness.

## Requirements

- macOS 15 or newer
- SQLite databases you want to monitor

## Who This Is For

- Builders running agent orchestration stacks backed by SQLite
- Operators managing local-first app state stores
- Individuals using SQLite as a personal automation backbone
- Teams that want low-friction visibility into health, activity, and throughput

Litebar is not limited to mission-control agent databases. That is one common use case, but any SQLite-backed workflow can use it.

## Core Workflows

1. Agent-managed monitoring setup
- Your agent updates `~/.litebar/config.yaml` with database paths, groups, and watches.
- Litebar picks up updates automatically on the next refresh cycle.

2. Live operational review
- Open Litebar from the menu bar to see health, quiet status, size, deltas, and watch values.
- Expand a database row for full table list and detailed metadata.

3. Alert-driven response
- Configure thresholds in watches.
- Litebar sends notifications on transitions into warning/critical states.

4. Point-in-time backup
- Use per-database backup action to write a copy under `~/.litebar/backups/`.

## Installation

### Homebrew (tap)

```bash
brew tap buddyh/litebar
brew install --HEAD buddyh/litebar/litebar
```

Launch:

```bash
litebar
```

### Build From Source

```bash
git clone https://github.com/buddyh/litebar.git
cd litebar
swift build -c release
.build/release/Litebar
```

## Runtime Directory

Litebar uses:

```bash
~/.litebar/
```

On first run, Litebar ensures:

- `~/.litebar/config.yaml`
- `~/.litebar/AGENTS.md`
- `~/.litebar/backups/`

`~/.litebar/AGENTS.md` is a built-in guide for future agents that need to modify configuration safely.

Template sources in this repository:

- `Sources/Resources/litebar/config.yaml`
- `Sources/Resources/litebar/AGENTS.md`

## Configuration Schema

```yaml
refresh_interval: 60
activity_timeout_minutes: 30
databases:
  - path: /absolute/path/to/app.sqlite
    name: App DB
    group: Production
    watches:
      - name: Failed Jobs (1h)
        query: "SELECT COUNT(*) FROM jobs WHERE status = 'failed' AND created_at > datetime('now', '-1 hour')"
        warn_above: 0

      - name: Queue Depth
        query: "SELECT COUNT(*) FROM queue WHERE status = 'pending'"
        warn_above: 50

      - name: Cost Today
        query: "SELECT ROUND(COALESCE(SUM(cost_usd), 0), 2) FROM sessions WHERE date(created_at) = date('now')"
        warn_above: 25
        format: dollar
```

## What Litebar Computes Automatically

Without extra configuration, Litebar inspects each registered database and shows:

- Integrity and fragmentation health
- Last write activity and quiet detection
- Full table list with row counts
- Table row-count deltas between refreshes
- DB + WAL + SHM total size
- SQLite metadata (journal mode, page size/count, encoding, version)

## What Comes From Config

Your agent-controlled config determines:

- Which databases are shown (`path`)
- Display names and grouping (`name`, `group`)
- Watch labels/queries/formats (`watches`)
- Alert thresholds (`warn_above`, `warn_below`)
- Refresh and quiet timing (`refresh_interval`, `activity_timeout_minutes`)

## Agent Operation Guidelines

- Use absolute database paths only.
- Keep `refresh_interval >= 10` seconds.
- Write watch queries that return exactly one value (one row, one column).
- Use `COALESCE()` for aggregate queries that may return `NULL`.
- Prefer actionable alerts over vanity metrics.

## UI Action Behavior

Per-database actions in expanded rows:

- `Refresh`: re-inspects metadata and reruns watches for that database.
- `Health Check`: reruns health diagnostics for that database.
- `Backup`: writes a backup copy and reports success/failure in-row.

## Development

```bash
swift build
swift test
```

## License

MIT
