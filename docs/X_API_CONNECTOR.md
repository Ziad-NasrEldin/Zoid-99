# Official X API Connector

## Scope

The connector uses only the official X API v2 at `https://api.x.com`.
It does not scrape X and never manufactures posts when the API is unavailable.
It maps public posts and expanded referenced posts into the existing `SourceItem` contract.
It retains individual public engagement metrics in `XCollectionReport` and maps observable interactions into `SourceItem.engagement`.

Supported collection targets are monitored public accounts, X Lists where the API grants access, and recent-search queries.
Account names are resolved with `GET /2/users/by`, then collected with `GET /2/users/:id/tweets`.
Lists use `GET /2/lists/:id/tweets`.
Keywords use `GET /2/tweets/search/recent`, which covers the most recent seven days.

## Access and credentials

X currently documents its API as pay-per-usage rather than the former Free, Basic, and Pro subscriptions.
Create an approved developer App in the X Developer Console, purchase API credits, and set a spending limit before enabling scheduled collection.
Current per-operation prices and endpoint permissions must be checked in the Developer Console because X does not publish all live rates on the public pricing page.

For read-only public monitoring, provide one of these environment variables:

```text
ZOID99_X_BEARER_TOKEN
ZOID99_X_OAUTH2_ACCESS_TOKEN
```

The app-only Bearer Token is the preferred minimum credential for public data.
An OAuth 2.0 user access token is accepted for deployments that already use user-context authorization.
Request read-only scopes and do not request write, follow, like, direct-message, or posting permissions.

Never put tokens in source files, fixtures, command arguments, screenshots, logs, or committed environment files.
Production deployments should inject the token from secure server configuration.

## Collection behavior

Post requests ask only for the fields used by Zoid 99:

```text
tweet.fields=id,text,author_id,created_at,lang,public_metrics,referenced_tweets
expansions=author_id,referenced_tweets.id,referenced_tweets.id.author_id
user.fields=id,name,username
```

List requests use only the `author_id` expansion because that is the expansion supported by the List-post endpoint.

Pagination is bounded to two pages per target by default and can be configured from one to ten pages.
The connector uses each response's unmodified `next_token`.
For recent search and account timelines, it saves the first page's `newest_id` only after every advertised page is drained, then sends that value as `since_id` during the next collection.
If the configured page limit stops collection early, the connector reports delayed and leaves the checkpoint unchanged so unseen posts cannot be skipped.
The List-post endpoint currently exposes pagination but not `since_id`, so the connector does not send an unsupported incremental parameter to Lists.

The connector reads `x-rate-limit-limit`, `x-rate-limit-remaining`, and `x-rate-limit-reset`.
HTTP 429 becomes an explicit rate-limited state with a retry delay.
Authentication, credit, permission, and service failures become explicit unavailable states with the HTTP status but without response bodies or secrets.
Missing credentials or missing monitoring targets become an explicit setup-required state.
Successful collections containing only stale posts become delayed.

## Deterministic validation

Run the connector contract tests without network access:

```sh
swift test --filter XAPIConnectorContractTests
```

The fixtures cover posts, referenced posts, authors, public metrics, pagination, rate-limit headers, bounded requests, and `since_id` checkpoints.

## Opt-in live validation

Choose a deliberate, narrow query to control billable reads.
The live test performs at most one page and never prints request headers, environment values, response bodies, post text, usernames, or post IDs.

```sh
ZOID99_RUN_LIVE_X=1 \
ZOID99_X_LIVE_QUERY='from:XDevelopers -is:retweet' \
ZOID99_X_BEARER_TOKEN='set-in-your-secure-shell' \
swift test --filter LiveXAPIConnectorTests
```

The proof line contains only the official endpoint, collection time, item count, and connector state.

## Official references

- [Getting access and credentials](https://docs.x.com/x-api/getting-started/getting-access)
- [Pay-per-usage pricing](https://docs.x.com/x-api/getting-started/pricing)
- [Usage and billing](https://docs.x.com/x-api/fundamentals/post-cap)
- [Rate limits](https://docs.x.com/x-api/fundamentals/rate-limits)
- [Recent search](https://docs.x.com/x-api/posts/search-recent-posts)
- [Recent-search pagination and polling](https://docs.x.com/x-api/posts/search/integrate/paginate)
- [List posts](https://docs.x.com/x-api/lists/get-list-posts)
- [Fields and expansions](https://docs.x.com/x-api/fundamentals/expansions)
