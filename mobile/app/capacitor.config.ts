import type { CapacitorConfig } from "@capacitor/cli";

const appUrl = process.env.INKCREATE_APP_URL?.trim() || "";

let hostname: string | null = null;
let cleartext = false;

if (appUrl) {
  try {
    const parsed = new URL(appUrl);
    hostname = parsed.hostname;
    cleartext = parsed.protocol === "http:";
  } catch (error) {
    throw new Error(`Invalid INKCREATE_APP_URL: ${appUrl}`);
  }
}

const config: CapacitorConfig = {
  appId: "com.inkcreate.mobile",
  appName: "Inkcreate",
  webDir: "www",
  bundledWebRuntime: false,
  server: appUrl
    ? {
        url: appUrl,
        cleartext,
        allowNavigation: hostname ? [hostname] : []
      }
    : undefined
};

export default config;
