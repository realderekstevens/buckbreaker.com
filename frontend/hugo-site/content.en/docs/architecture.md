---
title: "Architecture"
weight: 2
---

# Architecture

## System Overview

```
┌─────────────────────────────────────────────────────────┐
│                    Data Sources                          │
│   Finviz (daily scrape)    1929 Newspapers (manual)     │
└────────────────┬───────────────────────┬────────────────┘
                 │                       │
                 ▼                       ▼
        ┌────────────────────────────────────┐
        │         PostgreSQL Database        │
        │  stock_quote | newspaper_stock_    │
        │  quotes | graham_valuation         │
        └────────────────┬───────────────────┘
                         │
                         ▼
                ┌─────────────────┐
                │   PostgREST     │  ← instant REST API, zero code
                │  :3000/api/v1   │
                └────────┬────────┘
                         │
           ┌─────────────┴─────────────┐
           ▼                           ▼
  ┌─────────────────┐       ┌─────────────────────┐
  │  Hugo Site      │       │  Flutter Mobile App  │
  │  (static HTML)  │       │  (iOS + Android)     │
  └─────────────────┘       └─────────────────────┘
```

## Component Breakdown

### `app.sh` — Master CLI

A 5,500-line Bash TUI (powered by `gum`) that orchestrates the entire stack:

- **§12** Newspaper transcription (quick entry, form, CSV import)
- **§14** Finviz scraper control and monitoring
- **§11** PostgREST API server start/stop
- **§15** Hugo site build, preview, deploy
- **§6**  Database management and backups
- **§7**  Analytics queries and Graham valuations

### `backend/scraper/dataminer.py`

Python scraper that pulls live equity data from Finviz into the `stock_quote`
table. Runs on a schedule (cron or manually via the CLI).

### `backend/api/`

PostgREST configuration. Exposes the database as a JSON REST API used by
both the Hugo templates and the Flutter app.

### `frontend/hugo-site/`

This documentation and public-facing site. Built with Hugo and the
`hugo-book` theme.

### `frontend/flutter-app/`

Cross-platform mobile app for browsing stock data, running Graham valuations,
and comparing 1929 historical data against current market conditions.
