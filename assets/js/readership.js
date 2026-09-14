// The /readership page. Every figure is drawn from the JSON _layouts/readership.html
// inlines from _data/readership.json. The one thing fetched at run time is the
// world map's country outlines, from assets/vendor on this same site.
(function () {
  "use strict";

  const SVG_NS = "http://www.w3.org/2000/svg";
  const DAY_MS = 86_400_000;
  const MINUTE_MS = 60_000;
  const MINUTES_PER_HOUR = 60;
  const SECONDS_PER_MINUTE = 60;
  const HOURS_PER_DAY = 24;
  const DAYS_PER_WEEK = 7;
  const HOURS_PER_WEEK = HOURS_PER_DAY * DAYS_PER_WEEK;

  const FRONT_PAGE_RANK = 30;
  const RANK_TICKS = [1, 10, 20, 30];
  const RANK_HOURS = 36;
  const RANK_HOUR_STEP = 6;
  // Buckets further apart than this are a hole in the samples, not a run.
  const RANK_GAP_MINUTES = 45;

  const Site = Object.freeze({ HN: "hn", LOBSTERS: "lobsters", REDDIT: "reddit" });
  const SITES = [Site.HN, Site.LOBSTERS, Site.REDDIT];
  const SITE_NAMES = { [Site.HN]: "Hacker News", [Site.LOBSTERS]: "Lobsters", [Site.REDDIT]: "Reddit" };
  const SITE_SHORT = { [Site.HN]: "HN", [Site.LOBSTERS]: "Lobsters", [Site.REDDIT]: "Reddit" };
  const SITE_LINK = {
    [Site.HN]: (id) => `https://news.ycombinator.com/item?id=${id}`,
    [Site.LOBSTERS]: (id) => `https://lobste.rs/s/${id}`,
    [Site.REDDIT]: (id) => `https://www.reddit.com/comments/${id}`,
  };

  const Range = Object.freeze({ ALL: "all", YEAR: "year", RECENT: "recent" });
  const RANGE_LABELS = { [Range.RECENT]: "90 days", [Range.YEAR]: "12 months", [Range.ALL]: "All time" };
  const RANGE_DAYS = { [Range.RECENT]: 90, [Range.YEAR]: 365 };

  const SiteFilter = Object.freeze({ ALL: "all", HN: Site.HN, LOBSTERS: Site.LOBSTERS, REDDIT: Site.REDDIT });
  const SortDirection = Object.freeze({ ASC: "ascending", DESC: "descending" });

  // Definitions shown in the tooltips of the column headers that use them.
  const TIPS = {
    impressions: "How many times the page appeared in Google search results.",
    clicks: "How many times someone clicked the page in Google search results.",
    ctr: "Click-through rate: clicks divided by impressions.",
    position: "Where the page appeared in Google results on average; 1 is the top result.",
    named: "Share of clicks from searches Google reports. Google withholds searches made by very few people.",
    reading: "Average engaged time per visit to the page, over the same days as the clicks.",
    peak: "The best position the story reached on the Hacker News front page.",
    top30: "Hours the story spent in the top 30, the front page.",
    top10: "Hours the story spent in the top 10.",
  };

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  const byId = (id) => document.getElementById(id);
  const fmt = new Intl.NumberFormat("en-US");
  const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
  const dayOf = (iso) => iso.slice(0, 10);
  const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
  const pct = (v, digits = 1) => (v * 100).toFixed(digits) + "%";
  const duration = (s) => `${Math.floor(s / SECONDS_PER_MINUTE)}m ${String(Math.round(s % SECONDS_PER_MINUTE)).padStart(2, "0")}s`;
  const daysBetween = (start, end) => Math.round((Date.parse(end) - Date.parse(start)) / DAY_MS) + 1;
  const isMissing = (v) => v === null || v === undefined;
  const hh = (h) => String(h).padStart(2, "0");
  const monthLabel = (t) =>
    new Date(t).toLocaleString("en-US", { month: "short", timeZone: "UTC" }) + " ’" + String(new Date(t).getUTCFullYear()).slice(2);
  const dayLabel = (t) => new Date(t).toLocaleString("en-US", { month: "short", day: "numeric", timeZone: "UTC" });
  const muted = (text) => `<span class="muted">${text}</span>`;
  const numCell = (v) => `<td class="num">${isMissing(v) ? muted("—") : v}</td>`;
  // A sequential fill: the accent mixed into the raised paper by `share`.
  const heatFill = (share) => `color-mix(in oklab, var(--accent) ${(clamp(share, 0, 1) * 100).toFixed(0)}%, var(--paper-raised))`;

  function median(xs) {
    const s = [...xs].sort((a, b) => a - b);
    const mid = s.length >> 1;
    return s.length % 2 ? s[mid] : (s[mid - 1] + s[mid]) / 2;
  }

  // A round axis maximum and the step that divides it into about four ticks.
  function niceMax(max) {
    const TICKS = 4;
    const raw = Math.max(max, 1) / TICKS;
    const magnitude = 10 ** Math.floor(Math.log10(raw));
    const step = [1, 2, 5, 10].map((k) => k * magnitude).find((s) => s >= raw);
    return { max: Math.ceil(max / step) * step || step, step };
  }

  function svg(tag, attrs, parent) {
    const el = document.createElementNS(SVG_NS, tag);
    for (const [k, v] of Object.entries(attrs || {})) {
      el.setAttribute(k, v);
    }
    if (parent) {
      parent.appendChild(el);
    }
    return el;
  }

  function svgText(parent, x, y, text, attrs) {
    const el = svg("text", Object.assign({ x, y }, attrs), parent);
    el.textContent = text;
    return el;
  }

  // How a tooltip sits against the point it describes. A mouse pointer is
  // small, so the tooltip goes beside it; a finger covers the area around a
  // tap, so the tooltip goes above the tap, clear of the thumb.
  const TipPlacement = Object.freeze({ BESIDE: "beside", ABOVE: "above" });
  const TIP_BESIDE_PX = 14;
  const TIP_ABOVE_PX = 36;
  const TIP_EDGE_PX = 8;
  const TOUCH_POINTER = "touch";
  const NOOP = () => {};

  // Where a tooltip of `size` goes for `point`, as [left, top].
  function tipPosition(point, size, placement) {
    // Above a tap and centred on it; below it only where there is no room above.
    if (placement === TipPlacement.ABOVE) {
      const above = point.clientY - size.height - TIP_ABOVE_PX;
      const top = above < TIP_EDGE_PX ? point.clientY + TIP_ABOVE_PX : above;
      return [point.clientX - size.width / 2, top];
    }

    // Beside a pointer, flipped to its other side at the viewport's edges.
    let left = point.clientX + TIP_BESIDE_PX;
    let top = point.clientY + TIP_BESIDE_PX;
    if (left + size.width > window.innerWidth - TIP_EDGE_PX) {
      left = point.clientX - size.width - TIP_BESIDE_PX;
    }
    if (top + size.height > window.innerHeight - TIP_EDGE_PX) {
      top = point.clientY - size.height - TIP_BESIDE_PX;
    }
    return [left, top];
  }

  // One tooltip, placed by the point it describes and kept inside the viewport.
  const tip = byId("readership-tip");
  function showTip(html, point, placement = TipPlacement.BESIDE) {
    tip.innerHTML = html;
    tip.hidden = false;
    const r = tip.getBoundingClientRect();
    const [left, top] = tipPosition(point, r, placement);
    tip.style.left = Math.max(TIP_EDGE_PX, Math.min(left, window.innerWidth - r.width - TIP_EDGE_PX)) + "px";
    tip.style.top = Math.max(TIP_EDGE_PX, top) + "px";
  }

  // The tooltip a tap opened: the chart that opened it, the mark it describes,
  // and the function that removes that chart's highlight. Null when the
  // tooltip is closed or follows a mouse.
  let tapped = null;

  // The kind of pointer that pressed last. Not every browser says which
  // pointer fired a click, so a tap is told apart from a mouse click by the
  // pointerdown before it.
  let lastPointerType = null;

  // The click a tap tooltip handled, so the page-wide click handler below
  // does not close the tooltip that click just opened.
  let claimedClick = null;

  function hideTip() {
    tip.hidden = true;
    if (!tapped) {
      return;
    }
    const { clear } = tapped;
    tapped = null;
    clear();
  }

  // A tap on a mark closes any tooltip a tap opened and opens this mark's,
  // unless this mark's tooltip was the one open: then the tap only closes it.
  function toggleTapTip(click, owner, pick, clear) {
    claimedClick = click;
    const previous = tapped;
    hideTip();
    const hit = pick(click);
    if (!hit) {
      return;
    }
    if (previous && previous.owner === owner && previous.key === hit.key) {
      clear();
      return;
    }
    showTip(hit.html, click, TipPlacement.ABOVE);
    tapped = { owner, key: hit.key, clear };
  }

  // Tooltips for the marks of a chart. `pick(event)` finds the mark under a
  // pointer, draws the chart's highlight for that mark, and returns
  // { key, html }, where equal keys mean the same mark; with no mark there,
  // `pick` removes the highlight and returns null. `clear()` removes the
  // highlight.
  //
  // A mouse hovers: the tooltip follows the pointer and leaves with it. A
  // finger cannot hover, and a long press opens the phone's own menus, so a
  // tap toggles the tooltip instead, and the tooltip stays up until the next
  // tap or a scroll.
  function markTips(el, pick, clear) {
    el.addEventListener("pointermove", (e) => {
      if (e.pointerType === TOUCH_POINTER) {
        return;
      }
      const hit = pick(e);
      if (!hit) {
        hideTip();
        return;
      }
      showTip(hit.html, e);
    });
    el.addEventListener("pointerleave", (e) => {
      if (e.pointerType === TOUCH_POINTER) {
        return;
      }
      clear();
      hideTip();
    });

    // The chart's box outlives its redraws, so a mark keeps its owner when a
    // tap redraws the chart under it.
    el.addEventListener("click", (e) => {
      if (lastPointerType !== TOUCH_POINTER) {
        return;
      }
      toggleTapTip(e, el.closest(".plot") ?? el, pick, clear);
    });
  }

  // A click that no tooltip claimed closes the tooltip a tap opened, and a
  // scroll closes any tooltip, which would otherwise float over whatever
  // scrolled under it.
  document.addEventListener(
    "pointerdown",
    (e) => {
      lastPointerType = e.pointerType;
    },
    { capture: true },
  );
  document.addEventListener("click", (e) => {
    if (e === claimedClick || !tapped) {
      return;
    }
    hideTip();
  });
  window.addEventListener("scroll", hideTip, { passive: true });

  // Anything carrying data-tip explains itself on hover or a tap, and on
  // keyboard focus for readers who can do neither.
  function setUpDefinitionTips() {
    const article = document.querySelector(".readership");
    article.addEventListener("pointerover", (e) => {
      const target = e.target.closest("[data-tip]");
      if (target && e.pointerType !== TOUCH_POINTER) {
        showTip(esc(target.dataset.tip), e);
      }
    });
    article.addEventListener("pointerout", (e) => {
      if (e.target.closest("[data-tip]") && e.pointerType !== TOUCH_POINTER) {
        hideTip();
      }
    });

    // The definition itself is the key: tapping a header sorts and redraws the
    // table, so the element tapped does not survive to be compared with the
    // next tap's.
    article.addEventListener("click", (e) => {
      const target = e.target.closest("[data-tip]");
      if (!target || lastPointerType !== TOUCH_POINTER) {
        return;
      }
      const definition = target.dataset.tip;
      toggleTapTip(e, article, () => ({ key: definition, html: esc(definition) }), NOOP);
    });
    article.addEventListener("focusin", (e) => {
      const target = e.target.closest("[data-tip]");
      if (!target) {
        return;
      }
      const r = target.getBoundingClientRect();
      showTip(esc(target.dataset.tip), { clientX: r.left, clientY: r.bottom });
    });
    // Focus leaving closes only a tooltip that focus opened. Tapping a header
    // sorts the table, and the redraw removes the focused button, which fires
    // a focusout that would otherwise close the definition the tap just opened
    // and forget it, so the next tap on the term could not close it.
    article.addEventListener("focusout", () => {
      if (tapped) {
        return;
      }
      hideTip();
    });
  }

  // Redraw a chart when its container's width changes, or when asked to.
  function mount(container, draw) {
    let lastWidth = 0;
    const run = (force) => {
      const w = Math.floor(container.clientWidth);
      if (!w || (w === lastWidth && !force)) {
        return;
      }
      lastWidth = w;
      container.replaceChildren();
      draw(w);
    };
    new ResizeObserver(() => run(false)).observe(container);
    run(false);
    return () => run(true);
  }

  // A segmented control whose buttons carry a value. Returns a function that
  // marks a value pressed, or none when given null.
  function segmented(host, options, initial, onChange) {
    host.innerHTML = options
      .map(([value, label]) => `<button type="button" data-value="${esc(value)}" aria-pressed="${value === initial}">${esc(label)}</button>`)
      .join("");
    const press = (value) => {
      for (const c of host.children) {
        c.setAttribute("aria-pressed", String(c.dataset.value === value));
      }
    };
    host.addEventListener("click", (e) => {
      const b = e.target.closest("button");
      if (!b) {
        return;
      }
      press(b.dataset.value);
      onChange(b.dataset.value);
    });
    return press;
  }

  function hideFigure(id) {
    byId(id).closest("figure").hidden = true;
  }

  // How a header click changes a table's sort: a plain click sorts by that
  // column alone, a shift-click adds it as the next key.
  const SortClick = Object.freeze({ REPLACE: "replace", ADD: "add" });
  const MAX_SORT_KEYS = 3;
  const SORT_HINT = "Click to sort by this column; shift-click to add it as another sort key";

  const flipDirection = (direction) => (direction === SortDirection.ASC ? SortDirection.DESC : SortDirection.ASC);

  // The sort keys after a header click. A plain click on a column makes it the
  // only key, flipping it if it already was; a shift-click appends it, or flips
  // it where it already stands.
  function nextSort(current, column, click) {
    const position = current.findIndex((s) => s.key === column.key);
    if (click === SortClick.ADD) {
      if (position !== -1) {
        return current.map((s, i) => (i === position ? { key: s.key, direction: flipDirection(s.direction) } : s));
      }
      return [...current, { key: column.key, direction: column.first }].slice(0, MAX_SORT_KEYS);
    }
    if (position === 0) {
      const direction = current.length === 1 ? flipDirection(current[0].direction) : current[0].direction;
      return [{ key: column.key, direction }];
    }
    return [{ key: column.key, direction: column.first }];
  }

  // A rendered cell with its column's name attached. On a narrow screen each row
  // is drawn as a card with no header row above it, and every value is labelled
  // from this attribute instead.
  const labelCell = (cell, label) => cell.replace(/^<td/, `<td data-label="${esc(label)}"`);

  // A table whose headers sort it. Each column gives a `value` to sort by, a
  // `cell` to render, an optional `tip` defining it and `width` to fix its
  // share of the table, and `first`: the direction a first click sorts in, so
  // newest, most and best come first. Missing values always sort last.
  //
  // Sorting can use several keys (see nextSort). Rows that tie on every key
  // keep the order they had before the click, so tapping the secondary column
  // and then the primary one sorts by both on a phone, which has no shift key.
  //
  // `rows` is a function so a filter outside the table can change what it
  // shows; the returned function redraws. At most `maxRows` rows are rendered.
  function sortableTable(host, columns, rows, initialSort, maxRows = Infinity) {
    let sort = [initialSort];
    let previousRank = new Map();
    const rankOf = (row) => (previousRank.has(row) ? previousRank.get(row) : Number.MAX_SAFE_INTEGER);

    const compare = (a, b) => {
      for (const { key, direction } of sort) {
        const column = columns.find((c) => c.key === key);
        const va = column.value(a);
        const vb = column.value(b);
        if (isMissing(va) && isMissing(vb)) {
          continue;
        }
        if (isMissing(va) || isMissing(vb)) {
          return isMissing(va) ? 1 : -1;
        }
        if (va === vb) {
          continue;
        }
        const order = va < vb ? -1 : 1;
        return direction === SortDirection.ASC ? order : -order;
      }
      return rankOf(a) - rankOf(b);
    };

    const header = (column) => {
      const position = sort.findIndex((s) => s.key === column.key);
      const active = position !== -1;
      const direction = active ? sort[position].direction : null;
      const ariaSort = position === 0 ? ` aria-sort="${direction}"` : "";
      const width = column.width ? ` style="width:${column.width}"` : "";
      const arrow = active ? (direction === SortDirection.ASC ? " ↑" : " ↓") : "";
      const rank = active && sort.length > 1 ? `<sup class="sort-rank">${position + 1}</sup>` : "";
      const label = column.tip ? `<span class="has-tip" data-tip="${esc(column.tip)}">${esc(column.label)}</span>` : esc(column.label);
      return `<th class="${column.numeric ? "num" : ""}"${ariaSort}${width}><button type="button" class="sort" data-key="${column.key}" title="${SORT_HINT}">${label}${arrow}${rank}</button></th>`;
    };

    const draw = () => {
      const sorted = [...rows()].sort(compare);
      previousRank = new Map(sorted.map((row, i) => [row, i]));
      host.innerHTML = `<table>
        <thead><tr>${columns.map(header).join("")}</tr></thead>
        <tbody>${sorted
          .slice(0, maxRows)
          .map((row) => `<tr>${columns.map((c) => labelCell(c.cell(row), c.label)).join("")}</tr>`)
          .join("")}</tbody>
      </table>`;
    };

    host.addEventListener("click", (e) => {
      const button = e.target.closest("button.sort");
      if (!button) {
        return;
      }
      const column = columns.find((c) => c.key === button.dataset.key);
      sort = nextSort(sort, column, e.shiftKey ? SortClick.ADD : SortClick.REPLACE);
      draw();
    });

    draw();
    return draw;
  }

  // Horizontal bars for [label, share, detail] rows, longest bar at full width.
  function barList(host, rows) {
    const maxShare = Math.max(...rows.map(([, share]) => share), 1e-9);
    host.innerHTML = rows
      .map(
        ([name, share, detail]) => `<span class="bars__name">${esc(name)}</span>
        <span class="bars__track"><span class="bars__fill" style="width: calc(${(share / maxShare) * 100}% - 5rem)"></span><span class="bars__value">${pct(share, 0)}${detail ? ` · ${esc(detail)}` : ""}</span></span>`,
      )
      .join("");
  }

  // Drag across a time chart to zoom into the dragged span. `overlay` is the
  // chart's hit area, `toTime` maps an x in the chart to a timestamp, and
  // `onZoom` receives [start, end]. A press that barely moves is left to the
  // tooltip handlers; a double-click resets. Returns nothing: the chart is
  // redrawn by the caller from the new span.
  const ZOOM_MIN_DRAG_PX = 8;
  const ZOOM_MIN_SPAN_MS = 2 * DAY_MS;

  function enableDragZoom(root, overlay, { top, height, toTime, onZoom, onReset }) {
    const band = svg("rect", { y: top, height, class: "zoom-band", visibility: "hidden" }, root);
    let startX = null;

    const localX = (e) => e.clientX - root.getBoundingClientRect().left;

    overlay.addEventListener("pointerdown", (e) => {
      if (e.button !== 0) {
        return;
      }
      startX = localX(e);
      overlay.setPointerCapture(e.pointerId);
    });
    overlay.addEventListener("pointermove", (e) => {
      if (startX === null) {
        return;
      }
      const x = localX(e);
      if (Math.abs(x - startX) < ZOOM_MIN_DRAG_PX) {
        return;
      }
      hideTip();
      band.setAttribute("x", Math.min(x, startX));
      band.setAttribute("width", Math.abs(x - startX));
      band.setAttribute("visibility", "visible");
    });
    const finish = (e) => {
      if (startX === null) {
        return;
      }
      const x = localX(e);
      const dragged = Math.abs(x - startX) >= ZOOM_MIN_DRAG_PX;
      const from = toTime(Math.min(x, startX));
      const to = toTime(Math.max(x, startX));
      startX = null;
      band.setAttribute("visibility", "hidden");
      if (!dragged) {
        return;
      }
      // Too narrow a span has nothing to show; widen it around its middle.
      const middle = (from + to) / 2;
      const span = Math.max(to - from, ZOOM_MIN_SPAN_MS);
      onZoom([middle - span / 2, middle + span / 2]);
    };
    overlay.addEventListener("pointerup", finish);
    overlay.addEventListener("pointercancel", () => {
      startX = null;
      band.setAttribute("visibility", "hidden");
    });
    overlay.addEventListener("dblclick", onReset);
  }

  // ---------------------------------------------------------------------------
  // Data
  // ---------------------------------------------------------------------------

  const node = byId("readership-data");
  const data = node ? JSON.parse(node.textContent.trim() || "null") : null;
  const sources = (data && data.sources) || {};
  const submissions = (data && data.submissions) || [];
  const hnRanks = (data && data.hn_ranks) || {};

  const hn = submissions.filter((s) => s.site === Site.HN);
  const lobsters = submissions.filter((s) => s.site === Site.LOBSTERS);
  const reddit = submissions.filter((s) => s.site === Site.REDDIT);
  const subredditOf = (s) => (s.site === Site.REDDIT && s.tags.length ? `r/${s.tags[0]}` : "");
  const onFrontPage = (s) => !isMissing(s.peak_rank) && s.peak_rank <= FRONT_PAGE_RANK;
  const frontPage = hn.filter(onFrontPage);
  const rankedStories = frontPage
    .filter((s) => hnRanks[s.id])
    .sort((a, b) => a.peak_rank - b.peak_rank || b.front_page_hours - a.front_page_hours);

  const postsNode = byId("readership-posts");
  const postTitles = postsNode ? JSON.parse(postsNode.textContent.trim() || "{}") : {};
  const isPost = (path) => Object.prototype.hasOwnProperty.call(postTitles, path);
  const titleOf = (path) => postTitles[path] || path;

  const search = (data && data.search) || null;
  const traffic = (data && data.traffic) || null;
  const engagement = (data && data.engagement) || null;
  const platforms = (data && data.platforms) || null;
  const geography = (data && data.geography) || null;
  const hours = (data && data.hours) || null;
  const trafficStart = traffic && traffic.daily.length ? traffic.daily[0].date : null;
  const trafficEnd = traffic && traffic.daily.length ? traffic.daily[traffic.daily.length - 1].date : null;

  // Series of the traffic chart, in a fixed order so each source keeps its
  // colour. Lobsters sends too few visits to read as a band of its own, so it
  // rides with everything else.
  const TRAFFIC_SERIES = [
    { name: "Google search", color: "var(--s1)", keys: ["search"] },
    { name: "Hacker News", color: "var(--s2)", keys: ["hn"] },
    { name: "Reddit", color: "var(--s3)", keys: ["reddit"] },
    { name: "Direct", color: "var(--s4)", keys: ["direct"] },
    { name: "Everything else", color: "var(--dot)", keys: ["lobsters", "other"] },
  ];
  const TRAFFIC_KEYS = TRAFFIC_SERIES.flatMap((s) => s.keys);

  // ---------------------------------------------------------------------------
  // Ledger, empty states and fields filled from the data
  // ---------------------------------------------------------------------------

  function drawLedger() {
    const missing = "not fetched yet";
    const cells = [["Last updated", data ? dayOf(data.generated_at) : "never", data ? data.generated_at.slice(11, 16) + " UTC" : missing]];

    if (search) {
      const clicks = search.pages.reduce((a, p) => a + p.clicks, 0);
      const impressions = search.pages.reduce((a, p) => a + p.impressions, 0);
      cells.push(["Clicks from Google", fmt.format(clicks), `${daysBetween(search.start, search.end)} days · ${fmt.format(impressions)} impressions`]);
    } else {
      cells.push(["Search Console", "—", missing]);
    }

    if (trafficStart) {
      const visits = traffic.daily.reduce((a, d) => a + TRAFFIC_KEYS.reduce((x, k) => x + d[k], 0), 0);
      cells.push(["Visits", fmt.format(visits), `${trafficStart} to ${trafficEnd}`]);
    } else {
      cells.push(["Google Analytics", "—", missing]);
    }

    const hoursOnFront = hn.reduce((a, s) => a + (s.front_page_hours || 0), 0);
    const best = frontPage.length ? Math.min(...frontPage.map((s) => s.peak_rank)) : null;
    cells.push([
      "Hacker News",
      `${hn.length} submissions`,
      `${frontPage.length} on the front page · ${fmt.format(Math.round(hoursOnFront))} hours${best ? ` · best #${best}` : ""}`,
    ]);
    cells.push(["Lobsters", `${lobsters.length} submissions`, `${fmt.format(lobsters.reduce((a, s) => a + s.points, 0))} points in total`]);
    cells.push([
      "Reddit",
      `${reddit.length} posts`,
      `${new Set(reddit.map(subredditOf)).size} subreddits · ${fmt.format(reddit.reduce((a, s) => a + s.points, 0))} points`,
    ]);

    byId("ledger").innerHTML = cells.map(([k, v, s]) => `<div><dt>${esc(k)}</dt><dd>${esc(v)}<small>${esc(s)}</small></dd></div>`).join("");
  }

  // Empty states show while their source is missing; figures show only once
  // every source they draw from exists.
  function drawEmptyStates() {
    for (const el of document.querySelectorAll("[data-requires]")) {
      el.hidden = Boolean(sources[el.dataset.requires]);
    }
    for (const el of document.querySelectorAll("[data-section]")) {
      el.hidden = !el.dataset.section.split(" ").every((name) => sources[name]);
    }
  }

  function fillSearchWindow() {
    for (const el of document.querySelectorAll('[data-field="search-window"]')) {
      el.textContent = search ? `${search.start} to ${search.end}` : "";
    }
  }

  // ---------------------------------------------------------------------------
  // Shared by the timeline and the traffic chart: date ticks and submission lanes
  // ---------------------------------------------------------------------------

  function dateTicks(start, end) {
    const span = (end - start) / DAY_MS;
    const ticks = [];
    const d = new Date(start);
    d.setUTCHours(0, 0, 0, 0);
    d.setUTCDate(1);
    while (d.getTime() <= end) {
      const t = d.getTime();
      const month = d.getUTCMonth();
      if (span > 3 * 365) {
        if (month === 0) {
          ticks.push([t, String(d.getUTCFullYear())]);
        }
      } else if (span > 200) {
        if (month % 3 === 0) {
          ticks.push([t, monthLabel(t)]);
        }
      } else if (span > 45) {
        ticks.push([t, dayLabel(t)]);
        const mid = Date.UTC(d.getUTCFullYear(), month, 15);
        ticks.push([mid, dayLabel(mid)]);
      } else {
        // Zoomed in to a few weeks: a tick every seven days.
        for (let day = 1; day <= 29; day += 7) {
          const tt = Date.UTC(d.getUTCFullYear(), month, day);
          ticks.push([tt, dayLabel(tt)]);
        }
      }
      d.setUTCMonth(month + 1);
    }
    return ticks.filter(([t]) => t >= start && t <= end);
  }

  function submissionTip(s) {
    const where = subredditOf(s) ? ` · ${esc(subredditOf(s))}` : "";
    return `<b>${esc(s.title)}</b>
      <div class="row"><span>${SITE_NAMES[s.site]}${where}</span><span>${dayOf(s.created_at)}</span></div>
      <div class="row"><span>Points</span><span>${fmt.format(s.points)}</span></div>
      <div class="row"><span>Comments</span><span>${fmt.format(s.comments)}</span></div>`;
  }

  // One lane per site under a time axis: a circle per submission sized by its
  // points. Returns a function that finds the submission nearest a point, for
  // the caller's hover handler.
  function drawLanes(root, { top, laneHeight, left, right, x, start, end }) {
    const MIN_R = 3;
    const SCALE = 2.2;
    const HIT_PX = 18;
    const radius = (points) => Math.min(MIN_R + Math.sqrt(points) / SCALE, laneHeight / 2 - 3);

    const lanes = SITES.map((site, li) => {
      const cy = top + li * laneHeight + laneHeight / 2;
      svg("line", { x1: left, x2: right, y1: cy, y2: cy, class: "base" }, root);
      svgText(root, left - 10, cy + 3.5, SITE_SHORT[site], { class: "lane", "text-anchor": "end" });

      // Big circles first, so small ones stay visible on top.
      const points = submissions
        .filter((s) => s.site === site && Date.parse(s.created_at) >= start && Date.parse(s.created_at) <= end)
        .sort((a, b) => b.points - a.points)
        .map((s) => ({ s, cx: x(Date.parse(s.created_at)), cy }));
      for (const { s, cx } of points) {
        svg("circle", { cx, cy, r: radius(s.points), fill: "var(--paper)", "fill-opacity": 0.8, stroke: "var(--ink-muted)", "stroke-width": 1.25 }, root);
      }
      return points;
    });

    return (px, py) => {
      const li = Math.floor((py - top) / laneHeight);
      if (li < 0 || li >= SITES.length) {
        return null;
      }
      let best = null;
      let bestD = HIT_PX;
      for (const pt of lanes[li]) {
        const dist = Math.abs(pt.cx - px);
        if (dist < bestD) {
          bestD = dist;
          best = pt;
        }
      }
      return best;
    };
  }

  // A time chart's span: a preset range, or the span a drag zoomed into.
  function spanOf(range, zoom, earliest, latest) {
    if (zoom) {
      return [Math.max(zoom[0], earliest), Math.min(zoom[1], latest)];
    }
    if (range === Range.ALL) {
      return [earliest, latest];
    }
    return [Math.max(earliest, latest - RANGE_DAYS[range] * DAY_MS), latest];
  }

  // ---------------------------------------------------------------------------
  // Fig. 1: clicks from Google against reading time
  // ---------------------------------------------------------------------------

  // Reading time from a handful of visits is noise; those posts are left out.
  const SCATTER_MIN_SESSIONS = 10;
  const SCATTER_Y_TICKS = 6;

  function scatterPoints() {
    return search.pages
      .filter((p) => isPost(p.path) && p.clicks > 0 && p.sessions >= SCATTER_MIN_SESSIONS)
      .map((p) => ({ path: p.path, clicks: p.clicks, seconds: p.seconds_per_session }));
  }

  function drawScatter(W) {
    const box = byId("fig-scatter");
    const points = scatterPoints();
    if (!points.length) {
      box.innerHTML = '<p class="readership__empty">No post has both search clicks and enough visits yet.</p>';
      return;
    }

    const H = Math.round(clamp(W * 0.6, 280, 460));
    const m = { l: 44, r: 16, t: 26, b: 42 };
    const pw = W - m.l - m.r;
    const ph = H - m.t - m.b;
    const xMax = 10 ** Math.ceil(Math.log10(Math.max(10, ...points.map((d) => d.clicks))));
    const minutes = Math.max(1, Math.ceil(Math.max(...points.map((d) => d.seconds)) / SECONDS_PER_MINUTE));
    const yMax = minutes * SECONDS_PER_MINUTE;
    const x = (v) => m.l + (Math.log10(Math.max(v, 1)) / Math.log10(xMax)) * pw;
    const y = (v) => m.t + ph - (v / yMax) * ph;

    const root = svg("svg", { width: W, height: H, viewBox: `0 0 ${W} ${H}`, role: "img", "aria-label": "Clicks from Google against average reading time, one dot per post" }, box);

    // Grid: whole minutes up the side, powers of ten along the bottom.
    const minuteStep = Math.max(1, Math.ceil(minutes / SCATTER_Y_TICKS));
    for (let t = 0; t <= minutes; t += minuteStep) {
      const ty = y(t * SECONDS_PER_MINUTE);
      svg("line", { x1: m.l, x2: W - m.r, y1: ty, y2: ty, class: t === 0 ? "base" : "grid" }, root);
      svgText(root, m.l - 8, ty + 3.5, t === 0 ? "0" : `${t}m`, { class: "ax", "text-anchor": "end" });
    }
    for (let v = 1; v <= xMax; v *= 10) {
      svg("line", { x1: x(v), x2: x(v), y1: m.t, y2: m.t + ph, class: "grid" }, root);
      svgText(root, x(v), m.t + ph + 16, fmt.format(v), { class: "ax", "text-anchor": "middle" });
    }
    svgText(root, 0, 12, "Reading time per visit", { class: "ax-title" });
    svgText(root, W - m.r, H - 4, "Clicks from Google (log scale)", { class: "ax-title", "text-anchor": "end" });

    // Medians split the posts into quadrants.
    const mx = median(points.map((d) => d.clicks));
    const my = median(points.map((d) => d.seconds));
    svg("line", { x1: x(mx), x2: x(mx), y1: m.t, y2: m.t + ph, class: "base" }, root);
    svg("line", { x1: m.l, x2: W - m.r, y1: y(my), y2: y(my), class: "base" }, root);

    // Every dot looks the same; hover names the post.
    const placed = points.map((d) => ({ d, cx: x(d.clicks), cy: y(d.seconds) }));
    for (const { cx, cy } of placed) {
      svg("circle", { cx, cy, r: 4, fill: "var(--accent)", "fill-opacity": 0.65, stroke: "var(--paper)", "stroke-width": 1.5 }, root);
    }

    // Nearest dot to the pointer or tap, so small dots are easy to hit.
    const HIT_PX = 28;
    const ring = svg("circle", { r: 8, fill: "none", stroke: "var(--ink)", "stroke-width": 1.5, visibility: "hidden" }, root);
    const overlay = svg("rect", { x: m.l, y: m.t, width: pw, height: ph, fill: "transparent" }, root);
    const hideRing = () => ring.setAttribute("visibility", "hidden");
    const pick = (e) => {
      const r = root.getBoundingClientRect();
      const px = e.clientX - r.left;
      const py = e.clientY - r.top;
      let best = null;
      let bestD = HIT_PX;
      for (const pt of placed) {
        const dist = Math.hypot(pt.cx - px, pt.cy - py);
        if (dist < bestD) {
          bestD = dist;
          best = pt;
        }
      }
      if (!best) {
        hideRing();
        return null;
      }
      ring.setAttribute("cx", best.cx);
      ring.setAttribute("cy", best.cy);
      ring.setAttribute("visibility", "visible");
      return {
        key: best.d,
        html: `<b>${esc(titleOf(best.d.path))}</b>
        <div class="row"><span>Clicks from Google</span><span>${fmt.format(best.d.clicks)}</span></div>
        <div class="row"><span>Reading time per visit</span><span>${duration(best.d.seconds)}</span></div>`,
      };
    };
    markTips(overlay, pick, hideRing);
  }

  // ---------------------------------------------------------------------------
  // Table 1: pages with the most clicks
  // ---------------------------------------------------------------------------

  const HEAT_MAX_PERCENT = 30;

  function pageCell(path) {
    const title = titleOf(path);
    const sub = title === path ? "" : `<span class="sub">${esc(path)}</span>`;
    return `<td><a href="${esc(path)}">${esc(title)}</a>${sub}</td>`;
  }

  // A numeric cell shaded by where its value falls in its column.
  function heatCell(value, [lo, hi], text) {
    const t = hi === lo ? 0 : (value - lo) / (hi - lo);
    return `<td class="num" style="background: color-mix(in oklab, var(--accent) ${(t * HEAT_MAX_PERCENT).toFixed(1)}%, transparent)">${text}</td>`;
  }

  function setUpTopPages() {
    const pages = search.pages.filter((p) => p.impressions > 0);
    const range = (f) => [Math.min(...pages.map(f)), Math.max(...pages.map(f))];
    const ranges = { impressions: range((p) => p.impressions), clicks: range((p) => p.clicks), ctr: range((p) => p.ctr) };
    const columns = [
      { key: "title", label: "Page", width: "34%", first: SortDirection.ASC, value: (p) => titleOf(p.path).toLowerCase(), cell: (p) => pageCell(p.path) },
      { key: "impressions", label: "Impressions", tip: TIPS.impressions, numeric: true, first: SortDirection.DESC, value: (p) => p.impressions, cell: (p) => heatCell(p.impressions, ranges.impressions, fmt.format(p.impressions)) },
      { key: "clicks", label: "Clicks", tip: TIPS.clicks, numeric: true, first: SortDirection.DESC, value: (p) => p.clicks, cell: (p) => heatCell(p.clicks, ranges.clicks, fmt.format(p.clicks)) },
      { key: "ctr", label: "Click-through", tip: TIPS.ctr, numeric: true, first: SortDirection.DESC, value: (p) => p.ctr, cell: (p) => heatCell(p.ctr, ranges.ctr, pct(p.ctr)) },
      { key: "position", label: "Position", tip: TIPS.position, numeric: true, first: SortDirection.ASC, value: (p) => p.position, cell: (p) => numCell(p.position.toFixed(1)) },
      { key: "reading", label: "Reading time", tip: TIPS.reading, numeric: true, first: SortDirection.DESC, value: (p) => p.seconds_per_session, cell: (p) => numCell(isMissing(p.seconds_per_session) ? null : duration(p.seconds_per_session)) },
      { key: "named", label: "Named", tip: TIPS.named, numeric: true, first: SortDirection.DESC, value: (p) => (p.clicks ? p.named_clicks / p.clicks : null), cell: (p) => numCell(p.clicks ? pct(p.named_clicks / p.clicks, 0) : null) },
    ];
    sortableTable(byId("top-pages"), columns, () => pages, { key: "clicks", direction: SortDirection.DESC });
  }

  // ---------------------------------------------------------------------------
  // Table 2: every named search, filterable by page, position and click-through
  // ---------------------------------------------------------------------------

  const ALL_PAGES = "all";
  const SEARCH_PAGES = 40;
  const SEARCH_ROWS = 200;
  // Slider values at which a filter lets everything through.
  const ANY_POSITION = 100;
  const ANY_CTR_PERCENT = 100;

  function setUpSearches() {
    const all = [];
    for (const [path, queries] of Object.entries(search.queries)) {
      for (const [query, clicks, impressions, position] of queries) {
        all.push({ path, query, clicks, impressions, position, ctr: impressions ? clicks / impressions : 0 });
      }
    }

    const select = byId("search-page");
    const pages = search.pages.filter((p) => (search.queries[p.path] || []).length).slice(0, SEARCH_PAGES);
    select.innerHTML =
      `<option value="${ALL_PAGES}">All pages</option>` + pages.map((p) => `<option value="${esc(p.path)}">${esc(titleOf(p.path))}</option>`).join("");

    const inputs = { pos: byId("search-pos"), ctr: byId("search-ctr"), impr: byId("search-impr") };
    const filters = () => ({
      page: select.value,
      maxPosition: Number(inputs.pos.value),
      maxCtr: Number(inputs.ctr.value),
      minImpressions: Number(inputs.impr.value),
    });
    const rows = () => {
      const f = filters();
      return all.filter(
        (r) =>
          (f.page === ALL_PAGES || r.path === f.page) &&
          (f.maxPosition >= ANY_POSITION || r.position <= f.maxPosition) &&
          (f.maxCtr >= ANY_CTR_PERCENT || r.ctr * 100 < f.maxCtr) &&
          r.impressions >= f.minImpressions,
      );
    };

    const columns = [
      {
        key: "query",
        label: "Search",
        width: "44%",
        first: SortDirection.ASC,
        value: (r) => r.query,
        cell: (r) => `<td>${esc(r.query)}${select.value === ALL_PAGES ? `<span class="sub">${esc(titleOf(r.path))}</span>` : ""}</td>`,
      },
      { key: "clicks", label: "Clicks", tip: TIPS.clicks, numeric: true, first: SortDirection.DESC, value: (r) => r.clicks, cell: (r) => numCell(fmt.format(r.clicks)) },
      { key: "impressions", label: "Impressions", tip: TIPS.impressions, numeric: true, first: SortDirection.DESC, value: (r) => r.impressions, cell: (r) => numCell(fmt.format(r.impressions)) },
      { key: "ctr", label: "Click-through", tip: TIPS.ctr, numeric: true, first: SortDirection.DESC, value: (r) => r.ctr, cell: (r) => numCell(pct(r.ctr)) },
      { key: "position", label: "Position", tip: TIPS.position, numeric: true, first: SortDirection.ASC, value: (r) => r.position, cell: (r) => numCell(r.position.toFixed(1)) },
    ];
    const table = sortableTable(byId("searches"), columns, rows, { key: "clicks", direction: SortDirection.DESC }, SEARCH_ROWS);

    // The named/withheld split only means something for a single page.
    const drawSplit = (path) => {
      const page = search.pages.find((p) => p.path === path);
      if (!page || !page.clicks) {
        byId("search-split").innerHTML = "";
        return;
      }
      const named = Math.round((page.named_clicks / page.clicks) * 100);
      byId("search-split").innerHTML = `
        <div class="split__bar" role="img" aria-label="${named}% of clicks from searches Google reports, ${100 - named}% withheld">
          <span class="split__named" style="flex-basis:${named}%"></span><span class="split__withheld" style="flex-basis:${100 - named}%"></span>
        </div>
        <div class="split__legend"><span>Searches Google reports · ${named}%</span><span>Withheld by Google · ${100 - named}%</span></div>`;
    };

    const redraw = () => {
      const f = filters();
      byId("search-pos-v").textContent = f.maxPosition >= ANY_POSITION ? "any" : `1 to ${f.maxPosition}`;
      byId("search-ctr-v").textContent = f.maxCtr >= ANY_CTR_PERCENT ? "any" : `below ${f.maxCtr}%`;
      byId("search-impr-v").textContent = f.minImpressions === 0 ? "any" : `${fmt.format(f.minImpressions)}+`;
      const shown = rows().length;
      byId("search-count").innerHTML = `<b>${fmt.format(shown)}</b> of ${fmt.format(all.length)} searches${shown > SEARCH_ROWS ? ` · top ${SEARCH_ROWS} listed` : ""}`;
      drawSplit(f.page);
      table();
    };
    select.addEventListener("change", redraw);
    for (const input of Object.values(inputs)) {
      input.addEventListener("input", redraw);
    }
    redraw();
  }

  // ---------------------------------------------------------------------------
  // Fig. 2: every submission on a timeline
  // ---------------------------------------------------------------------------

  let timelineRange = Range.ALL;
  let timelineZoom = null;

  function drawTimeline(W, onZoom, onReset) {
    const box = byId("fig-timeline");
    const LANE_H = 46;
    const m = { l: 72, r: 16, t: 8, b: 26 };
    const H = m.t + SITES.length * LANE_H + m.b;
    const pw = W - m.l - m.r;

    const latest = Date.parse(data.generated_at);
    const earliest = Math.min(...submissions.map((s) => Date.parse(s.created_at))) - 30 * DAY_MS;
    const [start, end] = spanOf(timelineRange, timelineZoom, earliest, latest);
    const x = (t) => m.l + ((t - start) / (end - start)) * pw;

    const root = svg("svg", { width: W, height: H, viewBox: `0 0 ${W} ${H}`, role: "img", "aria-label": "Submissions to Hacker News, Lobsters and Reddit over time" }, box);
    for (const [t, label] of dateTicks(start, end)) {
      svg("line", { x1: x(t), x2: x(t), y1: m.t, y2: m.t + SITES.length * LANE_H, class: "grid" }, root);
      svgText(root, x(t), H - 8, label, { class: "ax", "text-anchor": "middle" });
    }
    const guide = svg("line", { y1: m.t, y2: m.t + SITES.length * LANE_H, stroke: "var(--ink-faint)", "stroke-width": 1, visibility: "hidden" }, root);
    const nearest = drawLanes(root, { top: m.t, laneHeight: LANE_H, left: m.l, right: W - m.r, x, start, end });

    const overlay = svg("rect", { x: m.l, y: m.t, width: pw, height: SITES.length * LANE_H, fill: "transparent", class: "zoomable" }, root);
    const hideGuide = () => guide.setAttribute("visibility", "hidden");
    const pick = (e) => {
      const r = root.getBoundingClientRect();
      const best = nearest(e.clientX - r.left, e.clientY - r.top);
      if (!best) {
        hideGuide();
        return null;
      }
      guide.setAttribute("x1", best.cx);
      guide.setAttribute("x2", best.cx);
      guide.setAttribute("visibility", "visible");
      return { key: best.s, html: submissionTip(best.s) };
    };
    markTips(overlay, pick, hideGuide);
    enableDragZoom(root, overlay, {
      top: m.t,
      height: SITES.length * LANE_H,
      toTime: (px) => start + (clamp(px, m.l, m.l + pw) - m.l) / pw * (end - start),
      onZoom,
      onReset,
    });
  }

  function setUpTimeline() {
    const reset = byId("timeline-reset");
    let press = () => {};
    let redraw = () => {};

    const zoomTo = (span) => {
      timelineZoom = span;
      reset.hidden = false;
      press(null);
      redraw();
    };
    const clearZoom = () => {
      timelineZoom = null;
      reset.hidden = true;
      press(timelineRange);
      redraw();
    };

    redraw = mount(byId("fig-timeline"), (W) => drawTimeline(W, zoomTo, clearZoom));
    press = segmented(byId("timeline-range"), Object.entries(RANGE_LABELS), timelineRange, (value) => {
      timelineRange = value;
      clearZoom();
    });
    reset.addEventListener("click", clearZoom);
  }

  // ---------------------------------------------------------------------------
  // Table 3: every submission
  // ---------------------------------------------------------------------------

  function setUpSubmissions() {
    let filter = SiteFilter.ALL;
    const rows = () => submissions.filter((s) => filter === SiteFilter.ALL || s.site === filter);
    const columns = [
      {
        key: "title",
        label: "Title",
        width: "46%",
        first: SortDirection.ASC,
        value: (s) => s.title.toLowerCase(),
        cell: (s) => `<td><a href="${SITE_LINK[s.site](s.id)}">${esc(s.title)}</a>${subredditOf(s) ? `<span class="sub">${esc(subredditOf(s))}</span>` : ""}</td>`,
      },
      { key: "site", label: "Site", width: "12%", first: SortDirection.ASC, value: (s) => s.site, cell: (s) => `<td><span class="chip">${SITE_SHORT[s.site]}</span></td>` },
      { key: "created_at", label: "Submitted", width: "16%", first: SortDirection.DESC, value: (s) => s.created_at, cell: (s) => `<td class="num" style="text-align:left">${dayOf(s.created_at)}</td>` },
      { key: "points", label: "Points", width: "13%", numeric: true, first: SortDirection.DESC, value: (s) => s.points, cell: (s) => numCell(fmt.format(s.points)) },
      { key: "comments", label: "Comments", width: "13%", numeric: true, first: SortDirection.DESC, value: (s) => s.comments, cell: (s) => numCell(fmt.format(s.comments)) },
    ];

    const table = sortableTable(byId("submissions"), columns, rows, { key: "created_at", direction: SortDirection.DESC });
    const redraw = () => {
      byId("submissions-count").innerHTML = `<b>${rows().length}</b> submissions`;
      table();
    };
    segmented(byId("submissions-site"), [[SiteFilter.ALL, "All"], ...SITES.map((site) => [site, SITE_NAMES[site]])], filter, (value) => {
      filter = value;
      redraw();
    });
    redraw();
  }

  // ---------------------------------------------------------------------------
  // Fig. 3: Hacker News rank over time
  // ---------------------------------------------------------------------------

  let selectedStory = rankedStories.length ? rankedStories[0].id : null;
  let redrawRanks = () => {};

  // A story's samples split into runs, broken wherever it left the top 30 or
  // the samples have a hole.
  function runsOf(series) {
    const runs = [];
    let run = [];
    let previous = null;
    for (const [minute, rank] of series) {
      if (minute / MINUTES_PER_HOUR > RANK_HOURS) {
        break;
      }
      const hole = previous !== null && minute - previous > RANK_GAP_MINUTES;
      if ((rank > FRONT_PAGE_RANK || hole) && run.length) {
        runs.push(run);
        run = [];
      }
      if (rank <= FRONT_PAGE_RANK) {
        run.push([minute, rank]);
      }
      previous = minute;
    }
    if (run.length) {
      runs.push(run);
    }
    return runs;
  }

  function drawRankSummary() {
    const s = rankedStories.find((r) => r.id === selectedStory);
    if (!s) {
      byId("rank-summary").textContent = "";
      return;
    }
    byId("rank-summary").innerHTML =
      `peak <b>#${s.peak_rank}</b> · <b>${s.front_page_hours}</b> hours in the top 30 · <b>${fmt.format(s.points)}</b> points · ` +
      `<a href="${SITE_LINK[Site.HN](s.id)}">${fmt.format(s.comments)} comments</a>`;
  }

  function drawRanks(W) {
    const box = byId("fig-ranks");
    const H = Math.round(clamp(W * 0.42, 260, 360));
    const m = { l: 40, r: 16, t: 24, b: 30 };
    const pw = W - m.l - m.r;
    const ph = H - m.t - m.b;
    const x = (minute) => m.l + (minute / MINUTES_PER_HOUR / RANK_HOURS) * pw;
    const y = (rank) => m.t + ((rank - 1) / (FRONT_PAGE_RANK - 1)) * ph;

    const root = svg("svg", { width: W, height: H, viewBox: `0 0 ${W} ${H}`, role: "img", "aria-label": "Hacker News front-page rank over time for each story" }, box);
    for (const t of RANK_TICKS) {
      svg("line", { x1: m.l, x2: W - m.r, y1: y(t), y2: y(t), class: "grid" }, root);
      svgText(root, m.l - 8, y(t) + 3.5, `#${t}`, { class: "ax", "text-anchor": "end" });
    }
    for (let h = 0; h <= RANK_HOURS; h += RANK_HOUR_STEP) {
      svgText(root, x(h * MINUTES_PER_HOUR), H - 8, `${h}h`, { class: "ax", "text-anchor": "middle" });
    }
    // Axis titles share the top edge, clear of the tick labels on both axes.
    svgText(root, 0, 12, "Rank", { class: "ax-title" });
    svgText(root, W - m.r, 12, "hours since first ranked", { class: "ax-title", "text-anchor": "end" });

    const pathOf = (runs) => runs.map((run) => "M" + run.map(([minute, rank]) => `${x(minute).toFixed(1)},${y(rank).toFixed(1)}`).join("L")).join("");

    // Every story quietly, then the selected one on top in the accent.
    const lines = rankedStories.map((s) => ({ s, runs: runsOf(hnRanks[s.id].series) }));
    for (const { s, runs } of lines) {
      if (s.id === selectedStory) {
        continue;
      }
      svg("path", { d: pathOf(runs), fill: "none", stroke: "var(--dot)", "stroke-width": 1.25, "stroke-opacity": 0.7, "stroke-linejoin": "round" }, root);
    }
    const hover = svg("path", { fill: "none", stroke: "var(--ink-muted)", "stroke-width": 2, "stroke-linejoin": "round", visibility: "hidden" }, root);

    const selected = lines.find((l) => l.s.id === selectedStory);
    if (selected) {
      svg("path", { d: pathOf(selected.runs), fill: "none", stroke: "var(--accent)", "stroke-width": 2.25, "stroke-linejoin": "round", "stroke-linecap": "round" }, root);
      const peak = selected.runs.flat().reduce((best, p) => (p[1] < best[1] ? p : best), [0, Infinity]);
      if (Number.isFinite(peak[1])) {
        svg("circle", { cx: x(peak[0]), cy: y(peak[1]), r: 4.5, fill: "var(--accent)", stroke: "var(--paper)", "stroke-width": 2 }, root);
        // The label sits above the peak, where the line cannot pass: nothing
        // ranks better than the peak.
        svgText(root, x(peak[0]), y(peak[1]) - 9, `#${peak[1]}`, { class: "lab", "text-anchor": "middle" });
      }
    }

    // Hover or a tap finds the story whose line passes closest to the pointer;
    // a click or the tap selects it.
    const HIT_PX = 14;
    const overlay = svg("rect", { x: m.l, y: m.t, width: pw, height: ph, fill: "transparent" }, root);
    const hideHover = () => hover.setAttribute("visibility", "hidden");
    const pick = (e) => {
      const r = root.getBoundingClientRect();
      const px = e.clientX - r.left;
      const py = e.clientY - r.top;
      const minute = ((px - m.l) / pw) * RANK_HOURS * MINUTES_PER_HOUR;
      let best = null;
      let bestD = HIT_PX;
      for (const line of lines) {
        for (const run of line.runs) {
          for (const [bucket, rank] of run) {
            if (Math.abs(bucket - minute) > RANK_GAP_MINUTES / 2) {
              continue;
            }
            const dist = Math.hypot(x(bucket) - px, y(rank) - py);
            if (dist < bestD) {
              bestD = dist;
              best = { line, bucket, rank };
            }
          }
        }
      }
      if (!best) {
        hideHover();
        return null;
      }
      hover.setAttribute("d", pathOf(best.line.runs));
      hover.setAttribute("visibility", "visible");
      const s = best.line.s;
      return {
        key: `${s.id}@${best.bucket}`,
        story: s,
        html: `<b>${esc(s.title)}</b>
        <div class="row"><span>${(best.bucket / MINUTES_PER_HOUR).toFixed(1)}h in</span><span>#${best.rank}</span></div>
        <div class="row"><span>Peak</span><span>#${s.peak_rank}</span></div>
        <div class="row"><span>Hours in the top 30</span><span>${s.front_page_hours}</span></div>`,
      };
    };
    markTips(overlay, pick, hideHover);

    // Registered after the tooltip's own click handler, which runs first and
    // opens the tooltip before the selection redraws the chart.
    overlay.addEventListener("click", (e) => {
      const hit = pick(e);
      if (!hit) {
        return;
      }
      selectRankStory(hit.story.id);
    });
  }

  function selectRankStory(id) {
    selectedStory = id;
    byId("rank-story").value = id;
    drawRankSummary();
    redrawRanks();
  }

  function setUpRanks() {
    if (!rankedStories.length) {
      hideFigure("fig-ranks");
      return;
    }
    const select = byId("rank-story");
    select.innerHTML = rankedStories.map((s) => `<option value="${esc(s.id)}">#${s.peak_rank} · ${esc(s.title)} (${dayOf(s.created_at)})</option>`).join("");
    select.value = selectedStory;
    select.addEventListener("change", () => selectRankStory(select.value));
    drawRankSummary();
    redrawRanks = mount(byId("fig-ranks"), drawRanks);
  }

  // ---------------------------------------------------------------------------
  // Table 4: stories that reached the Hacker News front page
  // ---------------------------------------------------------------------------

  function setUpFrontPage() {
    if (!frontPage.length) {
      hideFigure("front-page");
      return;
    }
    byId("front-page-count").innerHTML = `<b>${frontPage.length}</b> of ${hn.length} submissions`;
    const columns = [
      { key: "title", label: "Title", width: "32%", first: SortDirection.ASC, value: (s) => s.title.toLowerCase(), cell: (s) => `<td><a href="${SITE_LINK[Site.HN](s.id)}">${esc(s.title)}</a></td>` },
      { key: "created_at", label: "Submitted", first: SortDirection.DESC, value: (s) => s.created_at, cell: (s) => `<td class="num" style="text-align:left">${dayOf(s.created_at)}</td>` },
      { key: "points", label: "Points", numeric: true, first: SortDirection.DESC, value: (s) => s.points, cell: (s) => numCell(fmt.format(s.points)) },
      { key: "comments", label: "Comments", numeric: true, first: SortDirection.DESC, value: (s) => s.comments, cell: (s) => numCell(fmt.format(s.comments)) },
      { key: "peak_rank", label: "Peak rank", tip: TIPS.peak, numeric: true, first: SortDirection.ASC, value: (s) => s.peak_rank, cell: (s) => `<td class="num"><span class="rank-chip">#${s.peak_rank}</span></td>` },
      { key: "front_page_hours", label: "Hours in top 30", tip: TIPS.top30, numeric: true, first: SortDirection.DESC, value: (s) => s.front_page_hours, cell: (s) => numCell(s.front_page_hours) },
      { key: "top10_hours", label: "Hours in top 10", tip: TIPS.top10, numeric: true, first: SortDirection.DESC, value: (s) => s.top10_hours, cell: (s) => numCell(s.top10_hours) },
    ];
    sortableTable(byId("front-page"), columns, () => frontPage, { key: "peak_rank", direction: SortDirection.ASC });
  }

  // ---------------------------------------------------------------------------
  // Fig. 4: visits per day by source, with submission lanes
  // ---------------------------------------------------------------------------

  let trafficRange = Range.RECENT;
  let trafficZoom = null;

  // One entry per calendar day, zeros where GA4 reported nothing.
  function trafficDays() {
    const byDate = new Map(traffic.daily.map((d) => [d.date, d]));
    const days = [];
    for (let t = Date.parse(trafficStart); t <= Date.parse(trafficEnd); t += DAY_MS) {
      const date = new Date(t).toISOString().slice(0, 10);
      const d = byDate.get(date) || {};
      days.push({ t, date, values: TRAFFIC_SERIES.map((s) => s.keys.reduce((a, k) => a + (d[k] || 0), 0)) });
    }
    return days;
  }

  function drawTrafficLegend() {
    byId("traffic-legend").innerHTML = TRAFFIC_SERIES.map((s) => `<span><i style="background:${s.color}"></i>${esc(s.name)}</span>`).join("");
  }

  function drawTraffic(W, allDays, onZoom, onReset) {
    const box = byId("fig-traffic");
    const [spanStart, spanEnd] = spanOf(trafficRange, trafficZoom, allDays[0].t, allDays[allDays.length - 1].t);
    const days = allDays.filter((d) => d.t >= spanStart && d.t <= spanEnd);
    if (days.length < 2) {
      return;
    }

    const LANE_H = 30;
    const m = { l: 72, r: 16, t: 24, b: 26 };
    const ph = Math.round(clamp(W * 0.34, 200, 300));
    const lanesTop = m.t + ph + 12;
    const H = lanesTop + SITES.length * LANE_H + m.b;
    const pw = W - m.l - m.r;
    const start = days[0].t;
    const end = days[days.length - 1].t;
    const x = (t) => m.l + ((t - start) / (end - start)) * pw;
    const toTime = (px) => start + ((clamp(px, m.l, m.l + pw) - m.l) / pw) * (end - start);
    const totals = days.map((d) => d.values.reduce((a, b) => a + b, 0));
    const { max: yMax, step } = niceMax(Math.max(...totals));
    const y = (v) => m.t + ph - (v / yMax) * ph;

    const root = svg("svg", { width: W, height: H, viewBox: `0 0 ${W} ${H}`, role: "img", "aria-label": "Visits per day stacked by source, with submissions below" }, box);
    for (let t = 0; t <= yMax; t += step) {
      svg("line", { x1: m.l, x2: W - m.r, y1: y(t), y2: y(t), class: t === 0 ? "base" : "grid" }, root);
      svgText(root, m.l - 8, y(t) + 3.5, fmt.format(t), { class: "ax", "text-anchor": "end" });
    }
    svgText(root, 0, 12, "Visits per day", { class: "ax-title" });
    for (const [t, label] of dateTicks(start, end)) {
      svgText(root, x(t), H - 8, label, { class: "ax", "text-anchor": "middle" });
    }

    // Stacked layers, bottom up, each a closed band between two running sums.
    const lower = days.map(() => 0);
    const bands = TRAFFIC_SERIES.map((s, k) => {
      const below = [...lower];
      days.forEach((d, i) => {
        lower[i] += d.values[k];
      });
      return { s, below, above: [...lower] };
    });
    for (const { s, below, above } of bands) {
      const top = days.map((d, i) => `${x(d.t).toFixed(1)},${y(above[i]).toFixed(1)}`);
      const bottom = days.map((d, i) => `${x(d.t).toFixed(1)},${y(below[i]).toFixed(1)}`).reverse();
      svg("path", { d: `M${top.join("L")}L${bottom.join("L")}Z`, fill: s.color }, root);
    }

    const guide = svg("line", { y1: m.t, y2: lanesTop + SITES.length * LANE_H, stroke: "var(--ink-faint)", "stroke-width": 1, visibility: "hidden" }, root);
    const nearest = drawLanes(root, { top: lanesTop, laneHeight: LANE_H, left: m.l, right: W - m.r, x, start, end: end + DAY_MS });

    // One hit area over the chart and the lanes: hover or a tap shows the
    // day's visits, or the nearest submission when over a lane; dragging zooms.
    const overlay = svg("rect", { x: m.l, y: m.t, width: pw, height: lanesTop + SITES.length * LANE_H - m.t, fill: "transparent", class: "zoomable" }, root);
    const hideGuide = () => guide.setAttribute("visibility", "hidden");
    const pick = (e) => {
      const r = root.getBoundingClientRect();
      const px = e.clientX - r.left;
      const py = e.clientY - r.top;
      if (py >= lanesTop) {
        const best = nearest(px, py);
        if (!best) {
          hideGuide();
          return null;
        }
        guide.setAttribute("x1", best.cx);
        guide.setAttribute("x2", best.cx);
        guide.setAttribute("visibility", "visible");
        return { key: best.s, html: submissionTip(best.s) };
      }
      const i = clamp(Math.round(((px - m.l) / pw) * (days.length - 1)), 0, days.length - 1);
      const d = days[i];
      guide.setAttribute("x1", x(d.t));
      guide.setAttribute("x2", x(d.t));
      guide.setAttribute("visibility", "visible");
      const rows = TRAFFIC_SERIES.map((s, k) => `<div class="row"><span>${esc(s.name)}</span><span>${fmt.format(d.values[k])}</span></div>`)
        .reverse()
        .join("");
      return { key: d, html: `<b>${d.date}</b>${rows}<div class="row"><span>Total</span><span>${fmt.format(totals[i])}</span></div>` };
    };
    markTips(overlay, pick, hideGuide);
    enableDragZoom(root, overlay, { top: m.t, height: ph, toTime, onZoom, onReset });
  }

  function setUpTraffic() {
    const allDays = trafficDays();
    if (allDays.length < 2) {
      hideFigure("fig-traffic");
      return;
    }
    drawTrafficLegend();

    const reset = byId("traffic-reset");
    let press = () => {};
    let redraw = () => {};
    const zoomTo = (span) => {
      trafficZoom = span;
      reset.hidden = false;
      press(null);
      redraw();
    };
    const clearZoom = () => {
      trafficZoom = null;
      reset.hidden = true;
      press(trafficRange);
      redraw();
    };

    redraw = mount(byId("fig-traffic"), (W) => drawTraffic(W, allDays, zoomTo, clearZoom));
    press = segmented(byId("traffic-range"), Object.entries(RANGE_LABELS), trafficRange, (value) => {
      trafficRange = value;
      clearZoom();
    });
    reset.addEventListener("click", clearZoom);
  }

  // ---------------------------------------------------------------------------
  // Fig. 5: world map of visits
  // ---------------------------------------------------------------------------

  const MAP_URL = "/assets/vendor/countries-110m.json";
  const MAP_ASPECT = 0.52;
  const ANTARCTICA_NUMERIC = "010";
  const MAP_TOP_COUNTRIES = 3;

  function drawMap(W, features) {
    const box = byId("fig-map");
    const H = Math.round(W * MAP_ASPECT);
    const byNumeric = new Map(geography.filter((c) => c.iso_numeric).map((c) => [c.iso_numeric, c]));
    const total = geography.reduce((a, c) => a + c.sessions, 0) || 1;
    const maxLog = Math.log1p(Math.max(...geography.map((c) => c.sessions), 1));

    const projection = d3.geoNaturalEarth1().fitSize([W, H], { type: "Sphere" });
    const path = d3.geoPath(projection);
    const root = svg("svg", { width: W, height: H, viewBox: `0 0 ${W} ${H}`, role: "img", "aria-label": "World map of visits by country" }, box);
    svg("path", { d: path({ type: "Sphere" }), class: "map-sphere" }, root);

    for (const feature of features) {
      const country = byNumeric.get(feature.id);
      const share = country ? Math.log1p(country.sessions) / maxLog : 0;
      const shape = svg("path", {
        d: path(feature),
        class: "map-country",
        style: `fill: ${country ? heatFill(share) : "var(--paper)"}`,
      }, root);
      const name = country ? country.country : feature.properties.name;
      const visits = country ? country.sessions : 0;
      const html = `<b>${esc(name)}</b>
          <div class="row"><span>Visits</span><span>${fmt.format(visits)}</span></div>
          <div class="row"><span>Share</span><span>${pct(visits / total)}</span></div>`;
      markTips(shape, () => ({ key: feature, html }), NOOP);
    }
  }

  async function setUpMap() {
    const top = geography.slice(0, MAP_TOP_COUNTRIES);
    const total = geography.reduce((a, c) => a + c.sessions, 0) || 1;
    byId("map-top").innerHTML = top.map((c) => `${esc(c.country)} <b>${pct(c.sessions / total, 0)}</b>`).join(" · ");

    if (!window.d3 || !d3.geoNaturalEarth1 || !window.topojson) {
      byId("fig-map").innerHTML = '<p class="readership__empty">The map could not load.</p>';
      return;
    }
    const topology = await fetch(MAP_URL).then((r) => r.json());
    const features = topojson.feature(topology, topology.objects.countries).features.filter((f) => f.id !== ANTARCTICA_NUMERIC);
    mount(byId("fig-map"), (W) => drawMap(W, features));
  }

  // ---------------------------------------------------------------------------
  // Fig. 6: when readers visit, by source and in a chosen time zone
  // ---------------------------------------------------------------------------

  // GA4 numbers weekdays from 0 for Sunday; the grid reads Monday first.
  const WEEKDAY_NAMES = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
  const WEEKDAY_ORDER = [1, 2, 3, 4, 5, 6, 0];
  const HOUR_LABEL_STEP = 3;
  const HOUR_LABEL_NARROW_STEP = 6;
  const NARROW_WIDTH = 520;

  const ALL_SOURCES = "all";
  const HOURS_SOURCES = [
    [ALL_SOURCES, "All"],
    ["hn", "Hacker News"],
    ["reddit", "Reddit"],
    ["lobsters", "Lobsters"],
    ["search", "Google search"],
  ];
  const ZONE_CHOICES = ["UTC", "America/Los_Angeles", "America/New_York", "Europe/London", "Europe/Berlin", "Asia/Kolkata", "Asia/Shanghai", "Asia/Tokyo", "Australia/Sydney"];

  const viewerZone = Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";
  let hoursSource = ALL_SOURCES;
  let hoursZone = viewerZone;

  // Minutes a zone is ahead of UTC right now. Hours are shifted by today's
  // offset, so a week that crosses a daylight-saving change is off by one hour
  // on the days it has not changed yet.
  function zoneOffsetMinutes(zone) {
    const now = new Date(Math.floor(Date.now() / MINUTE_MS) * MINUTE_MS);
    const parts = new Intl.DateTimeFormat("en-US", {
      timeZone: zone,
      hourCycle: "h23",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
    }).formatToParts(now);
    const part = (type) => Number(parts.find((p) => p.type === type).value);
    const asUtc = Date.UTC(part("year"), part("month") - 1, part("day"), part("hour"), part("minute"));
    return Math.round((asUtc - now.getTime()) / MINUTE_MS);
  }

  // The selected source's grid, moved from the property's zone into the chosen
  // one by whole hours; weekdays roll over with the hours.
  function shiftedGrid() {
    const base = hoursSource === ALL_SOURCES || !hours.by_source ? hours.sessions : hours.by_source[hoursSource];
    return shiftGrid(base);
  }

  function shiftGrid(base) {
    const from = hours.time_zone || "UTC";
    const shift = Math.round((zoneOffsetMinutes(hoursZone) - zoneOffsetMinutes(from)) / MINUTES_PER_HOUR);
    const grid = Array.from({ length: DAYS_PER_WEEK }, () => new Array(HOURS_PER_DAY).fill(0));
    for (let day = 0; day < DAYS_PER_WEEK; day++) {
      for (let hour = 0; hour < HOURS_PER_DAY; hour++) {
        const moved = (((day * HOURS_PER_DAY + hour + shift) % HOURS_PER_WEEK) + HOURS_PER_WEEK) % HOURS_PER_WEEK;
        grid[Math.floor(moved / HOURS_PER_DAY)][moved % HOURS_PER_DAY] += base[day][hour];
      }
    }
    return grid;
  }

  const zoneLabel = (zone) => zone.replace(/_/g, " ");

  function drawHours(W) {
    const box = byId("fig-hours");
    const grid = shiftedGrid();
    const m = { l: 40, r: 4, t: 18, b: 4 };
    const pw = W - m.l - m.r;
    const cell = pw / HOURS_PER_DAY;
    const rowHeight = clamp(cell * 0.85, 14, 26);
    const H = m.t + WEEKDAY_ORDER.length * rowHeight + m.b;
    const max = Math.max(1, ...grid.flat());
    const total = grid.flat().reduce((a, b) => a + b, 0) || 1;

    const root = svg("svg", { width: W, height: H, viewBox: `0 0 ${W} ${H}`, role: "img", "aria-label": "Visits by weekday and hour" }, box);
    const step = W < NARROW_WIDTH ? HOUR_LABEL_NARROW_STEP : HOUR_LABEL_STEP;
    for (let h = 0; h < HOURS_PER_DAY; h += step) {
      svgText(root, m.l + h * cell, 11, `${hh(h)}:00`, { class: "ax" });
    }

    WEEKDAY_ORDER.forEach((day, row) => {
      const y = m.t + row * rowHeight;
      svgText(root, m.l - 8, y + rowHeight / 2 + 3.5, WEEKDAY_NAMES[day].slice(0, 3), { class: "ax", "text-anchor": "end" });
      grid[day].forEach((sessions, h) => {
        const rect = svg("rect", {
          x: m.l + h * cell + 1,
          y: y + 1,
          width: Math.max(1, cell - 2),
          height: rowHeight - 2,
          rx: 2,
          style: `fill: ${heatFill(sessions / max)}`,
        }, root);
        const html = `<b>${WEEKDAY_NAMES[day]}, ${hh(h)}:00 to ${hh((h + 1) % HOURS_PER_DAY)}:00</b>
            <div class="row"><span>Visits</span><span>${fmt.format(sessions)}</span></div>
            <div class="row"><span>Share of the week</span><span>${pct(sessions / total)}</span></div>`;
        markTips(rect, () => ({ key: rect, html }), NOOP);
      });
    });
  }

  // A smooth curve through [x, y] points, as the cubic segments of a
  // Catmull-Rom spline. Returns path commands continuing from the first point.
  const SPLINE_TENSION = 6;
  function smoothPath(points) {
    let d = "";
    for (let i = 0; i < points.length - 1; i++) {
      const p0 = points[Math.max(i - 1, 0)];
      const p1 = points[i];
      const p2 = points[i + 1];
      const p3 = points[Math.min(i + 2, points.length - 1)];
      const c1 = [p1[0] + (p2[0] - p0[0]) / SPLINE_TENSION, p1[1] + (p2[1] - p0[1]) / SPLINE_TENSION];
      const c2 = [p2[0] - (p3[0] - p1[0]) / SPLINE_TENSION, p2[1] - (p3[1] - p1[1]) / SPLINE_TENSION];
      d += `C${c1[0].toFixed(1)},${c1[1].toFixed(1)} ${c2[0].toFixed(1)},${c2[1].toFixed(1)} ${p2[0].toFixed(1)},${p2[1].toFixed(1)}`;
    }
    return d;
  }

  // One row per source: visits by hour of the day, summed over the week and
  // scaled to that source's busiest hour. The source picked above is drawn in
  // the accent. `onPick`, when given, receives a source's key when its row is
  // clicked.
  function drawRidgeline(W, onPick) {
    const box = byId("fig-ridgeline");
    const rows = HOURS_SOURCES.filter(([key]) => key === ALL_SOURCES || (hours.by_source && hours.by_source[key]));
    const ROW_H = 48;
    const OVERLAP = 1.35;
    // A ridge may rise above its own row by the overlap; the top margin leaves
    // room for the first row to do so without reaching the heading above.
    const m = { l: 112, r: 12, t: Math.ceil(ROW_H * (OVERLAP - 1)) + 10, b: 24 };
    const pw = W - m.l - m.r;
    const H = m.t + rows.length * ROW_H + m.b;
    const x = (h) => m.l + (h / (HOURS_PER_DAY - 1)) * pw;

    const root = svg("svg", { width: W, height: H, viewBox: `0 0 ${W} ${H}`, role: "img", "aria-label": "Hour of the day profile for each source" }, box);
    const step = W < NARROW_WIDTH ? HOUR_LABEL_NARROW_STEP : HOUR_LABEL_STEP;
    for (let h = 0; h < HOURS_PER_DAY; h += step) {
      svg("line", { x1: x(h), x2: x(h), y1: m.t, y2: H - m.b, class: "grid" }, root);
      svgText(root, x(h), H - 6, `${hh(h)}:00`, { class: "ax", "text-anchor": "middle" });
    }

    const ridges = [];
    rows.forEach(([key, name], i) => {
      const base = key === ALL_SOURCES ? hours.sessions : hours.by_source[key];
      const grid = shiftGrid(base);
      const profile = Array.from({ length: HOURS_PER_DAY }, (_, h) => grid.reduce((a, day) => a + day[h], 0));
      const max = Math.max(...profile);
      const min = Math.min(...profile);
      const baseline = m.t + (i + 1) * ROW_H;
      // Scaled from the quietest hour to the busiest, so a source whose visits
      // barely vary across the day still shows where its day peaks.
      const y = (v) => baseline - (max > min ? (v - min) / (max - min) : 0) * ROW_H * OVERLAP;
      const points = profile.map((v, h) => [x(h), y(v)]);
      const curve = smoothPath(points);
      const active = key === hoursSource;

      // Rows are drawn top to bottom and filled with the page's own colour,
      // so each ridge hides the part of the one behind it that it overlaps.
      ridges.push(svg("path", {
        d: `M${x(0)},${baseline}L${points[0][0].toFixed(1)},${points[0][1].toFixed(1)}${curve}L${x(HOURS_PER_DAY - 1)},${baseline}Z`,
        class: active ? "ridge ridge--active" : "ridge",
      }, root));
      svg("line", { x1: m.l, x2: W - m.r, y1: baseline, y2: baseline, class: "base" }, root);

      const labelY = baseline - ROW_H / 2 + 4;
      svgText(root, m.l - 12, labelY, name, { class: "lane", "text-anchor": "end" });
      if (max) {
        const peak = profile.indexOf(max);
        svgText(root, m.l - 12, labelY + 13, `peak ${hh(peak)}:00`, { class: "ax", "text-anchor": "end" });
        svg("circle", { cx: points[peak][0], cy: points[peak][1], r: 2.5, class: active ? "ridge-peak ridge-peak--active" : "ridge-peak" }, root);
      }
    });

    // A transparent band over each row, label included, drawn above every
    // ridge. The bands do not overlap, so a click picks the row it lands in
    // even where the ridge below rises into that row.
    if (!onPick) {
      return;
    }
    rows.forEach(([key], i) => {
      const hit = svg("rect", { x: 0, y: m.t + i * ROW_H, width: W, height: ROW_H, fill: "transparent", class: "ridge-hit" }, root);
      hit.addEventListener("pointerenter", () => ridges[i].classList.add("ridge--hover"));
      hit.addEventListener("pointerleave", () => ridges[i].classList.remove("ridge--hover"));
      hit.addEventListener("click", () => onPick(key));
    });
  }

  function setUpHours() {
    const zones = [...new Set([viewerZone, hours.time_zone || "UTC", ...ZONE_CHOICES])];
    const select = byId("hours-zone");
    select.innerHTML = zones
      .map((zone) => `<option value="${esc(zone)}">${esc(zoneLabel(zone))}</option>`)
      .join("");
    select.value = hoursZone;

    // Picking a source, from its button or by clicking its ridge, marks the
    // button pressed and redraws both charts. There is nothing to pick without
    // a per-source breakdown.
    let pressSource = () => {};
    const pickSource = (value) => {
      hoursSource = value;
      pressSource(value);
      redraw();
    };

    const redrawHeat = mount(byId("fig-hours"), drawHours);
    const redrawRidges = mount(byId("fig-ridgeline"), (W) => drawRidgeline(W, hours.by_source ? pickSource : null));
    const redraw = () => {
      redrawHeat();
      redrawRidges();
    };

    if (hours.by_source) {
      pressSource = segmented(byId("hours-source"), HOURS_SOURCES, hoursSource, pickSource);
    }
    select.addEventListener("change", () => {
      hoursZone = select.value;
      redraw();
    });
  }

  // ---------------------------------------------------------------------------
  // Fig. 7: operating system and device
  // ---------------------------------------------------------------------------

  const PLATFORM_PAGES = 20;
  const OS_SHOWN = 6;
  // Shares below half a percent round to 0% and only add rows.
  const MIN_SHARE = 0.005;
  const DEVICE_ORDER = ["desktop", "mobile", "tablet"];
  const DEVICE_COLORS = ["var(--s1)", "var(--s2)", "var(--s3)", "var(--dot)"];

  // The largest entries of a count map as shares, with the rest folded into
  // "Other" and anything too small to show dropped.
  function topShares(counts, shown) {
    const entries = Object.entries(counts).sort((a, b) => b[1] - a[1]);
    const total = entries.reduce((a, [, v]) => a + v, 0) || 1;
    const top = entries.slice(0, shown).map(([k, v]) => [k, v / total]);
    const rest = entries.slice(shown).reduce((a, [, v]) => a + v, 0) / total;
    if (rest >= MIN_SHARE) {
      top.push(["Other", rest]);
    }
    return top.filter(([, share]) => share >= MIN_SHARE);
  }

  // Known devices in a fixed order so each keeps its colour; anything else last.
  const deviceRank = (name) => {
    const i = DEVICE_ORDER.indexOf(name);
    return i === -1 ? DEVICE_ORDER.length : i;
  };

  function setUpPlatforms() {
    const paths = (engagement || [])
      .filter((e) => isPost(e.path) && platforms.by_path[e.path])
      .slice(0, PLATFORM_PAGES)
      .map((e) => e.path);
    const select = byId("platform-page");
    select.innerHTML = `<option value="${ALL_PAGES}">All pages</option>` + paths.map((path) => `<option value="${esc(path)}">${esc(titleOf(path))}</option>`).join("");

    const render = () => {
      const counts = select.value === ALL_PAGES ? platforms.all : platforms.by_path[select.value];
      barList(byId("os-bars"), topShares(counts.os, OS_SHOWN).map(([name, share]) => [name, share, ""]));

      const devices = topShares(counts.device, DEVICE_ORDER.length).sort((a, b) => deviceRank(a[0]) - deviceRank(b[0]));
      const bar = byId("device-bar");
      bar.innerHTML = devices.map(([, share], i) => `<span style="flex-basis:${share * 100}%; background:${DEVICE_COLORS[i]}"></span>`).join("");
      bar.setAttribute("role", "img");
      bar.setAttribute("aria-label", devices.map(([name, share]) => `${name} ${pct(share, 0)}`).join(", "));
      byId("device-legend").innerHTML = devices
        .map(([name, share], i) => `<div class="legend"><span><i style="background:${DEVICE_COLORS[i]}"></i>${esc(name)}</span><span style="margin-left:auto">${pct(share, 0)}</span></div>`)
        .join("");
    };
    select.addEventListener("change", render);
    render();
  }

  // ---------------------------------------------------------------------------
  // Boot
  // ---------------------------------------------------------------------------

  setUpDefinitionTips();
  drawLedger();
  drawEmptyStates();
  fillSearchWindow();

  if (search) {
    if (sources.ga4) {
      mount(byId("fig-scatter"), drawScatter);
    }
    setUpTopPages();
    setUpSearches();
  }

  if (submissions.length) {
    setUpTimeline();
    setUpSubmissions();
  } else {
    hideFigure("fig-timeline");
    hideFigure("submissions");
  }

  setUpRanks();
  setUpFrontPage();

  if (trafficStart) {
    setUpTraffic();
  }

  if (geography && geography.length) {
    setUpMap();
  } else if (sources.ga4) {
    hideFigure("fig-map");
  }

  if (hours) {
    setUpHours();
  } else if (sources.ga4) {
    hideFigure("fig-hours");
  }

  if (platforms) {
    setUpPlatforms();
  }
})();
