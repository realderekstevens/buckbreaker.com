+++
# ── Identity ──────────────────────────────────────────────────────────────────
title       = "{{ replace .Name "-" " " | title }}"
date        = {{ .Date }}
draft       = false
layout      = "article"

# ── Publication info ──────────────────────────────────────────────────────────
publication = ""
edition     = ""
location    = ""

# ── Authorship ────────────────────────────────────────────────────────────────
byline      = ""          # Name as printed on the page
wire        = ""          # e.g. "Associated Press", "United Press", "Reuters"
dateline    = ""          # e.g. "LONDON, Oct. 28"

# ── Position in paper ─────────────────────────────────────────────────────────
page        = 0
column      = ""
section     = ""
above_fold  = false

# ── Continuation ──────────────────────────────────────────────────────────────
continued_from_page = 0   # 0 = article starts here
continued_on_page   = 0   # 0 = article ends here
continued_on_column = ""

# ── Summary and classification ────────────────────────────────────────────────
summary     = ""

tags        = []
topics      = []
people      = []
places      = []

# ── Article type ──────────────────────────────────────────────────────────────
# news | editorial | column | advertisement | obituary | letter | financial | sports
article_type = "news"

# ── Related content ───────────────────────────────────────────────────────────
related     = []

# ── Media ─────────────────────────────────────────────────────────────────────
has_photo     = false
has_chart     = false
photo_caption = ""
+++
