#! /usr/bin/env sh
DB_ID=$(bun run wrangler d1 list | sed -nE 's/^.*([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}).*db-pr-1.*/\1/p')
grep -q "^\$DB_ID$" wrangler.toml || {
  {
    printf "\n[[env.%s.d1_databases]]" "$PR_NUMBER"
    printf "\nbinding = \"DB\""
    printf "\ndatabase_name = \"db-%s\"" "$PR_NUMBER"
    printf "\ndatabase_id = \"%s\"" "$DB_ID"
  } >>wrangler.toml
}

bun run wrangler delete -e "$PR_NUMBER"
bun run wrangler d1 delete "db-$PR_NUMBER" -y
