#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_BINARY=$(mktemp -u /tmp/spotter-raycast-test.XXXXXX)
trap 'rm -f "$TEST_BINARY"' EXIT
swiftc -swift-version 6 -parse-as-library \
  Tools/RaycastExtensions/ext-test.swift \
  Tools/RaycastExtensions/ext-menu-bar-test.swift \
  Tools/RaycastExtensions/ext-fetch-test.swift \
  Spotter/Plugins/RaycastExtensions/Model/ExtensionLaunchError.swift \
  Spotter/Plugins/RaycastExtensions/Model/ExtensionMenuBarSnapshot.swift \
  Spotter/Plugins/RaycastExtensions/Service/ExtensionStorage.swift \
  Spotter/Plugins/RaycastExtensions/Service/ExtensionMenuBarManager.swift \
  Spotter/Plugins/RaycastExtensions/Model/ExtensionCommandMetadata.swift \
  Spotter/Plugins/RaycastExtensions/Service/ExtensionCommandMetadataStore.swift \
  Spotter/Plugins/RaycastExtensions/UI/ExtensionMenuBarController.swift \
  Spotter/Plugins/RaycastExtensions/UI/ExtensionMenuBarImage.swift \
  Spotter/Core/Theme.swift \
  Spotter/Plugins/Note/NoteEngine.swift \
  Spotter/Plugins/RaycastExtensions/Service/ExtensionArtworkCache.swift \
  Spotter/Core/Theme+Raycast.swift \
  Spotter/Plugins/RaycastExtensions/UI/ExtensionMetrics.swift \
  Spotter/Plugins/RaycastExtensions/Model/ExtensionBootConfig.swift \
  Spotter/Plugins/RaycastExtensions/Model/ExtensionDeepLink.swift \
  Spotter/Plugins/RaycastExtensions/Model/ExtensionLaunchType.swift \
  Spotter/Plugins/RaycastExtensions/Model/ExtensionFormField.swift \
  Spotter/Plugins/RaycastExtensions/Model/ExtensionGridLayout.swift \
  Spotter/Plugins/RaycastExtensions/Model/ExtensionManifest.swift \
  Spotter/Plugins/RaycastExtensions/Model/ExtensionRefreshPolicy.swift \
  Spotter/Plugins/RaycastExtensions/Model/ExtensionRefreshState.swift \
  Spotter/Plugins/RaycastExtensions/Model/RenderNode.swift \
  Spotter/Plugins/RaycastExtensions/Model/ExtensionPickerItem.swift \
  Spotter/Plugins/RaycastExtensions/Model/ExtensionSearchAccessory.swift \
  Spotter/Plugins/RaycastExtensions/Service/ExtensionCatalog.swift \
  Spotter/Plugins/RaycastExtensions/Service/ExtensionFetcher.swift \
  Spotter/Plugins/RaycastExtensions/Service/ProcessExit.swift \
  Spotter/Plugins/RaycastExtensions/Service/ExtensionIconCache.swift \
  Spotter/Plugins/RaycastExtensions/Service/ExtensionNodeShims.swift \
  Spotter/Plugins/RaycastExtensions/Service/ExtensionOAuthKeychain.swift \
  Spotter/Plugins/RaycastExtensions/Service/ExtensionOAuthSession.swift \
  Spotter/Plugins/RaycastExtensions/Service/ExtensionRuntime.swift \
  Spotter/Plugins/RaycastExtensions/Service/ExtensionNameResolver.swift \
  Spotter/Plugins/RaycastExtensions/Service/ExtensionWebSocketBridge.swift \
  Spotter/Plugins/RaycastExtensions/UI/ExtensionAnimatedImage.swift \
  Spotter/Plugins/RaycastExtensions/UI/ExtensionImage.swift \
  Spotter/Plugins/RaycastExtensions/UI/ExtensionScreen.swift \
  Spotter/Core/SearchRelevance.swift \
  Spotter/Core/RaycastImport/Zlib.swift \
  Spotter/Plugins/RaycastExtensions/Model/ExtensionColorValue.swift \
  Spotter/Plugins/RaycastExtensions/Model/ExtensionColorSpaces.swift \
  -o "$TEST_BINARY"
"$TEST_BINARY" "$@"
