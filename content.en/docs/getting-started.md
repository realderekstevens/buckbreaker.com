---
title: "Getting Started"
weight: 1
---

# Getting Started

## Prerequisites

| Tool | Purpose | Install |
|---|---|---|
| `git` | Version control | [git-scm.com](https://git-scm.com) |
| `psql` / PostgreSQL | Database | [postgresql.org](https://www.postgresql.org) |
| `gum` | TUI CLI interface | `brew install gum` |
| `python3` | Finviz scraper | [python.org](https://python.org) |
| Hugo **extended** | Static site | See below |

### Installing Hugo Extended

The site requires the **extended** edition of Hugo (for SCSS):

```bash
# macOS
brew install hugo

# Verify — output must include "+extended"
hugo version
```

For other platforms, download the `+extended` binary from the
[Hugo releases page](https://github.com/gohugoio/hugo/releases).

---

## Clone the Repository

```bash
# Always use --recurse-submodules to pull the hugo-book theme
git clone --recurse-submodules https://github.com/realderekstevens/YourStockForecast.git
cd YourStockForecast
```

If you already cloned without the flag, initialize the theme submodule manually:

```bash
git submodule update --init --recursive
```

---

## Backend Setup

```bash
# 1. Copy the environment template
cp .env.example .env
# Edit .env with your PostgreSQL credentials

# 2. Launch the TUI CLI from the project root
chmod +x app.sh
./app.sh
```

The CLI (`app.sh`) handles everything: database setup, newspaper transcription,
scraper management, PostgREST, and Hugo builds — all from one terminal.

---

## Run the Hugo Site Locally

```bash
cd frontend/hugo-site
hugo server --minify --theme book
```

Then open [http://localhost:1313](http://localhost:1313).

> **Hot reload** is enabled by default — edit any Markdown file and the
> browser updates instantly.
