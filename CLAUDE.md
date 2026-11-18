# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository overview

Materials for Sber HSE Recommender Systems course. Two distinct parts:

- `weekNN_*/` — per-week lecture/practice materials (PDFs, notebooks) and notebook-based homeworks. Homework directories (`week04_dl_candgen/homework/`, `week07_dl_ranking/homework/`, `week10_transformers/homework/`, `week13_trends/homework/`) follow one pattern: students fill in `homework.ipynb`, which does `import tests` and calls validation functions like `tests.check_data_split(...)`, `tests.test_two_tower(...)` from the sibling `tests.py`. Solutions go in the notebook, not in `tests.py`.
- `minirec/` — an educational recommender framework. Course tasks live in `minirec/tasks/<block>/<task>/`; the code students write lives in the framework packages, not in `tasks/`.

There is no lint/typecheck/test setup at the repo root — everything is per-package inside `minirec/`.

## Python setup (minirec)

Python is pinned exactly to **3.13.5** (`requires-python = "==3.13.5"` in every pyproject); other versions are unsupported. Dependencies are managed with [uv](https://docs.astral.sh/uv/).

```bash
cd minirec
uv venv --python 3.13.5 rec_env
source rec_env/bin/activate
uv sync --active        # installs from root pyproject.toml (includes engine as workspace member)
```

### Running tests

Each package (`engine`, `engine_builder`, `engine_server`, `experiments_server`, `engine_downloader`) is its own uv project with its own tests. Run pytest from inside that package's directory (the task READMEs use a subshell `cd` so the caller's directory doesn't change):

```bash
(cd engine && uv run pytest tests/unit/cgs/test_top_pop.py)         # whole file
(cd engine && uv run pytest tests/unit/cgs/test_top_pop.py -k name) # single test
(cd experiments_server && uv run pytest)                            # whole package
```

The authoritative test command for every course task is in that task's `minirec/tasks/<block>/<task>/README.md`. Examples: feature storage → `(cd engine && uv run pytest tests/unit/storages/test_feature_storage.py)`; metrics → `(cd engine_builder && uv run pytest tests/evaluation/test_metric.py)`.

Tooling: `ruff` for lint/format, `ty` for type checking (config in `minirec/ty.toml` — it excludes `.venv`/`node_modules` and ignores `possibly-missing-attribute`). Test fixtures use `fakeredis` and `moto[s3]`, so unit tests need no running services.

## minirec architecture

Six packages with these dependencies (engine is a uv workspace member of the root; the services depend on it by editable path):

- **`engine/`** — core library (`src/engine`, src-layout). Protocols and the request pipeline.
- **`engine_builder/`** — offline pipeline: training, snapshot builds, evaluation. CLI scripts at package root (`build_recommender.py`, `build_ranker.py`, `train_implicit_als.py`); implementation under `tasks/`.
- **`engine_server/`** — FastAPI runtime; `POST /recommend` with pagination, periodic hot-reload of snapshots.
- **`experiments_server/`** — standalone FastAPI service: user→group splitting by hash, per-group parameter overrides, SQLite storage.
- **`engine_downloader/`** — sidecar that pulls the current snapshot from S3 into the shared volume.
- **`viewer/`** — React/Vite web UI for browsing recommendations.

### engine internals

Central abstractions in `src/engine/interfaces.py`: `RecContext` (user id, time, history, Bloom filter) and `Candidate`; the component protocols `CandidateGenerator`, `CandidateMixer`, `Ranker`, `Filterer`, `FeatureManager`; and shared deps `ComponentDeps` (storages, snapshot data `EngineData`, `CandidateLogger`).

Configuration is registry-based: each component in the engine's YAML config has a `type` (a key in a registry: `CANDGENS` in `cg/__init__.py`, `CANDGEN_MIXERS`, `RANKERS`, `FEATURE_MANAGERS`, `RUNTIME_PROFILES`) and typed pydantic `parameters`. `RecommenderEngine` (`recommender.py`) resolves components by registry, validates parameters against each class's `config_model`, and builds `ComponentDeps` once at startup.

Request flow: candidate generators → `CandidateMixer` (blend/dedupe) → filters (history, pagination via Bloom filter) → `FeatureManager` (hydrate features from storages) → rankers (factor-based `FeatureRanker` or ML `ModelRanker`).

Storages (`storages/`): `ValkeyFeatureStorage` (key-value features) and Qdrant-backed `EmbeddingStorage` (ANN search).

### Offline → runtime dataflow

`build_recommender.py` (engine_builder) trains components and uploads the snapshot archive to `s3://rec-engine/service/v1/archive.tar.gz`. `engine_downloader` extracts it to a shared volume; `engine_server` watches the archive + version marker and hot-swaps the recommender. `build_ranker.py` (run *after* `build_recommender.py`) replays historical requests through a live engine to produce `candidates.jsonl`, then `PoolBuilder` labels/weights it and trains a CatBoost ranker that is added to the snapshot; `factor_schema.json` records which features are context-level vs candidate-level for `ModelRanker`.

Point-in-time discipline constrains changes to this pipeline: features must be computed strictly before the request time of each training row, labels strictly after (within `window_size`), splits are by time not randomly, and position columns (`mixer_position`, `position`) are logged but must never become model features. See `minirec/tasks/ranking/README.md`.

### Course tasks

`minirec/tasks/<block>/<task>/README.md` holds each task's statement and its local test command. Blocks: `basics_and_services` (storages, CGs, services) → `candgens` (metrics, ALS/BPR/SLIM, vector indexes) → `ranking` (candidate logging, pool building, model ranker, Mixigen). Tasks build on each other conceptually (e.g. ranker training needs logging), but their test suites are independent — they stub out other components (see `engine_builder/tests/ranking/sim.py`).

## Running the full service stack

```bash
docker compose up -d storages s3-setup                                # moto S3, Qdrant, Valkey
cd engine_builder && uv run build_recommender.py --latest-dt <date>   # build snapshot
docker compose up -d engine-downloader engine-server viewer           # run the service
```

The moto S3 is ephemeral — buckets are lost on `docker compose down`, so rerun `build_recommender.py` after restarting. Requires the Yandex Lavka dataset (`dm_action.parquet`, `dm_product.parquet`, from the Yandex Disk linked in `minirec/README.md`); tests do not need it. Services expose: engine-server :8000, experiments-server :8010, viewer :5173.

## viewer

React 18 + TypeScript + Vite in `minirec/viewer/`: `npm run dev`, `npm run typecheck` (tsc), `npm run test` (vitest).
