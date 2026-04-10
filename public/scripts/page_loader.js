(() => {
  const loader = document.getElementById("page-loader");
  if (!loader) return;

  const messageElement = loader.querySelector("[data-page-loader-message]");
  const showDelayMs = Number.parseInt(loader.dataset.delayMs || "", 10) || 1500;
  const defaultMessage = loader.dataset.defaultMessage || "Loading your workspace...";
  const uploadMessage = loader.dataset.uploadMessage || "Uploading your files...";
  let hideTimer = null;
  let showTimer = null;
  let pendingMessage = defaultMessage;
  let visible = false;

  const setMessage = (message) => {
    if (!messageElement) return;
    messageElement.textContent = message || defaultMessage;
  };

  const reveal = () => {
    window.clearTimeout(hideTimer);
    setMessage(pendingMessage);
    loader.hidden = false;
    loader.classList.remove("is-hidden");
    loader.setAttribute("aria-hidden", "false");
    document.body?.classList.add("page-loader-active");
    visible = true;
    showTimer = null;
  };

  const show = (message = defaultMessage, { delayMs = showDelayMs } = {}) => {
    pendingMessage = message || defaultMessage;

    if (visible) {
      setMessage(pendingMessage);
      return;
    }

    window.clearTimeout(showTimer);

    if (delayMs <= 0) {
      reveal();
      return;
    }

    showTimer = window.setTimeout(reveal, delayMs);
  };

  const hide = () => {
    window.clearTimeout(showTimer);
    showTimer = null;
    loader.classList.add("is-hidden");
    loader.setAttribute("aria-hidden", "true");
    document.body?.classList.remove("page-loader-active");
    visible = false;

    hideTimer = window.setTimeout(() => {
      if (loader.classList.contains("is-hidden")) {
        loader.hidden = true;
      }
    }, 220);
  };

  const messageFor = (element, isUpload = false) => {
    if (!(element instanceof HTMLElement)) {
      return isUpload ? uploadMessage : defaultMessage;
    }

    if (isUpload && element.dataset.pageLoaderUploadMessage) {
      return element.dataset.pageLoaderUploadMessage;
    }

    return element.dataset.pageLoaderMessage || (isUpload ? uploadMessage : defaultMessage);
  };

  const formHasSelectedFiles = (form) => Array.from(form.querySelectorAll("input[type='file']")).some((input) => {
    return input instanceof HTMLInputElement && input.files && input.files.length > 0;
  });

  const isUploadForm = (form) => {
    return form.enctype === "multipart/form-data" || formHasSelectedFiles(form);
  };

  document.addEventListener("click", (event) => {
    const link = event.target instanceof Element ? event.target.closest("a[href]") : null;
    if (!(link instanceof HTMLAnchorElement) || event.defaultPrevented) {
      return;
    }

    if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) {
      return;
    }

    if (link.dataset.pageLoader === "false" || link.hasAttribute("download")) {
      return;
    }

    const target = link.getAttribute("target");
    if (target && target !== "_self") {
      return;
    }

    const href = link.getAttribute("href");
    if (!href || href.startsWith("#") || /^(javascript:|mailto:|tel:)/i.test(href)) {
      return;
    }

    let nextUrl;

    try {
      nextUrl = new URL(link.href, window.location.href);
    } catch (_error) {
      return;
    }

    if (nextUrl.origin !== window.location.origin) {
      return;
    }

    if (
      nextUrl.pathname === window.location.pathname &&
      nextUrl.search === window.location.search &&
      nextUrl.hash &&
      nextUrl.hash !== window.location.hash
    ) {
      return;
    }

    show(messageFor(link));
  });

  document.addEventListener("submit", (event) => {
    const form = event.target;
    if (!(form instanceof HTMLFormElement) || event.defaultPrevented || form.dataset.pageLoader === "false") {
      return;
    }

    show(messageFor(form, isUploadForm(form)));
  });

  if (document.readyState === "complete") {
    hide();
  } else {
    show(defaultMessage);
    window.addEventListener("load", hide, { once: true });
  }

  window.addEventListener("pageshow", hide);

  window.InkcreatePageLoader = {
    show,
    showNow: (message = defaultMessage) => show(message, { delayMs: 0 }),
    hide,
    setMessage
  };
})();
