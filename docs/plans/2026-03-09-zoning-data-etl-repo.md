# Zoning Data ETL — Dedicated Repo Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Extract the existing `data-pipeline/` into a standalone `city-zoning-etl` repo, wire it to `etl-worker-prod` Lambda via its own ECR repo, fix known field-mapping issues, and add the missing data sources identified by Codex review (parcel fabric, zoning companion layers, CoA applications, HCD polygons, TRCA, building violations).

**Architecture:** The core handler, contracts, retry/rate-limit infrastructure, and most jobs already exist. This plan is: repo extraction → ECR wiring → field mapping fix → new data sources → bootstrap deploy. New sources follow the existing blue-green pattern (`staging_*` → validate → promote to `production_*`).

**Tech Stack:** Existing — Python 3.12, geopandas, psycopg2, SQLAlchemy, requests, pytest. No new dependencies.

---

## Current State

| Source | Status | Tables | Gap |
|---|---|---|---|
| `aic` | Production-ready | `production_aic_applications` | — |
| `building_permits` | Production-ready | `production_building_permits` | — |
| `devapp` | Production-ready | `production_devapp` | — |
| `tier2` (SASP) | Production-ready | `production_sasp` | — |
| `overlays` | Partial — ravine + heritage only | `production_ravine`, `production_heritage` | TRCA, HCD polygons missing |
| `zoning` | Field mapping untested | `production_zoning` | Only keeps `zone_code`+geom; discards `FRONTAGE`, `COVERAGE`, `FSI_TOTAL`, `HOLDING_ID`, `EXCPTN_NO` |
| `parcel` | **Missing** | — | Fake PIN + hardcoded 350sqm lot area in backend |
| `coa` | **Missing** | — | Committee of Adjustment decisions modify per-parcel permissions |
| `violations` | **Missing** | — | Existing violations block permit issuance |

**ETL Lambda:** `etl-worker-prod` provisioned but uses reviewer's ECR — needs own repo.

---

## Task 1: Create `city-zoning-etl` Repo

**Files:**
- Create: new GitHub repo `dyf102/city-zoning-etl`
- Copy: entire `city-permit-reviewer/data-pipeline/` into repo root

**Step 1: Initialize from existing data-pipeline**

```bash
cp -r city-permit-reviewer/data-pipeline /tmp/city-zoning-etl
cd /tmp/city-zoning-etl
git init && git add -A
git commit -m "feat: initial commit — extracted from city-permit-reviewer/data-pipeline"
gh repo create dyf102/city-zoning-etl --private --source=. --remote=origin --push
```

**Step 2: Verify tests pass**

```bash
pip install -r requirements.txt
pytest --tb=short 2>&1 | tail -30
```

**Step 3: Commit any fixes**

```bash
git add -A && git commit -m "fix: resolve import issues after extraction"
```

---

## Task 2: Dedicated ECR Repo in Terraform

**Files:**
- Modify: `terraform/modules/etl_lambda/main.tf` — add `aws_ecr_repository`, update `image_uri`
- Modify: `terraform/modules/etl_lambda/variables.tf` — remove `ecr_repo_url` variable
- Modify: `terraform/modules/etl_lambda/outputs.tf` — add ECR URL output
- Modify: `terraform/environments/prod/main.tf` — remove `ecr_repo_url` arg from module call

**Step 1: Add ECR repo to `terraform/modules/etl_lambda/main.tf`**

Add before `aws_lambda_function`:

```hcl
resource "aws_ecr_repository" "etl" {
  name                 = "city-zoning-etl"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = false
  }
}
```

Update Lambda `image_uri`:

```hcl
image_uri = "${aws_ecr_repository.etl.repository_url}:latest"
```

**Step 2: Update `outputs.tf`**

```hcl
output "ecr_repo_url" {
  value = aws_ecr_repository.etl.repository_url
}
```

**Step 3: Remove `ecr_repo_url` variable from `variables.tf` and from `prod/main.tf`**

**Step 4: Format, commit, push with `[apply]`**

```bash
terraform fmt -recursive ../../
git add terraform/
git commit -m "feat: add dedicated ECR repo for city-zoning-etl [apply]"
git push origin main
```

**Step 5: Verify apply succeeds**

```bash
gh run list --repo dyf102/city-permit-infra --limit 3
```

---

## Task 3: GitHub Actions Deploy Workflow + IAM

**Files:**
- Create: `.github/workflows/deploy.yml` in `city-zoning-etl`
- Modify: `terraform/environments/prod/iam_github.tf` in `city-permit-infra`

**Step 1: Create `.github/workflows/deploy.yml`**

```yaml
name: Deploy ETL Lambda

on:
  push:
    branches: [main]

permissions:
  id-token: write
  contents: read

env:
  AWS_REGION: ca-central-1
  LAMBDA_FUNCTION: etl-worker-prod

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Run tests
        run: pip install -r requirements.txt && pytest --tb=short 2>&1 | tail -30

      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_DEPLOY_ROLE_ARN }}
          aws-region: ${{ env.AWS_REGION }}

      - name: Login to ECR
        id: login-ecr
        uses: aws-actions/amazon-ecr-login@v2

      - name: Build and push (arm64)
        env:
          ECR_URI: ${{ steps.login-ecr.outputs.registry }}/city-zoning-etl
        run: |
          docker buildx create --use
          docker buildx build --platform linux/arm64 \
            -t $ECR_URI:latest -t $ECR_URI:${{ github.sha }} --push .

      - name: Update Lambda
        run: |
          aws lambda update-function-code \
            --function-name ${{ env.LAMBDA_FUNCTION }} \
            --image-uri ${{ steps.login-ecr.outputs.registry }}/city-zoning-etl:latest
          aws lambda wait function-updated --function-name ${{ env.LAMBDA_FUNCTION }}
```

**Step 2: Add deploy role secret**

```bash
gh secret set AWS_DEPLOY_ROLE_ARN \
  --repo dyf102/city-zoning-etl \
  --body "arn:aws:iam::110428898775:role/github-actions-deploy-role"
```

**Step 3: Update `iam_github.tf` — add new repo + etl-worker Lambda + ECR permissions**

In `aws_iam_role.github_actions` assume policy `StringLike`, add:
```hcl
"repo:dyf102/city-zoning-etl:*",
```

In `aws_iam_role_policy.github_actions_policy`, update Lambda and ECR resource ARNs:
```hcl
# Lambda
Resource = [
  "arn:aws:lambda:ca-central-1:110428898775:function:city-permit-*",
  "arn:aws:lambda:ca-central-1:110428898775:function:etl-worker-*",
]

# ECR
Resource = [
  "arn:aws:ecr:ca-central-1:110428898775:repository/city-permit-*",
  "arn:aws:ecr:ca-central-1:110428898775:repository/city-zoning-etl",
]
```

**Step 4: Commit IAM with `[apply]`**

```bash
git add terraform/environments/prod/iam_github.tf
git commit -m "fix: allow city-zoning-etl repo + etl-worker Lambda in deploy role [apply]"
git push origin main
```

---

## Task 4: Fix Zoning Sync — Field Mapping + Companion Columns

**Context (Codex finding):** `sync.py` keeps only `zone_code` + geometry and discards structured fields already available in the CKAN dataset: `FRONTAGE`, `ZN_AREA`, `COVERAGE`, `FSI_TOTAL`, `HOLDING_ID`, `EXCPTN_NO`, `DENSITY`. These are needed by the math engine to compute real setbacks and coverage instead of using hardcoded defaults.

**Files:**
- Modify: `sources/zoning/sync.py`
- Modify: `shared/contracts.py` — expand `ZONING_CONTRACT`
- Modify: `sources/zoning/STATUS.md`

**Step 1: Fetch actual CKAN column names**

```bash
python3 - <<'EOF'
import requests, json
url = "https://ckan0.cf.opendata.inter.prod-toronto.ca/api/3/action/package_show?id=34927e44-fc11-4336-a8aa-a0dfb27658b7"
r = requests.get(url).json()
for res in r['result']['resources']:
    print(res.get('name'), res.get('format'))
# Then fetch first feature to inspect actual field names:
EOF
```

**Step 2: Update `ZONING_CONTRACT` in `shared/contracts.py`**

Expand columns list to include companion fields:

```python
ZONING_CONTRACT = TableContract(
    table_name="production_zoning",
    staging_table="staging_zoning",
    unique_key="zone_code",
    query_method="spatial_intersect",
    columns=[
        ColumnDef("zone_code", "str", nullable=False),
        ColumnDef("zone_description", "str"),
        ColumnDef("frontage_m", "float"),        # lot frontage minimum (metres)
        ColumnDef("area_sqm", "float"),           # zone area minimum (sqm)
        ColumnDef("coverage_pct", "float"),       # max lot coverage (%)
        ColumnDef("fsi_total", "float"),          # floor space index (density)
        ColumnDef("holding_id", "str"),           # holding symbol reference
        ColumnDef("exception_no", "str"),         # site-specific exception number
        ColumnDef("geometry", "geometry", nullable=False),
    ],
    required_columns=["zone_code", "geometry"],
    backend_select_columns=[
        "zone_code", "frontage_m", "area_sqm",
        "coverage_pct", "fsi_total", "holding_id", "exception_no",
    ],
)
```

**Step 3: Update `sources/zoning/sync.py` — field mapping**

Replace the guess-list with confirmed field name + retain companion columns:

```python
ZONE_CODE_COL = "ZBL_ZONE_CODE"   # confirmed Toronto CKAN field

COMPANION_COLS = {
    "FRONTAGE":   "frontage_m",
    "ZN_AREA":    "area_sqm",
    "COVERAGE":   "coverage_pct",
    "FSI_TOTAL":  "fsi_total",
    "HOLDING_ID": "holding_id",
    "EXCPTN_NO":  "exception_no",
}

# After gdf is loaded:
if ZONE_CODE_COL in gdf.columns:
    gdf = gdf.rename(columns={ZONE_CODE_COL: "zone_code"})
else:
    for col in ["GEN_ZONE", "ZONE_CODE", "ZONING", "ZON"]:
        if col in gdf.columns:
            gdf = gdf.rename(columns={col: "zone_code"})
            logger.warning(f"Fallback column used: {col}")
            break

for src, dst in COMPANION_COLS.items():
    if src in gdf.columns:
        gdf = gdf.rename(columns={src: dst})
    else:
        gdf[dst] = None  # column absent in this dataset version

keep = ["zone_code"] + list(COMPANION_COLS.values()) + ["geometry"]
gdf = gdf[[c for c in keep if c in gdf.columns]]
```

**Step 4: Run locally + verify companion columns present**

```bash
DATABASE_URL=postgresql://postgres:postgrespassword@localhost:5432/permitpulse \
  python -c "from sources.zoning.sync import sync_toronto_zoning; print(sync_toronto_zoning())"
```

**Step 5: Commit**

```bash
git add sources/zoning/ shared/contracts.py
git commit -m "feat: retain zoning companion columns (frontage, coverage, FSI, holding, exception)"
```

---

## Task 5: Add Property Boundaries + Address Points (Parcel Fabric)

**Context (Codex finding):** The backend hardcodes `lot_area_sqm=350.0` and generates fake PINs because there is no parcel source. Property Boundaries and Address Points (OAR) are available on Toronto CKAN and fix this.

**Files:**
- Create: `sources/parcel/` directory with `__init__.py`, `sync.py`, `STATUS.md`
- Modify: `shared/contracts.py` — add `PARCEL_CONTRACT`
- Modify: `lambda_handler.py` — add `parcel` job dispatch

**Step 1: Add `PARCEL_CONTRACT` to `shared/contracts.py`**

```python
PARCEL_CONTRACT = TableContract(
    table_name="production_parcel",
    staging_table="staging_parcel",
    unique_key="geo_id",
    query_method="spatial_intersect",
    columns=[
        ColumnDef("geo_id", "str", nullable=False,
                  description="City of Toronto parcel GEO_ID"),
        ColumnDef("address", "str"),
        ColumnDef("lot_area_sqm", "float"),
        ColumnDef("lot_frontage_m", "float"),
        ColumnDef("geometry", "geometry", nullable=False,
                  description="Polygon(4326) — parcel boundary"),
    ],
    required_columns=["geo_id", "geometry"],
    backend_select_columns=["geo_id", "address", "lot_area_sqm", "lot_frontage_m"],
)
```

**Step 2: Create `sources/parcel/sync.py`**

```python
import os, uuid, logging
import geopandas as gpd
from sqlalchemy import create_engine, text
from sources.zoning.sync import fetch_ckan_resource_url, download_and_extract
from shared.contracts import PARCEL_CONTRACT
from shared.validation import run_validation

logger = logging.getLogger(__name__)
PARCEL_PACKAGE_ID = "property-boundaries"
DATABASE_URL = os.getenv("DATABASE_URL",
    "postgresql://postgres:postgrespassword@localhost:5432/permitpulse")

def get_db_engine():
    url = DATABASE_URL.replace("+asyncpg", "")
    return create_engine(url, pool_pre_ping=True)

def sync_property_boundaries() -> bool:
    batch_id = str(uuid.uuid4())
    logger.info(f"Starting parcel sync (batch {batch_id})")

    url = fetch_ckan_resource_url(PARCEL_PACKAGE_ID, "GeoJSON")
    if not url:
        url = fetch_ckan_resource_url(PARCEL_PACKAGE_ID, "SHP")
    if not url:
        logger.error("No parcel resource found on CKAN")
        return False

    try:
        path = download_and_extract(url)
        gdf = gpd.read_file(path)
        logger.info(f"Loaded {len(gdf)} parcel features")

        if gdf.crs and gdf.crs.to_epsg() != 4326:
            gdf = gdf.to_crs(epsg=4326)
        gdf["geometry"] = gdf["geometry"].make_valid()

        # Map columns — inspect actual field names at runtime
        col_map = {
            "GEO_ID": "geo_id", "ADDRESS": "address",
            "AREA_SQM": "lot_area_sqm", "FRONTAGE": "lot_frontage_m",
        }
        for src, dst in col_map.items():
            if src in gdf.columns:
                gdf = gdf.rename(columns={src: dst})

        for col in ["geo_id", "address", "lot_area_sqm", "lot_frontage_m"]:
            if col not in gdf.columns:
                gdf[col] = None

        gdf = gdf[["geo_id", "address", "lot_area_sqm", "lot_frontage_m", "geometry"]]
        gdf["geo_id"] = gdf["geo_id"].astype(str)

        errors = PARCEL_CONTRACT.validate_dataframe(gdf)
        if errors:
            logger.error(f"Parcel contract violation: {errors}")
            return False

        engine = get_db_engine()
        staging = PARCEL_CONTRACT.staging_table
        prod = PARCEL_CONTRACT.table_name

        gdf.to_postgis(staging, engine, if_exists="replace", index=False)

        if not run_validation(staging, prod):
            logger.error("Validation failed")
            return False

        with engine.begin() as conn:
            conn.execute(text("DROP TABLE IF EXISTS backup_parcel;"))
            conn.execute(text(f"ALTER TABLE IF EXISTS {prod} RENAME TO backup_parcel;"))
            conn.execute(text(f"ALTER TABLE {staging} RENAME TO {prod};"))
            conn.execute(text(f"CREATE INDEX IF NOT EXISTS idx_{prod}_geom ON {prod} USING GIST (geometry);"))
            conn.execute(text(f"CREATE INDEX IF NOT EXISTS idx_{prod}_geo_id ON {prod} (geo_id);"))

        logger.info(f"Parcel sync complete: {len(gdf)} parcels")
        return True
    except Exception as e:
        logger.error(f"Parcel sync failed: {e}")
        return False
```

**Step 3: Wire into `lambda_handler.py`**

```python
from sources.parcel.sync import sync_property_boundaries

# Add to if/elif chain:
elif job == "parcel":
    success = sync_property_boundaries()
```

**Step 4: Add EventBridge rule for parcel job to Terraform**

In `terraform/modules/etl_lambda/main.tf`, add a new rule (weekly cadence — parcels change slowly):

```hcl
resource "aws_cloudwatch_event_rule" "parcel_weekly" {
  name                = "etl-parcel-weekly-${var.environment}"
  description         = "Triggers ETL Lambda for property boundary sync weekly"
  schedule_expression = "cron(0 7 ? * SUN *)"  # Sundays 7 AM UTC
}

resource "aws_cloudwatch_event_target" "parcel_target" {
  rule      = aws_cloudwatch_event_rule.parcel_weekly.name
  arn       = aws_lambda_function.etl_lambda.arn
  input     = jsonencode({ "job" : "parcel" })
  target_id = "etl-parcel"
}

resource "aws_lambda_permission" "allow_cloudwatch_parcel" {
  statement_id  = "AllowExecutionFromCloudWatchParcel"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.etl_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.parcel_weekly.arn
}
```

**Step 5: Commit**

```bash
git add sources/parcel/ shared/contracts.py lambda_handler.py
git commit -m "feat: add property boundary parcel sync (replaces hardcoded lot_area=350)"
```

---

## Task 6: Add TRCA Regulated Area + HCD Polygons to Overlays

**Context:** Overlays currently has ravine + heritage points only. TRCA is a prerequisite to municipal permits in regulated areas. HCD polygons gate heritage permits across entire districts (not just listed buildings).

**Files:**
- Modify: `sources/overlays/sync.py`
- Modify: `shared/contracts.py` — `TRCA_CONTRACT` already exists; add `HCD_CONTRACT`
- Modify: `sources/overlays/STATUS.md`

**Step 1: Add `HCD_CONTRACT` to `shared/contracts.py`**

```python
HCD_CONTRACT = TableContract(
    table_name="production_hcd",
    staging_table="staging_hcd",
    unique_key="hcd_name",
    query_method="spatial_intersect",
    columns=[
        ColumnDef("hcd_name", "str", nullable=False),
        ColumnDef("district_type", "str"),
        ColumnDef("geometry", "geometry", nullable=False,
                  description="MultiPolygon(4326) — HCD boundary"),
    ],
    required_columns=["hcd_name", "geometry"],
    backend_select_columns=["hcd_name", "district_type"],
)
```

**Step 2: Add TRCA and HCD syncs to `sources/overlays/sync.py`**

```python
def sync_trca_regulated_area(engine) -> bool:
    """Fetch TRCA Regulated Area polygons from TRCA ArcGIS REST using OID chunking."""
    from shared.contracts import TRCA_CONTRACT
    TRCA_URL = (
        "https://services1.arcgis.com/PWJUSsdoJDh2sC6c/ArcGIS/rest/services"
        "/Flood_Vulnerable_Areas/FeatureServer/0/query"
    )
    try:
        features, offset = [], 0
        while True:
            r = requests.get(TRCA_URL, params={
                "where": "1=1", "outFields": "OBJECTID", "f": "geojson",
                "outSR": "4326", "resultOffset": offset, "resultRecordCount": 1000,
            }, timeout=60)
            r.raise_for_status()
            batch = r.json().get("features", [])
            if not batch:
                break
            features.extend(batch)
            offset += len(batch)

        gdf = gpd.GeoDataFrame.from_features(features, crs="EPSG:4326")
        gdf["geometry"] = gdf["geometry"].make_valid()
        gdf = gdf[["geometry"]]

        errors = TRCA_CONTRACT.validate_dataframe(gdf)
        if errors:
            logger.error(f"TRCA contract violation: {errors}")
            return False

        staging, prod = TRCA_CONTRACT.staging_table, TRCA_CONTRACT.table_name
        gdf.to_postgis(staging, engine, if_exists="replace", index=False)
        if not run_validation(staging, prod):
            return False
        with engine.begin() as conn:
            conn.execute(text("DROP TABLE IF EXISTS backup_trca;"))
            conn.execute(text(f"ALTER TABLE IF EXISTS {prod} RENAME TO backup_trca;"))
            conn.execute(text(f"ALTER TABLE {staging} RENAME TO {prod};"))
            conn.execute(text(f"CREATE INDEX IF NOT EXISTS idx_{prod}_geom ON {prod} USING GIST (geometry);"))
        logger.info(f"TRCA sync complete: {len(gdf)} polygons")
        return True
    except Exception as e:
        logger.error(f"TRCA sync failed: {e}")
        return False


def sync_hcd_polygons(engine) -> bool:
    """Sync Heritage Conservation District boundary polygons from CKAN."""
    from shared.contracts import HCD_CONTRACT
    # HCD boundaries — check CKAN for exact package ID at runtime
    HCD_PACKAGE_ID = "heritage-conservation-districts"
    url = fetch_ckan_resource_url(HCD_PACKAGE_ID, "GeoJSON")
    if not url:
        url = fetch_ckan_resource_url(HCD_PACKAGE_ID, "SHP")
    if not url:
        logger.warning("HCD dataset not found on CKAN — skipping")
        return True  # Non-fatal: dataset may not be published yet
    try:
        path = download_and_extract(url)
        gdf = gpd.read_file(path)
        if gdf.crs and gdf.crs.to_epsg() != 4326:
            gdf = gdf.to_crs(epsg=4326)
        gdf["geometry"] = gdf["geometry"].make_valid()

        name_col = next((c for c in gdf.columns if "NAME" in c.upper()), None)
        type_col  = next((c for c in gdf.columns if "TYPE" in c.upper() or "STATUS" in c.upper()), None)
        gdf["hcd_name"]      = gdf[name_col] if name_col else "Unknown"
        gdf["district_type"] = gdf[type_col] if type_col else None
        gdf = gdf[["hcd_name", "district_type", "geometry"]]

        errors = HCD_CONTRACT.validate_dataframe(gdf)
        if errors:
            logger.error(f"HCD contract violation: {errors}")
            return False

        staging, prod = HCD_CONTRACT.staging_table, HCD_CONTRACT.table_name
        gdf.to_postgis(staging, engine, if_exists="replace", index=False)
        if not run_validation(staging, prod):
            return False
        with engine.begin() as conn:
            conn.execute(text("DROP TABLE IF EXISTS backup_hcd;"))
            conn.execute(text(f"ALTER TABLE IF EXISTS {prod} RENAME TO backup_hcd;"))
            conn.execute(text(f"ALTER TABLE {staging} RENAME TO {prod};"))
            conn.execute(text(f"CREATE INDEX IF NOT EXISTS idx_{prod}_geom ON {prod} USING GIST (geometry);"))
        logger.info(f"HCD sync complete: {len(gdf)} districts")
        return True
    except Exception as e:
        logger.error(f"HCD sync failed: {e}")
        return False
```

**Step 3: Call both from `sync_overlays()`**

```python
def sync_overlays() -> bool:
    engine = get_db_engine()
    results = [
        sync_ravine_data(),
        sync_heritage_data(),
        sync_trca_regulated_area(engine),
        sync_hcd_polygons(engine),
    ]
    return all(results)
```

**Step 4: Run tests**

```bash
pytest sources/overlays/ -v --tb=short 2>&1 | tail -20
```

**Step 5: Commit**

```bash
git add sources/overlays/ shared/contracts.py
git commit -m "feat: add TRCA regulated areas and HCD polygon overlays"
```

---

## Task 7: Add Committee of Adjustment (CoA) Applications

**Context (Codex finding):** CoA applications (minor variances, consents) directly modify what's permitted on a specific parcel — separate from AIC which tracks zoning applications. Our backend incorrectly uses *nearby* CoA grants to modify the subject parcel; having real per-parcel CoA data fixes this.

**Files:**
- Create: `sources/coa/` with `__init__.py`, `sync.py`, `STATUS.md`
- Modify: `shared/contracts.py` — add `COA_CONTRACT`
- Modify: `lambda_handler.py` — add `coa` job

**Step 1: Add `COA_CONTRACT` to `shared/contracts.py`**

```python
COA_CONTRACT = TableContract(
    table_name="production_coa_applications",
    staging_table="staging_coa_applications",
    unique_key="application_id",
    query_method="spatial_dwithin",
    columns=[
        ColumnDef("application_id", "str", nullable=False),
        ColumnDef("address", "str"),
        ColumnDef("decision", "str",
                  description="Approved / Refused / Withdrawn / Deferred"),
        ColumnDef("relief_type", "str",
                  description="Minor Variance / Consent / Combined"),
        ColumnDef("conditions", "str"),
        ColumnDef("decision_date", "date"),
        ColumnDef("geometry", "geometry", nullable=False,
                  description="Point(4326)"),
        ColumnDef("scraped_at", "datetime", nullable=False),
        ColumnDef("etl_batch_id", "str", nullable=False),
    ],
    required_columns=["application_id", "geometry", "scraped_at", "etl_batch_id"],
    backend_select_columns=[
        "application_id", "address", "decision", "relief_type",
        "conditions", "decision_date",
    ],
)
```

**Step 2: Create `sources/coa/sync.py`**

CoA applications are available via Toronto CKAN Open Data (Committee of Adjustment dataset). Use same pattern as AIC — ESRI REST or CKAN datastore.

```python
import os, uuid, logging
import geopandas as gpd
from datetime import datetime, timezone
from sqlalchemy import create_engine, text
from shared.contracts import COA_CONTRACT
from shared.validation import run_validation
from shared.rate_limiter import RateLimiter
from shared.retry import with_retry, RetryConfig, RetryableError
import requests

logger = logging.getLogger(__name__)

# Committee of Adjustment ArcGIS REST service
COA_URL = "https://gis.toronto.ca/arcgis/rest/services/cot_geospatial14/FeatureServer/0/query"
CHUNK_SIZE = 2000
DATABASE_URL = os.getenv("DATABASE_URL",
    "postgresql://postgres:postgrespassword@localhost:5432/permitpulse")

def get_db_engine():
    return create_engine(DATABASE_URL.replace("+asyncpg", ""), pool_pre_ping=True)

def fetch_coa_applications() -> list[dict]:
    """Fetch all CoA applications using OID-chunked pagination (same pattern as AIC)."""
    rate_limiter = RateLimiter()
    session = requests.Session()
    session.headers["User-Agent"] = "Mozilla/5.0 (compatible)"

    # Get OID range
    r = session.get(COA_URL, params={
        "where": "1=1", "outFields": "OBJECTID",
        "outStatistics": '[{"statisticType":"min","onStatisticField":"OBJECTID","outStatisticFieldName":"min_oid"},{"statisticType":"max","onStatisticField":"OBJECTID","outStatisticFieldName":"max_oid"}]',
        "f": "json",
    }, timeout=30)
    stats = r.json()["features"][0]["attributes"]
    min_oid, max_oid = int(stats["min_oid"]), int(stats["max_oid"])

    all_features = []
    current = min_oid
    while current <= max_oid:
        chunk_max = min(current + CHUNK_SIZE - 1, max_oid)
        rate_limiter.acquire()
        resp = session.get(COA_URL, params={
            "where": f"OBJECTID >= {current} AND OBJECTID <= {chunk_max}",
            "outFields": "*", "outSR": "4326", "f": "json",
        }, timeout=30)
        resp.raise_for_status()
        all_features.extend(resp.json().get("features", []))
        current = chunk_max + 1

    return all_features

def sync_coa_applications() -> bool:
    batch_id = str(uuid.uuid4())
    logger.info(f"Starting CoA sync (batch {batch_id})")
    try:
        features = fetch_coa_applications()
        rows = []
        for f in features:
            a = f.get("attributes", {})
            lat = a.get("LATITUDE") or a.get("Y")
            lng = a.get("LONGITUDE") or a.get("X")
            rows.append({
                "application_id": str(a.get("APPLICATION_NUMBER") or a.get("OBJECTID")),
                "address":        a.get("FULL_ADDRESS") or a.get("ADDRESS"),
                "decision":       a.get("DECISION") or a.get("STATUS_DESC"),
                "relief_type":    a.get("APPLICATION_TYPE") or a.get("FILE_TYPE"),
                "conditions":     a.get("CONDITIONS"),
                "decision_date":  a.get("DECISION_DATE"),
                "latitude": lat, "longitude": lng,
                "scraped_at": datetime.now(timezone.utc).isoformat(),
                "etl_batch_id": batch_id,
            })

        gdf = gpd.GeoDataFrame(rows, geometry=gpd.points_from_xy(
            [r["longitude"] for r in rows],
            [r["latitude"]  for r in rows],
        ), crs="EPSG:4326")
        gdf = gdf.drop(columns=["latitude", "longitude"])
        gdf = gdf[gdf.geometry.notna()]

        errors = COA_CONTRACT.validate_dataframe(gdf)
        if errors:
            logger.error(f"CoA contract violation: {errors}")
            return False

        engine = get_db_engine()
        staging, prod = COA_CONTRACT.staging_table, COA_CONTRACT.table_name
        gdf.to_postgis(staging, engine, if_exists="replace", index=False)
        if not run_validation(staging, prod):
            return False
        with engine.begin() as conn:
            conn.execute(text("DROP TABLE IF EXISTS backup_coa;"))
            conn.execute(text(f"ALTER TABLE IF EXISTS {prod} RENAME TO backup_coa;"))
            conn.execute(text(f"ALTER TABLE {staging} RENAME TO {prod};"))
            conn.execute(text(f"CREATE INDEX IF NOT EXISTS idx_{prod}_geom ON {prod} USING GIST (geometry);"))
            conn.execute(text(f"CREATE INDEX IF NOT EXISTS idx_{prod}_decision ON {prod} (decision);"))
        logger.info(f"CoA sync complete: {len(gdf)} applications")
        return True
    except Exception as e:
        logger.error(f"CoA sync failed: {e}")
        return False
```

**Step 3: Wire into `lambda_handler.py`**

```python
from sources.coa.sync import sync_coa_applications
# add: elif job == "coa": success = sync_coa_applications()
```

**Step 4: Add EventBridge rule to Terraform (weekly — decisions don't change daily)**

```hcl
resource "aws_cloudwatch_event_rule" "coa_weekly" {
  name                = "etl-coa-weekly-${var.environment}"
  schedule_expression = "cron(0 7 ? * SUN *)"
}
resource "aws_cloudwatch_event_target" "coa_target" {
  rule = aws_cloudwatch_event_rule.coa_weekly.name
  arn  = aws_lambda_function.etl_lambda.arn
  input     = jsonencode({ "job" : "coa" })
  target_id = "etl-coa"
}
resource "aws_lambda_permission" "allow_cloudwatch_coa" {
  statement_id  = "AllowExecutionFromCloudWatchCoA"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.etl_lambda.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.coa_weekly.arn
}
```

**Step 5: Commit**

```bash
git add sources/coa/ shared/contracts.py lambda_handler.py
git commit -m "feat: add Committee of Adjustment applications ETL"
```

---

## Task 8: Add Building Violations

**Context (Codex finding):** Existing violations on a property block permit issuance. Available on CKAN.

**Files:**
- Create: `sources/violations/` with `__init__.py`, `sync.py`, `STATUS.md`
- Modify: `shared/contracts.py` — add `VIOLATIONS_CONTRACT`
- Modify: `lambda_handler.py` — add `violations` job

**Step 1: Add `VIOLATIONS_CONTRACT` to `shared/contracts.py`**

```python
VIOLATIONS_CONTRACT = TableContract(
    table_name="production_violations",
    staging_table="staging_violations",
    unique_key="violation_id",
    query_method="address_match",
    columns=[
        ColumnDef("violation_id", "str", nullable=False),
        ColumnDef("address", "str"),
        ColumnDef("violation_type", "str"),
        ColumnDef("status", "str"),
        ColumnDef("issued_date", "date"),
        ColumnDef("closed_date", "date"),
        ColumnDef("geometry", "geometry"),
        ColumnDef("scraped_at", "datetime", nullable=False),
        ColumnDef("etl_batch_id", "str", nullable=False),
    ],
    required_columns=["violation_id", "scraped_at", "etl_batch_id"],
    backend_select_columns=["violation_id", "address", "violation_type", "status",
                            "issued_date", "closed_date"],
)
```

**Step 2: Create `sources/violations/sync.py`** using CKAN datastore pattern (same as building_permits).

```python
# Pattern: fetch from CKAN building violations dataset, transform, blue-green swap
# CKAN package: "building-construction-demolition-violations"
# Follow exact same pattern as sources/building_permits/sync.py
```

**Step 3: Wire + EventBridge rule (weekly)**

Follow same pattern as CoA task above with job name `"violations"`.

**Step 4: Commit**

```bash
git add sources/violations/ shared/contracts.py lambda_handler.py
git commit -m "feat: add building violations ETL"
```

---

## Task 9: Push Bootstrap Image + Smoke Test All Jobs

**Step 1: Build and push initial image**

```bash
cd /tmp/city-zoning-etl
AWS_PROFILE=SystemAdministrator-110428898775 aws ecr get-login-password \
  --region ca-central-1 | docker login --username AWS \
  --password-stdin 110428898775.dkr.ecr.ca-central-1.amazonaws.com

docker buildx build --platform linux/arm64 \
  -t 110428898775.dkr.ecr.ca-central-1.amazonaws.com/city-zoning-etl:latest \
  --push .
```

**Step 2: Update Lambda to use new image**

```bash
AWS_PROFILE=SystemAdministrator-110428898775 aws lambda update-function-code \
  --function-name etl-worker-prod \
  --image-uri 110428898775.dkr.ecr.ca-central-1.amazonaws.com/city-zoning-etl:latest \
  --region ca-central-1
aws lambda wait function-updated --function-name etl-worker-prod --region ca-central-1
```

**Step 3: Smoke test all jobs**

```bash
for job in zoning tier2 building_permits devapp overlays aic parcel coa violations; do
  echo "=== $job ==="
  AWS_PROFILE=SystemAdministrator-110428898775 aws lambda invoke \
    --function-name etl-worker-prod --region ca-central-1 \
    --payload "{\"job\": \"$job\"}" \
    --cli-binary-format raw-in-base64-out /tmp/etl-$job.json
  cat /tmp/etl-$job.json && echo
done
```

**Step 4: Check CloudWatch for errors**

```bash
AWS_PROFILE=SystemAdministrator-110428898775 aws logs filter-log-events \
  --log-group-name /aws/lambda/etl-worker-prod \
  --region ca-central-1 \
  --start-time $(($(date +%s%3N) - 3600000)) \
  --filter-pattern "ERROR" \
  --query 'events[*].message' --output text | head -30
```

---

## Summary

| Task | What | Driven by |
|---|---|---|
| 1 | Extract `data-pipeline/` → `city-zoning-etl` repo | Structural |
| 2 | Dedicated ECR repo in Terraform | Structural |
| 3 | Deploy workflow + IAM wiring | Structural |
| 4 | Fix zoning field mapping + retain companion columns (`FRONTAGE`, `COVERAGE`, `FSI_TOTAL`, `HOLDING_ID`, `EXCPTN_NO`) | Codex: zoning columns discarded |
| 5 | Property Boundaries + Address Points (parcel fabric) | Codex: fake PIN + hardcoded lot_area=350 |
| 6 | TRCA regulated areas + HCD polygon overlay | Codex + existing TODO |
| 7 | Committee of Adjustment applications | Codex: CoA grants misapplied in math engine |
| 8 | Building violations | Codex: violations block permit issuance |
| 9 | Bootstrap image deploy + smoke test all 9 jobs | Operational |
