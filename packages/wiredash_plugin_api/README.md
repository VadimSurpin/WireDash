# WireDash panel plugin API

A compile-time extension API for locally bundled dashboard panels. The host
keeps the database, dashboard layout, secure storage, and home network route.
Each plugin supplies its ID, picker labels/icon, tile, and editor controller.
The controller saves credentials through `PluginHost` and serializes only
non-secret settings. Missing plugins retain their configuration for export or
later installation.

This API is a Flutter package, not an Android Auto renderer or a downloadable
APK loader. Register extensions in `lib/plugins/panel_plugins.dart`. The first
implementation is `../wiredash_video`.
