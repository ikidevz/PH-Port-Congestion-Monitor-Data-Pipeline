import os
import json
import smtplib
import logging
import urllib.request
import urllib.error
from email.mime.text import MIMEText

from src.utils.db import get_connection, get_cursor

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [alert] %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S",
)

log = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

ALERT_THRESHOLD = float(os.getenv("ALERT_THRESHOLD", "75"))

WEBHOOK_URL = os.getenv("ALERT_WEBHOOK_URL", "")

SMTP_HOST = os.getenv("ALERT_SMTP_HOST", "")
SMTP_PORT = int(os.getenv("ALERT_SMTP_PORT", "587"))
SMTP_USER = os.getenv("ALERT_SMTP_USER", "")
SMTP_PASS = os.getenv("ALERT_SMTP_PASS", "")
ALERT_EMAIL_TO = os.getenv("ALERT_EMAIL_TO", "")

# ---------------------------------------------------------------------------
# Queries
# ---------------------------------------------------------------------------

BREACH_QUERY = """
SELECT
    cs.port_code,
    p.port_name,
    cs.congestion_score,
    cs.congestion_level,
    cs.berth_utilisation_pct,
    cs.avg_wait_hours,
    cs.active_vessels,
    cs.berth_capacity
FROM marts.congestion_scores cs
JOIN raw.ports p USING (port_code)
WHERE cs.score_hour = date_trunc('hour', NOW())
  AND cs.congestion_score >= %s
ORDER BY cs.congestion_score DESC;
"""

ALREADY_LOGGED = """
SELECT 1 FROM marts.alert_log
WHERE port_code = %s
  AND alert_type = %s
  AND triggered_at >= date_trunc('hour', NOW())
LIMIT 1;
"""

INSERT_ALERT = """
INSERT INTO marts.alert_log
    (port_code, alert_type, congestion_score, threshold_value, message)
VALUES (%s, %s, %s, %s, %s)
RETURNING alert_id;
"""

MARK_NOTIFIED = """
UPDATE marts.alert_log
SET notified = TRUE, notified_at = NOW()
WHERE alert_id = %s;
"""

# ---------------------------------------------------------------------------
# DB operations (cleaned using utils)
# ---------------------------------------------------------------------------


def fetch_breaches():
    with get_cursor() as cur:
        cur.execute(BREACH_QUERY, (ALERT_THRESHOLD,))
        cols = [d[0] for d in cur.description]
        return [dict(zip(cols, row)) for row in cur.fetchall()]


def already_logged(port_code: str, alert_type: str) -> bool:
    with get_cursor() as cur:
        cur.execute(ALREADY_LOGGED, (port_code, alert_type))
        return cur.fetchone() is not None


def log_alert(breach: dict, alert_type: str, message: str) -> str:
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(INSERT_ALERT, (
                breach["port_code"],
                alert_type,
                breach["congestion_score"],
                ALERT_THRESHOLD,
                message,
            ))
            alert_id = cur.fetchone()[0]
            return str(alert_id)


def mark_notified(alert_id: str):
    with get_connection() as conn:
        with conn.cursor() as cur:
            cur.execute(MARK_NOTIFIED, (alert_id,))

# ---------------------------------------------------------------------------
# Notifications
# ---------------------------------------------------------------------------


def build_message(breach: dict) -> str:
    level_emoji = {
        "LOW": "🟢",
        "MODERATE": "🟡",
        "HIGH": "🟠",
        "CRITICAL": "🔴"
    }.get(breach["congestion_level"], "⚠️")

    return (
        f"{level_emoji} PORT CONGESTION ALERT — {breach['port_name']} ({breach['port_code']})\n"
        f"Level: {breach['congestion_level']} | Score: {breach['congestion_score']:.1f}/100\n"
        f"Berth utilisation: {breach['berth_utilisation_pct']:.1f}% "
        f"({breach['active_vessels']}/{breach['berth_capacity']} berths)\n"
        f"Avg wait time: {breach['avg_wait_hours']:.1f} hrs\n"
        f"Threshold: {ALERT_THRESHOLD}"
    )


def send_webhook(message: str) -> bool:
    if not WEBHOOK_URL:
        return False

    payload = json.dumps({"text": message}).encode()

    req = urllib.request.Request(
        WEBHOOK_URL,
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return resp.status < 300
    except urllib.error.URLError as e:
        log.error(f"Webhook failed: {e}")
        return False


def send_email(message: str, port_name: str) -> bool:
    if not SMTP_HOST or not ALERT_EMAIL_TO:
        return False

    msg = MIMEText(message)
    msg["Subject"] = f"[PORT ALERT] Congestion at {port_name}"
    msg["From"] = "airflow@local"
    msg["To"] = ALERT_EMAIL_TO

    with smtplib.SMTP(SMTP_HOST, SMTP_PORT) as server:
        server.sendmail("airflow@local", [ALERT_EMAIL_TO], msg.as_string())

    return True

# ---------------------------------------------------------------------------
# Main logic (Airflow-safe)
# ---------------------------------------------------------------------------


def run():
    log.info(f"Alert check — threshold: {ALERT_THRESHOLD}")

    breaches = fetch_breaches()

    if not breaches:
        log.info("No breaches detected this hour.")
        return

    log.info(f"{len(breaches)} breach(es) detected")

    for breach in breaches:
        alert_type = f"CONGESTION_{breach['congestion_level']}"

        if already_logged(breach["port_code"], alert_type):
            log.info(f"{breach['port_code']} already alerted — skipping")
            continue

        message = build_message(breach)

        alert_id = log_alert(breach, alert_type, message)

        delivered = send_webhook(message) or send_email(
            message, breach["port_name"]
        )

        if delivered:
            mark_notified(alert_id)
            log.info(f"{breach['port_code']} alert sent — id={alert_id}")
        else:
            log.warning(f"{breach['port_code']} logged but not delivered")

    log.info("Alert check complete.")


if __name__ == "__main__":
    run()
