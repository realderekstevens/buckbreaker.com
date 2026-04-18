/**
 * YourStockForecast — PostgREST API Client
 * ==========================================
 * All data fetching goes through this module.
 * Works in both dev (localhost:3000) and prod (api.yourstockforecast.com).
 *
 * Auth flow:
 *   1. User calls YSF.auth.login(email, pass)  → JWT stored in localStorage
 *   2. All subsequent requests auto-attach the Bearer token
 *   3. Anon users still get full read access (PostgREST anon role)
 */

const YSF = (() => {
  // ── Config ─────────────────────────────────────────────────────────────────
  // Hugo injects these via the base template's <script> block
  const API  = window.YSF_CONFIG?.api  || 'http://localhost:3000';
  const ROWS = window.YSF_CONFIG?.rows || 100;

  // ── Token management ───────────────────────────────────────────────────────
  const token = {
    get()    { return localStorage.getItem('ysf_jwt'); },
    set(t)   { localStorage.setItem('ysf_jwt', t); },
    clear()  { localStorage.removeItem('ysf_jwt'); },
    isValid() {
      const t = this.get();
      if (!t) return false;
      try {
        const payload = JSON.parse(atob(t.split('.')[1]));
        return payload.exp > Math.floor(Date.now() / 1000);
      } catch { return false; }
    },
    role() {
      const t = this.get();
      if (!t) return 'anon';
      try {
        return JSON.parse(atob(t.split('.')[1])).role || 'anon';
      } catch { return 'anon'; }
    }
  };

  // ── Core fetch wrapper ─────────────────────────────────────────────────────
  async function apiFetch(path, opts = {}) {
    const headers = {
      'Accept':       'application/json',
      'Content-Type': 'application/json',
      'Prefer':       'count=exact',
      ...(opts.headers || {})
    };
    if (token.isValid()) {
      headers['Authorization'] = `Bearer ${token.get()}`;
    }
    const res = await fetch(`${API}${path}`, { ...opts, headers });
    if (!res.ok) {
      const err = await res.json().catch(() => ({ message: res.statusText }));
      throw new Error(err.message || `HTTP ${res.status}`);
    }
    // Attach total count from header for pagination
    const data  = await res.json();
    const total = res.headers.get('Content-Range')?.split('/')[1];
    return { data, total: total ? parseInt(total) : null };
  }

  // PostgREST query builder — returns a URL path string
  function q(table, params = {}) {
    const p = new URLSearchParams();
    if (params.select)  p.set('select',  params.select);
    if (params.order)   p.set('order',   params.order);
    if (params.limit)   p.set('limit',   params.limit ?? ROWS);
    if (params.offset)  p.set('offset',  params.offset ?? 0);
    // Filters: { symbol: 'eq.AAPL', price: 'gte.100' }
    if (params.filters) {
      Object.entries(params.filters).forEach(([k, v]) => p.set(k, v));
    }
    return `/${table}?${p.toString()}`;
  }

  // ── Auth module ────────────────────────────────────────────────────────────
  const auth = {
    async login(email, password) {
      const res = await fetch(`${API}/rpc/login`, {
        method:  'POST',
        headers: { 'Content-Type': 'application/json' },
        body:    JSON.stringify({ email, password })
      });
      if (!res.ok) {
        const err = await res.json().catch(() => ({}));
        throw new Error(err.message || 'Login failed — check your credentials.');
      }
      const { token: jwt } = await res.json();
      token.set(jwt);
      document.dispatchEvent(new CustomEvent('ysf:login', { detail: { role: token.role() } }));
      return jwt;
    },

    async register(email, password, displayName = '') {
      const res = await fetch(`${API}/rpc/register`, {
        method:  'POST',
        headers: { 'Content-Type': 'application/json' },
        body:    JSON.stringify({ email, password, display_name: displayName })
      });
      if (!res.ok) {
        const err = await res.json().catch(() => ({}));
        throw new Error(err.message || 'Registration failed.');
      }
      return res.json();
    },

    async me() {
      if (!token.isValid()) return null;
      const res = await apiFetch('/rpc/me');
      return res.data;
    },

    logout() {
      token.clear();
      document.dispatchEvent(new CustomEvent('ysf:logout'));
    },

    isLoggedIn: () => token.isValid(),
    role:       () => token.role()
  };

  // ── Stocks module ──────────────────────────────────────────────────────────
  const stocks = {
    /** Latest snapshot for a single symbol */
    async get(symbol) {
      const { data } = await apiFetch(q('latest_quotes', {
        filters: { symbol: `eq.${symbol.toUpperCase()}` },
        limit: 1
      }));
      return data[0] || null;
    },

    /** Paginated list of latest quotes with optional filters */
    async list({ page = 0, limit = 50, order = 'symbol', filters = {} } = {}) {
      return apiFetch(q('latest_quotes', {
        order,
        limit,
        offset: page * limit,
        filters
      }));
    },

    /** Full historical rows for a symbol (newest first) */
    async history(symbol, limit = 30) {
      return apiFetch(q('stock_quote', {
        filters: { symbol: `eq.${symbol.toUpperCase()}` },
        order:   'time_recorded.desc',
        limit
      }));
    },

    /** Top N gainers today */
    async gainers(limit = 20) {
      return apiFetch(q('latest_quotes', {
        filters: { performance_today: 'not.is.null' },
        order:   'performance_today.desc',
        limit
      }));
    },

    /** Top N losers today */
    async losers(limit = 20) {
      return apiFetch(q('latest_quotes', {
        filters: { performance_today: 'not.is.null' },
        order:   'performance_today.asc',
        limit
      }));
    },

    /** Screener — pass arbitrary PostgREST filters */
    async screen(filters = {}, order = 'market_capitalization.desc', limit = 100) {
      return apiFetch(q('latest_quotes', { filters, order, limit }));
    }
  };

  // ── Market overview ────────────────────────────────────────────────────────
  const market = {
    async summary() {
      const { data } = await apiFetch('/rpc/market_summary');
      return data;
    },

    async sectorPerformance() {
      return apiFetch('/rpc/sector_performance');
    },

    async mostActive(limit = 20) {
      return apiFetch(q('latest_quotes', {
        filters: { volume: 'not.is.null' },
        order:   'volume.desc',
        limit
      }));
    }
  };

  // ── Utility helpers ────────────────────────────────────────────────────────
  const fmt = {
    price:   v => v != null ? `$${parseFloat(v).toFixed(2)}` : '—',
    pct:     v => v != null ? `${parseFloat(v).toFixed(2)}%` : '—',
    mcap:    v => {
      if (v == null) return '—';
      const n = parseFloat(v);
      if (n >= 1e12) return `$${(n/1e12).toFixed(2)}T`;
      if (n >= 1e9)  return `$${(n/1e9).toFixed(2)}B`;
      if (n >= 1e6)  return `$${(n/1e6).toFixed(2)}M`;
      return `$${n.toFixed(0)}`;
    },
    vol:     v => v != null ? parseInt(v).toLocaleString() : '—',
    chgClass: v => {
      if (v == null) return '';
      return parseFloat(v) >= 0 ? 'pos' : 'neg';
    }
  };

  // ── UI helpers ─────────────────────────────────────────────────────────────
  function renderTable(containerId, rows, columns) {
    const el = document.getElementById(containerId);
    if (!el) return;
    if (!rows || rows.length === 0) {
      el.innerHTML = '<p class="no-data">No data available.</p>';
      return;
    }
    const thead = columns.map(c => `<th>${c.label}</th>`).join('');
    const tbody = rows.map(row =>
      `<tr>${columns.map(c => {
        const val = row[c.key];
        const cls = c.pct ? ` class="${fmt.chgClass(val)}"` : '';
        const txt = c.fmt ? c.fmt(val) : (val ?? '—');
        return `<td${cls}><a href="/stocks/${row.symbol || ''}">${txt}</a></td>`;
      }).join('')}</tr>`
    ).join('');
    el.innerHTML = `<table class="data-table"><thead><tr>${thead}</tr></thead><tbody>${tbody}</tbody></table>`;
  }

  function setLoading(id, isLoading) {
    const el = document.getElementById(id);
    if (el) el.classList.toggle('loading', isLoading);
  }

  function showError(id, msg) {
    const el = document.getElementById(id);
    if (el) el.innerHTML = `<p class="error">⚠ ${msg}</p>`;
  }

  // Public API
  return { auth, stocks, market, fmt, renderTable, setLoading, showError, token };
})();

// ── Auth UI wiring (runs on every page) ───────────────────────────────────────
document.addEventListener('DOMContentLoaded', () => {
  // Update nav based on login state
  const updateNav = () => {
    const nav    = document.getElementById('auth-nav');
    if (!nav) return;
    if (YSF.auth.isLoggedIn()) {
      nav.innerHTML = `
        <span class="nav-role">${YSF.token.role()}</span>
        <button onclick="YSF.auth.logout();location.reload()">Sign Out</button>`;
    } else {
      nav.innerHTML = `<button onclick="document.getElementById('auth-modal').classList.remove('hidden')">Sign In</button>`;
    }
  };

  document.addEventListener('ysf:login',  updateNav);
  document.addEventListener('ysf:logout', () => location.reload());
  updateNav();

  // Login form
  const loginForm = document.getElementById('login-form');
  if (loginForm) {
    loginForm.addEventListener('submit', async e => {
      e.preventDefault();
      const email = loginForm.querySelector('[name=email]').value;
      const pass  = loginForm.querySelector('[name=password]').value;
      const errEl = document.getElementById('login-error');
      try {
        await YSF.auth.login(email, pass);
        document.getElementById('auth-modal').classList.add('hidden');
        updateNav();
      } catch (err) {
        if (errEl) errEl.textContent = err.message;
      }
    });
  }

  // Register form
  const regForm = document.getElementById('register-form');
  if (regForm) {
    regForm.addEventListener('submit', async e => {
      e.preventDefault();
      const email = regForm.querySelector('[name=email]').value;
      const pass  = regForm.querySelector('[name=password]').value;
      const name  = regForm.querySelector('[name=display_name]')?.value || '';
      const errEl = document.getElementById('register-error');
      try {
        await YSF.auth.register(email, pass, name);
        // Auto-login after register
        await YSF.auth.login(email, pass);
        document.getElementById('auth-modal').classList.add('hidden');
        updateNav();
      } catch (err) {
        if (errEl) errEl.textContent = err.message;
      }
    });
  }
});
