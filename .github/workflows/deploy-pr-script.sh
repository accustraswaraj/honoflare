#! /usr/bin/env sh
SECTION="env.$PR_NUMBER"
grep -q "^\[$SECTION\]$" wrangler.toml || {
  {
    printf "\n[%s]" "$SECTION"
    printf "\nworkers_dev = true\n"
  } >>wrangler.toml
}
bunx wrangler d1 list | grep -q "db-$PR_NUMBER" || {
  bunx wrangler d1 create "db-$PR_NUMBER" | tail -n 5 | sed "s/^\\[\\[d1_databases\\]\\]/\\[\\[$SECTION.d1_databases\\]\\]/" >>wrangler.toml
}
cat wrangler.toml
