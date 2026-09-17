<link rel="icon" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 16 16'%3E%3Crect width='16' height='16' rx='3' fill='%238a3b12'/%3E%3Cpath d='M4 5h8M4 8h8M4 11h5' stroke='%23fbfaf7' stroke-width='1.6' stroke-linecap='round'/%3E%3C/svg%3E">
<script>
// Theme: follows the system unless the reader picked one; the choice stays in this browser.
(function () {
  var root = document.documentElement, saved = null;
  try { saved = localStorage.getItem("theme"); } catch (e) {}
  if (saved === "light" || saved === "dark") root.dataset.theme = saved;
  window.addEventListener("DOMContentLoaded", function () {
    var b = document.getElementById("theme");
    var dark = function () { return root.dataset.theme ? root.dataset.theme === "dark" : matchMedia("(prefers-color-scheme: dark)").matches; };
    var label = function () { b.textContent = dark() ? "◐ light" : "◐ dark"; };
    b.addEventListener("click", function () {
      root.dataset.theme = dark() ? "light" : "dark";
      try { localStorage.setItem("theme", root.dataset.theme); } catch (e) {}
      label();
    });
    label();
  });
})();
</script>
