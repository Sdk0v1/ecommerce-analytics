#!/usr/bin/env bash
# Downloads the Olist CSVs into data/raw/ (skips files that already exist).
# Source: Olist's own public copy of the dataset on GitHub
# (https://github.com/olist/work-at-olist-data) - identical row counts to the Kaggle version.
# The raw data is not committed to this repository (licence CC BY-NC-SA 4.0).
set -euo pipefail

BASE="https://raw.githubusercontent.com/olist/work-at-olist-data/master/datasets"
DEST="$(dirname "$0")/../data/raw"
mkdir -p "$DEST"

FILES=(
  olist_orders_dataset.csv
  olist_order_items_dataset.csv
  olist_customers_dataset.csv
  olist_products_dataset.csv
  olist_sellers_dataset.csv
  olist_order_payments_dataset.csv
  olist_order_reviews_dataset.csv
  product_category_name_translation.csv
)

for f in "${FILES[@]}"; do
  if [[ -s "$DEST/$f" ]]; then
    echo "exists  $f"
  else
    echo "download $f"
    curl -fsSL --retry 3 -o "$DEST/$f" "$BASE/$f"
  fi
done
echo "done: $(ls "$DEST"/*.csv | wc -l) CSV files in data/raw"
