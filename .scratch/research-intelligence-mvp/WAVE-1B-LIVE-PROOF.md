# Wave 1B Live Public Feed Proof

## Validation

Validation completed at 2026-07-23T16:11:07Z.

The command was:

```sh
ZOID99_RUN_LIVE_FEEDS=1 swift test --filter LivePublicFeedTests/testVerifiedStarterCatalogCollectsRealPublishedItems
```

The test completed with one passing test and no failures.

## Verified sources

| Official source | Supported public endpoint | Collection time | Published items mapped |
| --- | --- | --- | ---: |
| OpenAI News | `https://openai.com/news/rss.xml` | 2026-07-23T16:11:06Z | 1048 |
| Hugging Face Transformers Releases | `https://api.github.com/repos/huggingface/transformers/releases?per_page=30` | 2026-07-23T16:11:06Z | 30 |
| arXiv Computer Science - Artificial Intelligence | `https://export.arxiv.org/api/query?search_query=cat%3Acs.AI&start=0&max_results=30&sortBy=submittedDate&sortOrder=descending` | 2026-07-23T16:11:06Z | 30 |

The proof records connector output only.
It does not claim that every collected item is a new or important research opportunity.
