# Instagram Graph API connector

## Supported scope

This connector uses Meta's official Instagram API with Facebook Login.
It collects media owned by connected Instagram Business or Creator accounts and comments on that owned media.
It can collect media reference data for explicitly configured professional-account usernames through Business Discovery where Meta permits the app and token to use that feature.
It does not scrape Instagram.
It does not support personal accounts, arbitrary public-feed monitoring, private accounts, arbitrary public comments, or inferred audience location.
Business Discovery reference items remain unverified and are never labeled as owned original evidence.

## Meta prerequisites

1. Create a Meta app with the Instagram API product and Facebook Login for Business.
2. Connect an eligible Instagram Business or Creator account to a Facebook Page.
3. Authorize a Facebook user who has the required Page task access.
4. Request only the permissions needed by the enabled features.
   Account discovery and owned media require `pages_show_list`, `pages_read_engagement`, and `instagram_basic`.
   Reading and managing owned-media comments requires `instagram_manage_comments`.
5. Complete Meta App Review and Business Verification before serving professional accounts that are not owned by app-role users.
6. Use a supported explicit Graph API version.
   Do not silently advance API versions.
7. Exchange and refresh tokens on a trusted backend.
   Store access tokens in encrypted server configuration or macOS Keychain.
   Never put tokens in source files, fixtures, logs, URLs, screenshots, or documentation.
8. Configure `selectedProfessionalAccountID` when a token exposes more than one professional account.
9. Configure Business Discovery usernames only when the app has reviewed access and the target is an eligible professional account.

Meta permissions and review requirements can change.
Confirm them against the selected Graph API version before production use.

## Data and privacy boundaries

The API does not provide reliable language or country fields for media and comments.
Zoid 99 writes `und` and `Unknown` unless the operator supplies explicit locale evidence with a provenance note.
It does not infer language or country from captions, usernames, profiles, or comment text.
Media URLs can expire and must not be treated as durable public links.
The connector preserves the durable Instagram permalink when Meta returns one.
Comment text and usernames are personal data.
Retain only what the research purpose requires and honor deletion and account-disconnection requests.

## Pagination and incremental collection

Meta paging URLs can contain access tokens.
The connector never follows a returned `paging.next` URL.
It extracts only the opaque `after` cursor and reconstructs an HTTPS request with the token in the authorization header.
The connector stops repeated cursors and enforces a configurable page ceiling.
The incremental cursor records the newest media timestamp, the newest comment timestamp per owned media item, and owned media IDs.
Reference discovery is refreshed as a bounded snapshot because Meta does not expose a supported arbitrary monitoring stream.

## Explicit states

- `setupRequired` means OAuth, API version, account selection, or a connected professional account needs operator action.
- `unavailable` means Meta rejected the request, returned an unexpected response, or did not expose the requested account.
- `unsupported` means the requested transport or account capability is outside the official connector boundary.
- `rateLimited` means Meta returned an API error or usage header indicating the request limit was reached.
- `available` means the official API request completed.
  An empty item list can be a valid incremental result.

## Deterministic and live validation

The normal suite uses fixtures and never needs credentials or network access.

```sh
swift test --filter InstagramConnectorContractTests
```

Live validation is opt-in and prints only account and item counts.
It never prints tokens, request URLs, captions, comments, account IDs, or usernames.

```sh
ZOID99_RUN_LIVE_INSTAGRAM=1 \
ZOID99_INSTAGRAM_GRAPH_VERSION=v25.0 \
ZOID99_INSTAGRAM_ACCESS_TOKEN='secure-process-value' \
swift test --filter LiveInstagramConnectorTests
```

Optionally set `ZOID99_INSTAGRAM_ACCOUNT_ID` when account discovery returns more than one professional account.

## Official Meta references

- [Instagram API with Facebook Login](https://developers.facebook.com/docs/instagram-platform/instagram-api-with-facebook-login/)
- [Business Discovery](https://developers.facebook.com/docs/instagram-platform/instagram-api-with-facebook-login/business-discovery/)
- [Instagram User media edge](https://developers.facebook.com/docs/instagram-platform/instagram-graph-api/reference/ig-user/media/)
- [Instagram Media comments edge](https://developers.facebook.com/docs/instagram-platform/instagram-graph-api/reference/ig-media/comments/)
- [Graph API paging](https://developers.facebook.com/docs/graph-api/results/)
- [Graph API rate limiting](https://developers.facebook.com/docs/graph-api/overview/rate-limiting/)
