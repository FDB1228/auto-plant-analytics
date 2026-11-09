"""Ежедневный DAG хранилища данных автозавода (Apache Airflow).

Повторяет шаги `python -m pipeline.run daily`, но с разбивкой на задачи, ретраями
и проверкой свежести источников. Дата логического запуска ({{ ds }}) передаётся как
дата состояния операционной системы - так DAG можно перезапускать за прошлые даты (backfill).

Локально тот же пайплайн запускается без Airflow: `make pipeline`.
"""
from datetime import datetime, timedelta

from airflow import DAG

try:  # Airflow 3
    from airflow.providers.standard.operators.bash import BashOperator
except ImportError:  # Airflow 2
    from airflow.operators.bash import BashOperator

PROJECT = "/opt/auto-plant-analytics"
DBT = f"dbt --no-use-colors {{cmd}} --project-dir {PROJECT}/dwh --profiles-dir {PROJECT}/dwh"

default_args = {
    "owner": "analytics",
    "retries": 2,
    "retry_delay": timedelta(minutes=10),
}

with DAG(
    dag_id="plant_dwh_daily",
    description="MES + ERP + дилерский портал -> RAW -> dbt (staging / marts) -> тесты -> BI-выгрузка",
    start_date=datetime(2026, 7, 1),
    schedule="0 6 * * 1-5",          # будни, 06:00 - после закрытия ночной смены
    catchup=False,
    max_active_runs=1,
    default_args=default_args,
    tags=["dwh", "plant", "dbt"],
) as dag:
    load_source = BashOperator(
        task_id="mes_snapshot",
        bash_command=f"cd {PROJECT} && python -m pipeline.run load-source --as-of {{{{ ds }}}}",
    )
    ingest = BashOperator(
        task_id="ingest_external_files",
        bash_command=f"cd {PROJECT} && python -m pipeline.run ingest",
    )
    freshness = BashOperator(
        task_id="source_freshness",
        bash_command=DBT.format(cmd="source freshness"),
    )
    build = BashOperator(
        task_id="dbt_build",
        bash_command=DBT.format(cmd="build"),
    )
    export = BashOperator(
        task_id="export_bi",
        bash_command=f"cd {PROJECT} && python -m pipeline.run export-bi",
    )

    load_source >> ingest >> freshness >> build >> export
