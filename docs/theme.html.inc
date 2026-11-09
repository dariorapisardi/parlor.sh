<link rel="icon" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16'%3E%3Crect width='16' height='16' rx='3' fill='%231d1c1a'/%3E%3Ccircle cx='5' cy='8' r='2' fill='%23e9e6df'/%3E%3Ccircle cx='11' cy='8' r='2' fill='%23e0925f'/%3E%3C/svg%3E">
<script>
// Theme: follows the system unless the reader picked one; the choice stays in this browser.
(function () {
  var root = document.documentElement, saved = null;
  try { saved = localStorage.getItem("theme"); } catch (e) {}
  if (saved === "light" || saved === "dark") root.dataset.theme = saved;
  window.addEventListener("DOMContentLoaded", function () {
    var b = document.getElementById("theme");
    var dark = function () { return root.dataset.theme ? root.dataset.theme === "dark" : matchMedia("(prefers-color-scheme: dark)").matches; };
    var icon = '<svg viewBox="0 0 16 16" aria-hidden="true"><circle cx="8" cy="8" r="6.7" fill="none" stroke="currentColor" stroke-width="1.6"/><path d="M8 1.3a6.7 6.7 0 0 0 0 13.4z" fill="currentColor"/></svg>';
    var label = function () { b.innerHTML = icon + (dark() ? "light" : "dark"); };
    b.addEventListener("click", function () {
      root.dataset.theme = dark() ? "light" : "dark";
      try { localStorage.setItem("theme", root.dataset.theme); } catch (e) {}
      label();
    });
    label();
    b.hidden = false; // without this script the button would do nothing, so it starts hidden
  });
})();
</script>
