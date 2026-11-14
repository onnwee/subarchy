// Theme switch, copy buttons, the docs sidebar, its contents marker and the scroll marks.
// The pages read fully without this file.
(function () {
  var root = document.documentElement;
  var colours = { dark: "#100B19", light: "#F0ECE4" };
  try { var saved = localStorage.getItem("subarchy-theme"); if (saved === "light" || saved === "dark") root.setAttribute("data-theme", saved); } catch (e) {}
  function current() {
    return root.getAttribute("data-theme") || (window.matchMedia("(prefers-color-scheme: light)").matches ? "light" : "dark");
  }
  function paintBar() {
    document.querySelectorAll('meta[name="theme-color"]').forEach(function (m) { m.setAttribute("content", colours[current()]); });
  }
  if (root.getAttribute("data-theme")) paintBar();

  // One polite live region announces copies and theme changes.
  var live = document.createElement("p");
  live.className = "sr"; live.setAttribute("aria-live", "polite");
  document.body.appendChild(live);
  function say(text) { live.textContent = ""; setTimeout(function () { live.textContent = text; }, 50); }

  document.querySelectorAll("[data-theme-toggle]").forEach(function (b) {
    b.hidden = false;
    function label() {
      var next = current() === "dark" ? "paper" : "ink";
      b.textContent = next;
      b.setAttribute("aria-label", "Switch to the " + next + " theme");
    }
    label();
    b.addEventListener("click", function () {
      var next = current() === "dark" ? "light" : "dark";
      root.setAttribute("data-theme", next);
      try { localStorage.setItem("subarchy-theme", next); } catch (e) {}
      label(); paintBar();
      say(next === "light" ? "Paper theme" : "Ink theme");
    });
  });

  document.querySelectorAll(".cmd").forEach(function (box) {
    var code = box.querySelector("code");
    var text = code.textContent;
    var b = document.createElement("button");
    b.type = "button"; b.textContent = "copy"; b.setAttribute("aria-label", "copy: " + text);
    var timer;
    function pick() { var r = document.createRange(); r.selectNodeContents(code); var s = getSelection(); s.removeAllRanges(); s.addRange(r); }
    function done(ok) {
      b.textContent = ok ? "copied" : "selected";
      say(ok ? "Copied to the clipboard" : "Could not copy. The command is selected; press Control C to copy it.");
      clearTimeout(timer); timer = setTimeout(function () { b.textContent = "copy"; }, 1600);
    }
    b.addEventListener("click", function () {
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(function () { done(true); }, function () { pick(); done(false); });
      } else { pick(); done(false); }
    });
    box.appendChild(b);
  });

  // Docs: mark the contents link for the section being read.
  // The docs pages list starts closed; wide screens show it beside the page.
  var details = document.querySelector(".docs .toc");
  if (details && window.matchMedia("(min-width: 821px)").matches) details.open = true;
  var toc = document.querySelector(".docs .side .sections");
  if (toc) {
    var links = {};
    toc.querySelectorAll('a[href^="#"]').forEach(function (a) { links[a.getAttribute("href").slice(1)] = a; });
    var heads = Array.prototype.filter.call(document.querySelectorAll(".docs main h2[id]"), function (h) { return links[h.id]; });
    var queued = false;
    function update() {
      queued = false;
      var top = null;
      var atEnd = window.innerHeight + window.scrollY >= document.documentElement.scrollHeight - 2;
      if (atEnd) top = heads[heads.length - 1];
      else heads.forEach(function (h) { if (h.getBoundingClientRect().top < window.innerHeight * 0.3) top = h; });
      Object.keys(links).forEach(function (k) {
        if (top && k === top.id) links[k].setAttribute("aria-current", "true"); else links[k].removeAttribute("aria-current");
      });
    }
    window.addEventListener("scroll", function () { if (!queued) { queued = true; requestAnimationFrame(update); } }, { passive: true });
    update();
  }

  // Docs sidebar: hide it to give the text the width; hovering the toggle, or tabbing to it, floats it back.
  var docs = document.querySelector(".docs");
  var tog = document.querySelector("[data-side-toggle]");
  if (docs && tog) {
    var rail = tog.parentNode;
    var hidden = function () { return root.getAttribute("data-side") === "hidden"; };
    var paintToggle = function () {
      tog.textContent = hidden() ? "\u00bb" : "\u00ab hide";
      tog.setAttribute("aria-label", hidden() ? "Show the docs pages" : "Hide the docs pages");
      tog.setAttribute("aria-expanded", hidden() ? "false" : "true");
    };
    tog.hidden = false;
    paintToggle();
    tog.addEventListener("click", function () {
      var hide = !hidden();
      if (hide) { root.setAttribute("data-side", "hidden"); docs.classList.add("peek-off"); }
      else root.removeAttribute("data-side");
      try { localStorage.setItem("subarchy-side", hide ? "hidden" : "shown"); } catch (e) {}
      paintToggle();
      say(hide ? "Docs pages hidden" : "Docs pages shown");
    });
    // After a click or Escape the floating pages stay away until the pointer or focus leaves.
    rail.addEventListener("mouseleave", function () { docs.classList.remove("peek-off"); });
    rail.addEventListener("focusout", function (e) { if (!rail.contains(e.relatedTarget)) docs.classList.remove("peek-off"); });
    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape" && hidden() && rail.matches(":hover, :focus-within")) {
        docs.classList.add("peek-off");
        if (rail.contains(document.activeElement)) tog.focus();
      }
    });
  }

  // Plugins catalogue: search, category, state and cost filters, and sort. Without this file every card shows.
  var tools = document.querySelector(".ptools");
  var grid = document.querySelector(".pgrid");
  if (tools && grid) {
    tools.hidden = false;
    var cards = Array.prototype.slice.call(grid.children);
    var byName = cards.slice();
    var search = document.getElementById("psearch"), stateSel = document.getElementById("pstate");
    var offline = document.getElementById("poffline"), events = document.getElementById("pevents");
    var sortSel = document.getElementById("psort"), count = document.getElementById("pcount");
    var none = document.querySelector(".pnone"), chips = tools.querySelectorAll(".pchips button");
    var cat = "";
    var apply = function () {
      var words = search.value.toLowerCase().split(/\s+/).filter(Boolean);
      var shown = 0;
      cards.forEach(function (c) {
        var d = c.dataset;
        var ok = (!cat || d.cat === cat) && (!stateSel.value || d.on === stateSel.value) &&
          (!offline.checked || d.net === "0") && (!events.checked || d.timers === "0") &&
          words.every(function (w) { return d.text.indexOf(w) >= 0; });
        c.hidden = !ok;
        if (ok) shown++;
      });
      var order = byName.slice();
      if (sortSel.value === "bar") order.sort(function (a, b) { return a.dataset.order - b.dataset.order; });
      else if (sortSel.value === "cat") order.sort(function (a, b) { return a.dataset.cat < b.dataset.cat ? -1 : a.dataset.cat > b.dataset.cat ? 1 : 0; });
      order.forEach(function (c) { grid.appendChild(c); });
      count.textContent = shown === cards.length ? cards.length + " plugins" : shown + " of " + cards.length + " plugins";
      none.hidden = shown > 0;
      markAll();
    };
    chips.forEach(function (b) {
      b.addEventListener("click", function () {
        cat = b.dataset.cat;
        chips.forEach(function (o) { o.setAttribute("aria-pressed", o === b ? "true" : "false"); });
        apply();
      });
    });
    [search, stateSel, offline, events, sortSel].forEach(function (el) { el.addEventListener("input", apply); el.addEventListener("change", apply); });
    document.querySelector("[data-pclear]").addEventListener("click", function () {
      search.value = ""; stateSel.value = ""; offline.checked = false; events.checked = false;
      chips[0].click(); search.focus();
    });
    // "/" jumps to the search box unless you are already typing somewhere.
    document.addEventListener("keydown", function (e) {
      var t = e.target.tagName;
      if (e.key === "/" && !e.ctrlKey && !e.metaKey && !e.altKey && t !== "INPUT" && t !== "SELECT" && t !== "TEXTAREA") {
        e.preventDefault(); search.focus();
      }
    });
    apply();
  }

  // Scroll marks: the native bars are hidden in style.css. A 2px stroke on the right edge follows the page,
  // and one along the bottom (or right) edge of each scrolling box follows that box.
  var bar = document.createElement("div");
  bar.className = "sbar"; bar.setAttribute("aria-hidden", "true");
  var thumb = document.createElement("i");
  bar.appendChild(thumb);
  document.body.appendChild(bar);
  var boxes = Array.prototype.slice.call(document.querySelectorAll(".scroll, pre, .cmd code, .docs .side"));
  function markPage() {
    var full = document.documentElement.scrollHeight, view = bar.clientHeight || window.innerHeight;
    bar.hidden = full <= view + 1;
    if (bar.hidden) return;
    var size = Math.max(24, view * view / full);
    thumb.style.height = size + "px";
    thumb.style.transform = "translateY(" + (window.scrollY / (full - view)) * (view - size) + "px)";
  }
  function markBox(el) {
    var x = el.scrollWidth > el.clientWidth + 1, y = !x && el.scrollHeight > el.clientHeight + 1;
    el.classList.toggle("sbx", x);
    el.classList.toggle("sby", y);
    if (x) {
      el.style.setProperty("--sb-size", el.clientWidth / el.scrollWidth);
      el.style.setProperty("--sb-pos", el.scrollLeft / (el.scrollWidth - el.clientWidth));
    } else if (y) {
      el.style.setProperty("--sb-size", el.clientHeight / el.scrollHeight);
      el.style.setProperty("--sb-pos", el.scrollTop / (el.scrollHeight - el.clientHeight));
    }
  }
  var pending = false;
  function markAll() {
    if (pending) return;
    pending = true;
    requestAnimationFrame(function () { pending = false; markPage(); boxes.forEach(markBox); });
  }
  window.addEventListener("scroll", markAll, { passive: true });
  window.addEventListener("resize", markAll);
  boxes.forEach(function (el) { el.addEventListener("scroll", function () { requestAnimationFrame(function () { markBox(el); }); }, { passive: true }); });
  if (window.ResizeObserver) {
    var ro = new ResizeObserver(markAll);
    ro.observe(document.body);
    boxes.forEach(function (el) { ro.observe(el); });
  }
  markAll();
})();
