**Cloudflare Workers with D1, GitHub Actions: A Complete Guide**

This guide provides a detailed walkthrough on setting up a Cloudflare Workers deployment pipeline utilizing D1 databases and GitHub Actions. This approach enables isolated preview deployments for pull requests, automated cleanup of resources, and streamlined production deployments triggered by tagged releases.

**Create project**
- `bun create hono <name>`

**Core Files, Their Roles, and Code:**

1.  **`wrangler.toml` (Worker Configuration):**
    This file contains the configuration for your Cloudflare Worker. It specifies the worker's name, entry point (e.g., `src/index.ts`), compatibility settings, any D1 database bindings, and environment-specific variables. The base `wrangler.toml` will contain your production configuration, but during the PR deployments, this file will be updated to include the database and environment for that specific PR.

    ```toml
    name = "your-worker-name"
    main = "src/index.ts"
    compatibility_date = "2023-12-22"

    [[d1_databases]]
    binding = "DB"
    database_name = "db"
    database_id = "your-db-id"

    [vars]
    # Your base variables here
    ```

2.  **`.github/workflows/deploy-pr.yml` (PR Deployment Workflow):**
    This GitHub Actions workflow deploys preview environments for pull requests against the `main` branch. It checks out the code, sets up `bun`, and uses the Cloudflare Wrangler action for deployment to a unique environment based on the pull request number. It runs two bash scripts, one before, and one after the worker deployment, to configure the `wrangler.toml`, the d1 database, and the d1 migrations.

    ```yaml
    name: Deploy PR
    on:
      pull_request:
        branches:
          - main
    jobs:
      deploy:
        runs-on: ubuntu-latest
        timeout-minutes: 60
        steps:
          - uses: actions/checkout@v4
          - uses: oven-sh/setup-bun@v2
            with:
              bun-version: latest
          - name: Build & Deploy Worker
            uses: cloudflare/wrangler-action@v3
            env:
                PR_NUMBER: pr-${{ github.event.number }}
            with:
              apiToken: ${{ secrets.CLOUDFLARE_API_TOKEN }}
              accountId: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
              environment: pr-${{ github.event.number }}
              preCommands: |
                PR_NUMBER="$PR_NUMBER" sh .github/workflows/deploy-pr-script.sh
              postCommands: |
                PR_NUMBER="$PR_NUMBER" sh .github/workflows/deploy-pr-script-migrate-db.sh
    ```

3.  **`.github/workflows/cleanup-pr.yml` (PR Cleanup Workflow):**
    This workflow is triggered when a pull request is closed and merged into the `main` branch. It cleans up the resources created for the pull request's preview environment. It uses a script to delete the Cloudflare Worker environment and its associated D1 database.

    ```yaml
    name: Cleanup PR
    on:
      pull_request:
        branches:
          - main
        types:
          - closed
    jobs:
      cleanup:
        if: github.event.pull_request.merged == true
        runs-on: ubuntu-latest
        steps:
          - uses: actions/checkout@v4
          - uses: oven-sh/setup-bun@v2
            with:
              bun-version: latest
          - name: Delete db and destroy worker
            env:
                PR_NUMBER: pr-${{ github.event.number }}
                CLOUDFLARE_API_TOKEN: ${{ secrets.CLOUDFLARE_API_TOKEN }}
                CLOUDFLARE_ACCOUNT_ID: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
            run: bun install && PR_NUMBER=$PR_NUMBER sh .github/workflows/cleanup-pr-script.sh
    ```

4.  **`.github/workflows/deploy-prod.yml` (Production Deployment Workflow):**
    This workflow handles production deployments, triggered by a new Git tag that matches the semantic version pattern `v[0-9]+.[0-9]+.[0-9]+`. It deploys the worker to the production environment and runs database migrations after deployment.

    ```yaml
    name: Deploy Prod
    on:
      push:
        tags:
          - 'v[0-9]+.[0-9]+.[0-9]+'
    jobs:
      deploy:
        runs-on: ubuntu-latest
        timeout-minutes: 60
        steps:
          - uses: actions/checkout@v4
          - uses: oven-sh/setup-bun@v2
            with:
              bun-version: latest
          - name: Build & Deploy Worker
            uses: cloudflare/wrangler-action@v3
            with:
              apiToken: ${{ secrets.CLOUDFLARE_API_TOKEN }}
              accountId: ${{ secrets.CLOUDFLARE_ACCOUNT_ID }}
              environment: production
              postCommands: |
                wrangler d1 migrations apply DB -e=production --remote
    ```

5.  **`.github/workflows/deploy-pr-script.sh` (PR Environment Setup Script):**
    This Bash script is executed before deploying the worker in the PR deployment workflow. It configures `wrangler.toml` for the pull request environment and creates a dedicated D1 database, if it doesn't exists yet.

    ```sh
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
    ```

6.  **`.github/workflows/cleanup-pr-script.sh` (PR Resource Cleanup Script):**
    This Bash script is responsible for cleaning up resources after a pull request is merged. It deletes the worker and database associated to the merged PR.

    ```sh
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
    ```

7. **`.github/workflows/deploy-pr-script-migrate-db.sh` (PR Database Migration Script):**
    This Bash script is executed after the worker has been deployed in the PR deployment workflow. It applies the D1 database migrations for the specific PR environment.

    ```sh
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
    ```

**Setting up Your Environment:**

1.  **Cloudflare Account:**  You need an active Cloudflare account.

2.  **Cloudflare API Token:** Create an API token with permissions for Workers and D1 at: [https://dash.cloudflare.com/profile/api-tokens](https://dash.cloudflare.com/profile/api-tokens).

3.  **Wrangler CLI:** Install the Cloudflare Wrangler CLI. Use `bunx wrangler` to ensure you are using the version installed in `node_modules`. Install `bun` at: [https://bun.sh/](https://bun.sh/)

4.  **GitHub Repository:** Have a GitHub repository for your code and workflows.

5.  **`wrangler.toml` Setup:** Create or modify your `wrangler.toml` as shown above.

6.  **GitHub Secrets:** Add these secrets to your GitHub repository:
    *   `CLOUDFLARE_API_TOKEN`: Your Cloudflare API token.
    *   `CLOUDFLARE_ACCOUNT_ID`: Your Cloudflare Account ID.

**Deployment Process:**

1.  **Pull Request Deployment:** When you create a pull request against `main`, the `deploy-pr.yml` workflow creates a new environment, deploys the worker, and applies database migrations, using the bash scripts.

2.  **Cleanup:** After a pull request is merged, `cleanup-pr.yml` deletes the associated worker and database using the cleanup script.

3.  **Production Deployment:** When a tag is pushed, `deploy-prod.yml` deploys to production and runs the database migrations.

This complete guide, with code included, should make it easy to set up your Cloudflare Workers environment using D1 and GitHub Actions. If you have further questions or need more detail, feel free to ask!



