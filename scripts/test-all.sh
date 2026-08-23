#!/bin/bash
# Compile and run every standalone harness with bounded parallelism.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SELF="$ROOT/scripts/test-all.sh"

TESTS=(
    fuzz
    app-identity-migration
    app-version
    ranking
    launcher-fallback
    calc
    clipboard
    scopes
    file-search
    emoji
    custom-command
    commands
    world-clock
    kill-process
    change-case
    selection-tools
    image-modification
    note
    text-replacement
    settings-sync
    update
    window-command
    background-task
    mole
    coffee
    ai-chat
    dashboard-widgets
    theme
    quicklink
    hotkey
    menu-typeahead
    screenshot
)

usage() {
    echo "Usage: scripts/test-all.sh [--jobs N] [--list]" >&2
}

validate_manifest() {
    local listed
    local actual
    listed="$(printf '%s\n' "${TESTS[@]}" | sort)"
    actual="$(find Tools -maxdepth 1 -type f -name '*-test.swift' \
        | sed -E 's#^Tools/##; s/-test\.swift$//' | sort)"
    if [ "$listed" != "$actual" ]; then
        echo "✗ scripts/test-all.sh and Tools/*-test.swift are out of sync." >&2
        diff -u <(printf '%s\n' "$listed") <(printf '%s\n' "$actual") || true
        exit 1
    fi
}

run_harness() {
    local name="$1"
    local output="$2"

    case "$name" in
        app-identity-migration)
            swiftc -swift-version 6 Spotter/Core/AppIdentityMigration.swift \
                Tools/app-identity-migration-test.swift -o "$output" && "$output"
            ;;
        fuzz)
            swiftc -swift-version 6 Spotter/Core/SearchRelevance.swift \
                Tools/fuzz-test.swift -o "$output" && "$output"
            ;;
        app-version)
            swiftc -swift-version 6 Spotter/Core/AppVersion.swift \
                Tools/app-version-test.swift -o "$output" && "$output"
            ;;
        ranking)
            swiftc -swift-version 6 Spotter/Core/LauncherRankingStore.swift \
                Spotter/Core/SearchRelevance.swift Tools/ranking-test.swift \
                -o "$output" && "$output"
            ;;
        launcher-fallback)
            swiftc -swift-version 6 Spotter/Core/LauncherFallback.swift \
                Spotter/Core/TerminalCommandRunner.swift Tools/launcher-fallback-test.swift \
                -o "$output" && "$output"
            ;;
        calc)
            swiftc Spotter/Core/Calculator/*.swift \
                Spotter/Plugins/CurrencyConversion/CalcCurrency.swift \
                Spotter/Plugins/CurrencyConversion/CurrencyData.generated.swift \
                Tools/calc-test.swift -o "$output" && "$output"
            ;;
        clipboard)
            swiftc -swift-version 6 Spotter/Plugins/Clipboard/ClipboardStore.swift \
                Spotter/Plugins/Clipboard/ClipboardFilter.swift \
                Tools/clipboard-test.swift -o "$output" && "$output"
            ;;
        file-search)
            swiftc -swift-version 6 Spotter/Core/SearchRelevance.swift \
                Spotter/Plugins/FileSearch/FileSearchTypes.swift Tools/file-search-test.swift \
                -o "$output" && "$output"
            ;;
        scopes)
            swiftc -swift-version 6 Spotter/Core/SearchScopes.swift \
                Tools/scopes-test.swift -o "$output" && "$output"
            ;;
        emoji)
            swiftc Spotter/Plugins/EmojiSymbols/EmojiCatalog.swift \
                Spotter/Plugins/EmojiSymbols/EmojiGridGeometry.swift \
                Spotter/Plugins/EmojiSymbols/EmojiData.generated.swift \
                Tools/emoji-test.swift -o "$output" && "$output"
            ;;
        custom-command)
            swiftc -swift-version 6 Spotter/Core/CustomCommand.swift \
                Spotter/Core/ShellCommandRunner.swift Tools/custom-command-test.swift \
                -o "$output" && "$output"
            ;;
        commands)
            swiftc -swift-version 6 Spotter/Plugins/Infrastructure/PluginTypes.swift \
                Spotter/Core/CommandID.swift \
                Spotter/Plugins/Commands/SystemCommand.swift Tools/commands-test.swift \
                -o "$output" && "$output"
            ;;
        world-clock)
            swiftc -swift-version 6 Spotter/Plugins/Infrastructure/PluginTypes.swift \
                Spotter/Plugins/WorldClock/WorldClockEngine.swift \
                Spotter/Plugins/WorldClock/WorldClockStore.swift Tools/world-clock-test.swift \
                -o "$output" && "$output"
            ;;
        kill-process)
            swiftc -swift-version 6 Spotter/Plugins/KillProcess/KillProcessEngine.swift \
                Tools/kill-process-test.swift -o "$output" && "$output"
            ;;
        change-case)
            swiftc -swift-version 6 Spotter/Plugins/ChangeCase/ChangeCaseEngine.swift \
                Tools/change-case-test.swift -o "$output" && "$output"
            ;;
        selection-tools)
            swiftc -swift-version 6 Spotter/Plugins/Infrastructure/PluginTypes.swift \
                Spotter/Plugins/SelectionTools/SelectionToolsTypes.swift \
                Spotter/Plugins/SelectionTools/SearchURLBuilder.swift \
                Spotter/Plugins/SelectionTools/SelectionToolsResults.swift \
                Tools/selection-tools-test.swift -o "$output" && "$output"
            ;;
        image-modification)
            swiftc -swift-version 6 -framework AppKit -framework CoreImage \
                -framework ImageIO -framework Vision \
                Spotter/Plugins/ImageModification/ImageModificationTypes.swift \
                Spotter/Plugins/ImageModification/ImageModificationEngine.swift \
                Tools/image-modification-test.swift -o "$output" && "$output"
            ;;
        note)
            swiftc -swift-version 6 Spotter/Plugins/Note/NoteEngine.swift \
                Spotter/Plugins/Note/NoteStore.swift Spotter/Plugins/Note/NoteSyncDocument.swift \
                Tools/note-test.swift -o "$output" && "$output"
            ;;
        text-replacement)
            swiftc -swift-version 6 Spotter/Plugins/TextReplacement/TextReplacementEngine.swift \
                Spotter/Plugins/TextReplacement/TextReplacementStore.swift \
                Tools/text-replacement-test.swift -o "$output" && "$output"
            ;;
        settings-sync)
            swiftc -swift-version 6 Spotter/Core/Backup/SettingsSyncFile.swift \
                Tools/settings-sync-test.swift -o "$output" && "$output"
            ;;
        update)
            swiftc -swift-version 6 Spotter/Core/UpdateFeed.swift \
                Tools/update-test.swift -o "$output" && "$output"
            ;;
        window-command)
            swiftc -swift-version 6 Spotter/Plugins/WindowManagement/WindowCommand.swift \
                Spotter/Plugins/WindowManagement/WindowLayout.swift \
                Spotter/Plugins/WindowManagement/WindowActionMemory.swift \
                Tools/window-command-test.swift -o "$output" && "$output"
            ;;
        background-task)
            swiftc -swift-version 6 Spotter/Core/BackgroundTaskStore.swift \
                Tools/background-task-test.swift -o "$output" && "$output"
            ;;
        mole)
            swiftc -swift-version 6 Spotter/Plugins/Mole/MoleTypes.swift \
                Spotter/Plugins/Mole/MoleProcessRunner.swift Tools/mole-test.swift \
                -o "$output" && "$output"
            ;;
        coffee)
            swiftc -swift-version 6 Spotter/Plugins/Coffee/CoffeeTypes.swift \
                Tools/coffee-test.swift -o "$output" && "$output"
            ;;
        ai-chat)
            swiftc -swift-version 6 Spotter/Plugins/AIChat/AIChatTypes.swift \
                Spotter/Plugins/AIChat/AIChatMarkdown.swift \
                Spotter/Plugins/AIChat/AIChatSelectionPrompts.swift \
                Spotter/Core/OpenRouterModelCatalog.swift Tools/ai-chat-test.swift \
                -o "$output" && "$output"
            ;;
        dashboard-widgets)
            swiftc -swift-version 6 \
                Spotter/Plugins/DashboardWidgets/DashboardWidgetsEngine.swift \
                Spotter/Plugins/DashboardWidgets/DashboardWeatherEngine.swift \
                Spotter/Plugins/DashboardWidgets/DashboardUptimeEngine.swift \
                Spotter/Plugins/DashboardWidgets/DashboardDeviceBatteryEngine.swift \
                Spotter/Plugins/DashboardWidgets/DashboardFileInfoEngine.swift \
                Tools/dashboard-widgets-test.swift -o "$output" && "$output"
            ;;
        theme)
            swiftc -swift-version 6 Spotter/Core/Theme.swift \
                Tools/theme-test.swift -o "$output" && "$output"
            ;;
        quicklink)
            swiftc -swift-version 6 Spotter/Plugins/Quicklinks/QuicklinkTypes.swift \
                Spotter/Plugins/Quicklinks/QuicklinkStore.swift Tools/quicklink-test.swift \
                -o "$output" && "$output"
            ;;
        hotkey)
            swiftc -swift-version 6 Spotter/Core/HotKey/DoubleTapDetector.swift \
                Spotter/Core/HotKey/DoubleTapModifier.swift Tools/hotkey-test.swift \
                -o "$output" && "$output"
            ;;
        menu-typeahead)
            swiftc -swift-version 6 Spotter/Core/SearchRelevance.swift \
                Spotter/Core/PaletteMenuTypeahead.swift Tools/menu-typeahead-test.swift \
                -o "$output" && "$output"
            ;;
        screenshot)
            swiftc -swift-version 6 -framework CoreGraphics -framework CoreText \
                -framework ImageIO -framework UniformTypeIdentifiers \
                Spotter/Plugins/Screenshot/ScreenshotWindowPicker.swift \
                Spotter/Plugins/Screenshot/ScreenshotGeometry.swift \
                Spotter/Plugins/Screenshot/ScreenshotImageProcessor.swift \
                Spotter/Plugins/Screenshot/ScreenshotAnnotation.swift \
                Spotter/Plugins/Screenshot/ScreenshotTextLayout.swift \
                Tools/screenshot-test.swift -o "$output" && "$output"
            ;;
        *)
            echo "Unknown test harness: $name" >&2
            return 2
            ;;
    esac
}

run_child() {
    local name="$1"
    local test_root="$2"
    local case_root="$test_root/$name"
    local started
    local status

    mkdir -p "$case_root/tmp"
    started="$(date +%s)"
    set +e
    (
        cd "$ROOT"
        TMPDIR="$case_root/tmp" run_harness "$name" "$case_root/test"
    ) >"$case_root/output.log" 2>&1
    status=$?
    set -e
    printf '%s %s\n' "$status" "$(( $(date +%s) - started ))" >"$case_root/status"
    return "$status"
}

if [ "${1:-}" = "--run-case" ]; then
    [ "$#" -eq 3 ] || { usage; exit 2; }
    run_child "$2" "$3"
    exit $?
fi

JOBS="${SPOTTER_TEST_JOBS:-4}"
LIST_ONLY=false
while [ "$#" -gt 0 ]; do
    case "$1" in
        --jobs)
            [ "$#" -ge 2 ] || { usage; exit 2; }
            JOBS="$2"
            shift 2
            ;;
        --list)
            LIST_ONLY=true
            shift
            ;;
        *)
            usage
            exit 2
            ;;
    esac
done

if [ "$LIST_ONLY" = true ]; then
    printf '%s\n' "${TESTS[@]}"
    exit 0
fi
if [[ ! "$JOBS" =~ ^[1-9][0-9]*$ ]] || [ "$JOBS" -gt 16 ]; then
    echo "✗ --jobs must be an integer from 1 through 16." >&2
    exit 2
fi
command -v swiftc >/dev/null || { echo "✗ swiftc is required." >&2; exit 1; }
command -v xargs >/dev/null || { echo "✗ xargs is required." >&2; exit 1; }
validate_manifest

TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/spotter-tests.XXXXXX")"
cleanup_tests() {
    case "$TEST_ROOT" in
        */spotter-tests.*) rm -rf "$TEST_ROOT" ;;
    esac
}
trap cleanup_tests EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
STARTED="$(date +%s)"

echo "▸ Running ${#TESTS[@]} standalone harnesses with $JOBS workers…"
set +e
printf '%s\n' "${TESTS[@]}" \
    | xargs -P "$JOBS" -I '{}' "$SELF" --run-case '{}' "$TEST_ROOT"
XARGS_STATUS=$?
set -e

FAILURES=0
for name in "${TESTS[@]}"; do
    if [ ! -f "$TEST_ROOT/$name/status" ]; then
        echo "FAIL  $name (did not report a result)"
        FAILURES=$((FAILURES + 1))
        continue
    fi
    read -r status duration <"$TEST_ROOT/$name/status"
    if [ "$status" -eq 0 ]; then
        echo "PASS  $name (${duration}s)"
    else
        echo "FAIL  $name (${duration}s)"
        FAILURES=$((FAILURES + 1))
    fi
done

if [ "$FAILURES" -ne 0 ] || [ "$XARGS_STATUS" -ne 0 ]; then
    echo
    echo "Failure output:"
    for name in "${TESTS[@]}"; do
        if [ -f "$TEST_ROOT/$name/status" ]; then
            read -r status _ <"$TEST_ROOT/$name/status"
            [ "$status" -eq 0 ] && continue
        fi
        echo
        echo "[$name]"
        if [ -f "$TEST_ROOT/$name/output.log" ]; then
            sed -n '1,240p' "$TEST_ROOT/$name/output.log"
        else
            echo "No log was produced."
        fi
    done
    echo
    echo "✗ $FAILURES of ${#TESTS[@]} harnesses failed."
    exit 1
fi

echo "✓ All ${#TESTS[@]} harnesses passed in $(( $(date +%s) - STARTED ))s."
