import os
import time
import uuid
import random
import logging
from datetime import datetime, timezone
from dataclasses import dataclass

from src.utils.db import execute_many

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [generator] %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S",
)
log = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Reference data — realistic PH port simulation
# ---------------------------------------------------------------------------

PORTS = {
    "MNL": {"name": "Port of Manila", "berths": 22},
    "CEB": {"name": "Cebu International Port", "berths": 5},
    "DVO": {"name": "Sasa Port Davao", "berths": 7},
    "ILO": {"name": "Iloilo Commercial Port", "berths": 5},
    "GEN": {"name": "General Santos Port", "berths": 6},
    "ZAM": {"name": "Zamboanga Port", "berths": 4},
    "BTG": {"name": "Batangas International Port", "berths": 8},
    "CGY": {"name": "Port of Cagayan de Oro", "berths": 7},
    "SUB": {"name": "Subic Bay Port", "berths": 25},
    "TAC": {"name": "Port of Tacloban", "berths": 4},
    "OZA": {"name": "Port of Ozamiz", "berths": 3},
    "ILG": {"name": "Port of Iligan", "berths": 5},
    "PAG": {"name": "Port of Pagadian", "berths": 3},
    "CBO": {"name": "Port of Cotabato", "berths": 4},
    "DIP": {"name": "Port of Dipolog", "berths": 3},
    "TAG": {"name": "Port of Tagbilaran", "berths": 4},
    "TAC2": {"name": "Port of Catbalogan", "berths": 3},
    "SUG": {"name": "Port of Surigao", "berths": 4},
    "BUT": {"name": "Port of Butuan", "berths": 3},
    "LBP": {"name": "Port of Legazpi", "berths": 4},
    "ROM": {"name": "Port of Romblon", "berths": 2},
    "MAS": {"name": "Port of Masbate", "berths": 3},
}

PORT_CODES = list(PORTS.keys())

VESSEL_PREFIXES = ["MV", "MT", "LCT", "RoRo", "FB"]

VESSEL_NAMES = [
    "Cebu Princess", "Davao Pearl", "Manila Star", "Mindanao Express",
    "Visayas Queen", "Luzon Trader", "Southern Cross", "Pacific Gem",
    "Batangas Bay", "Iloilo Spirit", "Cagayan Breeze", "Leyte Gulf",
    "Palawan Dream", "Samar Wind", "Panay Sun", "Negros Hope",
    "Bohol Sea", "Sulu Sunrise", "Masbate Mist", "Romblon Wave",
]

CARGO_TYPES = ["CONTAINER", "RORO", "BULK", "TANKER", "PASSENGER", "GENERAL"]

SHIPPING_LINES = [
    "2GO Shipping", "Starlite Ferries", "Sulpicio Lines", "Trans-Asia Shipping",
    "WG&A", "Medallion Transport", "Lite Shipping", "FastCat",
]

PORT_WEIGHTS = [
    0.25, 0.15, 0.10, 0.08, 0.07, 0.06,
    0.07, 0.05, 0.06, 0.03, 0.02, 0.02,
    0.01, 0.01, 0.01, 0.01, 0.01, 0.01,
    0.01, 0.01, 0.005, 0.005
]

HOUR_LOAD = [
    0.3, 0.2, 0.2, 0.2, 0.3, 0.5,
    0.7, 0.9, 1.0, 1.0, 0.9, 0.9,
    0.8, 0.8, 0.9, 1.0, 1.0, 0.9,
    0.8, 0.7, 0.6, 0.5, 0.4, 0.3,
]

# ---------------------------------------------------------------------------
# Event model
# ---------------------------------------------------------------------------


@dataclass
class VesselEvent:
    event_id: str
    vessel_name: str
    imo_number: str
    port_code: str
    berth_id: int
    event_type: str
    cargo_type: str
    shipping_line: str
    gross_tonnage: int
    draft_meters: float
    expected_duration_hrs: float
    event_timestamp: str
    source: str


# ---------------------------------------------------------------------------
# Event generator
# ---------------------------------------------------------------------------

def make_event() -> VesselEvent:
    port_code = random.choices(PORT_CODES, weights=PORT_WEIGHTS)[0]
    port = PORTS[port_code]

    hour = datetime.now(timezone.utc).hour
    load_mult = HOUR_LOAD[hour]

    base_duration = random.uniform(4, 48)
    duration = round(
        base_duration * (1 + load_mult * random.uniform(0, 0.5)), 1)

    return VesselEvent(
        event_id=str(uuid.uuid4()),
        vessel_name=f"{random.choice(VESSEL_PREFIXES)} {random.choice(VESSEL_NAMES)}",
        imo_number=f"IMO{random.randint(1000000, 9999999)}",
        port_code=port_code,
        berth_id=random.randint(1, port["berths"]),
        event_type=random.choices(
            ["ARRIVAL", "DEPARTURE"], weights=[0.55, 0.45])[0],
        cargo_type=random.choice(CARGO_TYPES),
        shipping_line=random.choice(SHIPPING_LINES),
        gross_tonnage=random.randint(500, 45000),
        draft_meters=round(random.uniform(2.5, 12.0), 1),
        expected_duration_hrs=duration,
        event_timestamp=datetime.now(timezone.utc).isoformat(),
        source="synthetic",
    )


# ---------------------------------------------------------------------------
# Insert SQL (bulk)
# ---------------------------------------------------------------------------

INSERT_SQL = """
INSERT INTO raw.vessel_events (
    event_id, vessel_name, imo_number, port_code, berth_id,
    event_type, cargo_type, shipping_line, gross_tonnage,
    draft_meters, expected_duration_hrs, event_timestamp, source
) VALUES %s
"""


def to_records(events: list[VesselEvent]) -> list[tuple]:
    return [
        (
            e.event_id,
            e.vessel_name,
            e.imo_number,
            e.port_code,
            e.berth_id,
            e.event_type,
            e.cargo_type,
            e.shipping_line,
            e.gross_tonnage,
            e.draft_meters,
            e.expected_duration_hrs,
            e.event_timestamp,
            e.source,
        )
        for e in events
    ]


# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------

INTERVAL_SECONDS = float(os.getenv("INTERVAL_SECONDS", "5"))
BURST_CHANCE = float(os.getenv("BURST_CHANCE", "0.05"))


def generate_batch(batch_size: int = 60):
    log.info(f"Generating batch of {batch_size} vessel events")

    events = [make_event() for _ in range(batch_size)]

    execute_many(INSERT_SQL, to_records(events))

    log.info(f"Inserted {batch_size} vessel events successfully")

    return batch_size


def run():
    log.info("Starting real-time vessel event generator")
    log.info(
        f"Interval: {INTERVAL_SECONDS}s | Burst chance: {BURST_CHANCE*100:.0f}%")

    total = 0

    try:
        while True:
            count = random.randint(
                3, 8) if random.random() < BURST_CHANCE else 1
            events = [make_event() for _ in range(count)]

            execute_many(INSERT_SQL, to_records(events))

            total += count

            for e in events:
                log.info(
                    f"[{total:05d}] {e.event_type:<10} {e.vessel_name:<30} "
                    f"port={e.port_code} berth={e.berth_id:02d} "
                    f"cargo={e.cargo_type}"
                )

            if count > 1:
                log.info(f"BURST: emitted {count} events")

            time.sleep(INTERVAL_SECONDS)

    except KeyboardInterrupt:
        log.info(f"Stopped. Total events emitted: {total}")


if __name__ == "__main__":
    run()
