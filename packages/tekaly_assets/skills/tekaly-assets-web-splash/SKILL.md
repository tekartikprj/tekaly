---
name: tekaly-assets-web-splash
description: >-
  Use when setting up the tekartik logo, favicon, manifest icon or the quick
  web splash screen of a flutter web app with the shared tekaly_assets package.
---

# Shared assets for flutter apps (tekaly_assets)

`tekaly_assets` has no Dart code: it only ships the tekartik logo
(`img/tekartik_logo_256.png`) and the splash script (`js/tekaly_splash.js`)
used by the tekaly flutter web apps.

## Guidelines

* Declare the assets you use in the app `pubspec.yaml` under
  `flutter: assets:` with the `packages/tekaly_assets/...` prefix; flutter
  serves them at `assets/packages/tekaly_assets/...`.
* Reference them from `web/index.html` and `web/manifest.json` with the
  `assets/packages/tekaly_assets/` path (the app's own `web/` folder does not
  need a copy of the logo).
* Load `tekaly_splash.js` before `flutter_bootstrap.js` so the splash shows
  while flutter loads; it pairs with `tekartik_web_splash`
  (`tekartik/app_web_utils.dart`, `packages/web_splash`) on the dart side.

## Examples

`pubspec.yaml`:

```yaml
dependencies:
  tekaly_assets:
    git:
      url: https://github.com/tekartikprj/tekaly
      path: packages/tekaly_assets
  tekartik_web_splash:
    git:
      url: https://github.com/tekartik/app_web_utils.dart
      path: packages/web_splash

flutter:
  assets:
    - packages/tekaly_assets/img/tekartik_logo_256.png
    - packages/tekaly_assets/js/tekaly_splash.js
```

`web/index.html`:

```html
<head>
  <link rel="apple-touch-icon" href="assets/packages/tekaly_assets/img/tekartik_logo_256.png">
  <link rel="icon" type="image/png" href="assets/packages/tekaly_assets/img/tekartik_logo_256.png"/>
</head>
<body>
<script src="assets/packages/tekaly_assets/js/tekaly_splash.js"></script>
<script src="flutter_bootstrap.js" async></script>
</body>
```

`web/manifest.json`:

```json
"icons": [
  {
    "src": "assets/packages/tekaly_assets/img/tekartik_logo_256.png",
    "sizes": "256x256",
    "type": "image/png"
  }
]
```
