# =============================================================================
#  Baseball Analytics Database — operator interface
#  Every target is idempotent and safe to re-run. Sequence: up → load → migrate.
# =============================================================================
SHELL := /bin/bash
.DEFAULT_GOAL := help

# Load .env if present so DB credentials propagate to psql / docker
ifneq (,$(wildcard ./.env))
    include .env
    export
endif

POSTGRES_USER     ?= baseball
POSTGRES_PASSWORD ?= baseball
POSTGRES_DB       ?= baseball
POSTGRES_PORT     ?= 5432
POSTGRES_HOST     ?= localhost
COMPOSE           ?= docker compose
PSQL              := PGPASSWORD=$(POSTGRES_PASSWORD) psql -h $(POSTGRES_HOST) -p $(POSTGRES_PORT) -U $(POSTGRES_USER) -d $(POSTGRES_DB)
PSQL_DOCKER       := $(COMPOSE) exec -T postgres psql -U $(POSTGRES_USER) -d $(POSTGRES_DB)

# ----- Lifecycle -------------------------------------------------------------
.PHONY: help
help:  ## Show this help
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z0-9_.-]+:.*?## / {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.PHONY: up
up:  ## Boot Postgres (and pg_stat_statements) in the background
	$(COMPOSE) up -d postgres
	@./scripts/wait_for_db.sh

.PHONY: down
down:  ## Stop containers
	$(COMPOSE) down

.PHONY: clean
clean:  ## Stop containers and DELETE the data volume (irrecoverable)
	$(COMPOSE) down -v

.PHONY: logs
logs:  ## Tail Postgres logs
	$(COMPOSE) logs -f postgres

# ----- Data lifecycle --------------------------------------------------------
.PHONY: load
load:  ## Download Lahman CSVs and load via COPY
	./scripts/download_lahman.sh
	$(PSQL_DOCKER) -v ON_ERROR_STOP=1 -f /workspace/scripts/load_csvs.sql

.PHONY: migrate
migrate:  ## Apply all numbered migrations under migrations/
	@for f in migrations/V*.sql; do \
		echo "▶ Applying $$f"; \
		$(PSQL_DOCKER) -v ON_ERROR_STOP=1 -f /workspace/$$f || exit 1; \
	done

# ----- Analytics -------------------------------------------------------------
.PHONY: awards
awards:  ## Run the 6 historical award queries (results to stdout)
	$(PSQL_DOCKER) -v ON_ERROR_STOP=1 -f /workspace/sql/baseball_awards.sql | tee plans/awards_$$(date +%Y%m%d_%H%M%S).log

.PHONY: sabermetrics
sabermetrics:  ## Run FIP, wOBA, era-adjusted ERA, and WAR proxy
	$(PSQL_DOCKER) -v ON_ERROR_STOP=1 -f /workspace/sql/sabermetrics/fip.sql
	$(PSQL_DOCKER) -v ON_ERROR_STOP=1 -f /workspace/sql/sabermetrics/woba.sql
	$(PSQL_DOCKER) -v ON_ERROR_STOP=1 -f /workspace/sql/sabermetrics/era_adjusted.sql
	$(PSQL_DOCKER) -v ON_ERROR_STOP=1 -f /workspace/sql/sabermetrics/war_proxy.sql

.PHONY: dq
dq:  ## Data-quality report (NULL ratios, orphans, referential audits)
	$(PSQL_DOCKER) -v ON_ERROR_STOP=1 -f /workspace/sql/data_quality.sql

.PHONY: bench
bench:  ## Cold + warm cache benchmark, archived to benchmarks/results/
	@mkdir -p benchmarks/results
	$(PSQL_DOCKER) -v ON_ERROR_STOP=1 -f /workspace/sql/benchmarks.sql \
		| tee benchmarks/results/bench_$$(date +%Y%m%d_%H%M%S).log

.PHONY: plans
plans:  ## Archive EXPLAIN plans for every award to plans/
	@mkdir -p plans
	$(PSQL_DOCKER) -v ON_ERROR_STOP=1 -A -t -f /workspace/sql/baseball_awards.sql \
		> plans/awards_$$(date +%Y%m%d_%H%M%S).json

# ----- Tests ------------------------------------------------------------------
.PHONY: test
test:  ## Run SQL assertion suite
	$(PSQL_DOCKER) -v ON_ERROR_STOP=1 -f /workspace/tests/test_awards.sql
	$(PSQL_DOCKER) -v ON_ERROR_STOP=1 -f /workspace/tests/test_data_quality.sql

# ----- Consumers -------------------------------------------------------------
.PHONY: dbt
dbt:  ## Run dbt staging + marts and execute schema tests
	$(COMPOSE) run --rm dbt run
	$(COMPOSE) run --rm dbt test

.PHONY: api
api:  ## Boot the FastAPI read-only service
	$(COMPOSE) up -d api
	@echo "API up at http://localhost:$${API_PORT:-8000}/docs"

.PHONY: notebook
notebook:  ## Boot Jupyter notebook
	$(COMPOSE) up -d notebook
	@echo "Notebook up at http://localhost:$${JUPYTER_PORT:-8888}/?token=$${JUPYTER_TOKEN:-baseball}"

# ----- Aliases ---------------------------------------------------------------
.PHONY: all
all: up load migrate awards sabermetrics test  ## Full end-to-end pipeline

.PHONY: ci
ci: up load migrate test  ## CI subset (no interactive consumers)
