(() => {
  const TIME_ZONE_ALIASES = {
    "Asia/Calcutta": "Asia/Kolkata"
  };

  const syncDeviceTimeZone = () => {
    try {
      const resolvedTimeZone = Intl.DateTimeFormat().resolvedOptions().timeZone;
      const deviceTimeZone = TIME_ZONE_ALIASES[resolvedTimeZone] || resolvedTimeZone;
      if (!deviceTimeZone) return;

      const timeZoneSelect = document.getElementById("user_time_zone");
      if (
        timeZoneSelect &&
        timeZoneSelect.dataset.preferDeviceTimeZone === "true" &&
        Array.from(timeZoneSelect.options).some((option) => option.value === deviceTimeZone)
      ) {
        timeZoneSelect.value = deviceTimeZone;
      }

      const currentTimeZone = document.documentElement.dataset.timeZone || "";
      const cookieMatch = document.cookie.match(/(?:^|; )browser_time_zone=([^;]+)/);
      const cookieTimeZone = cookieMatch ? decodeURIComponent(cookieMatch[1]) : "";

      if (cookieTimeZone !== deviceTimeZone) {
        document.cookie = `browser_time_zone=${encodeURIComponent(deviceTimeZone)}; path=/; max-age=31536000; SameSite=Lax`;
      }

      if (!currentTimeZone || currentTimeZone === deviceTimeZone) {
        return;
      }

      const reloadKey = "inkcreate-device-time-zone-reload";
      if (sessionStorage.getItem(reloadKey) === deviceTimeZone) {
        return;
      }

      sessionStorage.setItem(reloadKey, deviceTimeZone);
      window.location.reload();
    } catch (_error) {
      // Ignore timezone detection issues and keep the page usable.
    }
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", syncDeviceTimeZone, { once: true });
  } else {
    syncDeviceTimeZone();
  }
})();
