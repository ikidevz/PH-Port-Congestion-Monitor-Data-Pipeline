# PH Port Congestion Monitor

> Real-time vessel event pipeline for Philippine ports — Python · dbt · Airflow · PostgreSQL · Docker

---

![IMG](https://tdhghaslnufgtzjybhhf.supabase.co/storage/v1/object/public/content/Data%20Engineering/PH-Port-Congestion-Monitor/archtecture_sketch.png)

## What this is

A batch + real-time data engineering pipeline that simulates and processes vessel arrival/departure events across six major Philippine ports. It computes per-port congestion scores every hour, surfaces them in Grafana, and fires alerts when thresholds are breached.

Built on two principles: **80/20** (biggest impact, least code) and **Unix philosophy** (small, single-purpose components that compose cleanly).

---

## Architecture

```
[generator.py] → raw.vessel_events (PostgreSQL)
                        │
                  [dbt run]
                        │
         ┌──────────────┴──────────────┐
         │                             │
 staging.vessel_events    marts.congestion_scores
                                       │
                          marts.vessel_turnaround
                                       │
                             [alert.py]   [Grafana]
                                       │
                               marts.alert_log
```

**Orchestrated by Airflow.** One DAG runs every 15 minutes: generate → dbt run → dbt test → alert check.

---

## Ports modelled

| Code | Port                                                | Berths |
| ---- | --------------------------------------------------- | ------ |
| MNL  | Port of Manila (MICT / South Harbor / North Harbor) | 22     |
| CEB  | Cebu International Port                             | 5      |
| DVO  | Sasa Port Davao                                     | 7      |
| ILO  | Iloilo Commercial Port Complex                      | 5      |
| GEN  | General Santos Fishport Complex (Makar Wharf)       | 6      |
| ZAM  | Zamboanga Port                                      | 4      |
| BTG  | Batangas International Port                         | 8      |
| CGY  | Port of Cagayan de Oro (Macabalan)                  | 7      |
| SUB  | Subic Bay Port and Freeport Zone                    | 25     |
| TAC  | Port of Tacloban                                    | 4      |
| OZA  | Port of Ozamiz                                      | 3      |
| ILG  | Port of Iligan                                      | 5      |
| PAG  | Port of Pagadian                                    | 3      |
| CBO  | Port of Cotabato                                    | 4      |
| DIP  | Port of Dipolog                                     | 3      |
| TAG  | Port of Tagbilaran                                  | 4      |
| TAC2 | Port of Catbalogan                                  | 3      |
| SUG  | Port of Surigao                                     | 4      |
| BUT  | Port of Butuan (Masao)                              | 3      |
| LBP  | Port of Legazpi                                     | 4      |
| ROM  | Port of Romblon                                     | 2      |
| MAS  | Port of Masbate                                     | 3      |

---

## Data model

Three-layer warehouse (Medallion architecture): `raw` → `staging` → `marts`.

### raw.vessel_events

Source-of-truth. Append-only. Never mutated after insert.

| Column                | Type         | Notes                     |
| --------------------- | ------------ | ------------------------- |
| event_id              | UUID         | PK                        |
| vessel_name           | VARCHAR(120) | e.g. `MV Cebu Princess`   |
| imo_number            | VARCHAR(20)  | e.g. `IMO1234567`         |
| port_code             | VARCHAR(5)   | MNL / CEB / DVO …         |
| berth_id              | SMALLINT     | 1 → port.berth_count      |
| event_type            | VARCHAR(15)  | `ARRIVAL` or `DEPARTURE`  |
| cargo_type            | VARCHAR(20)  | CONTAINER / RORO / BULK … |
| gross_tonnage         | INTEGER      |                           |
| draft_meters          | NUMERIC(4,1) |                           |
| expected_duration_hrs | NUMERIC(5,1) | planned port stay         |
| event_timestamp       | TIMESTAMPTZ  | UTC                       |
| source                | VARCHAR(20)  | `synthetic`               |

### marts.congestion_scores

One row per port per hour. Primary analytics surface.

| Column                          | Notes                                        |
| ------------------------------- | -------------------------------------------- |
| congestion_score                | 0–100 weighted composite (see formula below) |
| congestion_level                | LOW / MODERATE / HIGH / CRITICAL             |
| berth_utilisation_pct           | active vessels / berth capacity              |
| avg_wait_hours / max_wait_hours | derived from turnaround model                |

### marts.vessel_turnaround

Paired ARRIVAL → DEPARTURE per vessel per port call. Computes delay hours.

### marts.alert_log

Immutable breach log. `notified = FALSE` rows are pending delivery.

---

## Congestion score formula

```sql
congestion_score =
    (active_vessels / berth_capacity)         * 0.40   -- berth fill rate
  + (avg_wait_hours / 24.0)                   * 0.35   -- normalised wait time
  + (arrivals_last_hour / avg_arrival_rate)   * 0.25   -- arrival surge factor
) * 100
```

| Score  | Level    |
| ------ | -------- |
| 0–39   | LOW      |
| 40–59  | MODERATE |
| 60–79  | HIGH     |
| 80–100 | CRITICAL |

---

## Synthetic data

PPA (Philippine Ports Authority) has no clean public API. AIS vessel data requires paid subscriptions. This project uses a Python generator (`ingestion/generator.py`) that produces realistic vessel events modelled after PPA vessel manifests — realistic vessel names, cargo distributions, berth counts, and time-of-day arrival patterns.

> All vessel names, IMO numbers, and events are synthetic. No real vessel data is used.

---

## Project structure

```
ph-port-monitor/
├── docker/
│   ├── docker-compose.yml              # Postgres + Airflow + Grafana
│   ├── init.sql                        # Creates airflow DB, runs DDL on first boot
│   ├── 02_ddl.sql                      # Schema copy used by Postgres init
│   └── grafana/
│       └── provisioning/
│           └── datasources/
│               └── postgres.yml        # Auto-provisions PostgreSQL datasource
├── ingestion/
│   └── generator.py                    # Real-time event emitter (runs continuously)
├── sql/
│   ├── ddl.sql                         # Full schema: raw + staging + marts
│   └── analytics_queries.sql           # 20+ queries across 5 tiers (MON/KPI/OPS/TRD/DX)
├── dbt/
│   ├── dbt_project.yml
│   ├── profiles.yml                    # Reads PG connection from env vars
│   ├── packages.yml                    # dbt_utils dependency
│   ├── models/
│   │   ├── staging/
│   │   │   ├── sources.yml             # raw.vessel_events + raw.ports source tests
│   │   │   ├── schema.yml              # stg_vessel_events model tests
│   │   │   └── stg_vessel_events.sql   # Cleaned + derived fields (view)
│   │   └── marts/
│   │       ├── schema.yml              # congestion_scores + vessel_turnaround tests
│   │       ├── congestion_scores.sql   # Weighted score per port per hour (table)
│   │       └── vessel_turnaround.sql   # ARRIVAL→DEPARTURE pairing + delay (table)
│   ├── analyses/
│   │   └── congestion_score_distribution.sql  # Ad-hoc score spread analysis (DX-04)
│   ├── macros/
│   │   └── helpers.sql                 # ph_now() and score_to_level() macros
│   ├── snapshots/
│   │   └── congestion_level_history.sql # SCD Type 2 — tracks level changes over time
│   └── tests/
│       ├── assert_congestion_score_in_range.sql  # Score must be 0–100
│       └── assert_no_negative_turnaround.sql     # No negative actual duration
├── airflow/
│   └── dags/
│       └── port_pipeline.py            # 15-min DAG: generate → dbt run → dbt test → alert
├── alerting/
│   └── alert.py                        # Threshold monitor → webhook / SMTP
├── dashboard/
│   └── grafana_dashboard.json          # Pre-built 7-panel dashboard, import directly
├── .env.example                        # All environment variables with defaults
├── requirements.txt                    # psycopg2-binary, dbt-postgres
└── README.md
```

---

## Environment variables

```dotenv
# Database
PG_HOST=localhost
PG_PORT=5432
PG_DB=port_monitor
PG_USER=postgres
PG_PASS=postgres

# Generator tuning
INTERVAL_SECONDS=5        # seconds between events (default: 5)
BURST_CHANCE=0.05         # probability of multi-event burst (default: 5%)

# Alerting
ALERT_WEBHOOK_URL=        # Slack / Teams / Discord webhook URL
ALERT_SMTP_HOST=          # optional SMTP for email alerts
ALERT_THRESHOLD=75        # congestion_score that triggers an alert
```

Copy `.env.example` to `.env` and fill in your values before running.

---

## Running it

```bash
# 1. Spin up infrastructure
docker compose -f docker/docker-compose.yml up -d

# 2. Schema is auto-applied on first Postgres boot via docker/init.sql
#    To apply manually:
psql $DATABASE_URL -f sql/ddl.sql

# 3. Install Python dependencies
pip install -r requirements.txt

# 4. Start real-time generator (runs continuously, emits every 5 seconds)
python ingestion/generator.py

# 5. Install dbt packages (first time only)
cd dbt && dbt deps

# 6. Run transforms manually (Airflow handles this in production)
dbt run && dbt test

# 7. Check alerts
python alerting/alert.py
```

---

## DAG schedule

```
port_pipeline (every 15 min)
  └── generate_batch     → emits 60 synthetic events into raw.vessel_events
  └── dbt_run            → dbt run --select staging+ marts+
  └── dbt_test           → dbt test (schema + custom tests)
  └── alert_check        → alert.py — fires webhook/email on threshold breach
```

Airflow UI: http://localhost:8080 (admin / admin)

---

## dbt model details

| Model               | Materialization | Description                                                                |
| ------------------- | --------------- | -------------------------------------------------------------------------- |
| `stg_vessel_events` | View            | Cleans raw events; adds `event_date`, `event_hour`, `is_peak_hour`         |
| `vessel_turnaround` | Table           | Pairs ARRIVAL→DEPARTURE per IMO+port; computes `delay_hrs`, `is_delayed`   |
| `congestion_scores` | Table           | Weighted composite score per port per hour; calls `marts.score_to_level()` |

**Custom tests:**

- `assert_congestion_score_in_range` — score must be 0–100
- `assert_no_negative_turnaround` — actual duration must be positive

**Snapshot:**

- `congestion_level_history` — SCD Type 2 tracking when a port's congestion level changes

---

## Analytics queries

`sql/analytics_queries.sql` contains 20+ queries across 5 tiers:

| Tier | Queries         | Refresh   | Purpose              |
| ---- | --------------- | --------- | -------------------- |
| MON  | MON-01 → MON-06 | 1–5 min   | Real-time operations |
| KPI  | KPI-01 → KPI-07 | Hourly    | Performance today    |
| OPS  | OPS-01 → OPS-06 | Daily     | Operational patterns |
| TRD  | TRD-01 → TRD-04 | Weekly    | Historical trends    |
| DX   | DX-01 → DX-04   | On demand | Diagnostics / ad-hoc |

---

## Grafana dashboard

Import `dashboard/grafana_dashboard.json` into Grafana → Dashboards → Import.

**Panels:**

- Port congestion stat cards (colour-coded LOW → CRITICAL)
- Unresolved alert count badge
- Berth utilisation gauges per port
- Active vessels in port table
- KPI tiles — avg score, total movements, avg delay, fleet delay rate
- 24h congestion trend (multi-line time series)
- Hourly arrivals vs departures bar chart
- Most congested ports — 7-day ranked bar
- Worst delayed vessels — 7-day table
- Live vessel event feed (last 50 events)

Grafana UI: http://localhost:3000 (admin / admin)

---

## Portfolio story

> "Built an end-to-end batch + real-time data pipeline monitoring vessel congestion across 6 Philippine ports. Python generator emits realistic vessel events every 5 seconds with burst simulation. dbt transforms raw events into congestion scores using a weighted composite formula. Airflow orchestrates the 15-minute pipeline cycle. Alerts fire via webhook when congestion exceeds threshold. Visualised in Grafana."

**Stack:** Python · PostgreSQL · dbt Core · Apache Airflow · Grafana · Docker Compose

---

## What to build next

1. Swap synthetic source for real AIS feed (MarineTraffic API or VesselFinder)
2. Add Landed Cost Calculator as a second mart (pairs naturally with vessel data)
3. Promote PostgreSQL to BigQuery for scale
4. Add Great Expectations for data quality contracts
