---
title: "YourStockForecast — Documentation"
type: docs
---

# YourStockForecast

**Historical + Real-Time Stock Market Intelligence**

A full-stack, open-source platform combining 1929-era newspaper transcriptions,
daily Finviz fundamentals, a PostgreSQL + PostgREST API, a Hugo static website,
and a Flutter mobile app.

---

## Features

- **1929 Crash Archive** — 100+ digitized newspaper pages transcribed into a searchable PostgreSQL database. Daily stock quotes from the original Black Tuesday and surrounding days.
- **Live Market Data** — A Python scraper pulls current equity data from Finviz each day into the same database, so you can compare 1929 fundamentals directly against today's market.
- **PostgREST REST API** — Instant JSON endpoints over PostgreSQL. No custom backend code. Powers both the Hugo website and the Flutter mobile app.
- **Flutter Mobile App** — A cross-platform mobile app (iOS + Android) for browsing stock data, running Graham valuations, and viewing historical comparisons on the go.

---

## Quick Links

- [Getting Started](getting-started) — clone, configure, and run
- [Architecture](architecture) — how the pieces fit together
