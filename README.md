# YourStockForecast.com

**Historical + Real-Time Stock Market Intelligence**  
A full-stack open-source platform combining 1929-era newspaper transcriptions, daily Finviz fundamentals, PostgreSQL + PostgREST API, a Hugo static website, and a Flutter mobile app.

### ✨ Features
- **1929 Crash Transcription** — 100+ digitized newspaper pages with searchable daily quotes
- **PostgREST REST API** — instant JSON endpoints for Hugo/Flutter (no custom backend code)
- **Beautiful TUI CLI** (`app.sh`) — manage everything from one terminal
- **Hugo Static Website** (coming soon) — lightning-fast public site with live data
- **Flutter Mobile App** (in development)

### Project Structure
See [ARCHITECTURE.md](docs/ARCHITECTURE.md) for full details.

### Quick Start (Backend)

```bash
# 1. Clone + setup
git clone https://github.com/YOURUSERNAME/YourStockForecast.git
cd YourStockForecast

# 2. Copy environment
cp .env.example .env

# 3. Start the full stack with Docker (recommended)
docker compose up -d postgres postgrest

# 4. Run the CLI
cd backend/cli
chmod +x app.sh
./app.sh
