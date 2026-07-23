# Google Trends regional demand connector

## Provider decision

The production path is the official Google Trends API alpha behind a provider interface.
Google states that the API supports programmatic Trends access, a rolling five-year window, regular daily through yearly aggregation, and comparisons across regions and sub-regions.
Access remains limited and requires an application to the alpha program.
The connector therefore reports `Setup required` until an approved provider client is supplied.
It does not call undocumented Google Trends website endpoints and does not use scraping.

The official BigQuery Google Trends dataset is not the primary path.
It is a supported public dataset, but it contains top and rising queries rather than arbitrary watched keywords or topics.
That makes it useful for a future discovery connector, but insufficient for the MVP comparison contract.

## Supported connector contract

- Terms can be explicit keywords or Google topic identifiers.
- Comparison regions are Egypt (`EG`), Saudi Arabia (`SA`), United Arab Emirates (`AE`), Oman (`OM`), and the United States (`US`).
- Requests retain language, country, aggregation, and time-range metadata.
- The provider interface supports page tokens and the connector stops after a bounded number of pages.
- Rate-limited, delayed, unavailable, invalid-request, and setup-required outcomes remain distinct.
- Empty or failed responses never become zero-interest records.
- Secrets are not accepted, logged, serialized, or stored by this connector.
- The approved API client owns authentication and injects only typed provider results.

Google says the alpha data reaches up to two days ago.
The connector therefore exposes a delayed state rather than polling undocumented endpoints for fresher data.

## Setup and cost

Apply through the official [Google Trends API alpha page](https://developers.google.com/search/apis/trends).
Configure the approved client only after Google supplies access and authentication details.
Google's public alpha page does not publish pricing or a general-availability service-level commitment.
Treat both cost and production availability as dependent on the terms supplied with approved access.

The alternative [Google Trends BigQuery dataset](https://support.google.com/trends/answer/12764470?hl=en) can be queried in the BigQuery sandbox and has documented free-tier allowances, but normal BigQuery pricing applies above those allowances.

## Interpretation

Google Trends measures sampled, normalized search interest rather than absolute search volume.
Google also warns that low-volume terms may appear as zero and that statistical noise can create small fluctuations.
Downstream research should use Trends as one signal and retain the original Trends link.
See Google's [FAQ about Trends data](https://support.google.com/trends/answer/4365533?hl=en).
