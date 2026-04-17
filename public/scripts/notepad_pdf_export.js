document.addEventListener("DOMContentLoaded", () => {
  const root = document.querySelector("[data-notepad-pdf-export]");
  if (!root) return;

  const printButton = root.querySelector("[data-notepad-pdf-print]");
  printButton?.addEventListener("click", () => {
    window.print();
  });

  if (root.dataset.autoprint === "true") {
    window.setTimeout(() => {
      window.print();
    }, 160);
  }
});
