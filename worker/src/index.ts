/**
 * Cloudflare Worker that proxies a subset of the Firecrawl.dev API for OpenPRX.
 *
 * Required environment variable:
 *   FIRECRAWL_API_KEY - Your Firecrawl API key (get one at https://firecrawl.dev)
 *
 * Optional environment variable:
 *   APP_TOKEN - Bearer token the mobile app must send to use this worker.
 *
 * Endpoints:
 *   GET  /v1/health            - Health check
 *   POST /v1/search            - { query, limit }
 *   POST /v1/scrape            - { url }
 */

export interface Env {
  FIRECRAWL_API_KEY: string;
  APP_TOKEN?: string;
}

const FIRECRAWL_BASE = 'https://api.firecrawl.dev/v1';

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname;

    // Handle CORS preflight.
    if (request.method === 'OPTIONS') {
      return corsResponse();
    }

    // Optional bearer-token gate.
    if (env.APP_TOKEN) {
      const auth = request.headers.get('Authorization') ?? '';
      const token = auth.replace(/^Bearer\s+/i, '').trim();
      if (token !== env.APP_TOKEN) {
        return jsonResponse({ error: 'Unauthorized' }, 401);
      }
    }

    try {
      if (path === '/v1/health' && request.method === 'GET') {
        return jsonResponse({ ok: true });
      }

      if (path === '/v1/search' && request.method === 'POST') {
        const body = (await request.json()) as { query?: string; limit?: number };
        return await handleSearch(env, body.query ?? '', Math.min(Math.max(body.limit ?? 5, 1), 20));
      }

      if (path === '/v1/scrape' && request.method === 'POST') {
        const body = (await request.json()) as { url?: string };
        return await handleScrape(env, body.url ?? '');
      }

      return jsonResponse({ error: 'Not found' }, 404);
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Unknown error';
      return jsonResponse({ error: message }, 500);
    }
  },
};

async function handleSearch(env: Env, query: string, limit: number): Promise<Response> {
  if (!query) return jsonResponse({ error: 'Missing query' }, 400);

  const response = await fetch(`${FIRECRAWL_BASE}/search`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${env.FIRECRAWL_API_KEY}`,
    },
    body: JSON.stringify({ query, limit }),
  });

  if (!response.ok) {
    const text = await response.text();
    return jsonResponse({ error: 'Firecrawl search failed', detail: text }, response.status);
  }

  const data = (await response.json()) as FirecrawlSearchResponse;
  const results =
    data.success && Array.isArray(data.data)
      ? data.data.map((r) => ({
          url: r.metadata?.sourceURL ?? r.url ?? '',
          title: r.metadata?.title ?? r.title ?? '',
          markdown: r.markdown ?? '',
        }))
      : [];

  return jsonResponse({ results });
}

async function handleScrape(env: Env, targetUrl: string): Promise<Response> {
  if (!targetUrl) return jsonResponse({ error: 'Missing url' }, 400);

  const response = await fetch(`${FIRECRAWL_BASE}/scrape`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${env.FIRECRAWL_API_KEY}`,
    },
    body: JSON.stringify({
      url: targetUrl,
      formats: ['markdown'],
    }),
  });

  if (!response.ok) {
    const text = await response.text();
    return jsonResponse({ error: 'Firecrawl scrape failed', detail: text }, response.status);
  }

  const data = (await response.json()) as FirecrawlScrapeResponse;
  const result = data.success && data.data ? data.data : null;
  return jsonResponse({
    url: targetUrl,
    title: result?.metadata?.title ?? '',
    markdown: result?.markdown ?? '',
  });
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    },
  });
}

function corsResponse(): Response {
  return new Response(null, {
    status: 204,
    headers: {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    },
  });
}

interface FirecrawlSearchResponse {
  success?: boolean;
  data?: Array<{
    url?: string;
    title?: string;
    markdown?: string;
    metadata?: {
      sourceURL?: string;
      title?: string;
    };
  }>;
}

interface FirecrawlScrapeResponse {
  success?: boolean;
  data?: {
    markdown?: string;
    metadata?: {
      title?: string;
      sourceURL?: string;
    };
  };
}
