# OpenPRX Firecrawl Worker

A tiny Cloudflare Worker that proxies web-search and page-scrape requests to
[Firecrawl.dev](https://firecrawl.dev) for the OpenPRX mobile app.

## Setup

1. Install dependencies:
   ```bash
   npm install
   ```

2. Copy the example Wrangler config and add your secrets:
   ```bash
   cp wrangler.toml.example wrangler.toml
   wrangler secret put FIRECRAWL_API_KEY
   # optional: gate the worker with an app token
   wrangler secret put APP_TOKEN
   ```

3. Deploy:
   ```bash
   npm run deploy
   ```

## Endpoints

- `GET /v1/health`
- `POST /v1/search` with JSON body `{ "query": "...", "limit": 5 }`
- `POST /v1/scrape` with JSON body `{ "url": "..." }`

## Required environment variables

- `FIRECRAWL_API_KEY` – your Firecrawl API key.
- `APP_TOKEN` (optional) – if set, the app must send `Authorization: Bearer <token>`.

## Local development

```bash
npm run dev
```

Then point the OpenPRX app Settings → Worker URL to `http://localhost:8787`.
