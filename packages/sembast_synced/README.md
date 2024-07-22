## sembast_synced

Sembast synced is a package that allows to sync a sembast database with a remote server:
- firestore database
- export/import to/from a file
- predefined api
- only allow syncing stores with String key and Map content.

## Setup

`pubspec.yaml`:

```yaml
  tekaly_sembast_synced:
    git:
      url: https://github.com/tekartikprj/tekaly.git
      path: packages/sembast_synced
      ref: dart3a
    version: '>=0.1.0'
```