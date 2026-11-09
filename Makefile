# Полный цикл: make all   |   по шагам: make generate -> make pipeline -> make notebooks
SHELL := /bin/bash
PY ?= python3
export PGHOST ?= localhost
export PGPORT ?= 5432
export PGDATABASE ?= plant
export PGUSER ?= postgres
export PGPASSWORD ?= postgres

.PHONY: help install db-up generate init-db pipeline demo transform docs test notebooks export all clean

help:            ## список команд
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-12s %s\n", $$1, $$2}'

install:         ## установить зависимости Python
	$(PY) -m pip install -r requirements.txt

db-up:           ## поднять PostgreSQL в Docker
	docker compose up -d db

generate:        ## сгенерировать синтетические данные (24 месяца работы завода)
	$(PY) -m generator --out data/generated

init-db:         ## пересоздать схемы plant и raw
	$(PY) -m pipeline.run init-db --reset

pipeline:        ## два «дня» работы: состояние на 30.06.2026 и 30.09.2026 (инкремент + SCD2)
	$(PY) -m pipeline.run demo

transform:       ## только dbt build (модели + тесты)
	$(PY) -m pipeline.run transform

docs:            ## сгенерировать и открыть документацию dbt (lineage)
	cd dwh && dbt docs generate --profiles-dir . && dbt docs serve --profiles-dir .

test:            ## unit-тесты Python
	$(PY) -m pytest -q tests

notebooks:       ## выполнить аналитические ноутбуки и сохранить графики
	for nb in notebooks/0*.ipynb; do \
		$(PY) -m jupyter nbconvert --to notebook --execute --inplace --ExecutePreprocessor.timeout=600 $$nb || exit 1; \
	done

export:          ## выгрузить витрины в CSV для DataLens / Power BI
	$(PY) -m pipeline.run export-bi

all: generate pipeline test notebooks   ## полный прогон с нуля

clean:
	rm -rf data dwh/target dwh/logs
