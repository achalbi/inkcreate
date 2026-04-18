import { Controller } from "/scripts/vendor/stimulus.js";

const SEARCH_ENDPOINT = "https://nominatim.openstreetmap.org/search?format=jsonv2&addressdetails=1&limit=5";
const REVERSE_ENDPOINT = "https://nominatim.openstreetmap.org/reverse?format=jsonv2&zoom=18&addressdetails=1";

export default class extends Controller {
  static values = {
    formId: String,
    autoSubmit: Boolean
  };

  static targets = [
    "searchInput",
    "locationsInput",
    "status",
    "summary",
    "results",
    "currentButton",
    "addButton"
  ];

  connect() {
    this.searchTimeoutId = null;
    this.searchAbortController = null;
    this.locations = this.readStoredLocations();
    this.formElement = this.findFormElement();
    this.boundCommitOnSubmit = this.commitOnSubmit.bind(this);
    this.formElement?.addEventListener("submit", this.boundCommitOnSubmit);

    this.renderSummary();
    this.updateAddButtonState();
  }

  disconnect() {
    this.clearPendingSearch();
    this.abortInFlightSearch();
    this.formElement?.removeEventListener("submit", this.boundCommitOnSubmit);
  }

  search() {
    const query = this.query();
    this.updateAddButtonState();

    this.clearPendingSearch();
    this.abortInFlightSearch();

    if (!query) {
      this.clearStatus();
      this.clearResults();
      return;
    }

    if (query.length < 3) {
      this.clearResults();
      this.setStatus("Add the typed location now, or keep typing to search.");
      return;
    }

    this.setStatus("Searching places...");
    this.searchTimeoutId = window.setTimeout(() => this.performSearch(query), 280);
  }

  async performSearch(query) {
    this.abortInFlightSearch();
    this.searchAbortController = new AbortController();

    try {
      const response = await fetch(`${SEARCH_ENDPOINT}&q=${encodeURIComponent(query)}`, {
        headers: {
          Accept: "application/json"
        },
        signal: this.searchAbortController.signal
      });

      if (!response.ok) {
        throw new Error(`Search request failed with status ${response.status}`);
      }

      const results = await response.json();
      if (this.query() !== query) {
        return;
      }

      this.renderResults(Array.isArray(results) ? results : []);
      this.setStatus(results.length > 0 ? "Choose a result or add the typed location." : "No exact matches found. Add the typed location to keep it.");
    } catch (error) {
      if (error.name === "AbortError") {
        return;
      }

      this.clearResults();
      this.setStatus("Location search is unavailable right now. Add the typed location to keep it.");
    } finally {
      this.searchAbortController = null;
    }
  }

  useCurrentLocation(event) {
    event?.preventDefault();

    if (!navigator.geolocation) {
      this.setStatus("Current location is not available in this browser.");
      return;
    }

    this.toggleCurrentButton(true);
    this.clearResults();
    this.setStatus("Checking your current location...");

    navigator.geolocation.getCurrentPosition(
      (position) => this.applyCurrentLocation(position.coords.latitude, position.coords.longitude),
      () => {
        this.toggleCurrentButton(false);
        this.setStatus("Current location permission was denied or timed out.");
      },
      {
        enableHighAccuracy: true,
        maximumAge: 300000,
        timeout: 12000
      }
    );
  }

  async applyCurrentLocation(latitude, longitude) {
    const latitudeLabel = this.normalizedCoordinate(latitude);
    const longitudeLabel = this.normalizedCoordinate(longitude);

    try {
      const response = await fetch(`${REVERSE_ENDPOINT}&lat=${encodeURIComponent(latitude)}&lon=${encodeURIComponent(longitude)}`, {
        headers: {
          Accept: "application/json"
        }
      });

      if (!response.ok) {
        throw new Error(`Reverse geocode failed with status ${response.status}`);
      }

      const result = await response.json();
      const location = this.resultToLocation(result, "current");

      this.addLocation({
        name: location.name || `${latitudeLabel}, ${longitudeLabel}`,
        address: location.address,
        latitude: latitudeLabel,
        longitude: longitudeLabel,
        source: "current"
      }, { clearQuery: true, status: "Current location added." });
    } catch (_error) {
      this.addLocation({
        name: `${latitudeLabel}, ${longitudeLabel}`,
        address: "",
        latitude: latitudeLabel,
        longitude: longitudeLabel,
        source: "current"
      }, { clearQuery: true, status: "Coordinates added. Search details were unavailable." });
    } finally {
      this.toggleCurrentButton(false);
      this.clearResults();
    }
  }

  selectResult(event) {
    event?.preventDefault();

    const button = event.currentTarget;
    this.addLocation({
      name: button.dataset.locationName || "",
      address: button.dataset.locationAddress || "",
      latitude: button.dataset.locationLatitude || "",
      longitude: button.dataset.locationLongitude || "",
      source: button.dataset.locationSource || "search"
    }, { clearQuery: true, status: "Location added." });

    this.clearResults();
  }

  addTypedLocation(event) {
    event?.preventDefault();

    const location = this.typedLocationFromQuery();
    if (!location) {
      this.setStatus("Type a place name or address to add it.");
      return;
    }

    this.addLocation(location, { clearQuery: true, status: "Typed location added." });
    this.clearResults();
  }

  addTypedLocationFromKeyboard(event) {
    event?.preventDefault();
    this.addTypedLocation();
  }

  removeLocation(event) {
    event?.preventDefault();

    const index = Number.parseInt(event.currentTarget.dataset.locationIndex || "", 10);
    if (!Number.isInteger(index)) {
      return;
    }

    this.storeLocations(this.locations.filter((_location, locationIndex) => locationIndex !== index));
    this.setStatus("Location removed.");
    this.autoSubmitIfNeeded();
  }

  clear(event) {
    event?.preventDefault();

    this.storeLocations([]);
    this.searchInputTarget.value = "";
    this.clearResults();
    this.clearStatus();
    this.updateAddButtonState();
    this.autoSubmitIfNeeded();
  }

  commitOnSubmit() {
    const location = this.typedLocationFromQuery();
    if (location) {
      this.addLocation(location, { clearQuery: false, status: null });
    }
  }

  addLocation(location, { clearQuery = false, status = "Location added." } = {}) {
    const normalizedLocation = this.normalizeLocation(location);
    if (!normalizedLocation) {
      return;
    }

    if (this.locationAlreadyAdded(normalizedLocation)) {
      this.setStatus("That location is already saved.");
      if (clearQuery) this.clearQuery();
      return;
    }

    this.storeLocations([...this.locations, normalizedLocation]);

    if (clearQuery) {
      this.clearQuery();
    }

    if (status) {
      this.setStatus(status);
    }

    this.autoSubmitIfNeeded();
  }

  storeLocations(locations) {
    this.locations = this.normalizeLocations(locations);
    this.locationsInputTarget.value = JSON.stringify(this.locations);
    this.renderSummary();
    this.updateAddButtonState();
  }

  renderSummary() {
    if (!this.hasStoredLocation()) {
      this.summaryTarget.innerHTML = "<div class=\"location-picker__summary-empty\">No location added yet.</div>";
      return;
    }

    const countLabel = this.locations.length === 1 ? "1 location saved" : `${this.locations.length} locations saved`;
    const cards = this.locations.map((location, index) => this.summaryCardMarkup(location, index)).join("");

    this.summaryTarget.innerHTML = [
      `<div class="location-picker__summary-count">${this.escapeHtml(countLabel)}</div>`,
      `<div class="location-picker__summary-list">${cards}</div>`
    ].join("");
  }

  renderResults(results) {
    if (!results.length) {
      this.clearResults();
      return;
    }

    this.resultsTarget.replaceChildren(
      ...results.map((result) => this.buildResultButton(result))
    );
  }

  buildResultButton(result) {
    const location = this.resultToLocation(result, "search");
    const button = document.createElement("button");

    button.type = "button";
    button.className = "location-picker__result";
    button.dataset.action = "click->location-picker#selectResult";
    button.dataset.locationName = location.name;
    button.dataset.locationAddress = location.address;
    button.dataset.locationLatitude = location.latitude;
    button.dataset.locationLongitude = location.longitude;
    button.dataset.locationSource = location.source;

    const title = document.createElement("span");
    title.className = "location-picker__result-title";
    title.textContent = location.name;

    const detail = document.createElement("span");
    detail.className = "location-picker__result-detail";
    detail.textContent = location.address || this.coordinateLabelFor(location.latitude, location.longitude);

    button.append(title, detail);
    return button;
  }

  resultToLocation(result, source) {
    const name = this.resultPrimaryLabel(result);
    const address = result?.display_name?.trim() || "";
    const latitude = result?.lat ? this.normalizedCoordinate(result.lat) : "";
    const longitude = result?.lon ? this.normalizedCoordinate(result.lon) : "";

    return {
      name,
      address,
      latitude,
      longitude,
      source
    };
  }

  resultPrimaryLabel(result) {
    return result?.name?.trim() || result?.display_name?.split(",")?.[0]?.trim() || "Pinned location";
  }

  findFormElement() {
    if (this.hasFormIdValue && this.formIdValue) {
      return document.getElementById(this.formIdValue);
    }

    return this.element.closest("form");
  }

  toggleCurrentButton(isBusy) {
    if (!this.hasCurrentButtonTarget) return;

    this.currentButtonTarget.disabled = isBusy;
    this.currentButtonTarget.classList.toggle("disabled", isBusy);
  }

  updateAddButtonState() {
    if (!this.hasAddButtonTarget) return;

    const disabled = !this.query();
    this.addButtonTarget.disabled = disabled;
    this.addButtonTarget.classList.toggle("disabled", disabled);
  }

  hasStoredLocation() {
    return this.locations.length > 0;
  }

  clearQuery() {
    this.searchInputTarget.value = "";
    this.updateAddButtonState();
  }

  autoSubmitIfNeeded() {
    if (!this.autoSubmitValue || !this.formElement) {
      return;
    }

    if (this.autoSubmitPending) {
      this.autoSubmitQueued = true;
      return;
    }

    this.performAutoSubmit();
  }

  async performAutoSubmit() {
    this.autoSubmitPending = true;

    try {
      do {
        this.autoSubmitQueued = false;
        this.setStatus("Saving location...");

        const headers = {
          Accept: "text/vnd.turbo-stream.html, text/html, application/xhtml+xml",
          "X-Requested-With": "XMLHttpRequest"
        };
        const csrfToken = this.csrfToken();
        if (csrfToken) {
          headers["X-CSRF-Token"] = csrfToken;
        }

        const response = await fetch(this.formElement.action, {
          method: (this.formElement.method || "post").toUpperCase(),
          body: new FormData(this.formElement),
          credentials: "same-origin",
          headers
        });

        if (!response.ok) {
          throw new Error(`Autosave request failed with status ${response.status}`);
        }
      } while (this.autoSubmitQueued);

      this.setStatus("Location saved.");
    } catch (_error) {
      this.setStatus("Location could not be saved right now.");
    } finally {
      this.autoSubmitPending = false;
    }
  }

  sourceLabel(source) {
    if (source === "current") return "current location";
    if (source === "search") return "search";
    return "typed text";
  }

  query() {
    return this.searchInputTarget.value.trim();
  }

  normalizedCoordinate(value) {
    const numericValue = Number.parseFloat(value);
    return Number.isFinite(numericValue) ? numericValue.toFixed(6) : "";
  }

  setStatus(message) {
    this.statusTarget.textContent = message;
  }

  clearStatus() {
    this.statusTarget.textContent = "";
  }

  clearResults() {
    this.resultsTarget.replaceChildren();
  }

  csrfToken() {
    const formTokenField = this.formElement?.querySelector("input[name='authenticity_token']");
    if (formTokenField?.value) {
      return formTokenField.value;
    }

    const metaToken = document.querySelector("meta[name='csrf-token']");
    return metaToken?.content || "";
  }

  clearPendingSearch() {
    if (this.searchTimeoutId === null) {
      return;
    }

    window.clearTimeout(this.searchTimeoutId);
    this.searchTimeoutId = null;
  }

  abortInFlightSearch() {
    if (!this.searchAbortController) {
      return;
    }

    this.searchAbortController.abort();
    this.searchAbortController = null;
  }

  readStoredLocations() {
    try {
      const rawValue = this.locationsInputTarget.value.trim();
      if (!rawValue) {
        return [];
      }

      return this.normalizeLocations(JSON.parse(rawValue));
    } catch (_error) {
      return [];
    }
  }

  normalizeLocations(locations) {
    const seenSignatures = new Set();

    return Array.from(Array.isArray(locations) ? locations : [])
      .map((location) => this.normalizeLocation(location))
      .filter((location) => {
        if (!location) {
          return false;
        }

        const signature = this.locationSignature(location);
        if (seenSignatures.has(signature)) {
          return false;
        }

        seenSignatures.add(signature);
        return true;
      });
  }

  normalizeLocation(location) {
    if (!location || typeof location !== "object") {
      return null;
    }

    const name = String(location.name || location.location_name || "").trim();
    const address = String(location.address || location.location_address || "").trim();
    const latitude = this.normalizedCoordinate(location.latitude || location.location_latitude || "");
    const longitude = this.normalizedCoordinate(location.longitude || location.location_longitude || "");
    const source = String(location.source || location.location_source || "").trim();
    const normalizedSource = ["current", "search", "manual"].includes(source) ? source : "";
    const normalizedName = name || this.addressHeadline(address) || this.coordinateLabelFor(latitude, longitude);

    if (!normalizedName && !address && !latitude && !longitude) {
      return null;
    }

    return {
      name: normalizedName,
      address,
      latitude,
      longitude,
      source: normalizedSource
    };
  }

  typedLocationFromQuery() {
    const query = this.query();
    if (!query) {
      return null;
    }

    if (this.locations.some((location) => this.locationMatchesText(location, query))) {
      return null;
    }

    return {
      name: query,
      address: "",
      latitude: "",
      longitude: "",
      source: "manual"
    };
  }

  locationAlreadyAdded(location) {
    const signature = this.locationSignature(location);
    return this.locations.some((existingLocation) => this.locationSignature(existingLocation) === signature);
  }

  locationSignature(location) {
    return [
      (location.name || "").trim().toLowerCase(),
      (location.address || "").trim().toLowerCase(),
      location.latitude || "",
      location.longitude || ""
    ].join("|");
  }

  locationMatchesText(location, text) {
    const normalizedText = text.trim().toLowerCase();
    return [location.name || "", location.address || ""].some((value) => value.trim().toLowerCase() === normalizedText);
  }

  summaryCardMarkup(location, index) {
    const label = this.escapeHtml(this.locationLabel(location));
    const detail = this.locationDetail(location);
    const source = location.source ? `Saved from ${this.sourceLabel(location.source)}` : "";
    const mapsUrl = this.mapsUrlFor(location);

    return [
      "<div class=\"location-picker__summary-card\">",
      "  <div class=\"location-picker__summary-card-main\">",
      `    <div class="location-picker__summary-title">${label}</div>`,
      detail ? `    <div class="location-picker__summary-detail">${this.escapeHtml(detail)}</div>` : "",
      source ? `    <div class="location-picker__summary-meta">${this.escapeHtml(source)}</div>` : "",
      "  </div>",
      "  <div class=\"location-picker__summary-actions\">",
      mapsUrl ? `    <a class="location-picker__summary-action" href="${this.escapeHtml(mapsUrl)}" target="_blank" rel="noopener"><i class="ti ti-external-link" aria-hidden="true"></i><span>Maps</span></a>` : "",
      `    <button type="button" class="location-picker__summary-action" data-action="click->location-picker#removeLocation" data-location-index="${index}"><i class="ti ti-trash" aria-hidden="true"></i><span>Remove</span></button>`,
      "  </div>",
      "</div>"
    ].join("");
  }

  locationLabel(location) {
    return location.name || this.addressHeadline(location.address) || this.coordinateLabelFor(location.latitude, location.longitude) || "Pinned location";
  }

  locationDetail(location) {
    const label = this.locationLabel(location);

    if (location.address && location.address !== label) {
      return location.address;
    }

    const coordinates = this.coordinateLabelFor(location.latitude, location.longitude);
    if (coordinates && coordinates !== label) {
      return coordinates;
    }

    return "";
  }

  mapsUrlFor(location) {
    const query = location.latitude && location.longitude
      ? this.coordinateLabelFor(location.latitude, location.longitude)
      : [location.name, location.address].filter(Boolean).join(" ");

    return query ? `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(query)}` : "";
  }

  coordinateLabelFor(latitude, longitude) {
    if (!latitude || !longitude) {
      return "";
    }

    return `${latitude}, ${longitude}`;
  }

  addressHeadline(address) {
    return String(address || "").split(",")[0]?.trim() || "";
  }

  escapeHtml(value) {
    return String(value)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll("\"", "&quot;")
      .replaceAll("'", "&#39;");
  }
}
