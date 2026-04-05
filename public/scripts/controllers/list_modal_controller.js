import { Controller } from "/scripts/vendor/stimulus.js";

export default class extends Controller {
  static targets = ["search", "item", "empty", "count", "pageInfo", "pagination", "previous", "next"];
  static values = { pageSize: { type: Number, default: 5 } };

  connect() {
    this.currentPage = 1;
    this.modalElement = this.element.closest(".modal");
    this.boundReset = this.reset.bind(this);

    if (this.modalElement) {
      this.modalElement.addEventListener("show.bs.modal", this.boundReset);
    }

    this.render();
  }

  disconnect() {
    if (this.modalElement) {
      this.modalElement.removeEventListener("show.bs.modal", this.boundReset);
    }
  }

  search() {
    this.currentPage = 1;
    this.render();
  }

  previousPage() {
    if (this.currentPage > 1) {
      this.currentPage -= 1;
      this.render();
    }
  }

  nextPage() {
    if (this.currentPage < this.totalPages(this.filteredItems())) {
      this.currentPage += 1;
      this.render();
    }
  }

  reset() {
    if (this.hasSearchTarget) {
      this.searchTarget.value = "";
    }

    this.currentPage = 1;
    this.render();
  }

  filteredItems() {
    const query = this.hasSearchTarget ? this.searchTarget.value.trim().toLowerCase() : "";

    if (!query) {
      return this.itemTargets;
    }

    return this.itemTargets.filter((item) => {
      const haystack = item.dataset.searchText || "";
      return haystack.includes(query);
    });
  }

  totalPages(items) {
    return Math.max(Math.ceil(items.length / this.pageSizeValue), 1);
  }

  resultLabel(count) {
    return `${count} notebook${count === 1 ? "" : "s"}`;
  }

  render() {
    const filtered = this.filteredItems();
    const totalPages = this.totalPages(filtered);

    if (this.currentPage > totalPages) {
      this.currentPage = totalPages;
    }

    const startIndex = (this.currentPage - 1) * this.pageSizeValue;
    const visibleItems = new Set(filtered.slice(startIndex, startIndex + this.pageSizeValue));

    this.itemTargets.forEach((item) => {
      item.hidden = !visibleItems.has(item);
    });

    if (this.hasEmptyTarget) {
      this.emptyTarget.hidden = filtered.length > 0;
    }

    if (this.hasCountTarget) {
      this.countTarget.textContent = this.resultLabel(filtered.length);
    }

    if (this.hasPageInfoTarget) {
      if (filtered.length === 0) {
        this.pageInfoTarget.textContent = "No matching notebooks";
      } else if (totalPages === 1) {
        this.pageInfoTarget.textContent = this.resultLabel(filtered.length);
      } else {
        const endIndex = Math.min(startIndex + this.pageSizeValue, filtered.length);
        this.pageInfoTarget.textContent = `Showing ${startIndex + 1}-${endIndex} of ${filtered.length}`;
      }
    }

    if (this.hasPaginationTarget) {
      this.paginationTarget.hidden = totalPages <= 1 || filtered.length === 0;
    }

    if (this.hasPreviousTarget) {
      const disablePrevious = this.currentPage <= 1;
      this.previousTarget.disabled = disablePrevious;
      this.previousTarget.classList.toggle("disabled", disablePrevious);
    }

    if (this.hasNextTarget) {
      const disableNext = this.currentPage >= totalPages || filtered.length === 0;
      this.nextTarget.disabled = disableNext;
      this.nextTarget.classList.toggle("disabled", disableNext);
    }
  }
}
