
import os

from airflow import DAG
from airflow.providers.standard.operators.python import PythonOperator
from airflow.providers.standard.operators.bash import BashOperator

from src.ingestion.generator import generate_batch
from src.alerting.alert import run as alert_run

from datetime import datetime


def alert_check(**context):
    alert_run()


DEFAULT_ARGS = {
    "owner": "iki_data_engineer",
    "depends_on_past": False,
    "email_on_failure": False,
    "email_on_retry": False,
    "start_date": datetime(2026, 5, 1),
}

with DAG(
    dag_id="port_pipeline",
    description="PH Port Congestion Monitor — ingest → dbt → alert (every 15 min)",
    schedule="*/15 * * * *",
    catchup=False,
    default_args=DEFAULT_ARGS,
    tags=["port-monitor", "dbt", "real-time"],
) as dag:

    t_generate = PythonOperator(
        task_id="generate_batch",
        python_callable=generate_batch,
        op_kwargs={"batch_size": 60},
        doc_md="""
        Emits 60 synthetic vessel events into raw.vessel_events.

        This simulates real-time port activity in discrete batches
        suitable for Airflow scheduling (every 15 minutes).
        """,
    )

    t_dbt_run = BashOperator(
        task_id="dbt_run",
        bash_command="""
            cd /opt/airflow/dbt && \
            dbt deps && \
            dbt run \
                --profiles-dir . \
                --select staging+ marts+ \
                --no-partial-parse
        """,
        env={
            "PG_HOST": os.getenv("POSTGRES_HOST", "postgres"),
            "PG_PORT": os.getenv("POSTGRES_PORT", "5432"),
            "PG_DB":   os.getenv("PIPELINE_DB_NAME", "ph_port_monitor"),
            "PG_USER": os.getenv("POSTGRES_USER", "port_monitoring_user"),
            "PG_PASS": os.getenv("POSTGRES_PASSWORD", "port_monitoring_password"),
            **os.environ,
        },
        doc_md="Runs dbt staging → marts transform chain.",
    )

    t_dbt_test = BashOperator(
        task_id="dbt_test",
        bash_command="""
            cd /opt/airflow/dbt && \
            dbt test \
                --profiles-dir . \
                --select staging+ marts+
        """,
        env={
            "PG_HOST": os.getenv("POSTGRES_HOST", "postgres"),
            "PG_PORT": os.getenv("POSTGRES_PORT", "5432"),
            "PG_DB":   os.getenv("PIPELINE_DB_NAME", "ph_port_monitor"),
            "PG_USER": os.getenv("POSTGRES_USER", "port_monitoring_user"),
            "PG_PASS": os.getenv("POSTGRES_PASSWORD", "port_monitoring_password"),
            **os.environ,
        },
        doc_md="Runs dbt schema tests (uniqueness, not_null, accepted_values, FK).",
    )

    t_alert = PythonOperator(
        task_id="alert_check",
        python_callable=alert_check,
        doc_md="""
        Queries marts.congestion_scores for current-hour breaches.
        Fires webhook/email and logs to marts.alert_log.
        """,
    )

    t_generate >> t_dbt_run >> t_dbt_test >> t_alert
