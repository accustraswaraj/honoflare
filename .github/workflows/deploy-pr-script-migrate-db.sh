#! /usr/bin/env sh
DB_ID=$(bunx wrangler d1 list | sed -nE "s/^.*([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}).*db-$PR_NUMBER.*/\1/p")
grep -q "^\$DB_ID$" wrangler.toml || {
  {
    printf "\n[[env.%s.d1_databases]]" "$PR_NUMBER"
    printf "\nbinding = \"DB\""
    printf "\ndatabase_name = \"db-%s\"" "$PR_NUMBER"
    printf "\ndatabase_id = \"%s\"" "$DB_ID"
  } >>wrangler.toml
}

bunx wrangler d1 migrations apply DB -e="$PR_NUMBER" --remote
