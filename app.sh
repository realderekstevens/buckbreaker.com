#!/usr/bin/env bash
# =============================================================================
# YourStockForecast CLI  —  app.sh
# =============================================================================
# Terminal UI (gum + psql) for YourStockForecast.com operations:
#
#   1. NEWSPAPER STOCK TRANSCRIPTION
#      Record daily stock quotes from historical newspapers into PostgreSQL.
#      Supports quick-entry, guided form, CSV import, and SQL file import.
#      Schema: newspaper_stock_quotes  |  Embedded: NYSE Oct 28–29 1929
#
#   2. FINVIZ LIVE SCRAPER
#      backend/scraper/dataminer.py pulls current equity data → PostgreSQL.
#
#   3. HUGO STATIC SITE
#      Build, preview, and deploy YourStockForecast.com (frontend/hugo-site/).
#
#   4. POSTGREST API
#      Serve PostgreSQL data as a REST API for the site and Flutter app.
#
# DEPENDENCIES: gum  psql  git  gh  hugo  python3  rsync
# CONFIG FILE:  .ysf_cli.conf            (project root, auto-created)
# DB NAME:      yourstockforecast
# STOCK NAMES:  backend/historical/stock_names.txt
# SCRAPER:      backend/scraper/dataminer.py
# TICKERS:      backend/scraper/active_tickers.txt   ← single canonical location
# LOGS:         backend/logs/
#
# PROJECT LAYOUT (relative to this script):
#   backend/   scraper/  historical/  api/  sql/  logs/
#   data/      pdfs/  historical/
#   frontend/  hugo-site/  flutter-app/
#   docs/      scripts/  .github/
#
# STRUCTURE OF THIS FILE:
#   §1  Config & globals
#   §2  Helpers
#   §3  Dynamic pickers
#   §4  Newspaper entry modes (quick, form, CSV)
#   §5  Main menu & navigation
#   §6  Database management
#   §7  Analytics & queries
#   §8  Export menu
#   §9  Maintenance menu
#   §10 GitHub operations
#   §11 PostgREST API server
#   §12 Insert Data menu (stock quotes, 1929 data, CSV/SQL import)
#   §13 Settings menu
#   §14 Finviz scraper menu
#   §15 YourStockForecast.com site management
#   §16 App loop
# =============================================================================

# ── §1  CONFIG & GLOBALS ──────────────────────────────────────────────────────

# First, determine the directory where app.sh itself is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values (now all absolute and correct)
DEFAULT_PSQL_DB="yourstockforecast"
DEFAULT_PSQL_USER="postgres"
DEFAULT_SITE_DIR="/home/dude/Documents/GitHub/YourStockForecast"
DEFAULT_EXPORT_DIR="/home/dude/Documents/GitHub/YourStockForecast/data/historical"
DEFAULT_CONFIG_FILE="/home/dude/Documents/GitHub/YourStockForecast/.ysf_cli.conf"

# Load config first (before any readonly)
load_config() {
    [[ -f "$DEFAULT_CONFIG_FILE" ]] && source "$DEFAULT_CONFIG_FILE"
}
load_config

# Use values from .conf if present, otherwise fall back to defaults
PSQL_DB="${CONF_DB:-$DEFAULT_PSQL_DB}"
PSQL_USER="${CONF_USER:-$DEFAULT_PSQL_USER}"
SITE_DIR="${CONF_SITE_DIR:-$DEFAULT_SITE_DIR}"
EXPORT_DIR="${CONF_EXPORT_DIR:-$DEFAULT_EXPORT_DIR}"
CONFIG_FILE="${CONF_CONFIG_FILE:-$DEFAULT_CONFIG_FILE}"

# Now make them readonly
readonly PSQL_DB PSQL_USER SITE_DIR EXPORT_DIR CONFIG_FILE REPO_URL SCRIPT_DIR

# Build the psql commands using the (possibly overridden) values
readonly PSQL="psql -X --username=$PSQL_USER --dbname=$PSQL_DB --tuples-only -c"
readonly PSQL_ADMIN="psql -X --username=$PSQL_USER --dbname=postgres --tuples-only -c"

readonly REPO_URL="https://github.com/realderekstevens/YourStockForecast.git"

CURRENT_MENU="main"
declare -g POSTGREST_PID=""
declare -a MENU_BREADCRUMB=("Main")

# Optional: Change working directory to the script's location (recommended)
cd "$SCRIPT_DIR" || {
    echo "❌ Failed to change to script directory: $SCRIPT_DIR" >&2
    exit 1
}

###########
# Helpers #
###########
require() {
    command -v "$1" &>/dev/null || {
        echo "❌ Required command not found: $1" >&2
        exit 1
    }
}

section_header() {
    local crumb
    crumb=$(IFS=" › "; echo "${MENU_BREADCRUMB[*]}")
    gum style \
        --border normal \
        --margin "1" \
        --padding "1 2" \
        --border-foreground 008F11 \
        --bold "$crumb › $1"
}

info()    { gum style --foreground 244 "info:  $*" ; }
success() { gum style --foreground 76  "✓ $*"      ; }
error()   { gum style --foreground 196 "✗ $*" >&2  ; }
warn()    { gum style --foreground 214 "⚠ $*"      ; }

pause() {
    gum style --foreground 244 "Press ENTER to continue..."
    read -r
}

confirm() {
    gum confirm --default=false --timeout=30s -- "$1" || return 1
}

push_breadcrumb() { MENU_BREADCRUMB+=("$1"); }
pop_breadcrumb()  { [[ ${#MENU_BREADCRUMB[@]} -gt 1 ]] && unset 'MENU_BREADCRUMB[-1]'; }


####################
# Dependency Check #
####################
require gum
require psql
require git
require gh

#################
# Splash Screen #
#################
splash_screen() {
    clear
    gum style \
        --border normal \
        --margin "1" \
        --padding "1 2" \
        --border-foreground 212 \
        "Hello, $USER! Welcome to $(gum style --foreground 212 'YourStockForecast CLI')"
}

##################################
# Dynamic Pickers (gum filter)   #
##################################

# Stock name list file — one name per line, lives next to app.sh
STOCK_NAMES_FILE="${SCRIPT_DIR}/backend/historical/stock_names.txt"

# ── Finviz scraper paths (relative to SCRIPT_DIR) ──────────────────────────
DATAMINER_PY="${SCRIPT_DIR}/backend/scraper/dataminer.py"
ACTIVE_TICKERS_FILE="${SCRIPT_DIR}/backend/scraper/active_tickers.txt"
DATAMINER_LOG="${SCRIPT_DIR}/backend/logs/dataminer.log"
DATAMINER_PROGRESS="${SCRIPT_DIR}/backend/scraper/.dataminer_progress"

# Ensure the stock names file exists
_ensure_stock_names_file() {
    if [[ ! -f "$STOCK_NAMES_FILE" ]]; then
        cat > "$STOCK_NAMES_FILE" <<'EOF'
# Stock names for transcription — one name per line.
# Lines starting with # are comments and are ignored.
# Add new names here and they will appear in all pickers automatically.
#
# --- 1929 sample names ---
Anaconda Copper
AT&T
Chrysler
General Electric
General Motors
Montgomery Ward
New York Central
Pennsylvania RR
Radio Corp
Union Carbide
US Steel
Westinghouse
EOF
        info "Created stock names file: $STOCK_NAMES_FILE"
    fi
}

# Merge names from file + DB into a single sorted, deduplicated list
_stock_names_merged() {
    {
        # From names file (strip comments and blank lines)
        if [[ -f "$STOCK_NAMES_FILE" ]]; then
            grep -v '^\s*#' "$STOCK_NAMES_FILE" | grep -v '^\s*$'
        fi
        # From DB (may be empty on fresh setup)
        $PSQL "SELECT DISTINCT stock_name FROM newspaper_stock_quotes ORDER BY stock_name;" \
            2>/dev/null | sed 's/^ *//' | grep -v '^$' || true
    } | sort -u
}

pick_stock_name() {
    _ensure_stock_names_file
    local stocks
    stocks=$(_stock_names_merged)
    if [[ -z "$stocks" ]]; then
        gum input --placeholder "Stock name (e.g. US Steel)"
    else
        echo "$stocks" | gum filter --placeholder "Search stock name..."
    fi
}

pick_table() {
    local tables
    tables=$($PSQL "
        SELECT tablename FROM pg_tables
        WHERE schemaname NOT IN ('pg_catalog','information_schema')
        ORDER BY tablename;
    " 2>/dev/null | sed 's/^ *//' | grep -v '^$') || true
    if [[ -z "$tables" ]]; then
        gum input --placeholder "Table name"
    else
        echo "$tables" | gum filter --placeholder "Search table name..."
    fi
}

##################################
# Backup Before Destroy          #
##################################
backup_before_destroy() {
    local tbl="$1"
    mkdir -p "$EXPORT_DIR"
    local bkfile="$EXPORT_DIR/backup_${tbl}_$(date +%Y%m%d_%H%M%S).csv"
    psql -X --username="$PSQL_USER" --dbname="$PSQL_DB" \
        -c "\COPY $tbl TO '$bkfile' WITH CSV HEADER" 2>/dev/null \
        && info "Auto-backup saved to: $bkfile" \
        || info "Could not auto-backup '$tbl' (may be empty or not exist)."
}

###############################
# Dynamic Partition Creator   #
###############################
ensure_partition_for_date() {
    local date="$1"
    local year
    year=$(date -d "$date" +%Y 2>/dev/null || echo "1929")

    $PSQL "
        CREATE TABLE IF NOT EXISTS stock_quotes_${year}
        PARTITION OF newspaper_stock_quotes
            FOR VALUES FROM ('${year}-01-01') TO ('$((year+1))-01-01');
    " 2>/dev/null || true

    success "Year partition 'stock_quotes_${year}' ensured for date ${date}."
}

################################
# Newspaper Insert — Helpers   #
################################

# SQL NULL converter
_nullify() { [[ -z "$1" ]] && echo "NULL" || echo "'$1'"; }

# Validate a number field — returns 0 (ok) or 1 (bad)
_is_number() { [[ -z "$1" || "$1" =~ ^[0-9]+(\.[0-9]+)?$ ]]; }

# Core insert/update — shared by all entry modes
_newspaper_do_insert() {
    local quote_date="$1" stock_name="$2" daily_close="$3"
    local daily_high="$4" daily_low="$5" previous_close="$6"
    local year_high="$7"  year_low="$8"  dividend="$9"
    local sales_100s="${10:-0}"

    # Validate required fields
    if [[ -z "$quote_date" || -z "$stock_name" || -z "$daily_close" ]]; then
        error "Date, Stock Name, and Daily Close are required."
        return 1
    fi

    # Validate numeric fields
    for label_val in \
        "Daily Close:$daily_close" \
        "Daily High:$daily_high"   \
        "Daily Low:$daily_low"     \
        "Prev Close:$previous_close" \
        "Year High:$year_high"     \
        "Year Low:$year_low"       \
        "Sales 100s:$sales_100s"; do
        local lbl="${label_val%%:*}"
        local val="${label_val#*:}"
        if [[ -n "$val" ]] && ! _is_number "$val"; then
            error "$lbl must be a number (got: '$val')"
            return 1
        fi
    done

    ensure_partition_for_date "$quote_date"

    # Convert empty strings to SQL NULL
    local sql_yr_hi sql_yr_lo sql_div sql_hi sql_lo sql_close sql_prev
    sql_yr_hi=$(_nullify "$year_high")
    sql_yr_lo=$(_nullify "$year_low")
    sql_div=$(_nullify "$dividend")
    sql_hi=$(_nullify "$daily_high")
    sql_lo=$(_nullify "$daily_low")
    sql_close=$(_nullify "$daily_close")
    sql_prev=$(_nullify "$previous_close")
    [[ -z "$sales_100s" ]] && sales_100s=0

    # Preview table
    echo
    gum style --bold --foreground 212 "── Preview ──────────────────────────────"
    printf "%-20s %s\n" "Date:"           "$quote_date"
    printf "%-20s %s\n" "Stock:"          "$stock_name"
    printf "%-20s %s\n" "Close:"          "${daily_close:-—}"
    printf "%-20s %s\n" "High / Low:"     "${daily_high:-—} / ${daily_low:-—}"
    printf "%-20s %s\n" "Prev Close:"     "${previous_close:-—}"
    printf "%-20s %s\n" "52wk High/Low:"  "${year_high:-—} / ${year_low:-—}"
    printf "%-20s %s\n" "Dividend:"       "${dividend:-—}"
    printf "%-20s %s\n" "Sales (100s):"   "$sales_100s"
    gum style --foreground 240 "──────────────────────────────────────────"
    echo

    if ! confirm "Save this quote?"; then
        info "Discarded."
        return 2  # caller can treat 2 as "user cancelled, keep looping"
    fi

    $PSQL "
        INSERT INTO newspaper_stock_quotes
            (quote_date, stock_name, year_high, year_low, dividend, sales_100s,
             daily_high, daily_low, daily_close, previous_close)
        VALUES
            ('$quote_date', '$stock_name', $sql_yr_hi, $sql_yr_lo, $sql_div, $sales_100s,
             $sql_hi, $sql_lo, $sql_close, $sql_prev)
        ON CONFLICT (quote_date, stock_name) DO UPDATE SET
            year_high      = EXCLUDED.year_high,
            year_low       = EXCLUDED.year_low,
            dividend       = EXCLUDED.dividend,
            sales_100s     = EXCLUDED.sales_100s,
            daily_high     = EXCLUDED.daily_high,
            daily_low      = EXCLUDED.daily_low,
            daily_close    = EXCLUDED.daily_close,
            previous_close = EXCLUDED.previous_close;
    " && success "✅  Saved: $stock_name  on  $quote_date" || error "Insert failed — check psql output above."
}

# ── Quick Entry (one line, all fields at once) ────────────────
# Fastest for transcription. User sees the column order and types
# values separated by commas. Empty commas = NULL.
_newspaper_quick_entry() {
    local session_date
    session_date=$(gum input \
        --placeholder "Session date for all entries (YYYY-MM-DD)" \
        --value "1929-10-28")
    [[ -z "$session_date" ]] && return

    clear
    section_header "📋 Quick Entry  —  $session_date"

    # Column guide printed above the input box
    gum style --bold --foreground 212 \
        "Column order (comma-separated, leave blank for optional fields):"
    gum style --foreground 33 \
        "  STOCK NAME, CLOSE, HIGH, LOW, PREV CLOSE, YR HIGH, YR LOW, DIVIDEND, SALES(100s)"
    echo
    gum style --foreground 244 \
        "  Examples:"
    gum style --foreground 244 \
        "    US Steel, 205.50, 210.00, 195.00, 215.75, 261.00, 166.00, 2.00, 4520"
    gum style --foreground 244 \
        "    Radio Corp, 61.75, 68.00, 55.00, , 114.00, 26.00, , 8920"
    gum style --foreground 244 \
        "    Montgomery Ward, 85.50, 92.00, 82.00"
    echo
    gum style --foreground 240 "Type one stock per line. Leave the field blank and press Enter to finish."
    echo

    local inserted=0
    local skipped=0

    while true; do
        local line
        line=$(gum input \
            --placeholder "STOCK, CLOSE, HIGH, LOW, PREV, YR_HI, YR_LO, DIV, SALES  (blank = done)" \
            --width 90)

        # Blank line = done with this session
        [[ -z "$line" ]] && break

        # Parse comma-separated fields
        IFS=',' read -r \
            f_name f_close f_high f_low f_prev f_yr_hi f_yr_lo f_div f_sales \
            <<< "$line"

        # Trim whitespace from each field
        f_name=$(echo  "$f_name"  | xargs)
        f_close=$(echo "$f_close" | xargs)
        f_high=$(echo  "$f_high"  | xargs)
        f_low=$(echo   "$f_low"   | xargs)
        f_prev=$(echo  "$f_prev"  | xargs)
        f_yr_hi=$(echo "$f_yr_hi" | xargs)
        f_yr_lo=$(echo "$f_yr_lo" | xargs)
        f_div=$(echo   "$f_div"   | xargs)
        f_sales=$(echo "$f_sales" | xargs)

        if [[ -z "$f_name" || -z "$f_close" ]]; then
            warn "  Skipped (need at least STOCK NAME and CLOSE): '$line'"
            (( skipped++ ))
            continue
        fi

        # Validate numbers inline — give immediate feedback without leaving the loop
        local bad=0
        for chk_lbl_val in \
            "Close:$f_close" "High:$f_high" "Low:$f_low" \
            "Prev:$f_prev" "YrHi:$f_yr_hi" "YrLo:$f_yr_lo" \
            "Sales:$f_sales"; do
            local chk_lbl="${chk_lbl_val%%:*}"
            local chk_val="${chk_lbl_val#*:}"
            if [[ -n "$chk_val" ]] && ! _is_number "$chk_val"; then
                error "  Bad value for $chk_lbl: '$chk_val'  — re-enter this stock"
                bad=1; break
            fi
        done
        [[ $bad -eq 1 ]] && continue

        ensure_partition_for_date "$session_date" 2>/dev/null

        # Build SQL NULLs
        local sql_close sql_high sql_low sql_prev sql_yr_hi sql_yr_lo sql_div
        sql_close=$(_nullify "$f_close")
        sql_high=$(_nullify  "$f_high")
        sql_low=$(_nullify   "$f_low")
        sql_prev=$(_nullify  "$f_prev")
        sql_yr_hi=$(_nullify "$f_yr_hi")
        sql_yr_lo=$(_nullify "$f_yr_lo")
        sql_div=$(_nullify   "$f_div")
        [[ -z "$f_sales" ]] && f_sales=0

        $PSQL "
            INSERT INTO newspaper_stock_quotes
                (quote_date, stock_name, year_high, year_low, dividend, sales_100s,
                 daily_high, daily_low, daily_close, previous_close)
            VALUES
                ('$session_date', '$f_name', $sql_yr_hi, $sql_yr_lo, $sql_div, $f_sales,
                 $sql_high, $sql_low, $sql_close, $sql_prev)
            ON CONFLICT (quote_date, stock_name) DO UPDATE SET
                year_high      = EXCLUDED.year_high,
                year_low       = EXCLUDED.year_low,
                dividend       = EXCLUDED.dividend,
                sales_100s     = EXCLUDED.sales_100s,
                daily_high     = EXCLUDED.daily_high,
                daily_low      = EXCLUDED.daily_low,
                daily_close    = EXCLUDED.daily_close,
                previous_close = EXCLUDED.previous_close;
        " 2>/dev/null \
            && { success "  ✅  $f_name"; (( inserted++ )); } \
            || { error   "  ✗   $f_name — insert failed"; (( skipped++ )); }
    done

    echo
    gum style --bold "Session complete — $inserted saved, $skipped skipped."
}

# ── Field-by-field form entry ────────────────────────────────
# Displays all field names clearly before prompting, so the user
# always knows what's coming next. Validates inline.
_newspaper_form_entry() {
    section_header "📝 Form Entry"

    # Show the full layout so the user knows all fields upfront
    gum style --bold --foreground 212 "Fields you will be asked for:"
    gum style --foreground 33 \
        "  ① Date  ② Stock Name  ③ Close ④ High  ⑤ Low" \
        "  ⑥ Prev Close  ⑦ 52wk High  ⑧ 52wk Low  ⑨ Dividend  ⑩ Sales(100s)"
    gum style --foreground 244 "  Optional fields: ④ ⑤ ⑥ ⑦ ⑧ ⑨ ⑩  (just press Enter to skip)"
    echo

    local quote_date stock_name daily_close daily_high daily_low
    local previous_close year_high year_low dividend sales_100s

    quote_date=$(gum input \
        --prompt "① Date       › " \
        --placeholder "YYYY-MM-DD" \
        --value "1929-10-28")
    [[ -z "$quote_date" ]] && { info "Cancelled."; return; }

    stock_name=$(gum input \
        --prompt "② Stock Name › " \
        --placeholder "e.g. US Steel")
    [[ -z "$stock_name" ]] && { info "Cancelled."; return; }

    daily_close=$(gum input \
        --prompt "③ Close      › " \
        --placeholder "e.g. 205.50")
    [[ -z "$daily_close" ]] && { error "Close price is required."; return 1; }

    daily_high=$(gum input \
        --prompt "④ High       › " \
        --placeholder "optional — press Enter to skip")

    daily_low=$(gum input \
        --prompt "⑤ Low        › " \
        --placeholder "optional")

    previous_close=$(gum input \
        --prompt "⑥ Prev Close › " \
        --placeholder "optional — yesterday's close")

    year_high=$(gum input \
        --prompt "⑦ 52wk High  › " \
        --placeholder "optional")

    year_low=$(gum input \
        --prompt "⑧ 52wk Low   › " \
        --placeholder "optional")

    dividend=$(gum input \
        --prompt "⑨ Dividend   › " \
        --placeholder "optional  e.g. 2.00")

    sales_100s=$(gum input \
        --prompt "⑩ Sales(100s)› " \
        --placeholder "0" \
        --value "0")

    _newspaper_do_insert \
        "$quote_date" "$stock_name" "$daily_close" \
        "$daily_high" "$daily_low"  "$previous_close" \
        "$year_high"  "$year_low"   "$dividend" "$sales_100s"
}

# ── Batch CSV import from a file ─────────────────────────────
# Expects a header row then data rows. The header tells the parser
# which column maps to which field — order doesn't matter.
# Supported header names (case-insensitive, spaces/underscores flexible):
#   date, stock/name, close, high, low, prev/previous, yr_high/year_high,
#   yr_low/year_low, dividend, sales
_newspaper_csv_import() {
    section_header "📂 Batch CSV Import"

    gum style --bold --foreground 212 "Expected CSV format (header row required):"
    gum style --foreground 33 \
        "  date,stock_name,daily_close,daily_high,daily_low,previous_close,year_high,year_low,dividend,sales_100s"
    gum style --foreground 244 \
        "  • Column order is flexible — the header names drive the mapping"
    gum style --foreground 244 \
        "  • Optional columns may be omitted entirely or left blank"
    gum style --foreground 244 \
        "  • File must be readable by this user"
    echo

    local csv_path
    csv_path=$(gum input \
        --placeholder "Full path to CSV file  e.g. ~/quotes_oct1929.csv" \
        --width 80)
    # Expand ~ manually (gum doesn't expand it)
    csv_path="${csv_path/#\~/$HOME}"

    [[ -z "$csv_path" ]] && { info "Cancelled."; return; }

    if [[ ! -f "$csv_path" ]]; then
        error "File not found: $csv_path"
        return 1
    fi

    # Read header and lowercase it for matching
    local header
    header=$(head -1 "$csv_path" | tr '[:upper:]' '[:lower:]' | tr ' ' '_')

    # Find column indexes (0-based for awk)
    _col_idx() {
        echo "$header" | tr ',' '\n' | grep -n "$1" | head -1 | cut -d: -f1
    }

    local c_date c_name c_close c_high c_low c_prev c_yr_hi c_yr_lo c_div c_sales
    c_date=$(_col_idx "date")
    c_name=$(_col_idx "stock\|name")
    c_close=$(_col_idx "close")
    c_high=$(_col_idx "high")
    c_low=$(_col_idx "low")
    c_prev=$(_col_idx "prev")
    c_yr_hi=$(_col_idx "yr_high\|year_high")
    c_yr_lo=$(_col_idx "yr_low\|year_low")
    c_div=$(_col_idx "div")
    c_sales=$(_col_idx "sale")

    if [[ -z "$c_date" || -z "$c_name" || -z "$c_close" ]]; then
        error "CSV must have columns for date, stock name, and daily_close."
        info  "Detected header: $header"
        return 1
    fi

    info "Parsing: $csv_path"
    info "Columns found — date:$c_date  name:$c_name  close:$c_close  high:${c_high:-—}  low:${c_low:-—}"
    echo

    local total=0 ok=0 bad=0
    local row
    # Skip header row (tail -n +2)
    while IFS=',' read -r -a fields; do
        (( total++ ))

        # awk indexes are 1-based from grep -n; arrays are 0-based
        local f_date f_name f_close f_high f_low f_prev f_yr_hi f_yr_lo f_div f_sales
        f_date="${fields[$((c_date-1))]}"
        f_name="${fields[$((c_name-1))]}"
        f_close="${fields[$((c_close-1))]}"
        [[ -n "$c_high"   ]] && f_high="${fields[$((c_high-1))]}"
        [[ -n "$c_low"    ]] && f_low="${fields[$((c_low-1))]}"
        [[ -n "$c_prev"   ]] && f_prev="${fields[$((c_prev-1))]}"
        [[ -n "$c_yr_hi"  ]] && f_yr_hi="${fields[$((c_yr_hi-1))]}"
        [[ -n "$c_yr_lo"  ]] && f_yr_lo="${fields[$((c_yr_lo-1))]}"
        [[ -n "$c_div"    ]] && f_div="${fields[$((c_div-1))]}"
        [[ -n "$c_sales"  ]] && f_sales="${fields[$((c_sales-1))]}"

        # Trim whitespace
        f_date=$(echo  "$f_date"   | xargs)
        f_name=$(echo  "$f_name"   | xargs)
        f_close=$(echo "$f_close"  | xargs)
        f_high=$(echo  "$f_high"   | xargs)
        f_low=$(echo   "$f_low"    | xargs)
        f_prev=$(echo  "$f_prev"   | xargs)
        f_yr_hi=$(echo "$f_yr_hi"  | xargs)
        f_yr_lo=$(echo "$f_yr_lo"  | xargs)
        f_div=$(echo   "$f_div"    | xargs)
        f_sales=$(echo "$f_sales"  | xargs)
        [[ -z "$f_sales" ]] && f_sales=0

        if [[ -z "$f_date" || -z "$f_name" || -z "$f_close" ]]; then
            warn "  Row $total skipped — missing required fields: '$f_date' '$f_name' '$f_close'"
            (( bad++ )); continue
        fi

        ensure_partition_for_date "$f_date" 2>/dev/null

        local sql_close sql_high sql_low sql_prev sql_yr_hi sql_yr_lo sql_div
        sql_close=$(_nullify "$f_close")
        sql_high=$(_nullify  "$f_high")
        sql_low=$(_nullify   "$f_low")
        sql_prev=$(_nullify  "$f_prev")
        sql_yr_hi=$(_nullify "$f_yr_hi")
        sql_yr_lo=$(_nullify "$f_yr_lo")
        sql_div=$(_nullify   "$f_div")

        $PSQL "
            INSERT INTO newspaper_stock_quotes
                (quote_date, stock_name, year_high, year_low, dividend, sales_100s,
                 daily_high, daily_low, daily_close, previous_close)
            VALUES
                ('$f_date', '$f_name', $sql_yr_hi, $sql_yr_lo, $sql_div, $f_sales,
                 $sql_high, $sql_low, $sql_close, $sql_prev)
            ON CONFLICT (quote_date, stock_name) DO UPDATE SET
                year_high      = EXCLUDED.year_high,
                year_low       = EXCLUDED.year_low,
                dividend       = EXCLUDED.dividend,
                sales_100s     = EXCLUDED.sales_100s,
                daily_high     = EXCLUDED.daily_high,
                daily_low      = EXCLUDED.daily_low,
                daily_close    = EXCLUDED.daily_close,
                previous_close = EXCLUDED.previous_close;
        " 2>/dev/null \
            && { success "  ✅  [$total] $f_name  $f_date"; (( ok++ )); } \
            || { error   "  ✗   [$total] $f_name  $f_date — insert failed"; (( bad++ )); }

    done < <(tail -n +2 "$csv_path")

    echo
    gum style --bold "Import complete — $ok inserted/updated, $bad failed, $total total rows."
}

################################
# Custom Newspaper Insert      #
################################
insert_custom_newspaper_quote() {
    while true; do
        clear
        section_header "📋 Newspaper Stock Quote Entry"
        echo
        gum style --bold --foreground 212 "Choose your entry method:"
        gum style --foreground 244 \
            "  ⚡ Quick Entry  — type all fields for one stock on a single line (fastest)" \
            "  📝 Form Entry  — guided field-by-field with labels visible throughout" \
            "  📂 CSV Import  — load many quotes at once from a .csv file"
        echo

        local mode
        mode=$(gum choose \
            "⚡ Quick Entry  (one line per stock, comma-separated)" \
            "📝 Form Entry   (guided, all field names visible)" \
            "📂 CSV Import   (bulk load from file)" \
            "🔙 Back")

        case "$mode" in
            "⚡ Quick Entry"*)  _newspaper_quick_entry  ;;
            "📝 Form Entry"*)   _newspaper_form_entry   ;;
            "📂 CSV Import"*)   _newspaper_csv_import   ;;
            *)                  return                  ;;
        esac

        echo
        if ! confirm "Enter more stock quotes?"; then
            break
        fi
    done
}

#############
# Main Menu #
#############
main_menu() {
    MENU_BREADCRUMB=("Main")
    section_header "Main Menu"

    case "$(gum choose \
        "📈 Finviz Scraper" \
        "📰 YourStockForecast.com" \
        "Database Management" \
        "Table Management" \
        "Analytics & Queries" \
        "Export Data" \
        "Maintenance" \
        "GitHub Operations" \
        "PostgREST Setup" \
        "Insert Data" \
        "Settings" \
        "Exit")" in

        "📈 Finviz Scraper")         CURRENT_MENU="finviz"      ;;
        "📰 YourStockForecast.com")  CURRENT_MENU="ysf"         ;;
        "Database Management")       CURRENT_MENU="database"    ;;
        "Table Management")          CURRENT_MENU="table"       ;;
        "Analytics & Queries")       CURRENT_MENU="analytics"   ;;
        "Export Data")               CURRENT_MENU="export"      ;;
        "Maintenance")               CURRENT_MENU="maintenance" ;;
        "GitHub Operations")         CURRENT_MENU="github"      ;;
        "PostgREST Setup")           CURRENT_MENU="postgrest"   ;;
        "Insert Data")               CURRENT_MENU="insert_data" ;;
        "Settings")                  CURRENT_MENU="settings"    ;;
        *)                           CURRENT_MENU="exit"        ;;
    esac
}

############################
# Database Management Menu #
############################
database_menu() {
    push_breadcrumb "Database"
    section_header "Database Management"

    choice="$(gum choose \
        "List Schema" \
        "Create Database & Tables" \
        "Delete / Reset Database" \
        "Back")"

    case "$choice" in
        "List Schema")               list_schema_menu  ;;
        "Create Database & Tables")  create_db_menu    ;;
        "Delete / Reset Database")   delete_db_menu    ;;
        "Back" | *)
            pop_breadcrumb
            CURRENT_MENU="main"
            return
            ;;
    esac
    pop_breadcrumb
}

#########################
# Table Management Menu #
#########################
table_menu() {
    push_breadcrumb "Tables"
    while true; do
        section_header "Table Management"

        choice="$(gum choose \
            "List Tables in yourstockforecast database" \
            "List Schema for yahoo_finance" \
            "List Schema for finviz" \
            "List Schema for newspaper_stock_quotes" \
            "Back")"

        case "$choice" in
            "List Tables in yourstockforecast database")
                $PSQL "
                    SELECT tablename
                    FROM pg_tables
                    WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
                    ORDER BY tablename;
                " | cat
                ;;
            "List Schema for yahoo_finance")
                psql -X --username="$PSQL_USER" --dbname="$PSQL_DB" -c "\d yahoo_finance"
                ;;
            "List Schema for finviz")
                psql -X --username="$PSQL_USER" --dbname="$PSQL_DB" -c "\d finviz"
                ;;
            "List Schema for newspaper_stock_quotes")
                psql -X --username="$PSQL_USER" --dbname="$PSQL_DB" -c "\d newspaper_stock_quotes"
                ;;
            "Back" | *)
                pop_breadcrumb
                CURRENT_MENU="main"
                return
                ;;
        esac
        pause
    done
}

###############
# Schema Menu #
###############
list_schema_menu() {
    push_breadcrumb "Schema"
    while true; do
        section_header "Schema"

        choice="$(gum choose \
            "List Databases" \
            "List All Tables" \
            "Describe newspaper_stock_quotes" \
            "Describe yahoo_finance" \
            "List All Data in newspaper_stock_quotes" \
            "Back")"

        case "$choice" in
            "List Databases")
                $PSQL_ADMIN "SELECT datname FROM pg_database ORDER BY datname;" | cat
                ;;
            "List All Tables")
                $PSQL "
                    SELECT tablename
                    FROM pg_tables
                    WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
                    ORDER BY tablename;
                " | cat
                ;;
            "Describe newspaper_stock_quotes")
                psql -X --username="$PSQL_USER" --dbname="$PSQL_DB" -c "\d newspaper_stock_quotes"
                ;;
            "Describe yahoo_finance")
                psql -X --username="$PSQL_USER" --dbname="$PSQL_DB" -c "\d yahoo_finance"
                ;;
            "List All Data in newspaper_stock_quotes")
                echo "=== All Data in newspaper_stock_quotes ==="
                psql -X --username="$PSQL_USER" --dbname="$PSQL_DB" --tuples-only -x -c "
                    SELECT quote_date, stock_name, daily_high, daily_low, daily_close,
                           previous_close, year_high, year_low, dividend, sales_100s
                    FROM newspaper_stock_quotes
                    ORDER BY quote_date, stock_name;
                "
                ;;
            "Back" | *)
                pop_breadcrumb
                CURRENT_MENU="database"
                return
                ;;
        esac
        pause
    done
}

############################
# Create Database & Tables #
############################
create_database_if_missing() {
    if ! $PSQL_ADMIN "SELECT 1 FROM pg_database WHERE datname = '$PSQL_DB';" | grep -q 1; then
        gum spin --title "Creating database $PSQL_DB…" -- \
            psql -X --username="$PSQL_USER" --dbname=postgres -c "CREATE DATABASE $PSQL_DB;"
        success "Database '$PSQL_DB' created successfully."
    else
        info "Database '$PSQL_DB' already exists."
    fi
}

create_all_tables() {
    create_database_if_missing
    echo "Creating all core tables..."

    $PSQL "
        CREATE TABLE IF NOT EXISTS yahoo_finance (
            yahoo_finance_id SERIAL PRIMARY KEY,
            date             DATE DEFAULT CURRENT_DATE,
            open             NUMERIC(12,6),
            high             NUMERIC(12,6),
            low              NUMERIC(12,6),
            close            NUMERIC(12,6),
            adj_close        NUMERIC(12,6),
            volume           BIGINT
        );

        CREATE TABLE IF NOT EXISTS finviz (
            finviz_id               SERIAL PRIMARY KEY,
            date                    DATE DEFAULT CURRENT_DATE,
            major_index_membership  VARCHAR(10),
            price_to_earnings       NUMERIC(12,6),
            eps_ttm                 NUMERIC(12,6),
            insider_ownership       NUMERIC(12,6),
            shares_outstanding      NUMERIC(12,6),
            performance_week        INTEGER,
            market_capitalization   BIGINT,
            forward_pe              INTEGER,
            eps_next_year           INTEGER
        );


CREATE TABLE IF NOT EXISTS newspaper_stock_quotes (
    quote_date DATE NOT NULL,
    year_high NUMERIC(10,4),
    year_low NUMERIC(10,4),
    company_name TEXT NOT NULL,
    stock_variant TEXT DEFAULT '',
    dividend TEXT,
    sales_100s INTEGER,
    daily_high NUMERIC(10,4),
    daily_low NUMERIC(10,4),
    daily_close NUMERIC(10,4),
    previous_close NUMERIC(10,4),
    source_newspaper TEXT,
    source_market TEXT DEFAULT 'NYSE',
    PRIMARY KEY (quote_date, company_name, stock_variant)
) PARTITION BY RANGE (quote_date);

        CREATE TABLE IF NOT EXISTS monthly_stock_summary (
            month_year        DATE NOT NULL,
            stock_name        TEXT NOT NULL,
            avg_daily_close   NUMERIC(10,4),
            max_daily_high    NUMERIC(10,4),
            min_daily_low     NUMERIC(10,4),
            total_sales_100s  BIGINT,
            last_close        NUMERIC(10,4),
            PRIMARY KEY (month_year, stock_name)
        );
    "

    ensure_partition_for_date "1929-01-01"
    success "✅ All core tables (and 1929 partition) created or already existed."
}

create_db_menu() {
    push_breadcrumb "Create"
    while true; do
        section_header "Create Database & Tables"

        choice="$(gum choose \
            "Create Database (safe)" \
            "Create All Tables (Automated)" \
            "Create yahoo_finance table" \
            "Create finviz table" \
            "Create newspaper_stock_quotes table" \
            "Create Table Aggregated Summary" \
            "Create 1929 Year Partition" \
            "Create Partitioning Example Daily Partition" \
            "Create Index Date Name" \
            "Create Index Monthly Summary" \
            "Back")"

        case "$choice" in
            "Create Database (safe)")
                create_database_if_missing
                ;;
            "Create All Tables (Automated)")
                create_all_tables
                ;;
            "Create yahoo_finance table")
                $PSQL "
                    CREATE TABLE IF NOT EXISTS yahoo_finance (
                        yahoo_finance_id SERIAL PRIMARY KEY,
                        date             DATE DEFAULT CURRENT_DATE,
                        open             NUMERIC(12,6),
                        high             NUMERIC(12,6),
                        low              NUMERIC(12,6),
                        close            NUMERIC(12,6),
                        adj_close        NUMERIC(12,6),
                        volume           BIGINT
                    );
                "
                success "Table 'yahoo_finance' created (or already existed)."
                ;;
            "Create finviz table")
                $PSQL "
                    CREATE TABLE IF NOT EXISTS finviz (
                        finviz_id               SERIAL PRIMARY KEY,
                        date                    DATE DEFAULT CURRENT_DATE,
                        major_index_membership  VARCHAR(10),
                        price_to_earnings       NUMERIC(12,6),
                        eps_ttm                 NUMERIC(12,6),
                        insider_ownership       NUMERIC(12,6),
                        shares_outstanding      NUMERIC(12,6),
                        performance_week        INTEGER,
                        market_capitalization   BIGINT,
                        forward_pe              INTEGER,
                        eps_next_year           INTEGER
                    );
                "
                success "Table 'finviz' created (or already existed)."
                ;;
            "Create newspaper_stock_quotes table")
                $PSQL "
                    CREATE TABLE IF NOT EXISTS newspaper_stock_quotes (
                        quote_date     DATE        NOT NULL,
                        stock_name     TEXT        NOT NULL,
                        year_high      NUMERIC(10,4),
                        year_low       NUMERIC(10,4),
                        dividend       TEXT,
                        sales_100s     INTEGER,
                        daily_high     NUMERIC(10,4),
                        daily_low      NUMERIC(10,4),
                        daily_close    NUMERIC(10,4),
                        previous_close NUMERIC(10,4),
                        PRIMARY KEY (quote_date, stock_name)
                    ) PARTITION BY RANGE (quote_date);
                "
                success "Table 'newspaper_stock_quotes' created (or already existed)."
                ;;
            "Create Table Aggregated Summary")
                $PSQL "
                    CREATE TABLE IF NOT EXISTS monthly_stock_summary (
                        month_year        DATE NOT NULL,
                        stock_name        TEXT NOT NULL,
                        avg_daily_close   NUMERIC(10,4),
                        max_daily_high    NUMERIC(10,4),
                        min_daily_low     NUMERIC(10,4),
                        total_sales_100s  BIGINT,
                        last_close        NUMERIC(10,4),
                        PRIMARY KEY (month_year, stock_name)
                    );
                "
                success "Table 'monthly_stock_summary' created (or already existed)."
                ;;
            "Create 1929 Year Partition")
                $PSQL "
                    CREATE TABLE IF NOT EXISTS stock_quotes_1929
                    PARTITION OF newspaper_stock_quotes
                        FOR VALUES FROM ('1929-01-01') TO ('1930-01-01');
                "
                success "Partition 'stock_quotes_1929' created (or already existed)."
                ;;
            "Create Partitioning Example Daily Partition")
                $PSQL "
                    CREATE TABLE IF NOT EXISTS stock_quotes_1929_04_03
                    PARTITION OF stock_quotes_1929
                        FOR VALUES FROM ('1929-04-03') TO ('1929-04-04');
                "
                success "Daily partition 'stock_quotes_1929_04_03' created (or already existed)."
                ;;
            "Create Index Date Name")
                $PSQL "
                    CREATE INDEX IF NOT EXISTS idx_newspaper_stock_quotes_date_name
                    ON newspaper_stock_quotes (quote_date, stock_name);
                "
                success "Index 'idx_newspaper_stock_quotes_date_name' created (or already existed)."
                ;;
            "Create Index Monthly Summary")
                $PSQL "
                    CREATE INDEX IF NOT EXISTS idx_monthly_summary_month
                    ON monthly_stock_summary (month_year);
                "
                success "Index 'idx_monthly_summary_month' created (or already existed)."
                ;;
            "Back" | *)
                pop_breadcrumb
                return
                ;;
        esac
        pause
    done
}

############################
# Delete / Reset Database  #
############################
delete_db_menu() {
    push_breadcrumb "Delete/Reset"
    while true; do
        section_header "⚠️ Delete / Reset Database (Destructive!)"

        choice="$(gum choose \
            "Delete rows from table" \
            "Drop specific table" \
            "Drop entire database (with force)" \
            "Full Reset (Drop + Recreate + Tables)" \
            "Back")"

        case "$choice" in
            "Delete rows from table")    delete_rows_menu   ;;
            "Drop specific table")       drop_table_menu    ;;
            "Drop entire database (with force)")  drop_database        ;;
            "Full Reset (Drop + Recreate + Tables)") full_reset_database  ;;
            "Back" | *)
                pop_breadcrumb
                return
                ;;
        esac
        pause
    done
}

delete_rows_menu() {
    echo "Tables in '$PSQL_DB':"
    $PSQL "
        SELECT tablename FROM pg_tables
        WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
        ORDER BY tablename;
    " | cat

    echo
    if ! confirm "⚠️ This will DELETE ALL ROWS from a table. Continue?"; then return; fi

    local table
    table=$(pick_table)
    [[ -z "$table" ]] && { error "No table selected."; return; }

    if confirm "Really TRUNCATE table '$table'? This cannot be undone."; then
        backup_before_destroy "$table"
        $PSQL "TRUNCATE TABLE $table RESTART IDENTITY CASCADE;" || true
        success "All rows deleted from '$table'."
    fi
}

drop_table_menu() {
    echo "Tables in '$PSQL_DB':"
    $PSQL "
        SELECT tablename FROM pg_tables
        WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
        ORDER BY tablename;
    " | cat

    echo
    if ! confirm "⚠️ This will DROP a table permanently. Continue?"; then return; fi

    local table
    table=$(pick_table)
    [[ -z "$table" ]] && { error "No table selected."; return; }

    if confirm "FINAL WARNING: Drop table '$table' and all dependent objects?"; then
        backup_before_destroy "$table"
        $PSQL "DROP TABLE IF EXISTS $table CASCADE;" || true
        success "Table '$table' has been dropped."
    fi
}

drop_database() {
    if ! confirm "⚠️ This will permanently DELETE the entire database '$PSQL_DB'!"; then return; fi
    if ! confirm "FINAL WARNING: All data will be lost. Confirm?"; then return; fi

    gum spin --title "Dropping database $PSQL_DB with FORCE..." -- \
        psql -X --username="$PSQL_USER" --dbname=postgres -c \
            "DROP DATABASE IF EXISTS $PSQL_DB WITH (FORCE);"

    success "Database '$PSQL_DB' has been completely dropped."
}

full_reset_database() {
    if ! confirm "⚠️ FULL RESET: Drop, recreate, and reset everything. Continue?"; then return; fi
    if ! confirm "FINAL WARNING: All data will be permanently lost. Confirm?"; then return; fi

    gum spin --title "Dropping database $PSQL_DB..." -- \
        psql -X --username="$PSQL_USER" --dbname=postgres -c \
            "DROP DATABASE IF EXISTS $PSQL_DB WITH (FORCE);"

    psql -X --username="$PSQL_USER" --dbname=postgres -c "CREATE DATABASE $PSQL_DB;"
    success "Database '$PSQL_DB' has been fully reset."
    info "Use 'Create Database & Tables' → 'Create All Tables (Automated)' to rebuild."
}

########################
# Analytics & Queries  #
########################
analytics_menu() {
    push_breadcrumb "Analytics"
    while true; do
        section_header "📊 Analytics & Queries"

        choice="$(gum choose \
            "Top Movers by Date" \
            "Biggest Single-Day Drops (All Time)" \
            "Biggest Single-Day Gains (All Time)" \
            "Price Range Summary per Stock" \
            "Volume Leaders" \
            "Day-over-Day Change %" \
            "Compare Two Stocks" \
            "Monthly Summary Stats" \
            "Stocks at 52-Week Low on a Date" \
            "Back")"

        case "$choice" in
            "Top Movers by Date")
                local qdate
                qdate=$(gum input --placeholder "Date (YYYY-MM-DD)" --value "1929-10-28")
                $PSQL "
                    SELECT stock_name,
                           daily_close,
                           previous_close,
                           ROUND(((daily_close - previous_close) / NULLIF(previous_close,0)) * 100, 2) AS pct_change
                    FROM newspaper_stock_quotes
                    WHERE quote_date = '$qdate'
                      AND previous_close IS NOT NULL
                    ORDER BY pct_change DESC;
                " | cat
                ;;

            "Biggest Single-Day Drops (All Time)")
                $PSQL "
                    SELECT quote_date, stock_name,
                           daily_close,
                           previous_close,
                           ROUND(((daily_close - previous_close) / NULLIF(previous_close,0)) * 100, 2) AS pct_change
                    FROM newspaper_stock_quotes
                    WHERE previous_close IS NOT NULL
                    ORDER BY pct_change ASC
                    LIMIT 20;
                " | cat
                ;;

            "Biggest Single-Day Gains (All Time)")
                $PSQL "
                    SELECT quote_date, stock_name,
                           daily_close,
                           previous_close,
                           ROUND(((daily_close - previous_close) / NULLIF(previous_close,0)) * 100, 2) AS pct_change
                    FROM newspaper_stock_quotes
                    WHERE previous_close IS NOT NULL
                    ORDER BY pct_change DESC
                    LIMIT 20;
                " | cat
                ;;

            "Price Range Summary per Stock")
                local sname
                sname=$(pick_stock_name)
                [[ -z "$sname" ]] && { error "No stock selected."; pause; continue; }
                $PSQL "
                    SELECT quote_date,
                           daily_high,
                           daily_low,
                           daily_close,
                           ROUND(daily_high - daily_low, 4) AS daily_range
                    FROM newspaper_stock_quotes
                    WHERE stock_name ILIKE '%$sname%'
                    ORDER BY quote_date;
                " | cat
                ;;

            "Volume Leaders")
                $PSQL "
                    SELECT stock_name,
                           SUM(sales_100s)             AS total_volume_100s,
                           ROUND(AVG(sales_100s), 0)   AS avg_daily_volume_100s,
                           COUNT(*)                     AS trading_days
                    FROM newspaper_stock_quotes
                    GROUP BY stock_name
                    ORDER BY total_volume_100s DESC;
                " | cat
                ;;

            "Day-over-Day Change %")
                local sname
                sname=$(pick_stock_name)
                [[ -z "$sname" ]] && { error "No stock selected."; pause; continue; }
                $PSQL "
                    SELECT quote_date,
                           daily_close,
                           previous_close,
                           ROUND(((daily_close - previous_close) / NULLIF(previous_close,0)) * 100, 2) AS pct_change
                    FROM newspaper_stock_quotes
                    WHERE stock_name ILIKE '%$sname%'
                      AND previous_close IS NOT NULL
                    ORDER BY quote_date;
                " | cat
                ;;

            "Compare Two Stocks")
                info "Select first stock:"
                local s1
                s1=$(pick_stock_name)
                info "Select second stock:"
                local s2
                s2=$(pick_stock_name)
                [[ -z "$s1" || -z "$s2" ]] && { error "Two stocks required."; pause; continue; }
                $PSQL "
                    SELECT a.quote_date,
                           a.stock_name                AS stock_1,
                           a.daily_close               AS close_1,
                           b.stock_name                AS stock_2,
                           b.daily_close               AS close_2,
                           ROUND(a.daily_close - b.daily_close, 4) AS difference
                    FROM newspaper_stock_quotes a
                    JOIN newspaper_stock_quotes b
                         ON a.quote_date = b.quote_date
                    WHERE a.stock_name ILIKE '%$s1%'
                      AND b.stock_name ILIKE '%$s2%'
                    ORDER BY a.quote_date;
                " | cat
                ;;

            "Monthly Summary Stats")
                $PSQL "
                    SELECT DATE_TRUNC('month', quote_date) AS month,
                           stock_name,
                           ROUND(AVG(daily_close), 4)  AS avg_close,
                           MAX(daily_high)              AS month_high,
                           MIN(daily_low)               AS month_low,
                           SUM(sales_100s)              AS total_volume_100s
                    FROM newspaper_stock_quotes
                    GROUP BY month, stock_name
                    ORDER BY month, stock_name;
                " | cat
                ;;

            "Stocks at 52-Week Low on a Date")
                local qdate
                qdate=$(gum input --placeholder "Date (YYYY-MM-DD)" --value "1929-10-29")
                $PSQL "
                    SELECT stock_name, daily_low, year_low,
                           ROUND(daily_low - year_low, 4) AS above_52wk_low
                    FROM newspaper_stock_quotes
                    WHERE quote_date = '$qdate'
                      AND year_low IS NOT NULL
                    ORDER BY above_52wk_low ASC;
                " | cat
                ;;

            "Back" | *)
                pop_breadcrumb
                CURRENT_MENU="main"
                return
                ;;
        esac
        pause
    done
}

##############
# Export Menu#
##############
export_menu() {
    mkdir -p "$EXPORT_DIR"
    push_breadcrumb "Export"
    while true; do
        section_header "📤 Export Data"

        choice="$(gum choose \
            "Export table to CSV" \
            "Export date range to CSV" \
            "Export single stock history to CSV" \
            "Export all to JSON" \
            "List existing exports" \
            "Open export folder" \
            "Back")"

        case "$choice" in
            "Export table to CSV")
                local tbl ts fname
                tbl=$(pick_table)
                [[ -z "$tbl" ]] && { error "No table selected."; pause; continue; }
                ts=$(date +%Y%m%d_%H%M%S)
                fname="$EXPORT_DIR/${tbl}_${ts}.csv"
                gum spin --title "Exporting $tbl to CSV..." -- \
                    psql -X --username="$PSQL_USER" --dbname="$PSQL_DB" \
                        -c "\COPY $tbl TO '$fname' WITH CSV HEADER"
                success "Exported to $fname"
                ;;

            "Export date range to CSV")
                local d1 d2 fname
                d1=$(gum input --placeholder "Start date (YYYY-MM-DD)" --value "1929-10-28")
                d2=$(gum input --placeholder "End date   (YYYY-MM-DD)" --value "1929-10-29")
                fname="$EXPORT_DIR/quotes_${d1}_to_${d2}.csv"
                gum spin --title "Exporting date range..." -- \
                    psql -X --username="$PSQL_USER" --dbname="$PSQL_DB" \
                        -c "\COPY (SELECT * FROM newspaper_stock_quotes WHERE quote_date BETWEEN '$d1' AND '$d2' ORDER BY quote_date, stock_name) TO '$fname' WITH CSV HEADER"
                success "Exported to $fname"
                ;;

            "Export single stock history to CSV")
                local sname fname
                sname=$(pick_stock_name)
                [[ -z "$sname" ]] && { error "No stock selected."; pause; continue; }
                fname="$EXPORT_DIR/stock_${sname// /_}_$(date +%Y%m%d_%H%M%S).csv"
                gum spin --title "Exporting $sname..." -- \
                    psql -X --username="$PSQL_USER" --dbname="$PSQL_DB" \
                        -c "\COPY (SELECT * FROM newspaper_stock_quotes WHERE stock_name ILIKE '%$sname%' ORDER BY quote_date) TO '$fname' WITH CSV HEADER"
                success "Exported to $fname"
                ;;

            "Export all to JSON")
                local fname
                fname="$EXPORT_DIR/quotes_$(date +%Y%m%d_%H%M%S).json"
                gum spin --title "Exporting to JSON..." -- bash -c "
                    psql -X --username='$PSQL_USER' --dbname='$PSQL_DB' \
                        --no-align --tuples-only \
                        -c \"SELECT json_agg(row_to_json(t)) FROM (SELECT * FROM newspaper_stock_quotes ORDER BY quote_date, stock_name) t;\" \
                        > '$fname'
                "
                success "Exported JSON to $fname"
                ;;

            "List existing exports")
                echo "=== Files in $EXPORT_DIR ==="
                ls -lh "$EXPORT_DIR" 2>/dev/null || info "No exports yet."
                ;;

            "Open export folder")
                xdg-open "$EXPORT_DIR" 2>/dev/null \
                    || open "$EXPORT_DIR" 2>/dev/null \
                    || info "Folder: $EXPORT_DIR"
                ;;

            "Back" | *)
                pop_breadcrumb
                CURRENT_MENU="main"
                return
                ;;
        esac
        pause
    done
}

##################
# Maintenance    #
##################
maintenance_menu() {
    push_breadcrumb "Maintenance"
    while true; do
        section_header "🔧 Maintenance"

        choice="$(gum choose \
            "VACUUM ANALYZE all tables" \
            "Show table sizes" \
            "Show row counts" \
            "List active connections" \
            "Kill idle connections" \
            "Rebuild indexes on table" \
            "Check for missing year partitions" \
            "Back")"

        case "$choice" in
            "VACUUM ANALYZE all tables")
                gum spin --title "Running VACUUM ANALYZE..." -- \
                    psql -X --username="$PSQL_USER" --dbname="$PSQL_DB" -c "VACUUM ANALYZE;"
                success "VACUUM ANALYZE complete."
                ;;

            "Show table sizes")
                $PSQL "
                    SELECT relname                                          AS table_name,
                           pg_size_pretty(pg_total_relation_size(relid))   AS total_size,
                           pg_size_pretty(pg_relation_size(relid))         AS table_size,
                           pg_size_pretty(pg_indexes_size(relid))          AS index_size
                    FROM pg_catalog.pg_statio_user_tables
                    ORDER BY pg_total_relation_size(relid) DESC;
                " | cat
                ;;

            "Show row counts")
                $PSQL "
                    SELECT relname AS table_name, n_live_tup AS live_rows, n_dead_tup AS dead_rows
                    FROM pg_stat_user_tables
                    ORDER BY n_live_tup DESC;
                " | cat
                ;;

            "List active connections")
                $PSQL_ADMIN "
                    SELECT pid, usename, application_name, state,
                           query_start, LEFT(query, 60) AS query_preview
                    FROM pg_stat_activity
                    WHERE datname = '$PSQL_DB'
                    ORDER BY query_start;
                " | cat
                ;;

            "Kill idle connections")
                if confirm "Kill ALL IDLE connections to '$PSQL_DB'?"; then
                    $PSQL_ADMIN "
                        SELECT pg_terminate_backend(pid)
                        FROM pg_stat_activity
                        WHERE datname = '$PSQL_DB' AND state = 'idle';
                    " | cat
                    success "Idle connections terminated."
                fi
                ;;

            "Rebuild indexes on table")
                local tbl
                tbl=$(pick_table)
                [[ -z "$tbl" ]] && { error "No table selected."; pause; continue; }
                if confirm "REINDEX TABLE '$tbl'? This may lock the table briefly."; then
                    gum spin --title "Reindexing $tbl..." -- \
                        psql -X --username="$PSQL_USER" --dbname="$PSQL_DB" -c "REINDEX TABLE $tbl;"
                    success "Reindex of '$tbl' complete."
                fi
                ;;

            "Check for missing year partitions")
                info "Existing year partitions:"
                $PSQL "
                    SELECT child.relname AS partition_name
                    FROM pg_inherits
                    JOIN pg_class parent ON pg_inherits.inhparent = parent.oid
                    JOIN pg_class child  ON pg_inherits.inhrelid  = child.oid
                    WHERE parent.relname = 'newspaper_stock_quotes'
                    ORDER BY child.relname;
                " | cat
                echo
                info "Tip: Use 'Create Database & Tables → Create 1929 Year Partition' to add missing ones."
                ;;

            "Back" | *)
                pop_breadcrumb
                CURRENT_MENU="main"
                return
                ;;
        esac
        pause
    done
}

###############
# GitHub Menu #
###############
github_menu() {
    if [[ ! -d "$SITE_DIR" ]]; then
        error "Repo directory not found: $SITE_DIR"
        error "Clone it first or update SITE_DIR in this script."
        pause
        CURRENT_MENU="main"
        return
    fi

    cd "$SITE_DIR"
    push_breadcrumb "GitHub"

    while true; do
        section_header "GitHub Operations"

        choice="$(gum choose \
            "Status" \
            "Diff (staged)" \
            "Commit & Push" \
            "Pull Updates" \
            "View Recent Commits" \
            "Create Branch" \
            "Switch Branch" \
            "Login" \
            "Back")"

        case "$choice" in
            "Status")
                git status
                ;;
            "Diff (staged)")
                git diff --staged | head -n 100 || git diff | head -n 100
                ;;
            "Commit & Push")
                msg=$(gum input --placeholder "Commit message")
                [[ -z $msg ]] && continue
                git add -A
                git commit -m "$msg"
                git push
                success "Pushed: $msg"
                ;;
            "Pull Updates")
                gum spin --title "Pulling latest changes..." -- git pull --rebase
                success "Pull complete."
                ;;
            "View Recent Commits")
                git log --oneline -20
                ;;
            "Create Branch")
                local bname
                bname=$(gum input --placeholder "New branch name")
                [[ -z "$bname" ]] && continue
                git checkout -b "$bname"
                success "Created and switched to branch: $bname"
                ;;
            "Switch Branch")
                local branches chosen
                branches=$(git branch | sed 's/[* ]//g')
                chosen=$(echo "$branches" | gum filter --placeholder "Select branch...")
                [[ -z "$chosen" ]] && continue
                git checkout "$chosen"
                success "Switched to branch: $chosen"
                ;;
            "Login")
                gh auth login
                ;;
            "Back" | *)
                pop_breadcrumb
                CURRENT_MENU="main"
                return
                ;;
        esac
        pause
    done
}

##################################
# PostgREST Config & Globals     #
##################################
POSTGREST_CONF="${SCRIPT_DIR}/backend/api/postgrest.conf"
POSTGREST_LOG="${SCRIPT_DIR}/backend/logs/postgrest.log"
POSTGREST_HOST="localhost"
POSTGREST_PORT="3000"
POSTGREST_SCHEMA="public"
POSTGREST_ANON_ROLE="anon"
POSTGREST_AUTH_ROLE="authenticator"
POSTGREST_APP_ROLE="app_user"        # JWT-authenticated read/write role
POSTGREST_ADMIN_ROLE="api_admin"     # full admin access via JWT
POSTGREST_JWT_SECRET=""              # set by wizard; required for auth
POSTGREST_JWT_EXP=3600               # token lifetime in seconds (1 hour default)

# Auth schema – holds login function, users table, tokens view
POSTGREST_AUTH_SCHEMA="auth"

# Load PostgREST-specific overrides from the main config file
load_postgrest_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
        POSTGREST_HOST="${CONF_PGREST_HOST:-$POSTGREST_HOST}"
        POSTGREST_PORT="${CONF_PGREST_PORT:-$POSTGREST_PORT}"
        POSTGREST_SCHEMA="${CONF_PGREST_SCHEMA:-$POSTGREST_SCHEMA}"
        POSTGREST_ANON_ROLE="${CONF_PGREST_ANON_ROLE:-$POSTGREST_ANON_ROLE}"
        POSTGREST_JWT_SECRET="${CONF_PGREST_JWT_SECRET:-$POSTGREST_JWT_SECRET}"
        POSTGREST_JWT_EXP="${CONF_PGREST_JWT_EXP:-$POSTGREST_JWT_EXP}"
    fi
}
load_postgrest_config

# Helper: is PostgREST actually alive right now?
postgrest_is_running() {
    if [[ -n "$POSTGREST_PID" ]] && kill -0 "$POSTGREST_PID" 2>/dev/null; then
        return 0
    fi
    if pgrep -x postgrest &>/dev/null; then
        POSTGREST_PID=$(pgrep -x postgrest | head -1)
        return 0
    fi
    return 1
}

# Helper: base API URL
postgrest_base_url() {
    echo "http://${POSTGREST_HOST}:${POSTGREST_PORT}"
}

##################
# PostgREST Menu #
##################
postgrest_menu() {
    push_breadcrumb "PostgREST"
    while true; do
        local status_tag
        if postgrest_is_running; then
            status_tag="🟢 RUNNING (PID $POSTGREST_PID) — $(postgrest_base_url)"
        else
            status_tag="🔴 STOPPED"
        fi
        section_header "PostgREST API  [$status_tag]"

        choice="$(gum choose \
            "── Server Control ──" \
            "Start Server" \
            "Stop Server" \
            "Restart Server" \
            "Server Status & Health Check" \
            "── First-Time Setup ──" \
            "🚀 Full Setup Wizard  (roles + auth schema + JWT + config)" \
            "── Configuration ──" \
            "View Config File" \
            "Create / Regenerate Config" \
            "Edit Config File" \
            "── Auth & Users ──" \
            "List API Users" \
            "Create API User" \
            "Change User Password" \
            "Delete API User" \
            "Grant / Revoke User Role" \
            "Generate JWT Token" \
            "── Permissions ──" \
            "Show Role Permissions" \
            "Grant Table Access" \
            "Revoke Table Access" \
            "Sync Permissions (apply defaults)" \
            "── API Testing ──" \
            "List Exposed Endpoints" \
            "Test Endpoint (anonymous)" \
            "Test Endpoint (with JWT)" \
            "Run Custom API Query" \
            "── Logs & Diagnostics ──" \
            "View Live Logs (tail)" \
            "View Last 50 Log Lines" \
            "Clear Log File" \
            "Back")"

        case "$choice" in
            "── Server Control ──"|"── First-Time Setup ──"|"── Configuration ──"|"── Auth & Users ──"|"── Permissions ──"|"── API Testing ──"|"── Logs & Diagnostics ──")
                continue ;;

            "Start Server")                 postgrest_start ;;
            "Stop Server")                  postgrest_stop ;;
            "Restart Server")               postgrest_stop; sleep 1; postgrest_start ;;
            "Server Status & Health Check") postgrest_status ;;

            "🚀 Full Setup Wizard  (roles + auth schema + JWT + config)")
                postgrest_full_wizard ;;

            "View Config File")
                if [[ -f "$POSTGREST_CONF" ]]; then
                    echo "=== $POSTGREST_CONF ==="
                    cat "$POSTGREST_CONF"
                else
                    warn "No config file at: $POSTGREST_CONF"
                    info "Run the Full Setup Wizard to generate one."
                fi ;;

            "Create / Regenerate Config")   postgrest_create_config ;;
            "Edit Config File")
                [[ ! -f "$POSTGREST_CONF" ]] && postgrest_create_config
                "${EDITOR:-nano}" "$POSTGREST_CONF"
                success "Config saved. Restart PostgREST to apply." ;;

            "List API Users")               postgrest_list_users ;;
            "Create API User")              postgrest_create_user ;;
            "Change User Password")         postgrest_change_password ;;
            "Delete API User")              postgrest_delete_user ;;
            "Grant / Revoke User Role")     postgrest_manage_role ;;
            "Generate JWT Token")           postgrest_generate_jwt ;;

            "Show Role Permissions")        postgrest_show_permissions ;;
            "Grant Table Access")           postgrest_grant_table ;;
            "Revoke Table Access")          postgrest_revoke_table ;;
            "Sync Permissions (apply defaults)") postgrest_sync_permissions ;;

            "List Exposed Endpoints")       postgrest_list_endpoints ;;
            "Test Endpoint (anonymous)")    postgrest_test_endpoint "" ;;
            "Test Endpoint (with JWT)")     postgrest_test_endpoint "jwt" ;;
            "Run Custom API Query")         postgrest_custom_query ;;

            "View Live Logs (tail)")
                if [[ -f "$POSTGREST_LOG" ]]; then
                    info "Ctrl+C to stop…"
                    tail -f "$POSTGREST_LOG"
                else
                    warn "No log file at: $POSTGREST_LOG"
                fi ;;

            "View Last 50 Log Lines")
                if [[ -f "$POSTGREST_LOG" ]]; then
                    tail -n 50 "$POSTGREST_LOG"
                else
                    warn "No log file at: $POSTGREST_LOG"
                fi ;;

            "Clear Log File")
                if [[ -f "$POSTGREST_LOG" ]] && confirm "Clear the PostgREST log file?"; then
                    > "$POSTGREST_LOG"
                    success "Log cleared."
                fi ;;

            "Back" | *)
                pop_breadcrumb
                CURRENT_MENU="main"
                return ;;
        esac
        pause
    done
}

# ─────────────────────────────────────────────────────
# postgrest_start / stop
# ─────────────────────────────────────────────────────
postgrest_start() {
    if postgrest_is_running; then
        info "PostgREST is already running (PID $POSTGREST_PID)."
        return
    fi
    if [[ ! -f "$POSTGREST_CONF" ]]; then
        warn "No config file at: $POSTGREST_CONF"
        confirm "Generate a default config now?" && postgrest_create_config || return
    fi
    if ! command -v postgrest &>/dev/null; then
        error "PostgREST binary not found in PATH."
        info  "Install: https://postgrest.org/en/stable/install.html"
        return
    fi
    info "Starting PostgREST → log: $POSTGREST_LOG"
    postgrest "$POSTGREST_CONF" >> "$POSTGREST_LOG" 2>&1 &
    POSTGREST_PID=$!
    for i in 1 2 3; do
        sleep 1
        if ! kill -0 "$POSTGREST_PID" 2>/dev/null; then
            error "PostgREST exited immediately. Check the log:"
            tail -n 20 "$POSTGREST_LOG" 2>/dev/null
            POSTGREST_PID=""
            return
        fi
    done
    success "PostgREST started (PID $POSTGREST_PID) → $(postgrest_base_url)"
}

postgrest_stop() {
    local pid
    pid="${POSTGREST_PID:-$(pgrep -x postgrest 2>/dev/null | head -1)}"
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        kill "$pid"
        success "PostgREST stopped (PID $pid)."
        POSTGREST_PID=""
    else
        info "No running PostgREST process found."
    fi
}

postgrest_status() {
    echo
    postgrest_is_running && success "Process:  RUNNING  (PID $POSTGREST_PID)" \
                         || warn    "Process:  STOPPED"
    command -v postgrest &>/dev/null \
        && info "Binary:   $(postgrest --version 2>/dev/null | head -1)" \
        || warn "Binary:   not found in PATH"
    [[ -f "$POSTGREST_CONF" ]] \
        && info "Config:   $POSTGREST_CONF ($(wc -l < "$POSTGREST_CONF") lines)" \
        || warn "Config:   not found"
    [[ -f "$POSTGREST_LOG" ]] \
        && info "Log:      $POSTGREST_LOG ($(wc -l < "$POSTGREST_LOG") lines)"

    local base; base=$(postgrest_base_url)
    info "Endpoint: $base"
    if command -v curl &>/dev/null && postgrest_is_running; then
        local http_code
        http_code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "$base/" 2>/dev/null || echo "000")
        if   [[ "$http_code" == "200" ]]; then success "HTTP $http_code — API responding ✅"
        elif [[ "$http_code" == "000" ]]; then warn    "No response — connection refused / timeout"
        else                                   info    "HTTP $http_code — server responded"
        fi
    fi
    echo
    # Show DB roles
    echo "── PostgREST DB Roles ──────────────────────────────"
    psql -X --username="$PSQL_USER" --dbname="$PSQL_DB" -c "
        SELECT rolname AS role,
               CASE WHEN rolcanlogin THEN 'yes' ELSE 'no' END AS can_login,
               CASE WHEN rolinherit  THEN 'yes' ELSE 'no' END AS inherit
        FROM pg_roles
        WHERE rolname IN ('anon','authenticator','app_user','api_admin')
        ORDER BY rolname;" 2>/dev/null | cat || true
    echo
    # Show auth users if table exists
    local has_users
    has_users=$(psql -X --username="$PSQL_USER" --dbname="$PSQL_DB" --tuples-only -c \
        "SELECT 1 FROM information_schema.tables WHERE table_schema='auth' AND table_name='users';" \
        2>/dev/null | tr -d ' ')
    if [[ "$has_users" == "1" ]]; then
        echo "── auth.users ──────────────────────────────────────"
        psql -X --username="$PSQL_USER" --dbname="$PSQL_DB" -c \
            "SELECT id, email, role, created_at FROM auth.users ORDER BY created_at;" \
            2>/dev/null | cat || true
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# postgrest_full_wizard
# One-stop shop: DB roles → auth schema → users table → login fn → JWT → config
# ─────────────────────────────────────────────────────────────────────────────
postgrest_full_wizard() {
    section_header "🚀 PostgREST Full Setup Wizard"

    gum style --foreground 212 --bold \
        "This wizard sets up EVERYTHING needed for a secure PostgREST API:" \
        "  1. DB roles  (anon, authenticator, app_user, api_admin)" \
        "  2. auth schema with users table + bcrypt password hashing" \
        "  3. login() function that issues JWT tokens" \
        "  4. me() function so users can query their own profile" \
        "  5. Row-level security (users see only their own data where applicable)" \
        "  6. Broad anon SELECT on all public tables" \
        "  7. app_user INSERT/UPDATE/DELETE on stock data tables" \
        "  8. api_admin full access" \
        "  9. postgrest.conf with JWT secret baked in" \
        " 10. (Optional) first admin user"
    echo

    if ! confirm "Proceed with full setup on database '$PSQL_DB'?"; then return; fi

    # ── Generate JWT secret ────────────────────────────────────────────────────
    info "Generating a secure 32-byte JWT secret…"
    local jwt_secret
    if command -v openssl &>/dev/null; then
        jwt_secret=$(openssl rand -hex 32)
    elif command -v python3 &>/dev/null; then
        jwt_secret=$(python3 -c "import secrets; print(secrets.token_hex(32))")
    else
        jwt_secret=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 64)
    fi
    info "JWT secret generated (64 hex chars)."

    # Allow override
    local custom_secret
    custom_secret=$(gum input --placeholder "Paste your own JWT secret, or press Enter to use the generated one" --width 70)
    [[ -n "$custom_secret" ]] && jwt_secret="$custom_secret"

    local auth_password
    auth_password=$(gum input --placeholder "Password for 'authenticator' DB role (Enter = random)" --width 50 --password)
    if [[ -z "$auth_password" ]]; then
        auth_password=$(openssl rand -base64 24 2>/dev/null || echo "S3cur3Auth$(date +%s)")
    fi

    # ── 1. DB roles ────────────────────────────────────────────────────────────
    info "Step 1/5: Creating DB roles…"
    psql -X --username="$PSQL_USER" --dbname="$PSQL_DB" << SQL
-- ── Anon: unauthenticated API read access ─────────────────────────────────
DO \$\$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='anon') THEN
    CREATE ROLE anon NOLOGIN NOINHERIT;
    RAISE NOTICE 'Role anon created.';
  END IF;
END \$\$;

-- ── authenticator: PostgREST connects as this role ────────────────────────
DO \$\$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='authenticator') THEN
    CREATE ROLE authenticator NOINHERIT LOGIN PASSWORD '${auth_password}';
    RAISE NOTICE 'Role authenticator created.';
  ELSE
    ALTER ROLE authenticator PASSWORD '${auth_password}';
    RAISE NOTICE 'Role authenticator password updated.';
  END IF;
END \$\$;

-- ── app_user: authenticated Flutter / mobile user (JWT role claim) ────────
DO \$\$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='app_user') THEN
    CREATE ROLE app_user NOLOGIN NOINHERIT;
    RAISE NOTICE 'Role app_user created.';
  END IF;
END \$\$;

-- ── api_admin: full access, for trusted admin JWT tokens ─────────────────
DO \$\$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='api_admin') THEN
    CREATE ROLE api_admin NOLOGIN NOINHERIT;
    RAISE NOTICE 'Role api_admin created.';
  END IF;
END \$\$;

-- Grant role hierarchy to authenticator
GRANT anon      TO authenticator;
GRANT app_user  TO authenticator;
GRANT api_admin TO authenticator;
SQL
    success "DB roles ready."

    # ── 2. Auth schema + users table ──────────────────────────────────────────
    info "Step 2/5: Creating auth schema, users table, and login function…"
    psql -X --username="$PSQL_USER" --dbname="$PSQL_DB" << 'SQL'
-- ── Enable pgcrypto for bcrypt password hashing ───────────────────────────
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ── Auth schema (separate from public so it doesn't appear in PostgREST API)
CREATE SCHEMA IF NOT EXISTS auth;

-- ── Users table ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS auth.users (
    id            SERIAL        PRIMARY KEY,
    email         TEXT          NOT NULL UNIQUE,
    password_hash TEXT          NOT NULL,
    role          TEXT          NOT NULL DEFAULT 'app_user'
                                CHECK (role IN ('app_user','api_admin')),
    display_name  TEXT,
    created_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    last_login    TIMESTAMPTZ,
    active        BOOLEAN       NOT NULL DEFAULT TRUE
);

-- Index for fast email lookups (login)
CREATE INDEX IF NOT EXISTS idx_auth_users_email ON auth.users(email);

-- ── Active sessions / refresh tokens ────────────────────────────────────
CREATE TABLE IF NOT EXISTS auth.sessions (
    session_id    TEXT          PRIMARY KEY DEFAULT gen_random_uuid()::text,
    user_id       INTEGER       NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    expires_at    TIMESTAMPTZ   NOT NULL DEFAULT NOW() + INTERVAL '7 days',
    revoked       BOOLEAN       NOT NULL DEFAULT FALSE,
    user_agent    TEXT,
    ip_address    TEXT
);

-- Auto-expire old sessions (requires pg_cron in production; here we just clean on login)
CREATE OR REPLACE FUNCTION auth.cleanup_expired_sessions()
RETURNS void LANGUAGE sql AS $$
    DELETE FROM auth.sessions WHERE expires_at < NOW();
$$;

-- ── JWT helper types ────────────────────────────────────────────────────
CREATE TYPE IF NOT EXISTS auth.jwt_token AS (
    token TEXT
);
SQL

    # ── 3. Login function (uses pgjwt or manual JSON trick) ───────────────────
    info "Step 3/5: Creating login() and auth helper functions…"
    psql -X --username="$PSQL_USER" --dbname="$PSQL_DB" << SQL
-- ─────────────────────────────────────────────────────────────────────────────
--  auth.login(email, password) → returns a JWT token
--  Called via PostgREST:  POST /rpc/login  {"email":"…","password":"…"}
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION auth.login(email TEXT, password TEXT)
RETURNS auth.jwt_token
LANGUAGE plpgsql SECURITY DEFINER AS
\$\$
DECLARE
    v_user        auth.users;
    v_exp         BIGINT;
    v_payload     TEXT;
    v_header      TEXT;
    v_sig         TEXT;
    v_jwt         TEXT;
    v_secret      TEXT := '${jwt_secret}';
BEGIN
    -- 1. Fetch user
    SELECT * INTO v_user FROM auth.users WHERE auth.users.email = login.email AND active = TRUE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invalid credentials' USING ERRCODE = 'invalid_password';
    END IF;

    -- 2. Verify password
    IF v_user.password_hash != crypt(password, v_user.password_hash) THEN
        RAISE EXCEPTION 'Invalid credentials' USING ERRCODE = 'invalid_password';
    END IF;

    -- 3. Update last_login
    UPDATE auth.users SET last_login = NOW() WHERE id = v_user.id;

    -- 4. Build JWT manually (Header.Payload.Signature using HS256 via pgcrypto)
    --    PostgREST validates this with its jwt-secret setting.
    v_exp := EXTRACT(EPOCH FROM NOW())::BIGINT + 3600;  -- 1 hour

    v_header  := encode(convert_to('{"alg":"HS256","typ":"JWT"}', 'UTF8'), 'base64');
    -- Remove base64 padding and use URL-safe chars
    v_header  := replace(replace(rtrim(v_header, '='), '+', '-'), '/', '_');

    v_payload := encode(convert_to(
        json_build_object(
            'role',  v_user.role,
            'email', v_user.email,
            'sub',   v_user.id::text,
            'exp',   v_exp,
            'iat',   EXTRACT(EPOCH FROM NOW())::BIGINT
        )::text,
        'UTF8'
    ), 'base64');
    v_payload := replace(replace(rtrim(v_payload, '='), '+', '-'), '/', '_');

    -- HMAC-SHA256 signature
    v_sig := encode(
        hmac(v_header || '.' || v_payload, v_secret, 'sha256'),
        'base64'
    );
    v_sig := replace(replace(rtrim(v_sig, '='), '+', '-'), '/', '_');

    v_jwt := v_header || '.' || v_payload || '.' || v_sig;

    RETURN (v_jwt)::auth.jwt_token;
END;
\$\$;

-- ── register: create a new user account ──────────────────────────────────────
--  POST /rpc/register  {"email":"…","password":"…","display_name":"…"}
CREATE OR REPLACE FUNCTION auth.register(
    email        TEXT,
    password     TEXT,
    display_name TEXT DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER AS
\$\$
DECLARE
    v_id INTEGER;
BEGIN
    -- Validate password strength (minimum 8 chars)
    IF LENGTH(password) < 8 THEN
        RAISE EXCEPTION 'Password must be at least 8 characters.' USING ERRCODE = 'check_violation';
    END IF;

    INSERT INTO auth.users (email, password_hash, role, display_name)
    VALUES (email, crypt(password, gen_salt('bf', 10)), 'app_user', display_name)
    RETURNING id INTO v_id;

    RETURN json_build_object('success', TRUE, 'user_id', v_id, 'email', email);
EXCEPTION
    WHEN unique_violation THEN
        RAISE EXCEPTION 'Email already registered.' USING ERRCODE = 'unique_violation';
END;
\$\$;

-- ── me: returns the current user's profile (for authenticated requests) ───────
--  GET /rpc/me  (with Authorization: Bearer <jwt>)
CREATE OR REPLACE FUNCTION auth.me()
RETURNS JSON
LANGUAGE sql STABLE SECURITY DEFINER AS
\$\$
    SELECT json_build_object(
        'id',           id,
        'email',        email,
        'role',         role,
        'display_name', display_name,
        'created_at',   created_at,
        'last_login',   last_login
    )
    FROM auth.users
    WHERE id = (current_setting('request.jwt.claims', TRUE)::JSON->>'sub')::INTEGER;
\$\$;

-- ── change_password: authenticated users can change their own password ────────
CREATE OR REPLACE FUNCTION auth.change_password(old_password TEXT, new_password TEXT)
RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER AS
\$\$
DECLARE
    v_user auth.users;
    v_uid  INTEGER;
BEGIN
    v_uid := (current_setting('request.jwt.claims', TRUE)::JSON->>'sub')::INTEGER;
    SELECT * INTO v_user FROM auth.users WHERE id = v_uid AND active = TRUE;

    IF v_user.password_hash != crypt(old_password, v_user.password_hash) THEN
        RAISE EXCEPTION 'Incorrect current password.' USING ERRCODE = 'invalid_password';
    END IF;

    IF LENGTH(new_password) < 8 THEN
        RAISE EXCEPTION 'New password must be at least 8 characters.';
    END IF;

    UPDATE auth.users
    SET password_hash = crypt(new_password, gen_salt('bf', 10))
    WHERE id = v_uid;

    RETURN json_build_object('success', TRUE, 'message', 'Password changed successfully.');
END;
\$\$;
SQL
    success "Auth functions created."

    # ── 4. Expose functions to PostgREST ──────────────────────────────────────
    info "Step 4/5: Setting up permissions…"
    psql -X --username="$PSQL_USER" --dbname="$PSQL_DB" << SQL
-- ── Auth schema: anon can call login/register; app_user can call me/change_pw
GRANT USAGE ON SCHEMA auth TO anon, app_user, api_admin;

GRANT EXECUTE ON FUNCTION auth.login(TEXT, TEXT)          TO anon;
GRANT EXECUTE ON FUNCTION auth.register(TEXT, TEXT, TEXT) TO anon;
GRANT EXECUTE ON FUNCTION auth.me()                       TO app_user, api_admin;
GRANT EXECUTE ON FUNCTION auth.change_password(TEXT, TEXT) TO app_user, api_admin;

-- ── Public schema: anon gets SELECT on everything ─────────────────────────
GRANT USAGE ON SCHEMA public TO anon, app_user, api_admin;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO anon;

-- ── app_user: read/write on stock data tables ──────────────────────────────
GRANT SELECT, INSERT, UPDATE, DELETE ON
    newspaper_stock_quotes, monthly_stock_summary
    TO app_user;

-- Allow app_user to update their own market actions + use sequences
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO app_user;

-- ── api_admin: full DML on everything ─────────────────────────────────────
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO api_admin;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO api_admin;
GRANT SELECT, INSERT, UPDATE, DELETE ON auth.users TO api_admin;

-- ── Expose PostgREST-callable views ──────────────────────────────────────
-- (views inherit permissions from their base tables via SECURITY INVOKER)
GRANT SELECT ON latest_quotes TO anon, app_user, api_admin;
GRANT SELECT ON latest_quotes TO anon, app_user, api_admin;
SQL
    success "Permissions applied."

    # ── 5. Write postgrest.conf ────────────────────────────────────────────────
    info "Step 5/5: Writing postgrest.conf…"

    local db_port="${1:-5432}"
    cat > "$POSTGREST_CONF" << EOF
# PostgREST configuration — generated by YourStockForecast CLI
# $(date)
# ─────────────────────────────────────────────────────────────────
# SECURITY NOTE: This file contains your JWT secret and DB password.
# Do NOT commit this file to git. Add postgrest.conf to .gitignore.
# ─────────────────────────────────────────────────────────────────

# Database connection — PostgREST connects as 'authenticator'
# then switches role per-request (anon for public, app_user/api_admin for JWT)
db-uri             = "postgresql://authenticator:${auth_password}@localhost:5432/${PSQL_DB}"
db-schemas         = "public, auth"
db-anon-role       = "anon"

# Server
server-host        = "localhost"
server-port        = ${POSTGREST_PORT}

# JWT — must match the secret used in auth.login()
jwt-secret         = "${jwt_secret}"
jwt-aud            = "postgrest"

# Performance
db-max-rows        = 1000
db-pool            = 10
db-pool-timeout    = 10

# Reload schema cache when you run:  NOTIFY pgrst, 'reload schema';
server-timing-enabled = true

# For production VPS — change server-host to 0.0.0.0 and set up Nginx in front
# server-host       = "0.0.0.0"
EOF

    success "postgrest.conf written to: $POSTGREST_CONF"

    # Save JWT secret to app config
    sed -i "/^CONF_PGREST_JWT_SECRET=/d" "$CONFIG_FILE" 2>/dev/null || true
    echo "CONF_PGREST_JWT_SECRET=${jwt_secret}" >> "$CONFIG_FILE"
    POSTGREST_JWT_SECRET="$jwt_secret"

    echo
    gum style --bold --foreground 212 "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    gum style --foreground 76  "✅  Setup complete!"
    gum style --foreground 244 \
        "  Roles created:    anon, authenticator, app_user, api_admin" \
        "  Auth schema:      auth.users, auth.sessions" \
        "  API functions:    /rpc/login  /rpc/register  /rpc/me" \
        "  JWT secret:       ${jwt_secret:0:16}… (saved to .ysf_cli.conf)" \
        "  Authenticator pw: ${auth_password:0:6}… (saved to postgrest.conf)"
    gum style --bold --foreground 212 "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo
    info "Next steps:"
    info "  1. Start Server  (from this menu)"
    info "  2. Create first admin user  → Auth & Users → Create API User"
    info "  3. Test login:   curl -X POST http://localhost:${POSTGREST_PORT}/rpc/login \\"
    info "                     -H 'Content-Type: application/json' \\"
    info "                     -d '{\"email\":\"admin@example.com\",\"password\":\"yourpass\"}'"

    if confirm "Create your first admin user now?"; then
        postgrest_create_user "api_admin"
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# postgrest_create_config  (quick config regenerate without full wizard)
# ─────────────────────────────────────────────────────────────────────────────
postgrest_create_config() {
    info "Generating PostgREST config at: $POSTGREST_CONF"
    local db_host db_port schema anon_role jwt max_rows
    db_host=$(gum input   --placeholder "DB host"                  --value "localhost")
    db_port=$(gum input   --placeholder "DB port"                  --value "5432")
    schema=$(gum input    --placeholder "DB schema(s)"             --value "public, auth")
    anon_role=$(gum input --placeholder "Anon role"                --value "$POSTGREST_ANON_ROLE")
    jwt=$(gum input       --placeholder "JWT secret (required for auth)" --value "$POSTGREST_JWT_SECRET" --password)
    max_rows=$(gum input  --placeholder "Max rows per request"     --value "1000")

    cat > "$POSTGREST_CONF" << EOF
# PostgREST configuration — generated by YourStockForecast CLI
# $(date)
db-uri             = "postgresql://${POSTGREST_AUTH_ROLE}@${db_host}:${db_port}/${PSQL_DB}"
db-schemas         = "${schema}"
db-anon-role       = "${anon_role}"
server-host        = "${POSTGREST_HOST}"
server-port        = ${POSTGREST_PORT}
db-max-rows        = ${max_rows}
db-pool            = 10
$(if [[ -n "$jwt" ]]; then echo "jwt-secret         = \"${jwt}\""; else echo "# jwt-secret       = \"your-secret-here\""; fi)
server-timing-enabled = true
EOF
    success "Config written to: $POSTGREST_CONF"
    echo; cat "$POSTGREST_CONF"
}

# ─────────────────────────────────────────────────────────────────────────────
# User management functions
# ─────────────────────────────────────────────────────────────────────────────
postgrest_list_users() {
    local has_table
    has_table=$(psql -X --username="$PSQL_USER" --dbname="$PSQL_DB" --tuples-only -c \
        "SELECT 1 FROM information_schema.tables WHERE table_schema='auth' AND table_name='users';" \
        2>/dev/null | tr -d ' ')
    if [[ "$has_table" != "1" ]]; then
        warn "auth.users table not found. Run the Full Setup Wizard first."
        return
    fi
    echo
    psql -X --username="$PSQL_USER" --dbname="$PSQL_DB" -c \
        "SELECT id, email, role, display_name, active,
                to_char(created_at, 'YYYY-MM-DD') AS created,
                to_char(last_login, 'YYYY-MM-DD HH24:MI') AS last_login
         FROM auth.users ORDER BY created_at;" 2>/dev/null | cat
}

postgrest_create_user() {
    local default_role="${1:-app_user}"
    local email pass display_name role
    email=$(gum input        --placeholder "User email address" --width 50)
    [[ -z "$email" ]] && { warn "Email required."; return; }
    pass=$(gum input         --placeholder "Password (min 8 chars)" --width 40 --password)
    [[ ${#pass} -lt 8 ]] && { warn "Password must be at least 8 characters."; return; }
    display_name=$(gum input --placeholder "Display name (optional)" --width 40)
    role=$(gum choose "app_user" "api_admin")

    psql -X --username="$PSQL_USER" --dbname="$PSQL_DB" -c \
        "INSERT INTO auth.users (email, password_hash, role, display_name)
         VALUES ('${email}', crypt('${pass}', gen_salt('bf',10)), '${role}', '${display_name}')
         ON CONFLICT (email) DO NOTHING
         RETURNING id, email, role;" 2>/dev/null | cat
    success "User '${email}' created with role '${role}'."
    info "They can login via: POST /rpc/login  {\"email\":\"${email}\",\"password\":\"…\"}"
}

postgrest_change_password() {
    local email new_pass
    email=$(psql -X --username="$PSQL_USER" --dbname="$PSQL_DB" --tuples-only -c \
        "SELECT email FROM auth.users ORDER BY email;" 2>/dev/null | \
        grep -v '^\s*$' | gum filter --placeholder "Select user…")
    [[ -z "$email" ]] && return
    email=$(echo "$email" | xargs)
    new_pass=$(gum input --placeholder "New password (min 8 chars)" --width 40 --password)
    [[ ${#new_pass} -lt 8 ]] && { warn "Password too short."; return; }
    psql -X --username="$PSQL_USER" --dbname="$PSQL_DB" -c \
        "UPDATE auth.users SET password_hash = crypt('${new_pass}', gen_salt('bf',10))
         WHERE email = '${email}';" >/dev/null
    success "Password updated for '${email}'."
}

postgrest_delete_user() {
    local email
    email=$(psql -X --username="$PSQL_USER" --dbname="$PSQL_DB" --tuples-only -c \
        "SELECT email FROM auth.users ORDER BY email;" 2>/dev/null | \
        grep -v '^\s*$' | gum filter --placeholder "Select user to delete…")
    [[ -z "$email" ]] && return
    email=$(echo "$email" | xargs)
    warn "This will permanently delete user '${email}'."
    if confirm "Delete '${email}'?"; then
        psql -X --username="$PSQL_USER" --dbname="$PSQL_DB" -c \
            "DELETE FROM auth.users WHERE email = '${email}';" >/dev/null
        success "User '${email}' deleted."
    fi
}

postgrest_manage_role() {
    local email action role
    email=$(psql -X --username="$PSQL_USER" --dbname="$PSQL_DB" --tuples-only -c \
        "SELECT email FROM auth.users ORDER BY email;" 2>/dev/null | \
        grep -v '^\s*$' | gum filter --placeholder "Select user…")
    [[ -z "$email" ]] && return
    email=$(echo "$email" | xargs)
    role=$(gum choose "app_user" "api_admin")
    psql -X --username="$PSQL_USER" --dbname="$PSQL_DB" -c \
        "UPDATE auth.users SET role = '${role}' WHERE email = '${email}';" >/dev/null
    success "'${email}' is now '${role}'."
}

postgrest_generate_jwt() {
    if [[ -z "$POSTGREST_JWT_SECRET" ]]; then
        warn "JWT secret not configured. Run the Full Setup Wizard first."
        return
    fi
    local email
    email=$(psql -X --username="$PSQL_USER" --dbname="$PSQL_DB" --tuples-only -c \
        "SELECT email FROM auth.users ORDER BY email;" 2>/dev/null | \
        grep -v '^\s*$' | gum filter --placeholder "Select user to generate token for…")
    [[ -z "$email" ]] && return
    email=$(echo "$email" | xargs)

    info "Generating JWT for ${email} via PostgREST login function…"
    if postgrest_is_running; then
        local pass
        pass=$(gum input --placeholder "Password for ${email}" --password)
        local resp
        resp=$(curl -s -X POST "$(postgrest_base_url)/rpc/login" \
            -H "Content-Type: application/json" \
            -d "{\"email\":\"${email}\",\"password\":\"${pass}\"}" 2>/dev/null)
        echo
        if command -v jq &>/dev/null; then
            echo "$resp" | jq .
        else
            echo "$resp"
        fi
        local token
        token=$(echo "$resp" | grep -oP '"token":"[^"]+' | cut -d'"' -f4)
        if [[ -n "$token" ]]; then
            echo
            success "JWT Token:"
            echo "$token"
            echo
            info "Use in Flutter: Authorization: Bearer <token>"
            info "Test:  curl -H 'Authorization: Bearer ${token:0:30}…' $(postgrest_base_url)/latest_quotes"
        fi
    else
        warn "PostgREST is not running — start the server first to generate tokens via the API."
        info "Or use the login endpoint directly once started."
    fi
}

# ─────────────────────────────────────────────────────────────────────────────
# Permission management
# ─────────────────────────────────────────────────────────────────────────────
postgrest_show_permissions() {
    echo
    gum style --bold "── Table permissions per PostgREST role ────────────────────────"
    psql -X --username="$PSQL_USER" --dbname="$PSQL_DB" -c "
        SELECT
            grantee                          AS role,
            table_schema || '.' || table_name AS table,
            string_agg(privilege_type, ', ' ORDER BY privilege_type) AS privileges
        FROM information_schema.role_table_grants
        WHERE grantee IN ('anon','app_user','api_admin')
          AND table_schema IN ('public','auth')
        GROUP BY grantee, table_schema, table_name
        ORDER BY role, table;" 2>/dev/null | cat
    echo
    gum style --bold "── Function permissions ───────────────────────────────────────"
    psql -X --username="$PSQL_USER" --dbname="$PSQL_DB" -c "
        SELECT
            grantee             AS role,
            routine_schema      AS schema,
            routine_name        AS function,
            privilege_type
        FROM information_schema.role_routine_grants
        WHERE grantee IN ('anon','app_user','api_admin')
        ORDER BY role, schema, function;" 2>/dev/null | cat
}

postgrest_grant_table() {
    local tbl role privs
    tbl=$(psql -X --username="$PSQL_USER" --dbname="$PSQL_DB" --tuples-only -c \
        "SELECT table_name FROM information_schema.tables WHERE table_schema='public' ORDER BY table_name;" \
        2>/dev/null | grep -v '^\s*$' | gum filter --placeholder "Select table…")
    [[ -z "$tbl" ]] && return
    tbl=$(echo "$tbl" | xargs)
    role=$(gum choose "anon" "app_user" "api_admin")
    privs=$(gum choose "SELECT" "SELECT, INSERT, UPDATE, DELETE" "ALL")
    psql -X --username="$PSQL_USER" --dbname="$PSQL_DB" -c \
        "GRANT ${privs} ON ${tbl} TO ${role};" 2>/dev/null
    success "Granted ${privs} on ${tbl} to ${role}."
}

postgrest_revoke_table() {
    local tbl role
    tbl=$(psql -X --username="$PSQL_USER" --dbname="$PSQL_DB" --tuples-only -c \
        "SELECT table_name FROM information_schema.tables WHERE table_schema='public' ORDER BY table_name;" \
        2>/dev/null | grep -v '^\s*$' | gum filter --placeholder "Select table…")
    [[ -z "$tbl" ]] && return
    tbl=$(echo "$tbl" | xargs)
    role=$(gum choose "anon" "app_user" "api_admin")
    psql -X --username="$PSQL_USER" --dbname="$PSQL_DB" -c \
        "REVOKE ALL ON ${tbl} FROM ${role};" 2>/dev/null
    success "All privileges on ${tbl} revoked from ${role}."
}

postgrest_sync_permissions() {
    info "Re-applying default permissions to all public tables…"
    psql -X --username="$PSQL_USER" --dbname="$PSQL_DB" << 'SQL'
-- anon: SELECT on everything public
GRANT USAGE ON SCHEMA public TO anon, app_user, api_admin;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO anon;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO anon;

-- app_user: read/write on stock data tables
GRANT SELECT, INSERT, UPDATE, DELETE ON
    newspaper_stock_quotes, monthly_stock_summary
    TO app_user;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO app_user;

-- api_admin: everything
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO api_admin;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO api_admin;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO anon;
NOTIFY pgrst, 'reload schema';
SQL
    success "Permissions synced. PostgREST schema cache reloaded."
}

# ─────────────────────────────────────────────────────────────────────────────
# API testing
# ─────────────────────────────────────────────────────────────────────────────
postgrest_list_endpoints() {
    if ! postgrest_is_running; then warn "PostgREST not running."; return; fi
    local base; base=$(postgrest_base_url)
    info "Fetching OpenAPI spec from $base/ …"
    local response
    response=$(curl -s --max-time 5 -H "Accept: application/json" "$base/" 2>/dev/null)
    if [[ -z "$response" ]]; then error "No response from $base/"; return; fi
    if command -v jq &>/dev/null; then
        echo "=== Exposed Endpoints ==="
        echo "$response" | jq -r '.paths | to_entries[] | "  \(.key)  →  \(.value | keys | join(", "))"' 2>/dev/null
    else
        echo "$response"
    fi
}

postgrest_test_endpoint() {
    local use_jwt="${1:-}"
    if ! postgrest_is_running; then warn "PostgREST not running."; return; fi
    local base; base=$(postgrest_base_url)

    local table
    table=$(psql -X --username="$PSQL_USER" --dbname="$PSQL_DB" --tuples-only -c \
        "SELECT table_name FROM information_schema.tables WHERE table_schema='public'
         UNION SELECT routine_name FROM information_schema.routines WHERE routine_schema='auth'
         ORDER BY 1;" 2>/dev/null | grep -v '^\s*$' | gum filter --placeholder "Table or rpc/function…")
    [[ -z "$table" ]] && return
    table=$(echo "$table" | xargs)

    local method; method=$(gum choose "GET" "POST" "PATCH" "DELETE")
    local params=""
    if [[ "$method" == "GET" ]]; then
        info "Filter examples:  ?select=name,gold&order=gold.desc&limit=10"
        params=$(gum input --placeholder "Query string (blank = all rows)")
        [[ -n "$params" ]] && params="?${params}"
    fi

    local auth_header=""
    if [[ "$use_jwt" == "jwt" ]] || [[ -n "$POSTGREST_JWT_SECRET" ]]; then
        local token
        token=$(gum input --placeholder "JWT Bearer token (blank to skip)")
        [[ -n "$token" ]] && auth_header="-H \"Authorization: Bearer $token\""
    fi

    local body_flag=""
    if [[ "$method" == "POST" || "$method" == "PATCH" ]]; then
        local body; body=$(gum input --placeholder '{"key":"value"}')
        [[ -n "$body" ]] && body_flag="-d '${body}' -H 'Content-Type: application/json'"
    fi

    local url="${base}/${table}${params}"
    info "→ $method $url"
    echo
    eval curl -s -X "$method" \
        -H "Accept: application/json" \
        -H "Prefer: count=exact" \
        ${auth_header} ${body_flag} \
        --max-time 10 \
        "\"$url\"" | if command -v jq &>/dev/null; then jq .; else cat; fi
}

postgrest_custom_query() {
    if ! postgrest_is_running; then warn "PostgREST not running."; return; fi
    local base; base=$(postgrest_base_url)
    gum style --foreground 244 \
        "Base URL: $base" \
        "Examples:" \
        "  /latest_quotes?symbol=eq.AAPL" \
        "  /latest_quotes?select=symbol,current_stock_price&order=market_capitalization.desc&limit=20" \
        "  /rpc/login   (POST with JSON body)" \
        "  /newspaper_stock_quotes?quote_date=eq.1929-10-28&order=stock_name"
    echo
    local path; path=$(gum input --placeholder "/table?filter=value  or  /rpc/function_name")
    [[ -z "$path" ]] && return
    local token; token=$(gum input --placeholder "JWT token (blank for anonymous)")
    local auth_h=""
    [[ -n "$token" ]] && auth_h="-H \"Authorization: Bearer $token\""
    eval curl -s -X GET \
        -H "Accept: application/json" \
        ${auth_h} \
        --max-time 10 \
        "\"${base}${path}\"" | if command -v jq &>/dev/null; then jq .; else cat; fi
}


# ── §12 INSERT DATA MENU ──────────────────────────────────────────────────────
# ─────────────────────────────────────────────────────────────────────────────
# Embedded historical data: NYSE Oct 28 1929 (Black Monday)
# Source: The Evening Star, Washington D.C., Monday October 28 1929
# 781 companies, prices converted from fractional notation (57 1/2 → 57.5)
# company_name = full company name | stock_variant = share class (pf, A, B, etc.)
# ─────────────────────────────────────────────────────────────────────────────
_insert_oct28_1929_evening_star() {
    info "Loading 781 NYSE entries from The Evening Star, Oct 28 1929…"

    # Ensure the 1929 year partition exists before inserting
    psql -X --username="$PSQL_USER" --dbname="$PSQL_DB" -c "
        CREATE TABLE IF NOT EXISTS stock_quotes_1929
            PARTITION OF newspaper_stock_quotes
            FOR VALUES FROM ('1929-01-01') TO ('1930-01-01');
    " >/dev/null 2>&1 || true

    psql -X --username="$PSQL_USER" --dbname="$PSQL_DB" << 'ENDSQL'
INSERT INTO newspaper_stock_quotes
    (quote_date, company_name, stock_variant, year_high, year_low, dividend,
     sales_100s, daily_high, daily_low, daily_close, previous_close)
SELECT
    '1929-10-28'::date,
    v.company_name, v.stock_variant, v.year_high, v.year_low, v.dividend,
    v.sales_100s, v.daily_high, v.daily_low, v.daily_close, v.previous_close
FROM (VALUES
    (57.875, 38.125, 'Abitibi Power and Paper Company', '', NULL, 9, 48.5, 45, 45, 49),
    (88.625, 76, 'Abitibi Power and Paper Company', 'pf', 6, 2, 80, 80, 80, 80),
    (96, 84.25, 'Adams Express Company', 'pf', 5, 1, 88, 87.125, 88, 90),
    (35, 27.25, 'Adams-Millis Corporation', '', 2, 4, 27.625, 27.375, 27.375, 27.75),
    (104.5, 13, 'Advance-Rumely Company', '', NULL, 5, 15.25, 13, 13, 15.125),
    (119, 23, 'Advance-Rumely Company', 'pf', NULL, 3, 24.5, 23.875, 23.875, 23.875),
    (4.25, 1, 'Ahumada Lead Company', '', NULL, 1, 1.25, 1, 1.25, NULL),
    (223.5, 95.25, 'Air Reduction Company', '', '14%', 25, 189.25, 150, 194.75, NULL),
    (11.25, 2.75, 'Ajax Rubber Company', '', NULL, 9, 3.75, 2.25, 3, NULL),
    (10.25, 4.25, 'Alaska-Juneau Gold Mining Company', '', NULL, 17, 6.25, 6, 6.25, NULL),
    (25, 10.25, 'Albany Perforated Wrapping Paper Company', '', NULL, 1, 10.75, 10, 10.75, NULL),
    (56.75, 27.25, 'Alleghany Corporation', '', NULL, 151, 36, 30.25, 36.75, NULL),
    (118.75, 99.75, 'Alleghany Corporation', 'pf (5%)', '5%', 11, 105.25, 104, 105.75, NULL),
    (92, 80.75, 'Alleghany Corporation', 'pf (5%) x w', NULL, 13, 90, 89.25, 90.25, NULL),
    (254.25, 241, 'Allied Chemical and Dye Corporation', '', '6', 11, 275, 242, 281, NULL),
    (125, 120.25, 'Allied Chemical and Dye Corporation', 'pf', '7', 1, 122.75, 121.75, 121.75, NULL),
    (75.75, 44, 'Allis-Chalmers Manufacturing Company', '(n)', '2', 44, 56.75, 48, 55.75, NULL),
    (30.75, 29, 'Alpha Portland Cement Company', '', 'S', 2, 30.75, 30.25, 30.75, NULL),
    (42.75, 22.75, 'Amerada Corporation', '', '12', 3, 24.75, 23, 24.75, NULL),
    (23, 7.25, 'American Agricultural Chemical Company', '', NULL, 17, 8.75, 7.75, 8, NULL),
    (73.75, 31, 'American Agricultural Chemical Company', 'pf', NULL, 9, 33.75, 31.75, 32.25, NULL),
    (157, 110, 'American Banknote Company', '', '5', 3, 129, 111, 126, NULL),
    (20.75, 11, 'American Beet Sugar Company', '', NULL, 5, 11.75, 11.75, 11.75, NULL),
    (76.75, 40, 'American Bosch Magneto Corporation', '', NULL, 15, 42, 40, 41.75, NULL),
    (62, 45, 'American Brake Shoe Company', '', '2.40', 6, 62.25, 60.25, 62.25, NULL),
    (34.25, 13.75, 'American Brown Boveri Electric Corporation', '', NULL, 25, 14.75, 11, 14.25, NULL),
    (184.75, 107.75, 'American Can Company', '', '4', 93, 150, 136.25, 153.75, NULL),
    (142, 136.75, 'American Can Company', 'pf', '7', 2, 141.75, 141.75, 142, NULL),
    (106.25, 80, 'American Car and Foundry Company', '', '6', 6, 89.75, 82, 89, NULL),
    (120, 110.75, 'American Car and Foundry Company', 'pf', '7', 1, 113.75, 113.75, 113, NULL),
    (81.75, 45, 'American Chicle Company', '', '2', 5, 48, 44, 51, NULL),
    (65, 36, 'American Commercial Alcohol Company', '', '1.60', 13, 36, 36, 36.75, NULL),
    (47.25, 23.75, 'American Encaustic Tiling Company', '', '2', 6, 25, 25, 24.75, NULL),
    (98.75, 50, 'American European Sec', '', NULL, 6, 53, 50, 54.75, NULL),
    (199.75, 75.75, 'American & Foreign Power Company', '', NULL, 104, 96, 79.75, 98.75, NULL),
    (108.25, 104, 'American & Foreign Power Company', 'pf', '7', 1, 107, 106.75, 106.75, NULL),
    (103, 88, 'American & Foreign Power Company', '2d pf', NULL, 6, 93.75, 93.75, 90, NULL),
    (42, 24.75, 'American-Hawaiian Steamship Company', '', '1', 8, 25.75, 23, 25.75, NULL),
    (10, 6, 'American Hide and Leather Company', '', NULL, 2, 6.75, 6.75, 6.75, NULL),
    (62.75, 30.25, 'American Hide and Leather Company', 'pf', NULL, 2, 38, 37, 35.75, NULL),
    (85.75, 49.25, 'American Home Products Corporation', '', '8.60', 21, 56, 50, 65.75, NULL),
    (64, 38, 'American Ice Company', '', '3', 7, 40, 37.75, 40, NULL),
    (96.75, 62.75, 'American International Industries Incorporated', '', '22', 63, 60, 65, 61, NULL),
    (8.75, 3.75, 'American LaFrance and Foamite Corporation', '', NULL, 10, 3.75, 3.75, 3.75, NULL),
    (136, 100, 'American Locomotive Company', '', '8', 2, 108, 103.75, 109, NULL),
    (119.75, 112, 'American Locomotive Company', 'pf', '7', 1, 115.25, 115.25, 115.25, NULL),
    (279.75, 147.75, 'American Machine and Foundry', '', '6', 2, 216, 201, 225, NULL),
    (81.75, 60, 'American Metal Company', '', '1', 8, 60.75, 54.75, 60.75, NULL),
    (135, 113.75, 'American Metal Company', 'pf', '6', 2, 125, 125, 126.75, NULL),
    (17.25, 3.75, 'American Piano Company', '', NULL, 8, 5, 4.75, 5, NULL),
    (175.75, 81.75, 'American Power and Light Company', '', '11', 27, 97.75, 82.75, 100, NULL),
    (104, 98.75, 'American Power and Light Company', 'pf', '6', 1, 100.75, 100, 100, NULL),
    (80, 70, 'American Power and Light Company', 'pf A', '5', 2, 75, 75, 75.75, NULL),
    (84.25, 78, 'American Power and Light Company', 'pf Ast', '5', 1, 82, 82, 82, NULL),
    (65.75, 34.75, 'American Radiator Company and Standard Sanitary Manufacturing Company', '', '1%', 863, 38, 30.75, 38.75, NULL),
    (64.75, 20.75, 'American Republics Corporation', '', NULL, 15, 29.75, 22.75, 28, NULL),
    (144.75, 90.75, 'American Rolling Mill Company', '', '2', 23, 105.75, 97, 108.25, NULL),
    (74.75, 60, 'American Safety Razor Company', '', '6', 20, 61, 56, 64.75, NULL),
    (41.75, 30, 'American Seating Company', '', '2', 4, 31, 30, 30, NULL),
    (7, 2, 'American Ship and Commerce Corporation', '', NULL, 4, 2, 2, 2, NULL),
    (130.75, 95.25, 'American Smelting and Refining Company', '', '4', 70, 96.75, 91.75, 97.25, NULL),
    (138, 130, 'American Smelting and Refining Company', 'pf', '7', 1, 135.75, 135.75, 135.75, NULL),
    (49, 89.75, 'American Snuff Company', '', '3', 6, 42.75, 41, 44, NULL),
    (79.25, 46.75, 'American Steel Foundries', '', '5', 19, 52.75, 48, 52.25, NULL),
    (86, 64.75, 'American Stores Company', '', '12 %', 4, 65, 64, 65, NULL),
    (94.75, 71.75, 'American Sugar Refining Company', '', '6', 3, 72.25, 71.75, 72.75, NULL),
    (111, 102.75, 'American Sugar Refining Company', 'pf', '7', 1, 105, 105, 105, NULL),
    (60, 34, 'American Sumatra Tobacco Corporation', '', '3', 4, 34.25, 33.25, 37.75, NULL),
    (32.25, 17, 'Am Tel and Ca', '', '6', 1, 23.25, 23.75, 22.75, NULL),
    (210, 193.75, 'American Telephone and Telegraph Company', '', '9', 113, 263, 240, 266, NULL),
    (232.75, 160, 'American Tobacco Company', '', '5', 10, 215, 200, 217, NULL),
    (235, 160, 'American Tobacco Company', 'B', '5', 27, 214, 197.25, 216.25, NULL),
    (121.75, 115, 'American Tobacco Company', 'pf', '6', 1, 118, 118, 117, NULL),
    (181, 136.75, 'American Type Founders', '', '6', 2, 145, 145, 147.75, NULL),
    (199, 67.75, 'American Water Works Company', '', '1', 84, 105.75, 83, 104, NULL),
    (27.25, 5.25, 'American Woolen Company', '', NULL, 2, 11.75, 11, 11.25, NULL),
    (68.75, 30.75, 'American Woolen Company', '1929 pf', NULL, 4, 30.75, 28.75, 30.75, NULL),
    (16.75, 7.75, 'American Writ Paper', 'ctfs(?)', NULL, 4, 8.75, 7.75, 8, NULL),
    (49.75, 10.75, 'American Zinc, Lead and Smelting Company', '', NULL, 10, 14.75, 11, 14.75, NULL),
    (111.75, 79.75, 'American Zinc, Lead and Smelting Company', 'pf', '6', 1, 80, 80, 80.75, NULL),
    (140, 92, 'Anaconda Copper Mining Company', '', '7', 396, 102.75, 95.75, 102.75, NULL),
    (89.25, 62.25, 'Anaconda Copper Mining Company', 'W A C', '3', 4, 69.75, 69.75, 69.75, NULL),
    (80, 43, 'Anchor Cap and Closure Corporation', '', '2.40', 8, 58.75, 52.75, 57.75, NULL),
    (68.75, 42, 'Andes Copper Mining Company', '', '3', 4, 44.25, 42.75, 44.75, NULL),
    (49.75, 29, 'Archer-Daniels-Midland Company', '', '2', 5, 34.75, 31.75, 35, NULL),
    (95, 82, 'Armour Del', 'pf', '7', 5, 83.75, 83, 83, NULL),
    (18.75, 7.75, 'Armour Ill', 'A', 'A', 43, 8.75, 7.75, 8.75, NULL),
    (10.75, 3.75, 'Armour Ill', 'B', 'B', 49, 4.75, 4.75, 4.75, NULL),
    (86, 67.75, 'Armour Ill', 'pf', '7', 1, 68, 68, 68.75, NULL),
    (40.25, 12, 'Arnold Constable & Company', '', NULL, 8, 16.25, 15.75, 17.75, NULL),
    (68.25, 45, 'Asso Appl Ind', '', '6', 16, 45, 43, 46, NULL),
    (70.75, 41.75, 'Associated Dry Goods Corporation', '', '2 3/4', 10, 41.75, 38.75, 42.75, NULL),
    (298.75, 195.25, 'Atchison, Topeka and Santa Fe Railway', '', '10', 7, 261.75, 254.75, 262.75, NULL),
    (104.75, 99, 'Atchison, Topeka and Santa Fe Railway', 'pf', '6', 1, 103.75, 103, 103, NULL),
    (209.75, 169, 'The Atlantic Coast Line Railroad', '', '10', 3, 180, 177, 180, NULL),
    (86.25, 32.75, 'Atlantic, Gulf and West Indies Steamship Lines', '', NULL, 2, 79, 70.75, 76, NULL),
    (77.25, 40, 'Atlantic Petroleum', '', '2', 152, 49.75, 42.25, 49.75, NULL),
    (140, 90, 'Atlas Powder Company', '', '4', 20, 117, 100.75, 118.75, NULL),
    (14, 190, 'Auburn Automobile Company', '', '4', 6, 220, 175, 215, NULL),
    (11.75, 6.25, 'Austin, Nichols and Company', '', NULL, 9, 5.75, 5.75, 5.75, NULL),
    (35.75, 22.25, 'Autosales Corporation', '', NULL, 12, 27.75, 27, 27.75, NULL),
    (45.75, 36.75, 'Autosales Corporation', 'pf', '3', 1, 40, 39, 40, NULL),
    (50, 38.25, 'Autostrop Safety Razor Company', '', '3', 4, 39.75, 39, 39.75, NULL),
    (20, 9, 'Aviation Corporation Del', '', NULL, 62, 10.75, 9, 10.75, NULL),
    (66.75, 15, 'Baldwin Loco', '', 'new', 84, 32.75, 25, 32.25, NULL),
    (145.75, 115.75, 'Baltimore A Ohio', '', '7', 40, 127.25, 120, 128.75, NULL),
    (90.75, 60, 'Bang A Aroos', '', '3 1/4', 4, 72, 67.75, 72, NULL),
    (29.25, 4.75, 'Barnet Leather', '', NULL, 1, 4.75, 4.75, 4.75, NULL),
    (49.75, 20.25, 'Barnsdall', '', '2 3/4', 25, 27.75, 25.75, 27.75, NULL),
    (113.75, 80, 'Bayuk Cigar', '', '2', 1, 75, 75, 80, NULL),
    (32.75, 20, 'Beacon Oil', '', NULL, 3, 23, 22.75, 23.75, NULL),
    (131, 93.75, 'Beatrice Cream', '', '4', 19, 106.75, 100, 107.75, NULL),
    (101, 70.75, 'Beech-Nut Pack', '', '3', 3, 77, 74, 75.25, NULL),
    (17.75, 9, 'Beld ing-Hem in way', '', NULL, 2, 9.75, 9, 9.75, NULL),
    (84.75, 78.75, 'Belg Nat R ys', 'pf', '6.49', 2, 78.75, 78.75, 78.75, NULL),
    (104.75, 40, 'Bendix Aviation', '', '2', 39, 46, 42.75, 48.75, NULL),
    (60.25, 48.75, 'Best A Company', '', NULL, 8, 48.75, 42.75, 50, NULL),
    (140.75, 82.75, 'Bethlehem Steel', '', 'C', 161, 102.75, 97.75, 103.75, NULL),
    (128, 116.75, 'Bethlehem St', 'pf', '7', 7, 127.25, 126.75, 125.875, NULL),
    (61.25, 40.75, 'Bloom ingdale Bros', '', NULL, 3, 40.75, 38.75, 42, NULL),
    (136.75, 50, 'Bohn Alumn A B', '', '6', 10, 69.75, 66, 70, NULL),
    (11.75, 3.75, 'Booth Fisheries', '', NULL, 13, 4.25, 4, 4.75, NULL),
    (100.75, 73.75, 'Borden CO', '', '3', 31, 76.75, 72, 77, NULL),
    (86.75, 35, 'Borg Warner', '', '4', 11, 47.75, 44.75, 46.25, NULL),
    (145, 85, 'Boston A Maine', '', NULL, 2, 127, 125, 133, NULL),
    (15.75, 6, 'Botany Con M', '', 'A', 1, 16.75, 6.75, 7, NULL),
    (63.75, 13.75, 'Briggs Mfg', '', NULL, 73, 17.75, 15.75, 18, NULL),
    (43.75, 32, 'Briggs A Stratton', '', '3', 3, 34, 32.75, 33.75, NULL),
    (73.75, 20.75, 'Brock way M T', '', '3', 5, 23.25, 23, 23.75, NULL),
    (81.75, 67.75, 'Bklyn-Manhat', '', '4', 69, 60.75, 55.75, 61, NULL),
    (92.75, 79, 'Bklyn-Man', 'pf', '6', 4, 83, 82.75, 82.25, NULL),
    (12.25, 9, 'Brooklyn A Queens', '', NULL, 2, 9, 8, 9.75, NULL),
    (248.75, 160, 'Bklyn Union Gas', '', '5', 19, 154, 146, 160, NULL),
    (51.75, 36, 'Brown Shoe', '', '2%', 2, 45, 44, 46, NULL),
    (66.25, 29.75, 'Bruns-Balk-Col', '', '3', 15, 32, 31, 31, NULL),
    (44.25, 10, 'Bruns Ter A Ry', '', '5', 1, 11.75, 10, 12, NULL),
    (42.75, 22, 'Bucyrus Erie', '', '1', 9, 25.25, 23.75, 24, NULL),
    (60, 35.75, 'Bucyrus', 'cv pf', '2%', 13, 38, 36.75, 38, NULL),
    (22.75, 10, 'Budd (E G)', '', '1%', 19, 16, 13.75, 16, NULL),
    (54.75, 40.75, 'Bullard Co', '', '12', 5, 44.75, 40.75, 47, NULL),
    (127, 94, 'Burns Bros', 'A', '8', 1, 98.25, 98.75, 99, NULL),
    (39, 22.75, 'Burns Bros', 'B', NULL, 1, 30, 29.75, 31, NULL),
    (96.25, 59, 'Bur Add Mach', '', '11.80', 150, 65, 59.75, 66, NULL),
    (89.75, 42.75, 'Bush Term', '', 'g2', 3, 45, 43.75, 49.75, NULL),
    (9.75, 3, 'Butte Copper A Zinc', '', NULL, 73, 3, 3, 3.75, NULL),
    (12.75, 6, 'Butte A Superior', '', '2', 1, 6, 5.75, 6.75, NULL),
    (192.75, 76, 'Byers (A M)', '', NULL, 10, 107, 80, 110.875, NULL),
    (47.75, 31.25, 'By-Prod Coke', '', '1', 29, 34.75, 28.75, 35, NULL),
    (84.75, 70.75, 'Calif Packing', '', '4', 8, 74.75, 71.75, 75.75, NULL),
    (4, 1.75, 'Callahan Zinc A L', '', NULL, 8, 1.75, 1.75, 1.75, NULL),
    (136.25, 105, 'Calumet A Ariz', '', '10', 4, 111.75, 106.75, 112.75, NULL),
    (61.75, 28, 'Calumet A Hecla', '', '4', 46, 38.75, 36.75, 37.75, NULL),
    (49.75, 25, 'Campbell Wyant', '', '2', 11, 32.75, 31, 31.75, NULL),
    (98.75, 60, 'Canada Dry G A', '', '5', 16, 76, 71.75, 75.75, NULL),
    (266.75, 200, 'Canadian Pac', '', '10', 27, 211.75, 203.75, 212, NULL),
    (48.75, 35, 'Cannon Mills', '', '2.80', 4, 38.75, 36, 37, NULL),
    (65.75, 44.75, 'Cap Adminstratn', 'A', NULL, 5, 50.25, 46, 48.75, NULL),
    (467, 210, 'Case (J I)', '', '6', 5, 215, 200, 225, NULL),
    (42.25, 14, 'Cavanagh-Dobbs', '', NULL, 4, 14, 14, 15, NULL),
    (79.75, 45, 'Celotex', '', '8', 6, 46, 44, 46, NULL),
    (48.75, 30, 'Cent Aguirre As', '', '1 1/4', 3, 30, 30, 30, NULL),
    (69.75, 40.75, 'Cent Alloy Steel', '', '2', 10, 50, 47.75, 49.25, NULL),
    (60, 300, 'Cent RR of NJ', '', '112', 1, 295, 295, 305, NULL),
    (20.75, 4.75, 'Century Rib Mills', '', NULL, 3, 4.75, 4.75, 5, NULL),
    (120, 80, 'Cerro de Pasco', '', '6', 18, 84, 80.75, 82.75, NULL),
    (32, 16.75, 'Certain-teed Prod', '', NULL, 18, 18.75, 17.75, 19, NULL),
    (81.25, 47.75, 'Certain-teed', 'pf', NULL, 3, 65, 65, 60.75, NULL),
    (80.75, 46, 'Checker Cab Mfg Co', '', NULL, 46, 65.25, 46, 46, NULL),
    (27, 7.75, 'City Ice A F', '', '3.60', 6, 61, 60, 61, NULL),
    (27, 7.75, 'City Stores', '', '1', 116, 10.75, 10.75, 10.75, NULL),
    (72.75, 41, 'Cluett Peabody', '', '6', 3, 41.75, 41.75, 45, NULL),
    (154.75, 120.75, 'Coca-Cola', '', '4', 23, 140.75, 136.75, 144.75, NULL),
    (60, 46.75, 'Coca Cola', 'A', '3', 3, 47.25, 47, 47.75, NULL),
    (72.75, 20, 'Collins A Alkman', '', NULL, 16, 23.75, 21.75, 23, NULL),
    (78.75, 33, 'Colo Fuel A 1r0n', '', NULL, 30, 47.75, 41.75, 48.75, NULL),
    (135, 101, 'Colo A South', '', '3', 2, 103.75, 100.75, 105, NULL),
    (140, 53.75, 'Col Gas A El', '', '2', 154, 91.75, 76.75, 92.75, NULL),
    (109, 103.25, 'Col Gas A El', 'pf A', '8', 5, 107, 107, 107, NULL),
    (88.75, 27.75, 'Columb Graph', '', '87c', 200, 35.75, 28, 35.75, NULL),
    (344, 121.25, 'Columbian Carb', '', '6', 7, 205, 186, 220, NULL),
    (62.75, 30, 'Com Credit', '', '2', 20, 37.25, 30.75, 36.75, NULL),
    (51.75, 42.75, 'Comm Credit', 'A', '8', 2, 43.75, 38.75, 43, NULL),
    (79, 46.75, 'Comm Invest Trust', '', NULL, 44, 59.25, 50, 59.75, NULL),
    (63, 36.75, 'Comm Solvents', '', 'n', 76, 44, 38, 44.75, NULL),
    (24.75, 13, 'Comm A So', '', 'b6%stk', 335, 18.75, 15.75, 18.75, NULL),
    (35.75, 11, 'Congoleum-Nalrn', '', NULL, 37, 18, 16.75, 18, NULL),
    (92.75, 50, 'Cong Cigars', '', '6%', 6, 58.75, 55, 58.75, NULL),
    (96.25, 45, 'Consol Cigar', '', '7', 12, 51, 49, 50, NULL),
    (26.75, 12, 'Consol Film', '', '2', 9, 17.75, 15.75, 17.75, NULL),
    (30.25, 18.75, 'Consol Film', 'pf', '6', 11, 21, 20.75, 20.75, NULL),
    (183.75, 96.75, 'Consol Gas', '', '8', 226, 116, 102, 117.25, NULL),
    (100.75, 96.75, 'Consol Gas', 'of', '5', 13, 99, 99, 99.75, NULL),
    (70, 50, 'Consol RR Cub', 'pf', '8', 14, 68.75, 68, 69, NULL),
    (6.75, 1.75, 'Consol Textile', '', NULL, 32, 2, 2, 1.75, NULL),
    (23.75, 12, 'Container Corp', 'A', NULL, 7, 16.75, 16.75, 18, NULL),
    (11.75, 6, 'Container Corp', 'B', NULL, 3, 6.75, 6.75, 6.75, NULL),
    (90, 47.75, 'Conti Baking', 'A', NULL, 6, 63, 49.75, 55.75, NULL),
    (16.75, 6.25, 'Conti Baking', 'B', NULL, 21, 8.75, 7.75, 8.75, NULL),
    (100, 88.75, 'Conti Baking', 'pf', '8', 6, 92.75, 92, 92.75, NULL),
    (63.75, 60, 'Conti Can', '', '2 3/4', 66, 68.75, 61.75, 68.75, NULL),
    (110.75, 65, 'Conti Insurance', '', '2', 20, 81, 73, 81.75, NULL),
    (28.75, 6.25, 'Conti Motors', '', '80c', 70, 10.75, 9.75, 9.75, NULL),
    (47.75, 25.75, 'Conti Oil of Del', '', NULL, 65, 31.25, 29, 32.75, NULL),
    (126.75, 82, 'Corn Prod', '', '3 3/4', 30, 111, 96, 114.75, NULL),
    (82.75, 32, 'Coty Inc', '', 'g2', 40, 38.75, 33.75, 36.75, NULL),
    (57.75, 21, 'Crex Carpet', '', NULL, 1, 20, 20, 21, NULL),
    (125, 49, 'Crossley Radio', '', '1', 20, 60, 40.75, 50.875, NULL),
    (79, 42.25, 'Crown Cork A Seal', '', NULL, 5, 55, 53, 54.75, NULL),
    (25.75, 18.75, 'Crown Zellerbach', '', '1', 1, 20.75, 20.75, 20, NULL),
    (121.75, 85, 'Crucible Steel', '', '6', 7, 91.25, 88, 93, NULL),
    (5.75, 0.5, 'Cuba Cane Sugar', '', NULL, 4, 1.25, 0.5, 0.5, NULL),
    (18.75, 2.75, 'Cuba Cane Sugar', 'pf', NULL, 8, 2.75, 2.75, 3, NULL),
    (24.75, 11.75, 'Cuba Co', '', NULL, 4, 13.75, 12.25, 13.75, NULL),
    (17, 10.75, 'Cuban-Amer Sugar', '', NULL, 25, 10.75, 10.75, 11, NULL),
    (67.75, 43, 'Cudahy Packing', '', '4', 9, 44.75, 44, 44, NULL),
    (132, 116, 'Curtis Pub', '', '16%', 29, 118, 117, 119, NULL),
    (30.75, 11.25, 'Curtiss Wright Corp', '', NULL, 212, 14.25, 13.75, 14.75, NULL),
    (37.75, 15, 'Curt Wright Corp', 'A', NULL, 66, 23.75, 20.75, 23.75, NULL),
    (121.25, 58.75, 'Cutler-Ham', '', '3%', 7, 95.25, 95, 95.75, NULL),
    (126.25, 63, 'Cuyamel Fruit', '', NULL, 5, 110, 104.75, 117.25, NULL),
    (69.75, 38.75, 'Davison Chem', '', NULL, 6, 40, 38, 42, NULL),
    (226, 181, 'Delaware A Hud', '', '9', 40, 185, 175, 186, NULL),
    (169.75, 120.75, 'Del Lack A W', '', '17', 32, 146, 141, 146.75, NULL),
    (77.75, 55.75, 'Denv A R G W', 'pf', NULL, 7, 68, 58, 62, NULL),
    (64.75, 38, 'Devoe A R ry', 'A', '13', 3, 38, 38, 39.75, NULL),
    (11.75, 8.75, 'Dome Mines', '', '1', 9, 8.75, 8.75, 8.75, NULL),
    (64.75, 23, 'Dominion Strs', '', '0.26', 16, 29.75, 25, 29, NULL),
    (126.75, 95.75, 'Drug Corpn', '', '4', 22, 101, 96.75, 102, NULL),
    (92, 34, 'Dunhill Inter', '', '4', 8, 39, 37, 41, NULL),
    (4.75, 2.75, 'Duluth SS A Atl', '', NULL, 3, 2.25, 2.75, 2.75, NULL),
    (7.75, 3.75, 'Duluth SS A Atl', 'pf', NULL, 13, 8.75, 3.75, 3.75, NULL),
    (150, NULL, 'Du Pont de N', '', '4%', 101, 165, 154.75, 166.25, NULL),
    (119.75, 112, 'Dupont d N', 'deb', '6', 6, 115, 115, 115, NULL),
    (11.75, 3, 'Durham Hosiery', '', NULL, 13, 3.75, 3.75, 4, NULL),
    (39.75, 27.75, 'East Roll Mill', '', '1%', 10, 27, 27, 27.75, NULL),
    (264.75, 168, 'Eastman Kodak', '', '18', 24, 220.75, 196.75, 223, NULL),
    (76.75, 34, 'Eaton Axle A S', '', '3', 13, 39, 35, 38.25, NULL),
    (39.75, 17.75, 'Eitingon-Sch', '', '2%', 6, 17.75, 16.25, 18, NULL),
    (112.25, 73.75, 'Eitingon', 'pf', '6%', 3, 72.75, 69.75, 73.75, NULL),
    (174, 102.25, 'Elec Auto Lite', '', '4', 72, 106, 97.75, 108.75, NULL),
    (18.75, 5.75, 'Electric Boat', '', NULL, 4, 6, 5.75, 6.75, NULL),
    (86.75, 40, 'El Pwr A Lt', '', '1', 115, 48, 38.75, 49.75, NULL),
    (109.75, 103, 'El Pwr A Lt', 'pf', '7', 2, 107.75, 107.75, 106.75, NULL),
    (109.25, 77, 'Elec Stor Bat', '', '5', 20, 92.75, 88, 92, NULL),
    (22.25, 5, 'Emerson-Brnt', 'A', NULL, 8, 6, 6, 6, NULL),
    (83.75, 57.75, 'Endicott-John', '', '6', 1, 60, 60, 60, NULL),
    (124.75, 108.75, 'Endicott-John', 'pf', '7', 1, 109.5, 109.75, 108.75, NULL),
    (79.75, 47, 'Eng Pub Sery', '', '1', 31, 53, 46.75, 53.75, NULL),
    (93.75, 60, 'Erie R R', '', NULL, 148, 65, 57.75, 66.75, NULL),
    (66.75, 57, 'Erie R R', 'Ist pf', '4', 8, 63.75, 63, 64, NULL),
    (41, 31.25, 'Equitable 81 dg', '', '2%', 8, 37.75, 37.75, 38, NULL),
    (54, 44.25, 'Eureka Vac Cl', '', '4', 1, 45, 40.75, 44.75, NULL),
    (73.75, 35.75, 'Evans Auto L', '', '2%', 7, 36, 35, 36, NULL),
    (64.75, 40.75, 'Fairbanks Morse', '', '3', 3, 42.25, 41.75, 42.75, NULL),
    (72.75, 47, 'Fash Pk Assoc', '', '2%', 1, 46, 43, 47, NULL),
    (102, 97, 'Fed M A S', 'pf', '7', 1, 96, 96, 97, NULL),
    (22.75, 9.75, 'Fed Motor Tr', '', '80c', 79, 9.25, 9.75, 9.25, NULL),
    (56.75, 42, 'Fed Watr Ser', 'A', '2.40', 8, 44.75, 42.75, 45, NULL),
    (123, 84, 'Fid Phen F Ins', '', '2', 10, 94, 83.75, 94.75, NULL),
    (98.75, 57.75, 'Filene’s Sons', '', NULL, 1, 59, 59, 57.75, NULL),
    (76.25, 66.75, 'F ilenes', '', 'ctfs', 1, 55, 55, 66.75, NULL),
    (90, 62, 'First Nat Stores', '', '1%', 45, 75, 66.75, 71, NULL),
    (20.75, 4.75, 'Fisk Rubber', '', NULL, 38, 6.75, 5.75, 7, NULL),
    (54, 46, 'Florsheim Shoe', 'A', NULL, 1, 48, 46, 48.75, NULL),
    (82.75, 52, 'Follansbee Bros', '', '3', 5, 55, 54, 56, NULL),
    (95, 50, 'Foster Wheeler', '', '1', 8, 63, 50, 57.75, NULL),
    (105.75, 70, 'Fox Film', 'A', '4', 75, 81, 70.75, 81, NULL),
    (54.25, 33, 'Freeport-Texas', '', '4', 8, 40, 37.75, 39.75, NULL),
    (69.75, 28, 'Foundation Co', '', NULL, 2, 32, 32, 33, NULL),
    (107.25, 99, 'Fuller pr', 'pf', '8.61', 1, 100.75, 100.75, 103, NULL),
    (33.75, 7.75, 'Gabriel Snub', 'A', NULL, 12, 10, 8.75, 10.75, NULL),
    (83.75, 70, 'Gamewell Co', '', '4', 4, 74, 70, 77, NULL),
    (25, 5, 'Gardner Motor', '', NULL, 19, 6.75, 5.75, 6.75, NULL),
    (123.75, 81, 'Gen Am Tnk Car', '', '4', 26, 105.75, 101, 106.75, NULL),
    (94.75, 59.75, 'Gen Asphalt', '', NULL, 14, 64.75, 60, 64.75, NULL),
    (69.75, 36, 'Gen Bronze', '', '2', 9, 38, 36.75, 36, NULL),
    (61, 36, 'Gen Cable', '', NULL, 13, 43.75, 41.75, 43.75, NULL),
    (120.75, 81, 'Gen Cable', 'A', '4', 3, 92, 89.75, 92.75, NULL),
    (74, 69.75, 'Gen Cigar', '', '4', 1, 60, 58.75, 59.75, NULL),
    (403, 219, 'Gen Electric', '', '10', 390, 290.75, 251, 297.75, NULL),
    (11.75, 11, 'Gen Elec', 'spec', '60c', 8, 11.75, 11.75, 11.75, NULL),
    (81.75, 60, 'Gen''l Food Corpn', '', '1', 86, 64.75, 50, 64.75, NULL),
    (112, 70, 'Gen Gas A El', 'A', 'e1%', 22, 87.75, 83.75, 88, NULL),
    (89.75, 62, 'Gen Mills', '', '3 1/2', 6, 62.75, 62, 63, NULL),
    (91.75, 49, 'Gen Motors', '', '13.30', 1266, 53.75, 48.75, 54.75, NULL),
    (126.25, 121, 'Gen Motors', 'pf', '7', 7, 121.75, 116.75, 121.75, NULL),
    (41, 25, 'Gen Outd Ad', 'vtc', '2', 9, 27, 26, 26, NULL),
    (52, 43, 'Gen Outd Adv', 'A', '4', 3, 48, 45, 47, NULL),
    (98, 41.75, 'Gen Public Serv', '', '1', 15, 48, 39, 48, NULL),
    (126.75, 88.75, 'Gen Ry Signal', '', '5', 16, 102.75, 96, 101, NULL),
    (88.75, 68, 'Gen Refrac', '', '6', 18, 74.75, 70.25, 75, NULL),
    (143, 101, 'Gillette Saf Raz', '', 'cs', 268, 124.75, 112, 124.75, NULL),
    (48.75, 19, 'Gimbel Brothers', '', NULL, 3, 25, 25, 25, NULL),
    (94, 76.75, 'Gimbel Bros', 'pf', '7', 1, 81, 81, 82, NULL),
    (64.75, 36.75, 'Glidden Co', '', 'm1', 42, 45.75, 39, 46.75, NULL),
    (66, 16, 'Gobel (Adolf)', '', NULL, 22, 17.75, 16.75, 17.75, NULL),
    (82, 45, 'Gold Dust', '', '2%', 213, 61, 43.75, 52, NULL),
    (120, 105, 'Gold Dust', 'pf', '6', 8, 106, 106, 106, NULL),
    (105.75, 60, 'Goodrich B F', '', '4', 34, 61.75, 50, 61.75, NULL),
    (154, 75.75, 'Goodyear Tire', '', '5', 77, 84.75, 79.75, 83.75, NULL),
    (115.75, 105.75, 'Goodrich', 'pf', '7', 2, 106, 106, 107, NULL),
    (104.25, 98, 'Goodyear', '1st pf', '7', 72, 99, 99, 99, NULL),
    (60, 28.75, 'Gotham Silk H', '', '2%', 4, 30, 27.75, 30, NULL),
    (14, 7, 'Gould Coupler', '', NULL, 1, 8.75, 8.25, 8.75, NULL),
    (54, 12.75, 'Graham-Paige', '', NULL, 25, 13.75, 12, 11.75, NULL),
    (49.75, 9, 'Graham-Paige', 'ct', NULL, 3, 13.75, 12, 11.75, NULL),
    (102.75, 60.75, 'Granby Copper', '', '5', 16, 72.75, 68, 70, NULL),
    (96.75, 66.75, 'Grand Stores', '', '1', 5, 65, 63, 67, NULL),
    (32.75, 14.75, 'Grand Union', '', NULL, 4, 17.75, 16.75, 17.75, NULL),
    (54.75, 37, 'Grand Union', 'pf', '1', 2, 39.75, 39.25, 39.75, NULL),
    (63.75, 43.75, 'Granite City Stl', '', '4', 5, 61.75, 47, 51.25, NULL),
    (144.75, 114.75, 'Grant W T', '', '1', 33, 119, 56, 59, NULL),
    (200.75, 136.25, 'Greene Can Cop', '', '8', 1, 155, 155, 173, NULL),
    (128.75, 101, 'Grt North', 'pf', '5', 27, 105.75, 100.75, 106.75, NULL),
    (122.75, 100, 'Grt North', 'pf ct', '6', 65, 105.75, 103, 105.25, NULL),
    (39.75, 19, 'Grt Nor Ore', '', 'a1%', 18, 26.75, 24.75, 26.75, NULL),
    (44, 32.75, 'Grt West Sug', '', '2.80', 35, 35.25, 34, 35.75, NULL),
    (70, 30, 'Grigsby Grunow', '', '2', 79, 40.75, 34.75, 40, NULL),
    (59.75, 28, 'Gulf Mo A North', '', NULL, 3, 36, 35, 36, NULL),
    (103, 90.25, 'Gulf Mo A N', 'pf', '6', 4, 93.75, 93.25, 93.5, NULL),
    (79, 65.75, 'Gulf Sta Steel', '', '4', 4, 64, 62, 64, NULL),
    (66.75, 20, 'Hahn Dept Stores', '', NULL, 75, 20.75, 18.75, 20, NULL),
    (115, 86.75, 'Hahn Dept S', 'pf', '8%', 8, 87, 86.75, 87, NULL),
    (41.75, 16.75, 'Hartman B', '', '1.20', 17, 18, 16.75, 19.25, NULL),
    (68.75, 10.75, 'Hayes Body', 'b B% stk', NULL, 8, 14.75, 13, 14.5, NULL),
    (37, 29.75, 'Hercules Mot', '', '1.80', 2, 30.75, 30.75, 33, NULL),
    (143.25, 64, 'Hershey Chocolate', '', NULL, 10, 130, 119, 126.75, NULL),
    (143.25, 80, 'Hershey Choc', 'pf', '4', 9, 130, 120, 129, NULL),
    (33, 15, 'Hoo(R) A Co', '', NULL, 1, 24, 24, 25, NULL),
    (51, 29.75, 'Holland Furn', '', 'e2%', 10, 34, 31.75, 30, NULL),
    (24.75, 13.75, 'Hollander A Son', '', NULL, 1, 15, 15, 14.25, NULL),
    (93, 72, 'Homestake Min', '', '7', 2, 84, 82.75, 84, NULL),
    (62.75, 25, 'Houd Hersh', 'B', '1%', 42, 27.75, 22.25, 27.25, NULL),
    (52.25, 45, 'Household Fin', 'pf', '13.10', 1, 49.25, 49.25, 49.875, NULL),
    (79.75, 60, 'Household Prd', '', '14', 22, 60, 59.75, 60.75, NULL),
    (109, 60, 'Houston Oil', '', NULL, 16, 65, 52.75, 66.75, NULL),
    (82, 50, 'Howe Sound', '', '4%', 24, 50.75, 49, 50, NULL),
    (68.75, 34.75, 'Hud A Man Ry', '', '3.50', 25, 54.75, 49.75, 53, NULL),
    (93.75, 60.25, 'Hudson Motor', '', '6', 8, 63.75, 60, 63, NULL),
    (82, 28, 'Hupp Motor', '', 'f2', 308, 27.75, 25.75, 28, NULL),
    (153.75, 129.75, 'Illinois Central', '', '7', 7, 133.25, 132, 133, NULL),
    (39.75, 25.75, 'Independ Oil A G', '', '2', 15, 27.75, 26, 27.75, NULL),
    (32.75, 5, 'Indian Motor Cycle', '', NULL, 12, 6.75, 5.75, 6.75, NULL),
    (63, 23.25, 'Indian Refining', '', NULL, 92, 27.75, 19.75, 27, NULL),
    (63, 23.25, 'Indian Refining', 'ct', NULL, 39, 25.25, 19, 25, NULL),
    (135, 75, 'Industrial Rayon', '', NULL, 3, 86, 81, 86, NULL),
    (223, 120, 'Ingersoll Rand', '', NULL, 4, 179.75, 173.75, 179.75, NULL),
    (113, 78.75, 'Inland Steel', '', '3%', 3, 92, 90, 91.75, NULL),
    (66.75, 22, 'Inspiration', '', '4', 17, 36.75, 33.75, 36.75, NULL),
    (68.75, 15, 'Interboro Rap Tran', '', NULL, 33, 24.75, 23.75, 26, NULL),
    (14.25, 7, 'Intercontinental Rub', '', NULL, 5, 7, 6.75, 7.75, NULL),
    (38.25, 24.25, 'Intertype', '', '1 3/4', 1, 30, 30, 30, NULL),
    (72.75, 38, 'Int Hydro El', 'A', 'e2', 9, 57.75, 48.75, 56.75, NULL),
    (103, 70, 'Int Comb Eng', 'pf', '7', 4, 70, 70, 70, NULL),
    (59.75, 40, 'Int Hydro El', 'A', 'e2', 0, 44, 44, 44, NULL),
    (142, 92, 'Int Harv', '', '2%', 73, 101.75, 87, 101.75, NULL),
    (102.75, 63, 'Int Match', 'pf', '3.20', 32, 71, 65.75, 71.75, NULL),
    (39.25, 26.25, 'Int Mer Marine', 'otfs', NULL, 3, 33.75, 31, 34, NULL),
    (72.75, 40, 'Int Nickel of Can', '', '1', 306, 45.75, 40.25, 45, NULL),
    (44, 25, 'Int Pap A P A', '', '2.40', 6, 34.75, 34, 35, NULL),
    (33.25, 14.75, 'Int Pap A Pwr', 'B', NULL, 13, 25, 24, 22.75, NULL),
    (26.75, 10.75, 'Int Pap A Pwr', 'C', NULL, 89, 20.75, 17, 20, NULL),
    (68.75, 43.75, 'Int Print Ink', '', '2%', 3, 62, 57.25, 62, NULL),
    (59.75, 40.25, 'Int l Rys Cen', 'A', NULL, 1, 33.75, 33.75, 40.875, NULL),
    (77.75, 65, 'Int Shoe', '', '2%', 1, 66.25, 65, 69.75, NULL),
    (159.25, 118, 'Int Silver', '', NULL, 1, 137, 137, 138, NULL),
    (149.75, 78, 'Int Tel A Teleg', '', '2', 626, 100, 88, 103, NULL),
    (93.75, 40.75, 'Interstate Dept St', '', '2', 13, 40.25, 39, 43.25, NULL),
    (72.75, 38, 'Int Hydro El', 'A', 'e2', 9, 57.75, 48.75, 56.75, NULL),
    (142, 92, 'Int Harv', '', '2', 73, 101.75, 87, 101.75, NULL),
    (102.75, 63, 'Int Match', 'pf', '3.20', 32, 71, 65.75, 71.75, NULL),
    (39.25, 26.25, 'Int Mer Mar', 'otfs', NULL, 3, 33.75, 31, 34, NULL),
    (72.75, 40, 'Int Nickl of Can', '', NULL, 306, 45.75, 40.75, 45, NULL),
    (44, 25, 'Int Pap', '', '2.4o', 6, 34.75, 34, 35, NULL),
    (33, 14, 'Int Pa pr&Po', 'A', '2.4O', 13, 25, 24, 20.75, NULL),
    (26, 10, 'Int Pa pr&Po', 'B', NULL, 89, 20.75, 17, 15, NULL),
    (92.75, 92.75, 'Int Paper', 'pf', '7', 3, 92.75, 92.75, 92.75, NULL),
    (60, 60, 'Int Prtg Ink', '', '2%', 3, 60, 60, 60, NULL),
    (55.75, 55.75, 'Int Rys Cen Am', '', NULL, 1, 55.75, 55, 55, NULL),
    (76.75, 76.75, 'Int Ry CA', 'pf', '6', 0, 76.75, 76.75, 76.75, NULL),
    (75, 75, 'Int l Salt', '', 's', 6, 75, 75, 75, NULL),
    (144, 144, 'Int Silver', '', NULL, 1, 144, 144, 144, NULL),
    (224, 224, 'Int Tel & Tel', '', '6', 6, 224, 224, 223, NULL),
    (82, 82, 'Interstate D S', '', NULL, 3, 82, 82, 81.75, NULL),
    (30.25, 30.75, 'Intertype', '', 'tl 3/4', 1, 30, 30, 30.75, NULL),
    (56, 56, 'Island Creek', '', '4', 1, 56, 56, 55, NULL),
    (157.75, 158.75, 'Jewel Tea', '', 't5', 3, 157.75, 158.75, 158.75, NULL),
    (125, 125, 'Jewel Tea', 'pf', '7', 1, 125, 125, 125, NULL),
    (232.875, 238, 'Johns-Manv', '', '3', 3, 232, 238, 238, NULL),
    (120.875, 120.875, 'Johns-Man', 'pf', '7', 1, 120.875, 120.25, 120.875, NULL),
    (121.875, 121.875, 'Jones & Lau', '', '7', 1, 121.875, 121.875, 121, NULL),
    (13, 13, 'Jordan Motor', '', NULL, 1, 13, 13.875, 13, NULL),
    (108.25, 69, 'Kan City Sou', '', '5', 18, 83.875, 78, 83.875, NULL),
    (37.875, 24.875, 'Kaufmann DS', '', '1 1/2', 3, 25.875, 25.875, 25.875, NULL),
    (58.875, 45, 'Kayser J', '', '5', 6, 45, 44.875, 45, NULL),
    (138, 94.875, 'Keith-Albee', '', NULL, 3, 92, 85, 96.875, NULL),
    (24, 5, 'Kelly-Spring', '', NULL, 82, 6.875, 6, 6.875, NULL),
    (88.875, 30, 'Kelsey Hayes', '', '2', 2, 32, 30, 31.875, NULL),
    (19.875, 9.25, 'Kelvinator Corp', '', NULL, 13, 10.875, 9.875, 10, NULL),
    (104.25, 67, 'Kennecott', '', '6', 283, 76.25, 72.25, 77, NULL),
    (67.75, 45.75, 'Kimberly Clrk', '', '2 1/2', 1, 50, 50, 50, NULL),
    (78.75, 5.875, 'Kolster Radio', '', NULL, 72, 12.875, 11, 12.875, NULL),
    (76.875, 32.875, 'Kraft Ph Ch', '', '1 1/4', 76, 64.25, 58, 63.875, NULL),
    (105, 95, 'Kraft Ph Ch', 'pf', '6 1/2', 2, 105.875, 105.875, 105, NULL),
    (57.875, 38, 'Kresge S S', '', '1.60', 22, 41.875, 40, 41, NULL),
    (23, 12.75, 'Kresge Dept Stores', '', NULL, 2, 15.875, 15.875, 16.875, NULL),
    (114, 81.25, 'Kress (S H) Co', '', 'nl', 2, 81, 80, 81.875, NULL),
    (46.75, 30.875, 'Kreuger A Toll', '', 'd.34', 125, 32.25, 31.75, 33.875, NULL),
    (122.875, 60, 'Kroger Gr A Bak', '', 'cl', 141, 69, 60.75, 69.875, NULL),
    (38.875, 25, 'Lago Oil A Trans', '', NULL, 1, 27, 27, 29.875, NULL),
    (157.75, 105.75, 'Lambert', '', '5', 33, 115.75, 110.75, 115.75, NULL),
    (26, 8, 'Lee Rubber & Tire', '', NULL, 17, 8.75, 8, 8.75, NULL),
    (65, 35, 'Leh Port Cmt', '', '2 1/4', 2, 35, 35, 35, NULL),
    (32, 19, 'Lehigh Valley Coal', '', NULL, 16, 23.25, 22, 23.875, NULL),
    (44.75, 34.25, 'Leh Val Coal', 'pf', '3', 2, 40, 39, 40, NULL),
    (102.25, 75, 'Lehigh Valley', '', '3 1/2', 2, 77.75, 76.75, 75, NULL),
    (68.75, 35.75, 'Lehn A Fink', '', '3', 2, 38.875, 38, 39.75, NULL),
    (106, 81.25, 'Liggett A My', '', '16', 5, 96, 95.75, 99, NULL),
    (106.25, 81.75, 'Liggett A My', 'B', '16', 32, 98.75, 93.75, 97.75, NULL),
    (57.75, 37, 'Lima Locomotive', '', NULL, 7, 42, 39.75, 41.75, NULL),
    (61, 45, 'Link Belt', '', '2.60', 1, 46.75, 46, 46.75, NULL),
    (113.75, 58, 'Liq Carbonic', '', '14 1/4', 11, 64, 60, 63.25, NULL),
    (84.75, 48.75, 'Loew''s Inc', '', '3', 10, 52.75, 49.25, 55, NULL),
    (110.75, 87, 'Loew’s Inc', 'pf', '6 1/4', 1, 87, 87, 87, NULL),
    (11.75, 4.75, 'Loft Inc', '', NULL, 38, 5.25, 5, 6, NULL),
    (88.75, 53.75, 'Loose-Wiles', '', '2.80', 27, 64.75, 58, 65.75, NULL),
    (31.75, 18, 'Lorillard (P) Co', '', NULL, 45, 23, 21.75, 23, NULL),
    (99.75, 84.75, 'Lorillard (P)', 'pf', '1', 1, 96.75, 96.75, 97.75, NULL),
    (18, 10, 'Louisiana Oil', '', NULL, 23, 10.75, 10.75, 10.75, NULL),
    (72.75, 35.25, 'Lou U A El', 'A', '1%', 73, 42, 37, 41.75, NULL),
    (154.75, 137, 'Lou & Nash', '', '7', 1, 139, 139, 140, NULL),
    (108.25, 60, 'Ludlum Steel', '', '5', 13, 60, 49, 62.25, NULL),
    (118, 98.75, 'Ludlum Stl', 'pf', '6%', 1, 99, 99, 99, NULL),
    (46, 33, 'Mac A A Forb', '', '2.55', 1, 32, 32, 34.75, NULL),
    (82.25, 60, 'McKeesport T P', '', '4', 13, 60.75, 59, 60, NULL),
    (69, 35, 'Mc Kesson A Rob', '', '2', 14, 36, 35, 37, NULL),
    (63, 46, 'Mc Kes A Rb', 'pf', '3%', 5, 50.75, 49.75, 50, NULL),
    (59, 37, 'Mc Lellan Strs', '', '26c', 4, 41.75, 38.75, 40, NULL),
    (114.75, 83.75, 'Mack Trucks', '', '6', 24, 87.75, 80.75, 89.75, NULL),
    (255.75, 148, 'Macy (R H) A Co', '', 'ctt', 22, 181, 165, 185, NULL),
    (24, 14.75, 'Madison Sq G', '', '1 1/4', 1, 15.75, 15, 15.25, NULL),
    (82.25, 60, 'Magma Copper', '', '5', 7, 65.75, 58, 67.75, NULL),
    (39, 12, 'Mallinson A Co', '', NULL, 1, 12, 12, 14, NULL),
    (50.25, 31, 'Manati Sugar', 'pf', NULL, 1, 32.75, 32.75, 33, NULL),
    (38.75, 22, 'Mandel Brothers', '', NULL, 1, 24, 24, 24, NULL),
    (37.75, 23.75, 'Man Elec Supply', '', NULL, 1, 23.75, 23, 23.75, NULL),
    (67.75, 31.75, 'Man Elev mod', '', 'd6', 3, 36, 33, 35.25, NULL),
    (35.75, 25.75, 'Man Shirt', '', '2', 3, 25.75, 25.75, 26.75, NULL),
    (18.75, 11.75, 'Maracaibo Oil Exp', '', NULL, 5, 11.75, 11.75, 12, NULL),
    (39.25, 20, 'Market St Ry', 'pr pf', NULL, 1, 21.75, 21, 21.75, NULL),
    (89.25, 61, 'Marlin Rock', '', '1 3/4', 10, 58.75, 57.75, 61, NULL),
    (104, 28, 'Marmon Motor', '', '1', 8, 37, 31.75, 37, NULL),
    (72.75, 40, 'Mathieson Alk', '', 'e2', 35, 57.75, 48.75, 56.75, NULL),
    (108.75, 73.25, 'May Dept Stores', '', 'c2', 29, 76, 65.75, 76.75, NULL),
    (29.75, 16.25, 'Maytag Co', '', '12', 11, 19.75, 18.75, 19, NULL),
    (49.25, 36, 'Maytag Co', 'pf', '3', 5, 37, 36.25, 37, NULL),
    (72, 50, 'Melville Shoe', '', '1.40', 1, 49, 49, 50, NULL),
    (34.75, 15, 'Mengel Co', '', NULL, 100, 20.75, 18.75, 20.75, NULL),
    (69.75, 9.75, 'Mexican Seaboard', '', NULL, 377, 20, 16.75, 20, NULL),
    (54.75, 30.75, 'Miami Copper', '', '4', 35, 38.75, 36, 37.75, NULL),
    (39.75, 29.75, 'Mid-Continent P', '', '2', 39, 30.75, 29.75, 30.75, NULL),
    (5.75, 1, 'Middle States Oil', '', NULL, 14, 1.75, 1.75, 1.75, NULL),
    (3.75, 1, 'Middle States Oil', 'ct', NULL, 17, 1.75, 1.75, 1.75, NULL),
    (6.75, 1.75, 'Middle Sta', 'ctfs', 'n', 11, 1.75, 1.75, 1.75, NULL),
    (821, 220, 'Midland Stl', 'pf', '112', 3, 218, 218, 222, NULL),
    (123.75, 98, 'Minn Honeywell', '', '5%', 7, 95.75, 95, 100, NULL),
    (43.75, 19, 'Minn Moline Pwr', '', NULL, 28, 19.25, 16.75, 20, NULL),
    (102, 80, 'Minn Moline', 'pf', '6 1/2', 2, 82, 82, 82, NULL),
    (3.75, 3, 'Minn A St Louis', '', NULL, 7, 2.25, 2.75, 2.75, NULL),
    (65.75, 42.75, 'Mo Kan A Texas', '', NULL, 93, 50, 43, 51, NULL),
    (107.25, 101.75, 'Mo Kan A Tex', 'pf', '7', 5, 103.75, 102.75, 105, NULL),
    (101.75, 62.75, 'Missouri Pacific', '', NULL, 15, 86.75, 81, 86.25, NULL),
    (147.75, 120, 'Missouri Pac', 'pf', '6', 13, 143, 139.75, 144, NULL),
    (80.25, 68.75, 'Mohawk Carpet', '', '2%', 1, 56, 55.75, 57, NULL),
    (80.75, 68.75, 'Monsanto Ch', '', 'g1%', 2, 67.75, 60, 70.75, NULL),
    (156.75, 60, 'Montgomry Ward', '', '3', 356, 72.75, 60, 71.25, NULL),
    (5, 5, 'Moon Motor', '', 'new', 1, 5, 4.25, 5, NULL),
    (81.75, 65, 'Morrell J', '', '3.60', 18, 69, 66, 69, NULL),
    (6.75, 1.75, 'Mother Lode', '', '40c', 23, 2.75, 1.75, 2, NULL),
    (60.75, 12.75, 'Motion Picture', '', NULL, 2, 20.75, 18, 21.75, NULL),
    (31.75, 3.75, 'Motor Meter G A', '', '8', 42, 8.75, 7, 8, NULL),
    (142, 79, 'Motor Products', '', '10', 8, 79, 70, 80, NULL),
    (55.25, 32, 'Motor Wheel', '', '4', 39, 35.75, 33.75, 34.75, NULL),
    (81.75, 10, 'Mullins Mfg', '', NULL, 14, 20, 18, 18, NULL),
    (61.75, 50, 'Munsingwear', '', 't3 1/2', 1, 49.75, 49.75, 51, NULL),
    (67.25, 30, 'Murray Corp', '', 'kt', 60, 36.25, 31, 37.75, NULL),
    (58.25, 69.875, 'Nat Enamlg', '', '1', 1, 58.25, 69.875, 67.875, NULL),
    (148.75, 150.875, 'Nat Lead', '', '6', 1, 148.75, 150.875, 150.25, NULL),
    (141.875, 141.875, 'Nat Lead', 'pf A', '7', 1, 141.875, 141.875, 140, NULL),
    (55.875, 57, 'Nat Pow & Lt', '', '1', 1, 55.875, 57, 56.875, NULL),
    (14.875, 14.875, 'Nat Radiator', '', NULL, 1, 14.875, 14.875, 14.875, NULL),
    (6.875, 6.875, 'Nat Ry Mex', '1st', NULL, 1, 6.875, 6.875, 6.875, NULL),
    (3.25, 3.875, 'Nat Ry Mex', '2d', NULL, 1, 3.25, 3.875, 3.875, NULL),
    (125, 125, 'Nat Supply', '', '5', 1, 125, 125, 124.875, NULL),
    (150, 155, 'Nat Surety', '', '6', 1, 150, 155, 153.25, NULL),
    (344.875, 345, 'Nat Tea', '', '4', 1, 344.875, 345, 345, NULL),
    (48, 48.875, 'Nevada Cop', '', '2', 1, 48, 48.875, 47, NULL),
    (46.25, 49, 'N Y Air Br', '', '3', 1, 46.25, 49, 48.875, NULL),
    (256.875, 178.875, 'N Y Central', '', '8', 39, 208.875, 191, 208.875, NULL),
    (192.875, 128.875, 'N Y Chi & St L', '', '8', 1, 166.875, 163, 166.875, NULL),
    (109.25, 100, 'N Y Chi A St L', 'pf', '6', 1, 107.875, 107.875, 107.25, NULL),
    (90, 82.875, 'N Y Dock', 'pf', '5', 1, 87.875, 87, 87, NULL),
    (132.875, 80.25, 'N Y N H & Hart', '', '5', 47, 123, 114, 123.875, NULL),
    (134.875, 114.875, 'N Y NH & H', 'pf', '7', 2, 128, 125.875, 128.875, NULL),
    (32, 15.875, 'N Y Ont A West', '', NULL, 9, 17.875, 15.875, 17.875, NULL),
    (48.25, 29.875, 'Norfolk South', '', '2%', 2, 24.875, 24.875, 25, NULL),
    (290, 191, 'Norf & W stn', '', '10', 8, 262, 256, 261.875, NULL),
    (186.875, 90.875, 'North Am', '', '10%stk', 112, 115, 99.875, 116, NULL),
    (54.875, 51.875, 'North Am', 'pf', '3', 8, 53, 52.875, 52.875, NULL),
    (103.875, 99, 'Nor Am Ed', 'pf', '7', 1, 100.875, 100.875, 100.875, NULL),
    (64.875, 48.875, 'Nor Germn Lloyd', '', '3.41', 4, 48.25, 48.875, 49.875, NULL),
    (86.875, 82, 'Northern Central', '', '4', 80, 78.875, 78.875, 82, NULL),
    (118.25, 91.875, 'Northern Pac', '', '6', 5, 98, 93, 96.875, NULL),
    (114.875, 90.25, 'North Pac', 'ct', '5', 8, 95.25, 93, 96, NULL),
    (32, 16, 'Oil Well Supply', '', NULL, 13, 17, 16, 16.875, NULL),
    (46.25, 17, 'Oliver Farm Equip', '', NULL, 19, 25.875, 23.25, 25.875, NULL),
    (69.875, 44.25, 'Olvr Fr Ep', 'cv pt', '3', 18, 43.875, 41, 43.875, NULL),
    (99.25, 82, 'Olvr Fr Eq', 'pf A', '6', 2, 83, 83, 84, NULL),
    (10.25, 2.75, 'Omnibus Corp', '', NULL, 10, 4.75, 4, 5, NULL),
    (84.875, 61, 'Oppenhm Col', '', '6', 4, 63.5, 63.25, 65, NULL),
    (450, 276, 'Otis Elev', '', '6', 24, 350, 325, 360, NULL),
    (55, 37, 'Otis Steel', '', NULL, 2, 48.75, 46, 48.75, NULL),
    (108, 96.25, 'Otis Stl', 'pr pf', '7', 3, 99, 89, 99, NULL),
    (89.75, 60, 'Outlet Co', '', '4', 1, 67.75, 64, 68, NULL),
    (98.25, 53.75, 'Owens Ill Glass', '', '4', 1, 67.75, 64, 68, NULL),
    (65.75, 67, 'Pacific Gas', '', '3', 14, 64.75, 60.75, 64.75, NULL),
    (79, 79, 'Pac Lighting', '', '3', 12, 95.25, 86, 95, NULL),
    (1.75, 1.75, 'Pac Oil Stubs', '', NULL, 42, 2, 1, 1, NULL),
    (179, 179, 'Pac Tel & Tel', '', '7', 1, 179, 179, 179, NULL),
    (141, 141, 'Packard Mot', '', '3', 590, 21.75, 18.75, 21.875, NULL),
    (69, 40.25, 'Pan-Am Petrolm', '', NULL, 7, 64, 60.75, 64.875, NULL),
    (69.875, 40.875, 'Pan-Amer Pet', 'B', NULL, 107, 64.875, 59.875, 64.875, NULL),
    (15.875, 5, 'Panhandle P A R', '', NULL, 2, 5.25, 5.75, 5.875, NULL),
    (75.875, 60, 'Paramount-F-L', '', '5', 95, 60, 51.75, 60, NULL),
    (87.75, 38.75, 'Park & Tilford', '', '33', 9, 38, 35, 40, NULL),
    (13.25, 4, 'Park Utah', '', NULL, 23, 5, 4.75, 5, NULL),
    (14.25, 4, 'Pathé Exchange', '', NULL, 97, 6.75, 5.75, 6, NULL),
    (30, 10, 'Pathe Exchange', 'A', NULL, 50, 12, 10.75, 11.75, NULL),
    (47.75, 27.75, 'Patino Mines', '', '3.59', 14, 34.75, 31.75, 33.75, NULL),
    (22.75, 8.75, 'Peerless Motor Car', '', NULL, 3, 10, 10, 10.75, NULL),
    (60.25, 34.75, 'Penick A Ford', '', NULL, 16, 41, 35, 41, NULL),
    (14, 5.875, 'Penn C & Coke', '', NULL, 1, 10.25, 10.75, 10.75, NULL),
    (27, 6.875, 'Penn Dixie Cment', '', NULL, 3, 7, 7, 7.875, NULL),
    (94, 85.25, 'Penn Dixie Cm', 'pf', '7', 1, 88, 88, 88, NULL),
    (110, 72.25, 'Pennsylvania RR', '', '4', 47, 96.75, 92, 96.875, NULL),
    (105.875, 100, 'Penney (J C)', '', NULL, 11, 99, 97.75, 101, NULL),
    (404, 208, 'People’s Gas Chi', '', '8', 5, 294, 270, 305, NULL),
    (260, 148, 'Pere Marquette', '', '8', 1, 190, 187, 197.875, NULL),
    (45.75, 23.75, 'Pet Milk', '', '1%', 1, 25.75, 25, 25.75, NULL),
    (79.25, 53, 'Phelps Dodge', '', '3', 1, 55, 52, 56, NULL),
    (34, 17.875, 'Phil a & Read C A I', '', NULL, 22, 21.25, 17.75, 20.75, NULL),
    (23.875, 9.875, 'Philip Morris', '', '1', 1, 10.25, 9.75, 10, NULL),
    (73, 30, 'Phillips-Jones', '', '3', 3, 30, 30, 30, NULL),
    (47, 27.875, 'Phillips Pet', '', '1%', 43, 37.75, 36, 37.75, NULL),
    (37, 10.875, 'Phoenix Hosiery', '', NULL, 1, 14, 14, 16, NULL),
    (87, 72, 'Pierce Arrow', 'pf', '6', 2, 74.75, 74.75, 75, NULL),
    (3.875, 1.875, 'Pierce Oil', '', NULL, 21, 1.75, 1.75, 1.875, NULL),
    (61.75, 30, 'Pierce Oil', 'pf', NULL, 1, 36.25, 36.75, 35, NULL),
    (5, 3.875, 'Pierce Petrolm', '', NULL, 8, 3.75, 3, 3.75, NULL),
    (63.75, 39.25, 'Pillsbury Fl', '', '2%', 14, 41.75, 36, 41.875, NULL),
    (68, 50.875, 'Pirelli Co', 'A', '2.88', 9, 54.75, 52.75, 55.75, NULL),
    (83.25, 54.25, 'Pittsburgh Coal', '', NULL, 6, 70, 68, 70, NULL),
    (27.25, 21, 'Pittsbgh Screw', '', '1.40', 13, 22.75, 20.75, 22, NULL),
    (34.875, 20, 'Pitts Terminal Coal', '', NULL, 14, 23.75, 23.75, 25.875, NULL),
    (148.75, 125.875, 'Pitts & W Va', '', '6', 2, 124, 124, 128, NULL),
    (43.875, 26, 'Poor A Co', '', '2', 11, 34.75, 31.75, 35, NULL),
    (95.75, 70.75, 'P Rican Am To', '', 'A)7', 2, 76, 76, 76, NULL),
    (50.75, 22, 'P Rican Am To', 'B', 'B', 2, 23, 22, 22.75, NULL),
    (65.75, 49.25, 'Prairie Oil&Gas', '', '4%', 66, 50.75, 49, 50.875, NULL),
    (65, 53.75, 'Prairie Pipe L', '', '4 1/2', 41, 58.75, 56.75, 58.75, NULL),
    (25.75, 10.75, 'Pressed Stl Car', '', NULL, 58, 12.75, 11, 12.75, NULL),
    (81, 64.25, 'Pressed Stl C', 'pf', '7', 1, 64, 63.25, 65.5, NULL),
    (98, 79.25, 'Proc A Gamble', '', '2', 26, 81.75, 78.75, 81.75, NULL),
    (25.25, 4, 'Prod A Refiners', '', NULL, 11, 8.75, 8.75, 9.25, NULL),
    (137.75, 76, 'Pub Svc NJ', '', '2.80', 80, 97.25, 90, 97.875, NULL),
    (1.875, 1.875, 'Pub Svc NJ', 'rts', NULL, 1, 1.875, 1.875, 1.875, NULL),
    (108.25, 103.75, 'Pub Svc', 'pf', '6', 3, 107, 107, 107, NULL),
    (124, 117.75, 'Pub Svc NJ', 'pf', '7', 3, 122.75, 121.75, 120, NULL),
    (99.875, 78, 'Pullman Corp', '', '4', 82, 86.75, 80, 86.75, NULL),
    (21.25, 14, 'Punta Aleg Sugar', '', NULL, 2, 15, 14.75, 14.25, NULL),
    (30.75, 23.75, 'Pure Oil', '', '1', 125, 26.75, 25, 26.75, NULL),
    (148.75, 109.75, 'Purity Bakeries', '', '4', 42, 115.75, 106.75, 117, NULL),
    (114.75, 44.25, 'Radio Corp', '', NULL, 612, 58, 46, 58.875, NULL),
    (67, 62, 'Radio', 'pf A', '3%', 3, 63, 53, 54, NULL),
    (82, 68, 'Radio', 'pf B', '6', 16, 75, 72, 74.75, NULL),
    (46.25, 19, 'Radio-Keith-Orph', 'A', NULL, 105, 25.75, 20.75, 25.75, NULL),
    (61.75, 38.75, 'Railway A Exp', '', '2', 69, 43, 40, 43.75, NULL),
    (68.25, 42, 'Raybestos Manhatn', '', NULL, 30, 45, 40.25, 45, NULL),
    (147.75, 101.75, 'Reading', '', '4', 128, 125.75, 119, 125, NULL),
    (60.75, 43.75, 'Reading', '2d pf', '2', 1, 46.75, 46, 46, NULL),
    (84.75, 50, 'Real Silk', '', '6', 14, 60, 65, 60, NULL),
    (16.75, 6, 'Reis (R) A Co', '', NULL, 3, 7.75, 6.75, 7, NULL),
    (96.875, 90.875, 'Remington-Rand', '', NULL, 45, 48.25, 42, 48.875, NULL),
    (100.875, 93, 'Rem ing-R nd', '1st', '7', 1, 93, 92.75, 93, NULL),
    (100.875, 93, 'Rem ing-R nd', '2d', '8', 1, 99, 99, 100.875, NULL),
    (31.75, 11.75, 'Reo Motors', '', '1', 60, 15, 14.75, 14.75, NULL),
    (111, 93.875, 'Rep Brass', 'A', '4', 2, 93, 93, 94, NULL),
    (146.75, 79.25, 'Repub Ir A Steel', '', '4', 83, 99, 85.75, 97.75, NULL),
    (115, 108.25, 'Rep Ir A Stl', 'pf', '7', 1, 111, 111, 111, NULL),
    (12.75, 6, 'Reynolds Spring', '', NULL, 3, 8, 7.75, 7.75, NULL),
    (66, 62, 'Reynolds Tb', 'B', '2.40', 122, 54.75, 51.75, 54, NULL),
    (64, 48.875, 'Rhine West', '', '1.92', 5, 48.25, 47.75, 48.875, NULL),
    (49.75, 20, 'Richfield Oil', '', '2', 41, 32.75, 30, 32.75, NULL),
    (42.875, 15, 'Rio Grande Oil', '', 'k2', 20, 26.75, 22, 22.5, NULL),
    (70, 57, 'Ritter Dental', '', '2%', 3, 61, 60, 61, NULL),
    (96, 60, 'Rossia Ins', '', '2.20', 19, 57, 47.75, 57.875, NULL),
    (64, 48, 'Royal Dutch', '', 'a1.28', 63, 54.75, 49.75, 55.75, NULL),
    (195.875, 140.25, 'Safeway Stores', '', '3', 13, 150.75, 140.75, 148, NULL),
    (94, 59, 'St Joseph Lead', '', '1', 20, 65.75, 58.75, 65.75, NULL),
    (133.75, 109.25, 'St L-San Fran', '', '1', 6, 116, 114, 116.75, NULL),
    (96.875, 91, 'St L-San Fran', 'pf', '8', 2, 94.75, 94, 96, NULL),
    (115.25, 60, 'St L-Southwest', '', NULL, 7, 75.75, 74.75, 77, NULL),
    (61.25, 34, 'Savage Arms', '', '2', 20, 31.75, 31.75, 34, NULL),
    (41.75, 10.25, 'Schulte Retail Strs', '', NULL, 44, 11.75, 11.75, 12.75, NULL),
    (21, 12, 'Seaboard Air Line', '', NULL, 6, 14.75, 14, 14.75, NULL),
    (22, 12.25, 'Seagrave', '', '1.20', 4, 13.75, 12.75, 15, NULL),
    (181, 115, 'Sears Roebuck', '', '12%', 234, 122, 114, 127.75, NULL),
    (190.875, 110, 'Second Nat Inv Corp', '', NULL, 1, 117, 117, 116, NULL),
    (10.875, 3, 'Seneca Copper', '', NULL, 11, 4, 3.75, 4, NULL),
    (21.875, 12.75, 'Servel Inc', '', NULL, 47, 14, 11.75, 14, NULL),
    (63.875, 30, 'Sharon Steel H', '', '2', 11, 32, 32, 32, NULL),
    (65.875, 62, 'Sharp &Do', 'pf', '3 %', 2, 62.25, 62, 63, NULL),
    (71, 36.875, 'Shattuck (F G)', '', '1', 11, 46.75, 40.75, 46.75, NULL),
    (31.875, 24, 'Shell Union', '', '1.40', 10, 25.75, 24.75, 25.75, NULL),
    (74.875, 23, 'Shubert Theater', '', '6', 8, 25.75, 21, 25, NULL),
    (188, 75, 'Simmons Co', '', '3', 82, 100.875, 86, 101, NULL),
    (40.875, 18.875, 'Simms Pet', '', '1.60', 3, 24.75, 22, 25, NULL),
    (45, 25, 'Sinclair Oil', '', NULL, 166, 31, 26.75, 31, NULL),
    (111, 107.875, 'Sinclair Oil', 'pf', '8', 1, 109.75, 109.75, 109.75, NULL),
    (46.875, 31, 'Skelly Oil', '', '2', 27, 35.75, 32.75, 35, NULL),
    (125, 48, 'Sloss Sheffield steel', '', NULL, 2, 47.75, 34, 48, NULL),
    (16.875, 4, 'Snider Packing', '', NULL, 3, 6.75, 6, 6, NULL),
    (64.875, 25.875, 'Snider Packing', 'pf', NULL, 1, 21, 24, 25, NULL),
    (111, 100, 'S.''lvay Am In', 'pf', '5%', 11, 102, 101.875, 101, NULL),
    (45, 33.875, 'So Porto R Sug', '', '2%', 1, 35.75, 34.75, 35.75, NULL),
    (93.75, 63.875, 'Southern Cal Ed', '', '2', 21, 67, 60.75, 68.75, NULL),
    (16.875, 5, 'Southern Dairies', 'B', NULL, 1, 8, 7.75, 8, NULL),
    (157.75, 124, 'Southern Pacific', '', '6', 14, 133.75, 128.75, 135.75, NULL),
    (162.75, 138, 'Southern Rwy', '', '8', 12, 145.875, 141.875, 146, NULL),
    (52.25, 32, 'Spang-Chalfant', '', NULL, 2, 30.875, 30, 32, NULL),
    (73, 35.75, 'Sparks Withngtn', '', '1', 164, 36, 25, 36, NULL),
    (45, 35.75, 'Spencer Kel g', '', '0.60', 3, 35, 35, 35, NULL),
    (66.75, 35, 'Spicer Mfg', '', NULL, 1, 38, 36, 40.75, NULL),
    (55.875, 45, 'Spicer Mfg', 'pf', '8', 2, 46, 45, 45, NULL),
    (117.25, 65, 'Spiegel-May-St', '', '3', 9, 65, 60, 66, NULL),
    (44.875, 20, 'Stand Brands', '', '1 1/4', 619, 32.875, 29.75, 32.75, NULL),
    (43.875, 8, 'Stand Com Tob', '', '1', 2, 10.875, 10, 10.875, NULL),
    (243.875, 80.875, 'Stand Gas & El', '', '3 1/4', 20, 143, 108, 146, NULL),
    (67, 62.75, 'Stand G&E', 'pf', '4', 6, 64.75, 64.75, 64.75, NULL),
    (48, 31, 'Stand Inv Corp', '', '1', 1, 30, 30, 31.75, NULL),
    (81.75, 64, 'Stand Oil Cal', '', '3', 34, 70, 67.75, 69.75, NULL),
    (83, 48, 'Stand Oil N J', '', '2', 120, 72.75, 66, 72.75, NULL),
    (48.875, 34.75, 'Stand Oil N Y', '', '1.60', 67, 40, 37.75, 40, NULL),
    (7.75, 7.75, 'Stand Plate Glass', '', NULL, 1, 7.75, 7.75, 7.75, NULL),
    (22.875, 22.875, 'Std P Glass', 'pf', NULL, 1, 22.875, 22.875, 22.875, NULL),
    (53, 55.875, 'Std San Mi', '', '1.68', 1, 53, 55.875, 53.75, NULL),
    (40.875, 40.875, 'Stanley Co', '', NULL, 1, 40.875, 40.875, 40.875, NULL),
    (77, 47, 'Stewart Warn', '', '3 1/4', 34, 52.75, 48.75, 52.75, NULL),
    (201.875, 119, 'Stone & Webster', '', NULL, 11, 122, 111, 126.75, NULL),
    (98, 65.875, 'Studebaker', '', '5', 26, 58.875, 54.75, 59, NULL),
    (4.875, 1.875, 'Submarine Boat', '', NULL, 1, 1.875, 1, 1.875, NULL),
    (85.875, 57, 'Sun Oil', '', 'p1', 6, 73.75, 73, 73.25, NULL),
    (24, 9.875, 'Superior Oil', '', NULL, 34, 14, 12, 14.25, NULL),
    (73.875, 25, 'Superior Steel', '', NULL, 1, 28, 27.75, 27.75, NULL),
    (22.875, 8.875, 'Sweets of Amer', '', '1', 1, 10.875, 10.875, 10.875, NULL),
    (19.875, 10.875, 'Symington', 'A', NULL, 1, 11, 10.875, 11, NULL),
    (25.875, 18.875, 'Telautograph', '', '1', 3, 19.75, 19, 19.75, NULL),
    (20.875, 14.75, 'Tenn Cop & Ch', '', '1', 40, 15, 14.75, 16, NULL),
    (71.875, 57.875, 'Texas Corp', '', '3', 296, 58.875, 56, 58.875, NULL),
    (85.25, 55, 'Tex Gulf Sul', '', '4', 76, 62.75, 57.75, 63.75, NULL),
    (181, 130, 'Texas & Pac', '', '5', 1, 140.75, 128.75, 135, NULL),
    (23.875, 11.875, 'Texas P C & O', '', 'b6', 31, 14.875, 13.75, 14.875, NULL),
    (24.875, 9.875, 'Texas Pac Land Tr', '', NULL, 22, 11.75, 10, 11, NULL),
    (35, 16.875, 'Thatcher Mfg', '', NULL, 6, 25.75, 25.75, 26.75, NULL),
    (49.875, 35, 'Thatcher', 'pf', '3.60', 2, 43.75, 43.75, 43, NULL),
    (51.875, 34, 'The Fair', '', '2.40', 6, 36.75, 35.75, 36.75, NULL),
    (39, 10, 'Third Avenue', '', NULL, 1, 11, 10.75, 11, NULL),
    (23.875, 14, 'Tide Water Asso', '', NULL, 36, 16.75, 14.75, 15.75, NULL),
    (90.875, 83, 'Tide Wat Asso', 'pf', '6', 1, 84, 83, 84, NULL),
    (139.875, 73.875, 'Timkn Det Axle', '', '80c', 14, 21.75, 19.75, 21, NULL),
    (139.875, 73.875, 'Timken Roller', '', '3', 75, 105, 86, 105.75, NULL),
    (22.875, 4.875, 'Tobacco Prod', '', '1.40', 96, 6.75, 4.75, 6.875, NULL),
    (16, 3, 'Tob Prod', 'ctfs', '1.48', 24, 4.25, 4, 4, NULL),
    (22, 9, 'Tobacco Pr', 'A', '1.40', 9, 11.75, 10, 11.75, NULL),
    (19, 9, 'Tob Prod', 'ctfs A', '1.40', 5, 9.75, 9.75, 9.75, NULL),
    (15.875, 6.875, 'Transcontinental', '', NULL, 27, 9.75, 8.75, 9.75, NULL),
    (63, 38.875, 'Trico Prod', '', '2 3/4', 1, 40, 39, 40.75, NULL),
    (31.25, 18.875, 'Truax Traer', '', '1.60', 11, 21, 20.75, 21, NULL),
    (61.25, 44, 'Truscon Stl', '', '1.20', 1, 45, 44, 44, NULL),
    (68.25, 32, 'Twin City B p T', '', '4', 1, 35, 33, 34.75, NULL),
    (181.875, 91, 'Underw-El-Flsh', '', '4', 15, 140, 121, 145, NULL),
    (43, 14.875, 'Union Bag & Paper', '', NULL, 1, 16.75, 16, 18, NULL),
    (140, 75.25, 'Union Carbide', '', '2', 183, 102.75, 91, 104, NULL),
    (57, 43.75, 'Un Oil of Cal', '', '2', 30, 51.75, 49, 50.875, NULL),
    (1.875, 1.875, 'Union Oil', '', 'rts', 1, 1.875, 1.875, 1.875, NULL),
    (297.875, 209, 'Union Pac', '', '10', 4, 256, 245, 256, NULL),
    (85.875, 80.875, 'Un Pacific', 'pf', '4', 2, 84, 83.75, 84, NULL),
    (109.875, 68, 'Utd Aircraft & Trans', '', NULL, 67, 74.75, 62.75, 74.25, NULL),
    (60, 41, 'Utd Biscuit', '', '1.60', 1, 50.75, 47, 50, NULL),
    (111, 74.875, 'Utd Carbon', '', NULL, 19, 78, 70, 79.75, NULL),
    (27.875, 4.875, 'Utd Cigar Stores', '', '1', 45, 6, 6.75, 6, NULL),
    (16.875, 4.875, 'Unit''d Cig St.', 'ctf', '1', 5, 4.875, 4, 4.875, NULL),
    (104, 53, 'United Cigar Strs', 'pf', NULL, 1, 55, 55, 65, NULL),
    (75.875, 31.875, 'Utd Corporation', '', NULL, 333, 42, 35.75, 42.875, NULL),
    (49.875, 45, 'Utd Corp', 'pf', '3', 16, 48, 47.75, 47.875, NULL),
    (81.875, 20, 'Utd Electric Coal', '', '3', 10, 21.75, 18, 21.875, NULL),
    (158.875, 109.875, 'Utd Fruit', '', 'ts%', 10, 116.75, 114, 117, NULL),
    (59.875, 30, 'Utd Gas & Imp', '', '4', 359, 37.25, 32.75, 36.75, NULL),
    (96.875, 92.875, 'Utd Gas &lm', 'pf', '6', 8, 95.875, 95.875, 95, NULL),
    (26.875, 8.875, 'Utd Paperboard', '', NULL, 3, 8.875, 8.875, 8.875, NULL),
    (48.875, 29, 'Utd Piece Dye', '', NULL, 3, 29, 27, 29, NULL),
    (14, 9, 'United Stores', 'A', NULL, 474, 13, 12.875, 13, NULL),
    (40.875, 39, 'United Stores', 'pf', '6', 120, 40.875, 38.875, 40, NULL),
    (23, 12.875, 'U S Distributing', '', NULL, 2, 17.75, 17, 17, NULL),
    (79.875, 79.875, 'U S &Foreign Secur', '', NULL, 2, 42.75, 39, 43, NULL),
    (134.875, 101.875, 'U S Freight', '', '3', 20, 110.875, 107.875, 109.875, NULL),
    (49.875, 29.875, 'U S Hoffman', '', '4', 1, 32, 32, 33, NULL),
    (243.875, 128, 'U S Ind Alco', '', '6', 36, 190, 160, 191.875, NULL),
    (35.875, 12.875, 'U S Leather', '', NULL, 10, 15.875, 14.875, 16, NULL),
    (61.875, 23, 'U S Leather', 'A', '4', 7, 25, 23.875, 25, NULL),
    (55.875, 19, 'U S Pipe & Fdry', '', '2', 26, 20.875, 19.875, 20.875, NULL),
    (119.875, 78, 'U S Realty', '', '5', 19, 80, 75.875, 81, NULL),
    (65, 40.875, 'U S Rubber', '', NULL, 54, 45, 41.875, 46, NULL),
    (92.875, 69.875, 'U S Rub', '1st pf', NULL, 6, 70, 69.875, 70, NULL),
    (72.875, 35, 'U S Smelt Ref', '', '3%', 19, 41, 40, 41.875, NULL),
    (261.25, 163, 'U S Steel', '', '7', 244, 202.875, 192.875, 203.875, NULL),
    (144.875, 139.875, 'U S Steel', 'pf', '7', 9, 142.875, 142.875, 143.875, NULL),
    (109.875, 90.875, 'U S Tobacco', '', '4', 3, 85, 84.875, 85, NULL),
    (52.875, 43.875, 'Univ Leaf Tob', '', '3', 1, 46, 46, 45, NULL),
    (22, 3, 'Univ Pipe & Rad', '', NULL, 5, 4.875, 4.875, 4.875, NULL),
    (58.875, 34, 'Util Pwr & Lt', 'A', 'e2', 33, 40.875, 38, 41, NULL),
    (13.875, 4.875, 'Vadsco Sales', '', NULL, 24, 7.25, 6.75, 8.25, NULL),
    (82, 67.875, 'Vadsco Sales', 'pf', '7', 1, 67.875, 67.875, 67.875, NULL),
    (116.875, 60, 'Vanadium', '', '4', 19, 70.875, 67.875, 71.875, NULL),
    (51.875, 40, 'Vick Chemical', '', '2%', 7, 40.875, 39.875, 41, NULL),
    (24.875, 8, 'Virginia-Car Chem', '', NULL, 18, 8.25, 6, 8, NULL),
    (65.875, 33.875, 'Virginia-Car', '6% pf', NULL, 1, 33, 30.875, 33, NULL),
    (97.875, 83.875, 'Virginia-Car', 'pf', '7', 2, 83.875, 83.875, 85, NULL),
    (81.875, 52, 'Wabash', '', NULL, 8, 53.875, 52, 53, NULL),
    (36.875, 22.875, 'Waldorf Syst m', '', '1%', 6, 29.875, 27.875, 29, NULL),
    (49.875, 23.875, 'Walworth', '', '1.20', 11, 39.875, 34.25, 40, NULL),
    (21.25, 6, 'Ward Baking', 'B', NULL, 2, 6.875, 6.875, 7, NULL),
    (64.875, 40.875, 'Warner Bros Pic', '', '4', 172, 51.875, 45.875, 50.875, NULL),
    (69.25, 41.875, 'Warn Br P', 'pf', '2.20', 1, 41.875, 42, 42.875, NULL),
    (42.875, 15, 'Warner-Quinlan', '', '2', 66, 23.875, 20.875, 23.875, NULL),
    (207.875, 139, 'Warren Bros', '', '5', 3, 165, 160.25, 170.875, NULL),
    (34.875, 15.875, 'Warren Fdry & Pipe', '', NULL, 36, 23, 20.875, 23.875, NULL),
    (113.875, 15.875, 'Webster-Eisenlohr', '', NULL, 4, 14.875, 10, 15.875, NULL),
    (48, 30, 'Wess Oil & Snow', '', '2', 5, 33, 31.875, 33, NULL),
    (72.875, 56.875, 'Wess O&Sn', 'pf', '4', 4, 57, 56, 57, NULL),
    (40, 22.875, 'Westn Dairy', '', '8', 2, 26.875, 25.875, 26.875, NULL),
    (64, 20, 'Western Maryland', '', NULL, 34, 28.875, 22.875, 27.875, NULL),
    (53.875, 25, 'West Md', '2d pf', NULL, 2, 26.875, 25.875, 26, NULL),
    (41.875, 31.875, 'Western Pacific', '', NULL, 1, 31.875, 31, 31, NULL),
    (67.875, 53, 'Western Pac', 'pf', NULL, 3, 54.875, 53.875, 55.875, NULL),
    (272.875, 179.875, 'Western Union', '', '8', 14, 225, 198, 230.875, NULL),
    (67.25, 43.25, 'Westngh Air Brk', '', '2', 38, 52.875, 48, 52.875, NULL),
    (292.875, 137.875, 'Westngh El&M', '', '4', 613, 275, 150, 179.875, NULL),
    (64.875, 22, 'Weston El instru', '', NULL, 2, 61.875, 49.875, 61.875, NULL),
    (94.875, 49.875, 'Westvaco Chlor', '', '2', 2, 51.875, 51.875, 50.875, NULL),
    (75, 40, 'Westark Radio', '', 'c2', 4, 40.875, 36, 40, NULL),
    (38, 29.875, 'White Eagle Oil', '', '2', 33, 31.875, 30, 31.25, NULL),
    (53.875, 38, 'White Motor', '', '1', 30, 42.25, 41.875, 47, NULL),
    (41.875, 10, 'White Rock Al S', '', '3', 8, 46, 40, 45, NULL),
	(48, 10, 'White Sewing Mach', '', NULL, 19, 12, 11.25, 11.25, 12),
    (57.875, 32, 'White Sewing Mach', 'pf', 4, 1, 36, 36, 36, 36),
    (29.875, 16, 'Wilcox Oil & Gas', '', NULL, 1, 18.875, 18, 19, NULL),
    (61.875, 30, 'Wilcox Rich', '(A)', '2.5', 1, 30.5, 30.5, 30.5, 30),
    (62, 17, 'Wilcox Rich', 'B', 'c2', 19, 26.25, 21.625, 21.625, 25.125),
    (35, 14.125, 'Willys-Over', '', 'c 1.20', 212, 14.25, 13.75, 13.75, 14.5),
    (13.5, 4.625, 'Wilson & Co', '', NULL, 1, 5.25, 5.125, 5.125, 5.125),
    (27, 7, 'Wilson & Co', 'A', NULL, 12, 15, 9.5, 9.5, 10.125),
    (79, 46, 'Wilson & Co', 'pf', NULL, 4, 47.25, 47, 47.25, 47.25),
    (103.875, 82, 'Woolworth', '', '2.40', 33, 86.5, 82, 83, 87),
    (137.375, 43, 'Worthington Pump', '', NULL, 3, 89, 86, 86, 95),
    (80.875, 70, 'Wrigley Wm Company', '', '4', 1, 71.5, 70.125, 70.125, 72),
    (88, 61.75, 'Yale & Towne Manufacturing Company', '', '4', 1, 76, 74, 75, 78.125),
    (51.25, 11, 'Yellow Truck & Coach Company', '', NULL, 190, 18, 15.5, 15.5, 17.5),
    (59.75, 48.75, 'Young Spring and Wire Corporation', '', '3', 28, 47.75, 43.75, 43.75, 48.75),
    (143, 120, 'Youngstown Sheet and Tube Company', '', '5', 1, 125.5, 120, 120, 125.25),
    (52.75, 27.125, 'Zenith Radio Corporation', '', '2', 89, 29.875, 27, 27, 30)

) AS v(year_high, year_low, company_name, stock_variant, dividend,
       sales_100s, daily_high, daily_low, daily_close, previous_close)
ON CONFLICT (quote_date, company_name, stock_variant) DO UPDATE SET
    year_high      = EXCLUDED.year_high,
    year_low       = EXCLUDED.year_low,
    dividend       = EXCLUDED.dividend,
    sales_100s     = EXCLUDED.sales_100s,
    daily_high     = EXCLUDED.daily_high,
    daily_low      = EXCLUDED.daily_low,
    daily_close    = EXCLUDED.daily_close,
    previous_close = EXCLUDED.previous_close;

-- Tag source information
UPDATE newspaper_stock_quotes
SET source_newspaper = 'The Evening Star (Washington D.C.)',
    source_market    = 'NYSE'
WHERE quote_date = '1929-10-28'
  AND source_newspaper IS NULL;
ENDSQL

    local cnt
    cnt=$(psql -X --username="$PSQL_USER" --dbname="$PSQL_DB" \
        --tuples-only -c "SELECT COUNT(*) FROM newspaper_stock_quotes WHERE quote_date = '1929-10-28';" \
        2>/dev/null | tr -d ' ')
    success "✅ Oct 28 1929 loaded — ${cnt} rows in database for that date."
}

insert_data_menu() {
    push_breadcrumb "Insert Data"
    while true; do
        section_header "📋 Insert Data"

        choice="$(gum choose \
            "── Stock Quotes ──" \
            "Enter Stock Quotes  (Quick / Form / CSV)" \
            "Insert Black Monday  Oct 28 1929" \
            "Insert Black Tuesday Oct 29 1929" \
            "Import from SQL file  (.sql)" \
            "── Export / Backup ──" \
            "Export Stock Quotes to CSV  (all dates)" \
            "Export Stock Quotes to CSV  (date range)" \
            "Export Stock Quotes to CSV  (single date)" \
            "List existing exports" \
            "── View / Search ──" \
            "Browse All Quotes" \
            "Search Quotes by Stock" \
            "Search Quotes by Date" \
            "── Stock Name List ──" \
            "View Stock Names File" \
            "Add Name to Stock Names File" \
            "Edit Stock Names File" \
            "Import Names from CSV column" \
            "── Schema ──" \
            "List Tables" \
            "Describe newspaper_stock_quotes" \
            "Back")"

        case "$choice" in
            "── Stock Quotes ──"|"── Export / Backup ──"|"── View / Search ──"|"── Stock Name List ──"|"── Schema ──")
                continue ;;

            "Enter Stock Quotes  (Quick / Form / CSV)")
                insert_custom_newspaper_quote ;;

            "Insert Black Monday  Oct 28 1929")
                ensure_partition_for_date "1929-10-28"
                gum spin --title "Inserting Black Monday data..." -- \
                $PSQL "
                    INSERT INTO newspaper_stock_quotes
                        (quote_date, stock_name, year_high, year_low, dividend, sales_100s,
                         daily_high, daily_low, daily_close, previous_close)
                    VALUES
                        ('1929-10-28', 'US Steel',         261.00, 166.00, '2.00', 4520, 210.00, 195.00, 205.50, NULL),
                        ('1929-10-28', 'General Electric', 396.00, 201.00, '8.00', 6740, 240.00, 220.00, 225.75, NULL),
                        ('1929-10-28', 'AT&T',             304.00, 222.00, '9.00', 5210, 230.00, 215.00, 218.50, NULL),
                        ('1929-10-28', 'Westinghouse',     289.00, 140.00, '4.00', 3180, 190.00, 175.00, 182.25, NULL),
                        ('1929-10-28', 'Radio Corp',       114.00,  26.00,  NULL,  8920,  68.00,  55.00,  61.75, NULL),
                        ('1929-10-28', 'Montgomery Ward',  156.00,  50.00, '2.00', 2140,  92.00,  82.00,  85.50, NULL),
                        ('1929-10-28', 'Anaconda Copper',  132.00,  60.00, '3.00', 4560,  78.00,  70.00,  72.25, NULL),
                        ('1929-10-28', 'Chrysler',         135.00,  55.00, '3.00', 3120,  78.00,  68.00,  71.50, NULL),
                        ('1929-10-28', 'General Motors',   225.00,  80.00, '3.00', 5280, 132.00, 118.00, 122.75, NULL),
                        ('1929-10-28', 'New York Central', 192.00, 110.00, '4.00', 1840, 138.00, 125.00, 130.25, NULL),
                        ('1929-10-28', 'Pennsylvania RR',  110.00,  65.00, '3.00', 2650,  82.00,  74.00,  77.50, NULL),
                        ('1929-10-28', 'Union Carbide',    148.00,  85.00, '2.00', 1420, 105.00,  96.00,  99.75, NULL)
                    ON CONFLICT (quote_date, stock_name) DO UPDATE SET
                        year_high=EXCLUDED.year_high, year_low=EXCLUDED.year_low,
                        dividend=EXCLUDED.dividend, sales_100s=EXCLUDED.sales_100s,
                        daily_high=EXCLUDED.daily_high, daily_low=EXCLUDED.daily_low,
                        daily_close=EXCLUDED.daily_close, previous_close=EXCLUDED.previous_close;
                "
                success "Black Monday (Oct 28 1929) data inserted." ;;

            "Insert Black Tuesday Oct 29 1929")
                ensure_partition_for_date "1929-10-29"
                gum spin --title "Inserting Black Tuesday data..." -- \
                $PSQL "
                    INSERT INTO newspaper_stock_quotes
                        (quote_date, stock_name, year_high, year_low, dividend, sales_100s,
                         daily_high, daily_low, daily_close, previous_close)
                    VALUES
                        ('1929-10-29', 'US Steel',         261.00, 166.00, '2.00', 6120, 197.00, 167.00, 174.50, 205.50),
                        ('1929-10-29', 'General Electric', 396.00, 201.00, '8.00', 9850, 221.00, 188.00, 195.00, 225.75),
                        ('1929-10-29', 'AT&T',             304.00, 222.00, '9.00', 7340, 214.00, 197.00, 204.00, 218.50),
                        ('1929-10-29', 'Westinghouse',     289.00, 140.00, '4.00', 4210, 174.00, 150.00, 155.25, 182.25),
                        ('1929-10-29', 'Radio Corp',       114.00,  26.00,  NULL, 11540,  58.00,  40.00,  44.50,  61.75),
                        ('1929-10-29', 'Montgomery Ward',  156.00,  50.00, '2.00', 3190,  80.00,  64.00,  68.75,  85.50),
                        ('1929-10-29', 'Anaconda Copper',  132.00,  60.00, '3.00', 5870,  68.00,  55.00,  58.00,  72.25),
                        ('1929-10-29', 'Chrysler',         135.00,  55.00, '3.00', 4480,  65.00,  52.00,  55.75,  71.50),
                        ('1929-10-29', 'General Motors',   225.00,  80.00, '3.00', 7120, 120.00,  98.00, 103.00, 122.75),
                        ('1929-10-29', 'New York Central', 192.00, 110.00, '4.00', 2670, 125.00, 108.00, 112.50, 130.25),
                        ('1929-10-29', 'Pennsylvania RR',  110.00,  65.00, '3.00', 3910,  72.00,  60.00,  63.25,  77.50),
                        ('1929-10-29', 'Union Carbide',    148.00,  85.00, '2.00', 2180,  93.00,  79.00,  82.50,  99.75)
                    ON CONFLICT (quote_date, stock_name) DO UPDATE SET
                        year_high=EXCLUDED.year_high, year_low=EXCLUDED.year_low,
                        dividend=EXCLUDED.dividend, sales_100s=EXCLUDED.sales_100s,
                        daily_high=EXCLUDED.daily_high, daily_low=EXCLUDED.daily_low,
                        daily_close=EXCLUDED.daily_close, previous_close=EXCLUDED.previous_close;
                "
                success "Black Tuesday (Oct 29 1929) data inserted." ;;

            # ── SQL FILE IMPORT ───────────────────────────
            "Import from SQL file  (.sql)")
                section_header "📂 Import SQL File"
                gum style --foreground 212 --bold "This runs a .sql file directly against the database."
                gum style --foreground 244 \
                    "  • The file must contain valid PostgreSQL SQL" \
                    "  • It must handle partition creation itself (or run after partitions exist)" \
                    "  • Use ON CONFLICT DO UPDATE to avoid duplicate errors" \
                    "  • Tip: use the generated 1929-10-28_nyse.sql as a template"
                echo
                local sql_path
                sql_path=$(gum input --placeholder "Full path to .sql file  e.g. ~/1929-10-28_nyse.sql" --width 80)
                sql_path="${sql_path/#\~/$HOME}"
                [[ -z "$sql_path" ]] && { info "Cancelled."; pause; continue; }
                if [[ ! -f "$sql_path" ]]; then
                    error "File not found: $sql_path"
                    pause; continue
                fi
                local line_count
                line_count=$(wc -l < "$sql_path")
                info "File: $sql_path  ($line_count lines)"
                echo
                if confirm "Run this SQL file against database '$PSQL_DB'?"; then
                    local result
                    result=$(psql -X --username="$PSQL_USER" --dbname="$PSQL_DB" \
                        --set ON_ERROR_STOP=1 \
                        -f "$sql_path" 2>&1)
                    local rc=$?
                    if [[ $rc -eq 0 ]]; then
                        success "✅ SQL file executed successfully."
                        # Show row count as proof
                        local cnt
                        cnt=$(psql -X --username="$PSQL_USER" --dbname="$PSQL_DB" \
                            --tuples-only -c "SELECT COUNT(*) FROM newspaper_stock_quotes;" 2>/dev/null | tr -d ' ')
                        info "Total rows in newspaper_stock_quotes: $cnt"
                    else
                        error "SQL execution failed (exit $rc):"
                        echo "$result" | tail -20
                    fi
                else
                    info "Cancelled."
                fi ;;

            # ── EXPORT / BACKUP ──────────────────────────
            "Export Stock Quotes to CSV  (all dates)")
                mkdir -p "$EXPORT_DIR"
                local ts fname
                ts=$(date +%Y%m%d_%H%M%S)
                fname="$EXPORT_DIR/stock_quotes_ALL_${ts}.csv"
                gum spin --title "Exporting all stock quotes..." -- \
                    psql -X --username="$PSQL_USER" --dbname="$PSQL_DB" \
                        -c "\COPY (SELECT quote_date, stock_name, year_high, year_low, dividend, sales_100s, daily_high, daily_low, daily_close, previous_close FROM newspaper_stock_quotes ORDER BY quote_date, stock_name) TO '$fname' WITH CSV HEADER"
                local cnt; cnt=$(wc -l < "$fname")
                success "✅ Exported $((cnt-1)) rows to:"
                info "   $fname" ;;

            "Export Stock Quotes to CSV  (date range)")
                mkdir -p "$EXPORT_DIR"
                local d1 d2 fname ts
                d1=$(gum input --placeholder "Start date (YYYY-MM-DD)" --value "1929-10-28")
                d2=$(gum input --placeholder "End date   (YYYY-MM-DD)" --value "1929-10-28")
                [[ -z "$d1" || -z "$d2" ]] && { pause; continue; }
                ts=$(date +%Y%m%d_%H%M%S)
                fname="$EXPORT_DIR/stock_quotes_${d1}_to_${d2}_${ts}.csv"
                gum spin --title "Exporting $d1 → $d2..." -- \
                    psql -X --username="$PSQL_USER" --dbname="$PSQL_DB" \
                        -c "\COPY (SELECT quote_date, stock_name, year_high, year_low, dividend, sales_100s, daily_high, daily_low, daily_close, previous_close FROM newspaper_stock_quotes WHERE quote_date BETWEEN '$d1' AND '$d2' ORDER BY quote_date, stock_name) TO '$fname' WITH CSV HEADER"
                local cnt; cnt=$(wc -l < "$fname")
                success "✅ Exported $((cnt-1)) rows to:"
                info "   $fname" ;;

            "Export Stock Quotes to CSV  (single date)")
                mkdir -p "$EXPORT_DIR"
                local qdate fname ts
                qdate=$(gum input --placeholder "Date (YYYY-MM-DD)" --value "1929-10-28")
                [[ -z "$qdate" ]] && { pause; continue; }
                ts=$(date +%Y%m%d_%H%M%S)
                fname="$EXPORT_DIR/stock_quotes_${qdate}_${ts}.csv"
                gum spin --title "Exporting $qdate..." -- \
                    psql -X --username="$PSQL_USER" --dbname="$PSQL_DB" \
                        -c "\COPY (SELECT quote_date, stock_name, year_high, year_low, dividend, sales_100s, daily_high, daily_low, daily_close, previous_close FROM newspaper_stock_quotes WHERE quote_date = '$qdate' ORDER BY stock_name) TO '$fname' WITH CSV HEADER"
                local cnt; cnt=$(wc -l < "$fname")
                success "✅ Exported $((cnt-1)) rows to:"
                info "   $fname" ;;

            "List existing exports")
                echo
                gum style --bold "Export directory: $EXPORT_DIR"
                echo
                ls -lht "$EXPORT_DIR" 2>/dev/null | head -30 || info "No exports yet." ;;

            # ── VIEW / SEARCH ─────────────────────────────
            "Browse All Quotes")
                psql -X --username="$PSQL_USER" --dbname="$PSQL_DB" --tuples-only -x -c "
                    SELECT quote_date, stock_name, daily_high, daily_low, daily_close,
                           previous_close, year_high, year_low, dividend, sales_100s
                    FROM newspaper_stock_quotes
                    ORDER BY quote_date DESC, stock_name
                    LIMIT 100;" ;;

            "Search Quotes by Stock")
                local sname; sname=$(pick_stock_name)
                [[ -z "$sname" ]] && { pause; continue; }
                psql -X --username="$PSQL_USER" --dbname="$PSQL_DB" -c "
                    SELECT quote_date, daily_high, daily_low, daily_close,
                           previous_close, year_high, year_low, dividend, sales_100s
                    FROM newspaper_stock_quotes
                    WHERE stock_name ILIKE '%$sname%'
                    ORDER BY quote_date DESC;" ;;

            "Search Quotes by Date")
                local qdate; qdate=$(gum input --placeholder "Date (YYYY-MM-DD)" --value "1929-10-28")
                [[ -z "$qdate" ]] && { pause; continue; }
                psql -X --username="$PSQL_USER" --dbname="$PSQL_DB" -c "
                    SELECT stock_name, daily_high, daily_low, daily_close,
                           previous_close, dividend, sales_100s
                    FROM newspaper_stock_quotes
                    WHERE quote_date = '$qdate'
                    ORDER BY stock_name;" ;;

            # ── STOCK NAME LIST ──────────────────────────
            "View Stock Names File")
                _ensure_stock_names_file
                echo
                gum style --bold --foreground 212 "Stock names file: $STOCK_NAMES_FILE"
                echo
                local count
                count=$(grep -v '^\s*#' "$STOCK_NAMES_FILE" | grep -v '^\s*$' | wc -l | tr -d ' ')
                gum style --foreground 244 "  $count active names (# lines are comments)"
                echo
                while IFS= read -r line; do
                    if [[ "$line" =~ ^\s*# ]]; then
                        gum style --foreground 240 "  $line"
                    elif [[ -n "$line" ]]; then
                        gum style --foreground 33  "  $line"
                    fi
                done < "$STOCK_NAMES_FILE" ;;

            "Add Name to Stock Names File")
                _ensure_stock_names_file
                local newname
                newname=$(gum input --placeholder "Stock name to add  e.g. Bethlehem Steel Corporation")
                [[ -z "$newname" ]] && { pause; continue; }
                if grep -qi "^${newname}$" "$STOCK_NAMES_FILE" 2>/dev/null; then
                    warn "'$newname' is already in the names file."
                else
                    echo "$newname" >> "$STOCK_NAMES_FILE"
                    local hdr dat
                    hdr=$(grep '^\s*#' "$STOCK_NAMES_FILE")
                    dat=$(grep -v '^\s*#' "$STOCK_NAMES_FILE" | grep -v '^\s*$' | sort -u)
                    { echo "$hdr"; echo; echo "$dat"; } > "$STOCK_NAMES_FILE"
                    success "Added '$newname' to stock_names.txt."
                fi ;;

            "Edit Stock Names File")
                _ensure_stock_names_file
                local editor="${EDITOR:-nano}"
                info "Opening $STOCK_NAMES_FILE in $editor…"
                pause
                $editor "$STOCK_NAMES_FILE"
                local count
                count=$(grep -v '^\s*#' "$STOCK_NAMES_FILE" | grep -v '^\s*$' | wc -l | tr -d ' ')
                success "Saved — $count names active." ;;

            "Import Names from CSV column")
                _ensure_stock_names_file
                local csv_path
                csv_path=$(gum input --placeholder "Full path to CSV file")
                csv_path="${csv_path/#\~/$HOME}"
                [[ ! -f "$csv_path" ]] && { error "File not found: $csv_path"; pause; continue; }
                local header; header=$(head -1 "$csv_path")
                info "CSV header: $header"
                local col_name
                col_name=$(gum input --placeholder "Column header containing stock names (e.g. stock_name)")
                [[ -z "$col_name" ]] && { pause; continue; }
                local col_idx
                col_idx=$(echo "$header" | tr ',' '\n' | grep -in "$col_name" | head -1 | cut -d: -f1)
                if [[ -z "$col_idx" ]]; then
                    error "Column '$col_name' not found in header."
                    pause; continue
                fi
                local added=0
                while IFS=',' read -r -a fields; do
                    local nm; nm=$(echo "${fields[$((col_idx-1))]}" | xargs | tr -d '"')
                    [[ -z "$nm" ]] && continue
                    if ! grep -qi "^${nm}$" "$STOCK_NAMES_FILE" 2>/dev/null; then
                        echo "$nm" >> "$STOCK_NAMES_FILE"
                        (( added++ ))
                    fi
                done < <(tail -n +2 "$csv_path")
                local hdr dat
                hdr=$(grep '^\s*#' "$STOCK_NAMES_FILE")
                dat=$(grep -v '^\s*#' "$STOCK_NAMES_FILE" | grep -v '^\s*$' | sort -u)
                { echo "$hdr"; echo; echo "$dat"; } > "$STOCK_NAMES_FILE"
                success "Imported $added new names from $csv_path." ;;

            # ── SCHEMA ───────────────────────────────────
            "List Tables")
                $PSQL "
                    SELECT tablename FROM pg_tables
                    WHERE schemaname NOT IN ('pg_catalog','information_schema')
                    ORDER BY tablename;" | cat ;;

            "Describe newspaper_stock_quotes")
                psql -X --username="$PSQL_USER" --dbname="$PSQL_DB" -c "\d newspaper_stock_quotes" ;;

            "Back" | *)
                pop_breadcrumb
                CURRENT_MENU="main"
                return ;;
        esac
        pause
    done
}

##################
# Settings Menu  #
##################
settings_menu() {
    push_breadcrumb "Settings"
    while true; do
        section_header "⚙️ Settings"

        choice="$(gum choose \
            "View current config" \
            "Change database name" \
            "Change postgres user" \
            "Toggle verbose SQL output" \
            "Edit config file" \
            "Reset config to defaults" \
            "Back")"

        case "$choice" in
            "View current config")
                info "DB name:     $PSQL_DB"
                info "DB user:     $PSQL_USER"
                info "Repo dir:    $SITE_DIR"
                info "Export dir:  $EXPORT_DIR"
                info "Config file: $CONFIG_FILE"
                if [[ -f "$HOME/.ysf_verbose" ]]; then
                    info "Verbose SQL: ON"
                else
                    info "Verbose SQL: OFF"
                fi
                ;;

            "Change database name")
                local newdb
                newdb=$(gum input --placeholder "New database name" --value "$PSQL_DB")
                if [[ -n "$newdb" ]]; then
                    touch "$CONFIG_FILE"
                    sed -i "/^CONF_DB=/d" "$CONFIG_FILE"
                    echo "CONF_DB=$newdb" >> "$CONFIG_FILE"
                    success "Saved. Restart the script to apply."
                fi
                ;;

            "Change postgres user")
                local newuser
                newuser=$(gum input --placeholder "New postgres username" --value "$PSQL_USER")
                if [[ -n "$newuser" ]]; then
                    touch "$CONFIG_FILE"
                    sed -i "/^CONF_USER=/d" "$CONFIG_FILE"
                    echo "CONF_USER=$newuser" >> "$CONFIG_FILE"
                    success "Saved. Restart the script to apply."
                fi
                ;;

            "Toggle verbose SQL output")
                local flag="$HOME/.ysf_verbose"
                if [[ -f "$flag" ]]; then
                    rm "$flag"
                    info "Verbose SQL: OFF"
                else
                    touch "$flag"
                    info "Verbose SQL: ON"
                fi
                ;;

            "Edit config file")
                local editor="${EDITOR:-nano}"
                touch "$CONFIG_FILE"
                $editor "$CONFIG_FILE"
                load_config
                success "Config reloaded."
                ;;

            "Reset config to defaults")
                if confirm "Reset all settings to defaults? Config file will be deleted."; then
                    rm -f "$CONFIG_FILE" "$HOME/.ysf_verbose"
                    success "Config reset. Restart the script to apply."
                fi
                ;;

            "Back" | *)
                pop_breadcrumb
                CURRENT_MENU="main"
                return
                ;;
        esac
        pause
    done
}

############
# App Loop #
############
app_exit() {
    gum style --foreground 212 "Goodbye, $USER! 👋"
    exit 0
}


############################################################
#  📈  FINVIZ SCRAPER MENU                                 #
############################################################
# Manages dataminer.py — the Finviz → PostgreSQL live scraper.
# Files it manages (all relative to SCRIPT_DIR):
#   dataminer.py         — the scraper itself
#   active_tickers.txt   — confirmed-working symbols (maintained here)
#   blocked_tickers.txt  — rate-limited tickers from last log parse
#   delisted_tickers.txt — permanent 404s from last log parse
#   dataminer.log        — full run history
#   .dataminer_progress  — today's already-scraped tickers (for --resume)
#
# Rate-limit advice:
#   Finviz returns HTTP 200 with an error page (not a real 4xx) when it
#   blocks you.  The scraper detects "Snapshot table not found" in the HTML
#   and retries — but if every retry gets the same block, it gives up.
#   Fix: DELAY_MIN=5, DELAY_MAX=10, run overnight (2–6 AM local time).

finviz_menu() {
    push_breadcrumb "📈 Finviz Scraper"
    while true; do
        # ── live stats in header ────────────────────────────────────────────
        local py_ok="❌ not found"
        [[ -f "$DATAMINER_PY" ]] && py_ok="✅ found"

        local ticker_count=0
        [[ -f "$ACTIVE_TICKERS_FILE" ]] && \
            ticker_count=$(grep -v '^\s*#' "$ACTIVE_TICKERS_FILE" \
                           | grep -v '^\s*$' | wc -l | tr -d ' ')

        local today_date; today_date=$(date +%Y-%m-%d)
        local today_count=0
        [[ -f "$DATAMINER_PROGRESS" ]] && \
            today_count=$(grep -c "^${today_date}" "$DATAMINER_PROGRESS" 2>/dev/null \
                          || echo 0)

        section_header \
            "📈 Finviz Scraper  │  ${py_ok}  │  tickers: ${ticker_count}  │  done today: ${today_count}"

        choice="$(gum choose \
            "── Run Scraper ──" \
            "▶  Resume today  (skip already-done tickers)" \
            "▶  Full pass     (all active tickers)" \
            "▶  Spot-check    (type specific tickers)" \
            "── Ticker List ──" \
            "Build active_tickers.txt from progress file" \
            "View active_tickers.txt" \
            "Parse log → extract blocked & delisted tickers" \
            "Add a ticker to active list" \
            "Remove a ticker from active list" \
            "── Log & Progress ──" \
            "View last 50 log lines" \
            "View today progress" \
            "Clear today progress  (force full re-run today)" \
            "── Database ──" \
            "Row count & date range in stock_quote" \
            "Browse latest quotes" \
"Create / refresh latest_quotes API view" \
            "── Settings ──" \
            "Show scraper settings & rate-limit advice" \
            "Edit dataminer.py" \
            "Cron schedule helper" \
            "Back")"

        case "$choice" in
            "── Run Scraper ──"|"── Ticker List ──"|"── Log & Progress ──"|"── Database ──"|"── Settings ──")
                continue ;;

            # ── RUN SCRAPER ─────────────────────────────────────────────────
            "▶  Resume today  (skip already-done tickers)")
                if [[ ! -f "$DATAMINER_PY" ]]; then
                    error "dataminer.py not found: $DATAMINER_PY"
                    pause; continue
                fi
                gum style --foreground 244 \
                    "Skipping tickers already completed today." \
                    "Ctrl+C stops safely — progress is saved after each ticker."
                echo
                python3 "$DATAMINER_PY" --resume
                local rc=$?
                if [[ $rc -eq 0 ]]; then
                    success "Scrape completed."
                    # Nudge PostgREST to reload schema if it's running
                    psql -X --username="$PSQL_USER" --dbname="$PSQL_DB" \
                         -c "NOTIFY pgrst, 'reload schema';" >/dev/null 2>&1 || true
                else
                    warn "Exited with code $rc — progress was saved; use Resume to continue."
                fi ;;

            "▶  Full pass     (all active tickers)")
                if [[ ! -f "$DATAMINER_PY" ]]; then
                    error "dataminer.py not found: $DATAMINER_PY"
                    pause; continue
                fi
                warn "Ignores today's progress and re-scrapes all ${ticker_count} tickers."
                if confirm "Start full pass?"; then
                    python3 "$DATAMINER_PY"
                    success "Full pass complete."
                fi ;;

            "▶  Spot-check    (type specific tickers)")
                if [[ ! -f "$DATAMINER_PY" ]]; then
                    error "dataminer.py not found: $DATAMINER_PY"
                    pause; continue
                fi
                local tickers_input
                tickers_input=$(gum input \
                    --placeholder "Space-separated symbols  e.g. AAPL MSFT NVDA" \
                    --width 70)
                [[ -z "$tickers_input" ]] && { pause; continue; }
                # shellcheck disable=SC2086
                python3 "$DATAMINER_PY" --ticker $tickers_input ;;

            # ── TICKER LIST ──────────────────────────────────────────────────
            "Build active_tickers.txt from progress file")
                if [[ ! -f "$DATAMINER_PROGRESS" ]]; then
                    error "No progress file at: $DATAMINER_PROGRESS"
                    info  "Run the scraper at least once first."
                    pause; continue
                fi
                info "Extracting confirmed-working tickers from progress file…"
                python3 - << PYEOF
import os
prog = "${DATAMINER_PROGRESS}"
out  = "${ACTIVE_TICKERS_FILE}"
with open(prog) as f:
    tickers = sorted(set(
        line.split('\t')[1].strip()
        for line in f if '\t' in line and line.strip()
    ))
with open(out, 'w') as f:
    f.write("# active_tickers.txt — Finviz symbols confirmed working\n")
    f.write(f"# Auto-built from .dataminer_progress  |  {len(tickers)} tickers\n\n")
    f.write("\n".join(tickers) + "\n")
print(f"Written {len(tickers)} tickers → {out}")
PYEOF
                success "active_tickers.txt rebuilt." ;;

            "View active_tickers.txt")
                if [[ ! -f "$ACTIVE_TICKERS_FILE" ]]; then
                    warn "No active_tickers.txt yet — run Build first."; pause; continue
                fi
                echo
                gum style --bold "File: $ACTIVE_TICKERS_FILE"
                local cnt; cnt=$(grep -v '^\s*#' "$ACTIVE_TICKERS_FILE" \
                                  | grep -v '^\s*$' | wc -l | tr -d ' ')
                gum style --foreground 244 "  $cnt active tickers"
                echo
                grep -v '^\s*#' "$ACTIVE_TICKERS_FILE" | grep -v '^\s*$' | \
                    awk '{printf "%-10s", $0; if(NR%10==0) print ""}
                         END{if(NR%10!=0) print ""}' | head -80 ;;

            "Parse log → extract blocked & delisted tickers")
                if [[ ! -f "$DATAMINER_LOG" ]]; then
                    error "No log file at: $DATAMINER_LOG"
                    info  "Run the scraper to generate logs."; pause; continue
                fi
                info "Parsing $DATAMINER_LOG …"
                python3 - << PYEOF
import re, os

log_path      = "${DATAMINER_LOG}"
script_dir    = "${SCRIPT_DIR}"
blocked_file  = os.path.join(script_dir, "blocked_tickers.txt")
delisted_file = os.path.join(script_dir, "delisted_tickers.txt")

with open(log_path, encoding="utf-8", errors="replace") as f:
    log = f.read()

# Snapshot-blocked = rate-limited (server returns 200 but no data)
blocked = sorted(set(re.findall(
    r'ERROR\s+↳\s+([A-Z0-9.\$\-]+):\s+gave up after \d+ attempts.*Snapshot',
    log)))

# Permanently dead tickers (404 / 410)
delisted = sorted(set(re.findall(
    r'WARNING\s+↳\s+([A-Z0-9.\$\-]+):\s+HTTP 40[0-9].*skipping',
    log)))

with open(blocked_file, "w") as f:
    f.write("# blocked_tickers.txt — rate-limited by Finviz\n")
    f.write("# These MAY work with slower delays or at a later time\n")
    f.write(f"# Total: {len(blocked)}\n\n")
    f.write("\n".join(blocked) + "\n")

with open(delisted_file, "w") as f:
    f.write("# delisted_tickers.txt — permanent 404 on Finviz\n")
    f.write("# Remove these from active_tickers.txt\n")
    f.write(f"# Total: {len(delisted)}\n\n")
    f.write("\n".join(delisted) + "\n")

print(f"Rate-limited / blocked : {len(blocked):>5}  ->  blocked_tickers.txt")
print(f"404 / delisted         : {len(delisted):>5}  ->  delisted_tickers.txt")
if blocked[:5]:
    print(f"\nTop blocked (try again later): {blocked[:10]}")
if delisted[:5]:
    print(f"Top delisted (remove forever): {delisted[:10]}")
PYEOF
                echo
                gum style --foreground 244 \
                    "  blocked_tickers.txt  = throttled; try again later or with longer delays" \
                    "  delisted_tickers.txt = permanently gone; remove from active list"
                echo
                if [[ -f "${SCRIPT_DIR}/delisted_tickers.txt" ]]; then
                    if confirm "Auto-remove delisted tickers from active_tickers.txt?"; then
                        python3 - << PYEOF
import os
script_dir    = "${SCRIPT_DIR}"
delisted_file = os.path.join(script_dir, "delisted_tickers.txt")
active_file   = os.path.join(script_dir, "active_tickers.txt")

if not os.path.exists(delisted_file):
    print("delisted_tickers.txt not found.")
elif not os.path.exists(active_file):
    print("active_tickers.txt not found — nothing to clean.")
else:
    with open(delisted_file) as f:
        dead = {l.strip() for l in f if l.strip() and not l.startswith("#")}
    with open(active_file) as f:
        lines = f.readlines()
    before = sum(1 for l in lines if l.strip() and not l.startswith("#"))
    kept   = [l for l in lines
              if l.startswith("#") or not l.strip() or l.strip() not in dead]
    after  = sum(1 for l in kept if l.strip() and not l.startswith("#"))
    with open(active_file, "w") as f:
        f.writelines(kept)
    print(f"Removed {before - after} delisted symbols.  Active now: {after}")
PYEOF
                        success "active_tickers.txt cleaned."
                    fi
                fi ;;

            "Add a ticker to active list")
                local new_t
                new_t=$(gum input --placeholder "Ticker  e.g. NVDA" | tr '[:lower:]' '[:upper:]' | xargs)
                [[ -z "$new_t" ]] && { pause; continue; }
                if grep -qx "$new_t" "$ACTIVE_TICKERS_FILE" 2>/dev/null; then
                    warn "$new_t is already in active_tickers.txt"
                else
                    echo "$new_t" >> "$ACTIVE_TICKERS_FILE"
                    success "Added $new_t"
                fi ;;

            "Remove a ticker from active list")
                if [[ ! -f "$ACTIVE_TICKERS_FILE" ]]; then
                    warn "No active_tickers.txt yet."; pause; continue
                fi
                local rem_t
                rem_t=$(grep -v '^\s*#' "$ACTIVE_TICKERS_FILE" | grep -v '^\s*$' | \
                        gum filter --placeholder "Fuzzy search to pick ticker…")
                [[ -z "$rem_t" ]] && { pause; continue; }
                if confirm "Remove $rem_t from active_tickers.txt?"; then
                    sed -i "/^${rem_t}$/d" "$ACTIVE_TICKERS_FILE"
                    success "Removed $rem_t"
                fi ;;

            # ── LOG & PROGRESS ───────────────────────────────────────────────
            "View last 50 log lines")
                if [[ ! -f "$DATAMINER_LOG" ]]; then
                    warn "No log file yet."; pause; continue
                fi
                echo
                gum style --bold "Tail of $DATAMINER_LOG"
                echo
                tail -50 "$DATAMINER_LOG" ;;

            "View today progress")
                if [[ ! -f "$DATAMINER_PROGRESS" ]]; then
                    warn "No progress file yet."; pause; continue
                fi
                local done_today; done_today=$(grep -c "^${today_date}" \
                    "$DATAMINER_PROGRESS" 2>/dev/null || echo 0)
                echo
                gum style --bold "Tickers scraped today (${today_date}): $done_today"
                echo
                grep "^${today_date}" "$DATAMINER_PROGRESS" | cut -f2 | \
                    awk '{printf "%-10s", $0; if(NR%10==0) print ""}
                         END{if(NR%10!=0) print ""}' | head -80 ;;

            "Clear today progress  (force full re-run today)")
                warn "Next run will re-scrape all ${ticker_count} active tickers from scratch."
                if confirm "Delete today's (${today_date}) progress entries?"; then
                    sed -i "/^${today_date}/d" "$DATAMINER_PROGRESS" 2>/dev/null || true
                    success "Today's progress cleared."
                fi ;;

            # ── DATABASE ─────────────────────────────────────────────────────
            "Row count & date range in stock_quote")
                echo
                $PSQL "
                    SELECT
                        COUNT(*)                             AS total_rows,
                        COUNT(DISTINCT symbol)               AS unique_symbols,
                        COUNT(DISTINCT time_recorded::date)  AS distinct_days,
                        MIN(time_recorded)                   AS earliest,
                        MAX(time_recorded)                   AS latest
                    FROM stock_quote;" | cat ;;

            "Browse latest quotes")
                local sym
                sym=$(gum input \
                    --placeholder "Symbol for history, or blank for top-20 latest" \
                    | tr '[:lower:]' '[:upper:]' | xargs)
                if [[ -n "$sym" ]]; then
                    $PSQL "
                        SELECT time_recorded,
                               current_stock_price AS price,
                               market_capitalization AS mkt_cap,
                               price_to_earnings_ttm AS pe,
                               volume,
                               performance_today AS chg
                        FROM stock_quote
                        WHERE symbol = '$sym'
                        ORDER BY time_recorded DESC
                        LIMIT 10;" | cat
                else
                    $PSQL "
                        SELECT DISTINCT ON (symbol)
                               symbol,
                               time_recorded,
                               current_stock_price AS price,
                               market_capitalization AS mkt_cap,
                               performance_today AS chg
                        FROM stock_quote
                        ORDER BY symbol, time_recorded DESC
                        LIMIT 20;" | cat
                fi ;;


            "Create / refresh latest_quotes API view")
                info "Creating latest_quotes view for PostgREST API exposure…"
                psql -X --username="$PSQL_USER" --dbname="$PSQL_DB" << 'ENDSQL'
CREATE OR REPLACE VIEW latest_quotes AS
SELECT DISTINCT ON (symbol)
    symbol,
    time_recorded,
    current_stock_price,
    market_capitalization,
    price_to_earnings_ttm,
    diluted_earnings_per_share_ttm,
    gross_margin_ttm,
    net_profit_margin_ttm,
    return_on_equity,
    beta,
    volume,
    average_volume_3_month,
    relative_volume,
    relative_strength_index_14,
    performance_today,
    performance_week,
    performance_month,
    performance_year_to_date,
    analyst_mean_price,
    analyst_mean_recommendation_1_buy_5_sell,
    earnings_date,
    dividend_yield_annual_percentage,
    major_index_membership,
    week_range_52,
    distance_from_52_week_high,
    distance_from_52_week_low,
    distance_from_200_day_simple_moving_average
FROM stock_quote
ORDER BY symbol, time_recorded DESC;

COMMENT ON VIEW latest_quotes IS
    'Freshest row per ticker. Expose via PostgREST at /latest_quotes';
ENDSQL
                success "✅ latest_quotes view ready."
                info    "   Access via PostgREST: GET /latest_quotes"
                info    "   Filter example:       /latest_quotes?symbol=eq.AAPL"
                # Reload PostgREST schema cache if running
                psql -X --username="$PSQL_USER" --dbname="$PSQL_DB" \
                     -c "NOTIFY pgrst, 'reload schema';" >/dev/null 2>&1 || true ;;

            # ── SETTINGS ─────────────────────────────────────────────────────
            "Show scraper settings & rate-limit advice")
                echo
                gum style --bold --foreground 212 "── Paths ────────────────────────────────"
                info "  dataminer.py    : $DATAMINER_PY"
                info "  active tickers  : $ACTIVE_TICKERS_FILE  (${ticker_count} symbols)"
                info "  log file        : $DATAMINER_LOG"
                info "  progress file   : $DATAMINER_PROGRESS  (${today_count} done today)"
                echo
                gum style --bold --foreground 212 "── Recommended dataminer.py settings ────"
                gum style --foreground 76  "  DELAY_MIN  = 5.0    # never go below 5 s"
                gum style --foreground 76  "  DELAY_MAX  = 10.0   # random ceiling"
                gum style --foreground 76  "  MAX_RETRIES = 5     # more patience per ticker"
                echo
                gum style --bold --foreground 212 "── Rate-limit FAQ ───────────────────────"
                gum style --foreground 244 \
                    "  'Snapshot table not found' = Finviz returned an HTML block page." \
                    "  The scraper got HTTP 200 but no real data — it IS rate-limiting you." \
                    ""  \
                    "  Fixes (in order of effectiveness):" \
                    "  1. Increase DELAY_MIN / DELAY_MAX in dataminer.py" \
                    "  2. Run overnight (2–6 AM) when traffic is lowest" \
                    "  3. Use --resume to spread the run across multiple sessions" \
                    "  4. 'Parse log' here to identify which tickers were blocked," \
                    "     then retry just those with a spot-check run later" ;;

            "Edit dataminer.py")
                if [[ ! -f "$DATAMINER_PY" ]]; then
                    error "dataminer.py not found: $DATAMINER_PY"
                    pause; continue
                fi
                local editor="${EDITOR:-nano}"
                $editor "$DATAMINER_PY"
                success "dataminer.py saved." ;;

            "Cron schedule helper")
                section_header "Suggested Cron Entry"
                echo
                gum style --foreground 33 \
                    "# Run Finviz scraper weekday nights at 2:30 AM (low-traffic window)" \
                    "30 2 * * 1-5 cd ${SITE_DIR} && python3 backend/scraper/dataminer.py --resume >> backend/logs/dataminer.log 2>&1"
                echo
                gum style --foreground 244 \
                    "  Install: run 'crontab -e' and paste the line above." \
                    "  1-5 = Mon–Fri only (markets closed weekends)." \
                    "  --resume is safe to run multiple times — skips already-done tickers."
                echo
                if confirm "Copy cron line to clipboard?"; then
                    local cron_line="30 2 * * 1-5 cd ${SITE_DIR} && python3 backend/scraper/dataminer.py --resume >> backend/logs/dataminer.log 2>&1"
                    if command -v xclip &>/dev/null; then
                        echo "$cron_line" | xclip -selection clipboard && success "Copied."
                    elif command -v xsel &>/dev/null; then
                        echo "$cron_line" | xsel --clipboard --input && success "Copied."
                    else
                        warn "xclip/xsel not found — copy from above manually."
                    fi
                fi ;;

            "Back" | *)
                pop_breadcrumb
                CURRENT_MENU="main"
                return ;;
        esac
        pause
    done
}



####################################################
#  📰  YourStockForecast.com — Site Management    #
####################################################
# Manages the standalone YSF website project.
# Requires: hugo, python3, rsync (for deploy)
# YSF_DIR should point to the project root.

ysf_menu() {
    push_breadcrumb "📰 YourStockForecast"
    while true; do
        # ── Live status ───────────────────────────────────────────────────
        local ysf_dir; ysf_dir="${SCRIPT_DIR}"
        local hugo_ok="❌ hugo not found"
        command -v hugo &>/dev/null && hugo_ok="✅ $(hugo version 2>/dev/null | grep -oP 'v\d+\.\d+\.\d+' | head -1)"
        local postgrest_status="🔴 stopped"
        postgrest_is_running 2>/dev/null && postgrest_status="🟢 running"
        local site_exists="❌ not found"
        [[ -d "${ysf_dir}/frontend/hugo-site" ]] && site_exists="✅ ${ysf_dir}"

        section_header "📰 YourStockForecast  │  Hugo: ${hugo_ok}  │  PostgREST: ${postgrest_status}"

        choice="$(gum choose \
            "── Project Setup ──" \
            "📁 Set / Change YSF Project Directory" \
            "🚀 Bootstrap New YSF Project" \
            "Install Hugo (check / download)" \
            "── Data Pipeline ──" \
            "▶  Run Dataminer (Finviz → PostgreSQL)" \
            "▶  Resume Dataminer (skip today's done)" \
            "Generate Hugo Data Files from PostgreSQL" \
            "Generate Stock Page Stubs Only" \
            "Show Last Scrape Status" \
            "── Hugo Build ──" \
            "▶  Hugo Dev Server  (localhost:1313)" \
            "▶  Full Build  (data + hugo + deploy)" \
            "▶  Data + Build Only  (no deploy)" \
            "▶  Deploy Only  (rsync existing build)" \
            "View Build Log" \
            "── PostgREST SQL ──" \
            "Create market_summary() & sector_performance() functions" \
            "Reload PostgREST Schema Cache" \
            "Test API — market summary" \
            "Test API — top gainers" \
            "── Content Management ──" \
            "Count Stock Pages Generated" \
            "List Most Recent Scrape Data" \
            "Open Hugo Config" \
            "── VPS Deployment ──" \
            "Set VPS Host / Credentials" \
            "Test SSH Connection to VPS" \
            "Copy Nginx Config to VPS" \
            "Install PostgREST systemd Service on VPS" \
            "── Cron Jobs ──" \
            "Show Recommended Cron Schedule" \
            "Install Cron Jobs" \
            "Back")"

        case "$choice" in
            "── Project Setup ──"|"── Data Pipeline ──"|"── Hugo Build ──"|"── PostgREST SQL ──"|"── Content Management ──"|"── VPS Deployment ──"|"── Cron Jobs ──")
                continue ;;

            # ── PROJECT SETUP ────────────────────────────────────────────────
            "📁 Set / Change YSF Project Directory")
                local new_dir
                new_dir=$(gum input \
                    --placeholder "Full path to YSF project root" \
                    --value "${ysf_dir}" --width 70)
                [[ -z "$new_dir" ]] && { pause; continue; }
                sed -i "/^YSF_DIR=/d" "$CONFIG_FILE" 2>/dev/null || true
                echo "YSF_DIR=${new_dir}" >> "$CONFIG_FILE"
                success "YSF project directory set to: ${new_dir}" ;;

            "🚀 Bootstrap New YSF Project")
                ysf_bootstrap ;;

            "Install Hugo (check / download)")
                ysf_install_hugo ;;

            # ── DATA PIPELINE ────────────────────────────────────────────────
            "▶  Run Dataminer (Finviz → PostgreSQL)")
                local py="${DATAMINER_PY}"
                if [[ ! -f "$py" ]]; then
                    warn "dataminer.py not found at: $py"
                    info "Run 'Bootstrap New YSF Project' first, or check the path."
                    pause; continue
                fi
                gum style --foreground 244 \
                    "Running full dataminer pass (all active tickers)…" \
                    "Ctrl+C to stop safely — progress is saved after each ticker."
                echo
                python3 "$py"
                success "Dataminer run complete." ;;

            "▶  Resume Dataminer (skip today's done)")
                local py="${DATAMINER_PY}"
                [[ ! -f "$py" ]] && { error "dataminer.py not found: $py"; pause; continue; }
                python3 "$py" --resume ;;

            "Generate Hugo Data Files from PostgreSQL")
                local gen="${ysf_dir}/scripts/generate_hugo_data.py"
                [[ ! -f "$gen" ]] && { error "generate_hugo_data.py not found: $gen"; pause; continue; }
                info "Generating snapshot.json, sectors.json, and stock page stubs…"
                YSF_DIR="${ysf_dir}" YSF_DB="${PSQL_DB}" YSF_USER="${PSQL_USER}" python3 "$gen"
                success "Hugo data generation complete." ;;

            "Generate Stock Page Stubs Only")
                local gen="${ysf_dir}/scripts/generate_hugo_data.py"
                [[ ! -f "$gen" ]] && { error "generate_hugo_data.py not found: $gen"; pause; continue; }
                info "Generating content/stocks/*.md stubs…"
                YSF_DIR="${ysf_dir}" YSF_DB="${PSQL_DB}" YSF_USER="${PSQL_USER}" python3 "$gen" --pages-only
                success "Stock page stubs generated." ;;

            "Show Last Scrape Status")
                local status_file="${ysf_dir}/frontend/hugo-site/data/scrape_status.json"
                if [[ -f "$status_file" ]]; then
                    echo
                    gum style --bold "Last Scrape Status"
                    echo
                    cat "$status_file" | python3 -m json.tool 2>/dev/null || cat "$status_file"
                else
                    warn "No scrape_status.json found yet. Run the dataminer first."
                fi ;;

            # ── HUGO BUILD ───────────────────────────────────────────────────
            "▶  Hugo Dev Server  (localhost:1313)")
                if ! command -v hugo &>/dev/null; then
                    error "hugo not found in PATH. Use 'Install Hugo' option."
                    pause; continue
                fi
                local site="${ysf_dir}/frontend/hugo-site"
                [[ ! -d "$site" ]] && { error "Hugo site not found at: $site"; pause; continue; }
                info "Starting Hugo dev server at http://localhost:1313"
                info "PostgREST should be running at localhost:3000"
                info "Ctrl+C to stop the dev server."
                echo
                cd "$site" && hugo server --disableFastRender --bind 0.0.0.0 -p 1313
                cd "$SCRIPT_DIR" ;;

            "▶  Full Build  (data + hugo + deploy)")
                local build="${ysf_dir}/scripts/build.sh"
                [[ ! -f "$build" ]] && { error "build.sh not found: $build"; pause; continue; }
                warn "This will build the site AND deploy to VPS if VPS_HOST is set."
                if confirm "Run full build + deploy?"; then
                    bash "$build"
                fi ;;

            "▶  Data + Build Only  (no deploy)")
                local build="${ysf_dir}/scripts/build.sh"
                [[ ! -f "$build" ]] && { error "build.sh not found: $build"; pause; continue; }
                bash "$build" --data-only ;;

            "▶  Deploy Only  (rsync existing build)")
                local build="${ysf_dir}/scripts/build.sh"
                [[ ! -f "$build" ]] && { error "build.sh not found: $build"; pause; continue; }
                bash "$build" --deploy-only ;;

            "View Build Log")
                local log_f="${DATAMINER_LOG}"
                if [[ -f "$log_f" ]]; then
                    tail -n 60 "$log_f"
                else
                    warn "No dataminer log found at: $log_f"
                fi ;;

            # ── POSTGREST SQL ─────────────────────────────────────────────────
            "Create market_summary() & sector_performance() functions")
                info "Creating market_summary() and sector_performance() SQL functions…"
                psql -X --username="$PSQL_USER" --dbname="$PSQL_DB" << 'SQL'
-- Market summary — called by GET /rpc/market_summary
CREATE OR REPLACE FUNCTION market_summary()
RETURNS JSON LANGUAGE sql STABLE SECURITY DEFINER AS $$
    SELECT json_build_object(
        'total_symbols',  COUNT(*),
        'advancing',      COUNT(*) FILTER (WHERE performance_today::NUMERIC > 0),
        'declining',      COUNT(*) FILTER (WHERE performance_today::NUMERIC < 0),
        'unchanged',      COUNT(*) FILTER (WHERE performance_today::NUMERIC = 0),
        'avg_change_pct', ROUND(AVG(performance_today::NUMERIC), 2),
        'last_updated',   MAX(time_recorded)
    )
    FROM latest_quotes
    WHERE performance_today IS NOT NULL AND current_stock_price IS NOT NULL;
$$;

-- Sector performance — called by GET /rpc/sector_performance
CREATE OR REPLACE FUNCTION sector_performance()
RETURNS TABLE(
    sector       TEXT,
    symbol_count BIGINT,
    avg_today    NUMERIC,
    avg_week     NUMERIC,
    avg_month    NUMERIC
)
LANGUAGE sql STABLE SECURITY DEFINER AS $$
    SELECT
        major_index_membership,
        COUNT(*),
        ROUND(AVG(performance_today::NUMERIC), 2),
        ROUND(AVG(performance_week::NUMERIC),  2),
        ROUND(AVG(performance_month::NUMERIC), 2)
    FROM latest_quotes
    WHERE major_index_membership IS NOT NULL
      AND major_index_membership != ''
      AND performance_today IS NOT NULL
    GROUP BY major_index_membership
    ORDER BY AVG(performance_today::NUMERIC) DESC NULLS LAST;
$$;

-- Grant access so anon (unauthenticated site visitors) can call them
GRANT EXECUTE ON FUNCTION market_summary()     TO anon;
GRANT EXECUTE ON FUNCTION sector_performance() TO anon;

-- Notify PostgREST to pick up the new functions
NOTIFY pgrst, 'reload schema';
SQL
                success "Functions created. PostgREST schema reloaded." ;;

            "Reload PostgREST Schema Cache")
                psql -X --username="$PSQL_USER" --dbname="$PSQL_DB" \
                     -c "NOTIFY pgrst, 'reload schema';" >/dev/null
                success "PostgREST schema cache reloaded." ;;

            "Test API — market summary")
                if ! postgrest_is_running; then warn "PostgREST not running."; pause; continue; fi
                local base; base=$(postgrest_base_url)
                echo
                gum style --bold "GET ${base}/rpc/market_summary"
                echo
                curl -s "${base}/rpc/market_summary" \
                     -H "Accept: application/json" --max-time 5 | \
                     python3 -m json.tool 2>/dev/null || echo "No response / jq not available" ;;

            "Test API — top gainers")
                if ! postgrest_is_running; then warn "PostgREST not running."; pause; continue; fi
                local base; base=$(postgrest_base_url)
                echo
                gum style --bold "GET ${base}/latest_quotes?order=performance_today.desc&limit=10"
                echo
                curl -s "${base}/latest_quotes?order=performance_today.desc&limit=10&select=symbol,current_stock_price,performance_today" \
                     -H "Accept: application/json" --max-time 5 | \
                     python3 -m json.tool 2>/dev/null || echo "No response" ;;

            # ── CONTENT MANAGEMENT ────────────────────────────────────────────
            "Count Stock Pages Generated")
                local stocks_dir="${ysf_dir}/frontend/hugo-site/content/stocks"
                if [[ -d "$stocks_dir" ]]; then
                    local cnt; cnt=$(find "$stocks_dir" -name "*.md" | wc -l | tr -d ' ')
                    success "${cnt} stock page stubs in ${stocks_dir}"
                else
                    warn "Stocks content directory not found. Run 'Bootstrap' or 'Generate Stubs'."
                fi ;;

            "List Most Recent Scrape Data")
                echo
                $PSQL "
                    SELECT symbol,
                           current_stock_price AS price,
                           performance_today   AS chg_pct,
                           time_recorded
                    FROM stock_quote
                    ORDER BY time_recorded DESC
                    LIMIT 20;" | cat ;;

            "Open Hugo Config")
                local cfg="${ysf_dir}/frontend/hugo-site/hugo.toml"
                if [[ ! -f "$cfg" ]]; then
                    warn "Hugo config not found at: $cfg"
                    pause; continue
                fi
                "${EDITOR:-nano}" "$cfg"
                success "Hugo config saved." ;;

            # ── VPS DEPLOYMENT ────────────────────────────────────────────────
            "Set VPS Host / Credentials")
                local env_file="${ysf_dir}/.env"
                [[ ! -f "$env_file" ]] && cp "${ysf_dir}/.env.example" "$env_file" 2>/dev/null || true
                local vps_host vps_user vps_path
                vps_host=$(gum input --placeholder "VPS hostname  e.g. yourstockforecast.com" --width 50)
                vps_user=$(gum input --placeholder "SSH user      e.g. deploy"                --value "deploy")
                vps_path=$(gum input --placeholder "Web root      e.g. /var/www/yourstockforecast" \
                                     --value "/var/www/yourstockforecast")
                if [[ -n "$vps_host" && -f "$env_file" ]]; then
                    sed -i "/^VPS_HOST=/d;/^VPS_USER=/d;/^VPS_PATH=/d" "$env_file"
                    {
                        echo "VPS_HOST=${vps_host}"
                        echo "VPS_USER=${vps_user}"
                        echo "VPS_PATH=${vps_path}"
                    } >> "$env_file"
                    success "VPS credentials saved to ${env_file}"
                fi ;;

            "Test SSH Connection to VPS")
                local env_file="${ysf_dir}/.env"
                local vps_host vps_user
                [[ -f "$env_file" ]] && source "$env_file"
                vps_host="${VPS_HOST:-}"
                vps_user="${VPS_USER:-deploy}"
                [[ -z "$vps_host" ]] && { warn "VPS_HOST not set. Use 'Set VPS Host' first."; pause; continue; }
                info "Testing SSH → ${vps_user}@${vps_host}…"
                if ssh -o ConnectTimeout=5 "${vps_user}@${vps_host}" "echo 'SSH OK'"; then
                    success "SSH connection successful."
                else
                    error "SSH connection failed. Check your host, user, and SSH key setup."
                fi ;;

            "Copy Nginx Config to VPS")
                local env_file="${ysf_dir}/.env"
                [[ -f "$env_file" ]] && source "$env_file"
                local vps_host="${VPS_HOST:-}"; local vps_user="${VPS_USER:-deploy}"
                [[ -z "$vps_host" ]] && { warn "VPS_HOST not set."; pause; continue; }
                local nginx_src="${ysf_dir}/nginx/yourstockforecast.conf"
                [[ ! -f "$nginx_src" ]] && { error "Nginx config not found: $nginx_src"; pause; continue; }
                scp "$nginx_src" \
                    "${vps_user}@${vps_host}:/tmp/yourstockforecast.conf"
                ssh "${vps_user}@${vps_host}" \
                    "sudo mv /tmp/yourstockforecast.conf /etc/nginx/sites-available/yourstockforecast.com && \
                     sudo ln -sf /etc/nginx/sites-available/yourstockforecast.com \
                                 /etc/nginx/sites-enabled/ && \
                     sudo nginx -t && sudo systemctl reload nginx"
                success "Nginx config deployed and reloaded." ;;

            "Install PostgREST systemd Service on VPS")
                local env_file="${ysf_dir}/.env"
                [[ -f "$env_file" ]] && source "$env_file"
                local vps_host="${VPS_HOST:-}"; local vps_user="${VPS_USER:-deploy}"
                [[ -z "$vps_host" ]] && { warn "VPS_HOST not set."; pause; continue; }
                local svc_src="${ysf_dir}/systemd/postgrest-ysf.service"
                [[ ! -f "$svc_src" ]] && { error "Service file not found: $svc_src"; pause; continue; }
                scp "$svc_src" "${vps_user}@${vps_host}:/tmp/"
                ssh "${vps_user}@${vps_host}" \
                    "sudo mv /tmp/postgrest-ysf.service /etc/systemd/system/ && \
                     sudo systemctl daemon-reload && \
                     sudo systemctl enable postgrest-ysf && \
                     sudo systemctl start  postgrest-ysf && \
                     sudo systemctl status postgrest-ysf --no-pager"
                success "PostgREST service installed and started on VPS." ;;

            # ── CRON JOBS ─────────────────────────────────────────────────────
            "Show Recommended Cron Schedule")
                echo
                gum style --bold --foreground 212 "Recommended crontab entries:"
                echo
                gum style --foreground 33 \
                    "# Finviz scraper — nightly Mon-Fri at 2:30 AM" \
                    "30 2 * * 1-5  cd ${ysf_dir} && python3 backend/scraper/dataminer.py --resume >> backend/logs/dataminer.log 2>&1" \
                    "" \
                    "# Rebuild Hugo with fresh data — 6:00 AM (after scrape)" \
                    "0  6 * * 1-5  cd ${ysf_dir} && ./scripts/build.sh --data-only >> /tmp/ysf-build.log 2>&1" \
                    "" \
                    "# Full rebuild + deploy on weekdays at 6:15 AM" \
                    "15 6 * * 1-5  cd ${ysf_dir} && ./scripts/build.sh >> /tmp/ysf-build.log 2>&1"
                echo
                info "Install: run 'crontab -e' and paste the lines above." ;;

            "Install Cron Jobs")
                local ysf_py="${DATAMINER_PY}"
                local build_sh="${ysf_dir}/scripts/build.sh"
                local cron_block="
# YourStockForecast.com — managed by YourStockForecast app.sh
30 2 * * 1-5  cd ${ysf_dir} && python3 ${ysf_py} --resume >> ${DATAMINER_LOG} 2>&1
0  6 * * 1-5  cd ${ysf_dir} && bash ${build_sh} --data-only >> /tmp/ysf-build.log 2>&1
# END YourStockForecast"
                warn "This will add 2 cron entries to your crontab."
                if confirm "Install cron jobs?"; then
                    (crontab -l 2>/dev/null | grep -v "YourStockForecast"; echo "$cron_block") | crontab -
                    success "Cron jobs installed. Verify with: crontab -l"
                fi ;;

            "Back" | *)
                pop_breadcrumb
                CURRENT_MENU="main"
                return ;;
        esac
        pause
    done
}

# ── Bootstrap: create the full YSF project skeleton ───────────────────────────
ysf_bootstrap() {
    section_header "🚀 Bootstrap YourStockForecast.com"

    local ysf_dir; ysf_dir="${SCRIPT_DIR}"
    gum style --foreground 244 \
        "This creates the YourStockForecast project folder alongside app.sh:" \
        "  ${ysf_dir}" \
        "" \
        "It will:" \
        "  1. Create the directory structure" \
        "  2. Confirm active_tickers.txt exists at backend/scraper/" \
        "  3. Create .env from the template" \
        "  4. Check for Hugo and PostgREST binaries"
    echo

    if ! confirm "Bootstrap YSF project at ${ysf_dir}?"; then return; fi

    # Create directory structure
    info "Creating directories…"
    for d in backend/scraper backend/historical backend/api backend/sql backend/logs \
              data/tickers data/pdfs data/historical \
              frontend/hugo-site/content/stocks frontend/hugo-site/content/sectors \
              frontend/hugo-site/content/market frontend/hugo-site/layouts/_default \
              frontend/hugo-site/layouts/partials frontend/hugo-site/static/js \
              frontend/hugo-site/static/css frontend/hugo-site/data \
              frontend/flutter-app docs scripts nginx systemd .github/workflows; do
        mkdir -p "${ysf_dir}/${d}"
    done
    success "Directory structure created."

    # Copy active tickers if available
    if [[ -f "${ACTIVE_TICKERS_FILE}" ]]; then
        # active_tickers.txt is already at data/tickers/active_tickers.txt
        local cnt; cnt=$(grep -v '^\s*#' "${ACTIVE_TICKERS_FILE}" | grep -v '^\s*$' | wc -l | tr -d ' ')
        success "Active tickers file present: ${cnt} symbols."
    else
        warn "active_tickers.txt not found at ${ACTIVE_TICKERS_FILE}"
        info  "  Run dataminer at least once to generate it, or copy your ticker list there."
        info  "  Generate it via: Finviz Scraper → Build active_tickers.txt"
    fi

    # Create .env
    if [[ ! -f "${ysf_dir}/.env" ]]; then
        cat > "${ysf_dir}/.env" << EOF
# YourStockForecast — environment config
DB_NAME=${PSQL_DB}
DB_USER=${PSQL_USER}
DB_HOST=localhost
DB_PORT=5432
DB_PASSWORD=

DELAY_MIN=5.0
DELAY_MAX=10.0
MAX_RETRIES=5
BLOCK_LIMIT=3
BLOCK_SLEEP=120

# Set when ready to deploy
VPS_HOST=
VPS_USER=deploy
VPS_PATH=/var/www/yourstockforecast
VPS_NGINX_RELOAD=true
BUILD_WEBHOOK=
EOF
        success ".env created."
    else
        info ".env already exists — skipping."
    fi

    # Copy PostgREST config if available
    if [[ -f "${POSTGREST_CONF}" ]]; then
        cp "${POSTGREST_CONF}" "${ysf_dir}/backend/api/postgrest.conf"
        success "Copied postgrest.conf to backend/api/."
    fi

    # Binary checks
    echo
    gum style --bold "── Dependency check ─────────────────────────"
    command -v hugo       &>/dev/null && success "hugo:       found ($(hugo version 2>/dev/null | grep -oP 'v[\d.]+' | head -1))" || warn "hugo:       NOT FOUND — use 'Install Hugo' option"
    command -v postgrest  &>/dev/null && success "postgrest:  found" || warn "postgrest:  NOT FOUND — install from https://postgrest.org"
    command -v python3    &>/dev/null && success "python3:    found" || warn "python3:    NOT FOUND"
    command -v rsync      &>/dev/null && success "rsync:      found" || warn "rsync:      NOT FOUND (needed for VPS deploy)"

    echo
    success "Bootstrap complete!"
    info "Next steps:"
    info "  1. Add your Hugo site files to ${ysf_dir}/frontend/hugo-site/"
    info "  2. Run the dataminer to populate stock data"
    info "  3. Generate Hugo data files from PostgreSQL"
    info "  4. Start Hugo dev server to preview locally"
}

# ── Hugo install helper ───────────────────────────────────────────────────────
ysf_install_hugo() {
    if command -v hugo &>/dev/null; then
        success "Hugo is already installed: $(hugo version 2>/dev/null | head -1)"
        return
    fi
    warn "Hugo not found in PATH."
    info "Download the latest extended version from:"
    info "  https://github.com/gohugoio/hugo/releases/latest"
    echo
    gum style --foreground 33 \
        "# Quick install (Linux AMD64):" \
        "wget https://github.com/gohugoio/hugo/releases/latest/download/hugo_extended_0.x.x_linux-amd64.tar.gz" \
        "sudo tar -xf hugo_*.tar.gz -C /usr/local/bin hugo" \
        "" \
        "# Or via snap:" \
        "sudo snap install hugo" \
        "" \
        "# Or via apt (may be older version):" \
        "sudo apt install hugo"
    echo
    if confirm "Try 'sudo snap install hugo' now?"; then
        sudo snap install hugo 2>/dev/null \
            && success "Hugo installed via snap." \
            || error "Snap install failed — install manually from the URL above."
    fi
}


run_app() {
    splash_screen
    while true; do
        clear
        case "$CURRENT_MENU" in
            main)        main_menu        ;;
            database)    database_menu    ;;
            table)       table_menu       ;;
            analytics)   analytics_menu   ;;
            export)      export_menu      ;;
            maintenance) maintenance_menu ;;
            github)      github_menu      ;;
            postgrest)   postgrest_menu   ;;
            insert_data) insert_data_menu ;;
            finviz)      finviz_menu      ;;
            ysf)         ysf_menu          ;;
            settings)    settings_menu    ;;
            exit)        app_exit         ;;
            *)           CURRENT_MENU="main" ;;
        esac
    done
}

run_app
