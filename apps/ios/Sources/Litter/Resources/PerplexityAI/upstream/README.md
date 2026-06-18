# Perplexity AI for Alley Cat sideload builds

This bundle vendors the MIT-licensed helallao/perplexity-ai client surface for sideload-only fakefs use.

Included: normal Perplexity search client, async client, labs client, config, logger, MCP server entrypoint, docs that do not automate account generation, and examples for basic, async, batch, file upload, and streaming usage.

Excluded from the packaged app: disposable email helpers, browser-account automation, and disposable-account examples. Users can provide their own Perplexity cookies or use anonymous auto mode where the upstream client supports it.

Upstream: https://github.com/helallao/perplexity-ai
License: MIT
