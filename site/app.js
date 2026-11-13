// Theme switch and copy buttons. The pages read fully without this file.
(function () {
  var root = document.documentElement;
  try { var saved = localStorage.getItem("subarchy-theme"); if (saved === "light" || saved === "dark") root.setAttribute("data-theme", saved); } catch (e) {}
  function current() {
    return root.getAttribute("data-theme") || (window.matchMedia("(prefers-color-scheme: light)").matches ? "light" : "dark");
  }
  document.querySelectorAll("[data-theme-toggle]").forEach(function (b) {
    b.hidden = false;
    function label() { b.textContent = current() === "dark" ? "paper" : "ink"; b.setAttribute("aria-label", "Switch to the " + b.textContent + " theme"); }
    label();
    b.addEventListener("click", function () {
      var next = current() === "dark" ? "light" : "dark";
      root.setAttribute("data-theme", next);
      try { localStorage.setItem("subarchy-theme", next); } catch (e) {}
      label();
    });
  });
  document.querySelectorAll(".cmd").forEach(function (box) {
    var code = box.querySelector("code");
    var b = document.createElement("button");
    b.type = "button"; b.textContent = "copy"; b.setAttribute("aria-label", "Copy: " + code.textContent);
    b.addEventListener("click", function () {
      function done(ok) { b.textContent = ok ? "copied" : "select"; setTimeout(function () { b.textContent = "copy"; }, 1600); }
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(code.textContent).then(function () { done(true); }, function () { pick(); done(false); });
      } else { pick(); done(false); }
      function pick() { var r = document.createRange(); r.selectNodeContents(code); var s = getSelection(); s.removeAllRanges(); s.addRange(r); }
    });
    box.appendChild(b);
  });
})();
