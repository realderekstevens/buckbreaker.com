# YourStockForecast

> **Historical + Real-Time Stock Market Intelligence**  
> 1929 newspaper archives · Finviz live data · PostgreSQL · PostgREST · Hugo · Flutter

---

## What Is This?

YourStockForecast is a full-stack, open-source platform for studying stock market history alongside live market data. It combines:

- **1929 Crash Transcription** — 100+ digitized newspaper pages with searchable daily stock quotes from the original Black Tuesday and surrounding days
- **Live Finviz Scraper** — a Python script (`dataminer.py`) that pulls current equity fundamentals into the same PostgreSQL database daily
- **Benjamin Graham Valuations** — automated defensive-investor screening across thousands of tickers, stored in a dedicated `graham_valuation` table
- **PostgREST REST API** — instant JSON endpoints over PostgreSQL with zero custom backend code
- **Hugo Static Website** — this documentation site plus a public-facing data browser at [yourstockforecast.com](https://yourstockforecast.com)
- **Flutter Mobile App** — a cross-platform iOS/Android app for browsing data and valuations on the go
- **Beautiful TUI CLI** (`app.sh`) — a 5,500-line Bash terminal UI (powered by `gum`) that manages the entire stack from one place

---

## Project Structure

```
YourStockForecast/
├── app.sh                      ← Master TUI CLI (run this to manage everything)
├── .ysf_cli.conf               ← CLI config (auto-created on first run)
├── backend/
│   ├── scraper/
│   │   ├── dataminer.py        ← Finviz live scraper
│   │   ├── graham_valuation.py ← Graham defensive investor screener
│   │   └── active_tickers.txt  ← Canonical ticker list
│   ├── historical/
│   │   └── stock_names.txt     ← 1929 stock name list for transcription
│   ├── api/                    ← PostgREST configuration
│   ├── sql/                    ← Schema and seed SQL files
│   └── logs/                   ← Scraper and CLI logs
├── frontend/
│   ├── hugo-site/              ← Hugo static site (hugo-book theme)
│   │   ├── hugo.toml           ← Hugo configuration
│   │   ├── content/
│   │   │   └── docs/           ← All Markdown content (drives sidebar menu)
│   │   ├── themes/
│   │   │   └── book/           ← hugo-book theme (git submodule)
│   │   └── static/
│   └── flutter-app/            ← Cross-platform mobile app
├── data/
│   ├── pdfs/                   ← Scanned newspaper PDFs
│   └── historical/             ← CSV exports and backups
├── scripts/                    ← Utility scripts
└── docs/                       ← Extended documentation (ARCHITECTURE.md, etc.)
```

---

## Quick Start

### Prerequisites

| Tool | Required For | Notes |
|---|---|---|
| `git` | Everything | — |
| PostgreSQL / `psql` | Database | v14+ recommended |
| `gum` | TUI CLI | `brew install gum` |
| `python3` | Finviz scraper | v3.9+ |
| Hugo **extended** | Hugo site | Must be the `+extended` build |

**Install Hugo Extended:**
```bash
brew install hugo          # macOS — installs extended by default
hugo version               # verify: output must contain "+extended"
```

### Clone

```bash
# Use --recurse-submodules to pull the hugo-book theme automatically
git clone --recurse-submodules https://github.com/realderekstevens/YourStockForecast.git
cd YourStockForecast
```

> ⚠️ If you already cloned without that flag, run:
> `git submodule update --init --recursive`

### Run the CLI

```bash
cp .env.example .env        # fill in your PostgreSQL credentials
chmod +x app.sh
./app.sh
```

The CLI guides you through database setup, scraping, transcription, API management, and Hugo builds.

### Run the Hugo Site Locally

```bash
cd frontend/hugo-site
hugo server --minify --theme book
# → open http://localhost:1313
```

---

## CLI Overview (`app.sh`)

The master CLI is organized into numbered sections:

| Section | Description |
|---|---|
| §1 | Config & globals |
| §6 | Database management & backups |
| §7 | Analytics & Graham valuation queries |
| §8 | CSV export menu |
| §11 | PostgREST API server start/stop |
| §12 | Insert Data (newspaper quotes, CSV import, SQL) |
| §14 | Finviz scraper menu |
| §15 | Hugo site build, preview, deploy |

---

## The 1929 Transcription Project

The core of this project is a hand-transcribed archive of daily stock prices from newspaper financial pages spanning the 1929 market crash. The embedded seed data covers October 28–29, 1929 (Black Tuesday) across dozens of NYSE stocks including US Steel, General Electric, Chrysler, Radio Corp, and more.

The CLI provides three transcription modes:
- **Quick Entry** — type all fields comma-separated on one line (fastest)
- **Form Entry** — guided field-by-field with labels always visible
- **CSV Import** — bulk-load from a `.csv` file

---

## Graham Valuation

`backend/scraper/graham_valuation.py` runs Benjamin Graham's defensive investor criteria across the full Finviz dataset:

- P/E ratio thresholds
- P/B ratio limits
- Dividend history
- Earnings growth
- Financial strength ratios

Results are stored in `graham_valuation` and surfaced via the CLI's Market Explorer, which lets you sort, filter, and drill into any ticker.

---

## API

PostgREST exposes the PostgreSQL database as a REST API at `:3000/api/v1`. No custom backend code required. Example endpoints:

```
GET /newspaper_stock_quotes?quote_date=eq.1929-10-28
GET /stock_quote?symbol=eq.AAPL&order=time_recorded.desc&limit=1
GET /graham_valuation?grade=eq.A&order=margin_of_safety.desc
```

---

## Roadmap

- [x] 1929 newspaper transcription (100+ pages embedded)
- [x] Finviz live scraper
- [x] Graham valuation screener
- [x] PostgREST API
- [x] TUI CLI with full stack management
- [ ] Hugo public site with live data (in progress)
- [ ] Flutter mobile app (in development)
- [ ] GitHub Actions CI for automated scraper + Hugo deploy

---

## Contributing

Pull requests are welcome. For larger changes, please open an issue first to discuss scope. The codebase is primarily Bash + Python + SQL, with a Hugo/Dart frontend.

---

## License

MIT — see [LICENSE](LICENSE) for details.
