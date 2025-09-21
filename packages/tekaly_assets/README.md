## tekaly_assets

Common assets

## Setup

`pubspec.yaml`:

```yaml
  tekaly_assets:
    git:
      url: https://github.com/tekartikprj/tekaly.git
      path: packages/tekaly_assets
```

## Usage

### Setup quick splash screen and icon in Flutter Web

`pubspec.yaml`:
```yaml
dependency:
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
  ...
  <link rel="apple-touch-icon" href="assets/packages/tekaly_assets/img/tekartik_logo_256.png">

    ...
  <!-- Favicon -->
  <link rel="icon" type="image/png" href="assets/packages/tekaly_assets/img/tekartik_logo_256.png"/>
</head>
<body>
<script src="assets/packages/tekaly_assets/js/tekaly_splash.js"></script>
<script src="flutter_bootstrap.js" async></script>
</body>
```

`manifest.json`:
```json
  ...
  "icons": [
    {
      "src": "assets/packages/tekaly_assets/img/tekartik_logo_256.png",
      "sizes": "256x256",
      "type": "image/png"
    }
  ]
  ...
```

`lib/main.dart`:
```dart
Future main() async {
  WidgetsFlutterBinding.ensureInitialized();
  webSplashReady();
  // optional init stuff
  ... 
  webSplashHide(); // Fadeout
  
  // Or
  // Future<void>.delayed(const Duration(milliseconds: 300))
  //    .then((_) => webSplashHide());
  runApp(...);
}
```
