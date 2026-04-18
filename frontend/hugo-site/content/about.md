---
title: "About YourStockForecast"
description: "Free stock market data and analysis tools powered by self-hosted Finviz data."
---

## What is YourStockForecast?

YourStockForecast is a free stock data and screening tool built on top of a self-hosted
data pipeline. Stock fundamentals, price data, and technical indicators are scraped nightly
from Finviz and served via a PostgREST API backed by PostgreSQL.

## Data Sources

All fundamental and price data comes from **Finviz**, a popular financial data aggregator.
Data is collected nightly (Monday–Friday) and is current as of the previous market close.
Intraday price changes reflect the most recent scrape cycle.

## Tech Stack

- **Database**: PostgreSQL via TraderDude pipeline
- **API**: PostgREST (auto-generates a REST API from PostgreSQL schema)
- **Frontend**: Hugo static site + vanilla JavaScript
- **Hosting**: Self-hosted on a VPS with Nginx

## Disclaimer

All data is for informational and educational purposes only. Nothing on this site constitutes
investment advice. Past performance is not indicative of future results. Always consult a
qualified financial advisor before making investment decisions. Data may be delayed or
inaccurate — verify with your broker before trading.
