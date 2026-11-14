// Theme switch, copy buttons and the docs contents marker. The pages read fully without this file.
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
  var toc = document.querySelector(".docs nav");
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
})();
