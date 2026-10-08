#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR=$(mktemp -d /tmp/spotter-raycast-models.XXXXXX)
trap 'rm -rf "$TEST_DIR"' EXIT
E=Spotter/Plugins/RaycastExtensions
sources=(
  Spotter/Plugins/Infrastructure/PluginTypes.swift
  Spotter/Plugins/RaycastExtensions/Model/RaycastStorePresentation.swift
  Spotter/Core/RaycastImport/Zlib.swift
  Spotter/Core/SearchRelevance.swift
  Spotter/Core/Theme+Raycast.swift
  Spotter/Core/Theme.swift
  Spotter/Plugins/Note/NoteEngine.swift
  Spotter/Plugins/RaycastExtensions/Model/ExtensionAppearance.swift
  Spotter/Plugins/RaycastExtensions/Model/ExtensionBootConfig.swift
  Spotter/Plugins/RaycastExtensions/Model/ExtensionColorSpaces.swift
  Spotter/Plugins/RaycastExtensions/Model/ExtensionColorValue.swift
  Spotter/Plugins/RaycastExtensions/Model/ExtensionCommandMetadata.swift
  Spotter/Plugins/RaycastExtensions/Model/ExtensionDateExpression.swift
  Spotter/Plugins/RaycastExtensions/Model/ExtensionDeepLink.swift
  Spotter/Plugins/RaycastExtensions/Model/ExtensionFormField.swift
  Spotter/Plugins/RaycastExtensions/Model/ExtensionFormMetrics.swift
  Spotter/Plugins/RaycastExtensions/Model/ExtensionGitHubSource.swift
  Spotter/Plugins/RaycastExtensions/Model/ExtensionGridGeometry.swift
  Spotter/Plugins/RaycastExtensions/Model/ExtensionGridLayout.swift
  Spotter/Plugins/RaycastExtensions/Model/ExtensionImageSize.swift
  Spotter/Plugins/RaycastExtensions/Model/ExtensionLaunchError.swift
  Spotter/Plugins/RaycastExtensions/Model/ExtensionLaunchType.swift
  Spotter/Plugins/RaycastExtensions/Model/ExtensionListing.swift
  Spotter/Plugins/RaycastExtensions/Model/ExtensionManifest.swift
  Spotter/Plugins/RaycastExtensions/Model/ExtensionMenuBarSnapshot.swift
  Spotter/Plugins/RaycastExtensions/Model/ExtensionPackageManager.swift
  Spotter/Plugins/RaycastExtensions/Model/ExtensionPickerItem.swift
  Spotter/Plugins/RaycastExtensions/Model/ExtensionRefreshPolicy.swift
  Spotter/Plugins/RaycastExtensions/Model/ExtensionRefreshState.swift
  Spotter/Plugins/RaycastExtensions/Model/ExtensionSearchAccessory.swift
  Spotter/Plugins/RaycastExtensions/Model/ExtensionStoreResponse.swift
  Spotter/Plugins/RaycastExtensions/Model/RenderNode.swift
  Spotter/Plugins/RaycastExtensions/Service/ExtensionArtworkCache.swift
  Spotter/Plugins/RaycastExtensions/Service/ExtensionCatalog.swift
  Spotter/Plugins/RaycastExtensions/Service/ExtensionCleanup.swift
  Spotter/Plugins/RaycastExtensions/Service/ExtensionCommandMetadataStore.swift
  Spotter/Plugins/RaycastExtensions/Service/ExtensionFetcher.swift
  Spotter/Plugins/RaycastExtensions/Service/ExtensionIconCache.swift
  Spotter/Plugins/RaycastExtensions/Service/ExtensionMenuBarManager.swift
  Spotter/Plugins/RaycastExtensions/Service/ExtensionNameResolver.swift
  Spotter/Plugins/RaycastExtensions/Service/ExtensionNodeShims.swift
  Spotter/Plugins/RaycastExtensions/Service/ExtensionOAuthKeychain.swift
  Spotter/Plugins/RaycastExtensions/Service/ExtensionOAuthSession.swift
  Spotter/Plugins/RaycastExtensions/Service/ExtensionRuntime.swift
  Spotter/Plugins/RaycastExtensions/Service/ExtensionStorage.swift
  Spotter/Plugins/RaycastExtensions/Service/ExtensionVersionStore.swift
  Spotter/Plugins/RaycastExtensions/Service/ExtensionWebSocketBridge.swift
  Spotter/Plugins/RaycastExtensions/Service/ProcessExit.swift
  Spotter/Plugins/RaycastExtensions/UI/ExtensionAnimatedImage.swift
  Spotter/Plugins/RaycastExtensions/UI/ExtensionFormKey.swift
  Spotter/Plugins/RaycastExtensions/UI/ExtensionImage.swift
  Spotter/Plugins/RaycastExtensions/UI/ExtensionListKey.swift
  Spotter/Plugins/RaycastExtensions/UI/ExtensionMenuBarController.swift
  Spotter/Plugins/RaycastExtensions/UI/ExtensionMenuBarImage.swift
  Spotter/Plugins/RaycastExtensions/UI/ExtensionMetrics.swift
  Spotter/Plugins/RaycastExtensions/UI/ExtensionScreen.swift
)
tests=(catalog store cleanup refresh metadata version form image-size accessory)
if [[ $# -gt 0 ]]; then tests=("$@"); fi
for name in "${tests[@]}"; do
  extras=("Tools/RaycastExtensions/ext-$name-test.swift")
  if [[ "$name" == form ]]; then extras+=(Tools/RaycastExtensions/ext-list-key-test.swift); fi
  selectedSources=("${sources[@]}")
  if [[ "$name" == accessory ]]; then
    selectedSources=("$E/Model/RenderNode.swift" "$E/Model/ExtensionPickerItem.swift" "$E/Model/ExtensionSearchAccessory.swift" "$E/Service/ExtensionStorage.swift")
  fi
  swiftc -swift-version 6 -parse-as-library "${selectedSources[@]}" "${extras[@]}" -o "$TEST_DIR/$name"
  "$TEST_DIR/$name"
done
