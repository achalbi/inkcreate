# Inkcreate Mobile Shell

This is a standalone Capacitor host app for the existing Inkcreate Rails PWA.

## What it does

- opens the Inkcreate web app inside a Capacitor WebView
- links the local native plugin package at `../plugins/inkcreate-document-scanner`
- lets the Rails/web layer call `window.Capacitor.Plugins.InkcreateDocumentScanner`

## Configure the target app URL

Set `INKCREATE_APP_URL` before syncing native platforms.

Examples:

- Android emulator talking to local Rails: `http://10.0.2.2:3000`
- deployed app: `https://inkcreate.thoughtbasics.com`

## First-time setup

```bash
cd mobile/app
npm install
export INKCREATE_APP_URL=http://10.0.2.2:3000
npx cap add android
npx cap sync android
```

## Daily workflow

```bash
cd mobile/app
export INKCREATE_APP_URL=http://10.0.2.2:3000
npx cap sync android
npx cap open android
```

If you are using a physical device, replace the emulator URL with a LAN-accessible or deployed HTTPS URL.
