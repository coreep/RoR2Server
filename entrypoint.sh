#!/bin/bash
set -euo pipefail

GAME_DIR="/game"
ROR2_DLL_PATH="${GAME_DIR}/Risk of Rain 2_Data/Managed/RoR2.dll"
BACKUP_PATH="${ROR2_DLL_PATH}.bak"
PATCHED_DLL="RoR2_Patched.dll"
CONFIG_DIR="${GAME_DIR}/Risk of Rain 2_Data/Config"
LOG_PATH="/root/.wine/drive_c/users/root/AppData/LocalLow/Hopoo Games, LLC/Risk of Rain 2/Player.log"
WINEPREFIX="${WINEPREFIX:-/root/.wine}"

XVFB_PID=""
WINE_PID=""
TAIL_PID=""

cleanup() {
    if [ -n "${TAIL_PID}" ] && kill -0 "${TAIL_PID}" 2>/dev/null; then
        kill "${TAIL_PID}" 2>/dev/null || true
        wait "${TAIL_PID}" 2>/dev/null || true
    fi
    if [ -n "${XVFB_PID}" ] && kill -0 "${XVFB_PID}" 2>/dev/null; then
        kill "${XVFB_PID}" 2>/dev/null || true
        wait "${XVFB_PID}" 2>/dev/null || true
    fi
}

trap cleanup EXIT

init_wine_prefix() {
    echo "Initializing Wine prefix at $WINEPREFIX"
    mkdir -p "$WINEPREFIX"

    if ! wineboot -u >/tmp/wineboot.log 2>&1; then
        echo "Wine prefix init failed, recreating prefix and retrying..."
        rm -rf "$WINEPREFIX"
        mkdir -p "$WINEPREFIX"
        if ! wineboot -u >/tmp/wineboot.log 2>&1; then
            echo "ERROR: wineboot failed after retry"
            sed -n '1,120p' /tmp/wineboot.log
            exit 1
        fi
    fi
}

echo "Risk of Rain 2 Dedicated Server Starting..."

if [ ! -d "$GAME_DIR" ]; then
    echo "ERROR: Game directory not found at $GAME_DIR"
    echo "Please mount your Risk of Rain 2 game directory to /game"
    exit 1
fi

if [ ! -f "$ROR2_DLL_PATH" ]; then
    echo "ERROR: RoR2.dll not found at $ROR2_DLL_PATH"
    exit 1
fi

cp -f /tmp/steamworks_sdk/*64.dll "${GAME_DIR}/" 2>/dev/null || true

if [ ! -f "$BACKUP_PATH" ]; then
    echo "Backup not found. Patching RoR2.dll..."
    
    cp "$ROR2_DLL_PATH" "$BACKUP_PATH"
    echo "Created backup: $BACKUP_PATH"
    
    echo "Building patcher..."
    cd /app/RoR2Patcher
    dotnet build -c Release
    
    echo "Running patcher..."
    dotnet run -c Release -- --input "$ROR2_DLL_PATH" --output "/app/$PATCHED_DLL"
    
    cp "/app/$PATCHED_DLL" "$ROR2_DLL_PATH"
    echo "Applied patch to RoR2.dll"
else
    echo "Backup found. Skipping patching."
fi

echo "Processing configuration..."
mkdir -p "$CONFIG_DIR"
envsubst < /app/config.cfg > "$CONFIG_DIR/server.cfg"
cp -f "$CONFIG_DIR/server.cfg" "$CONFIG_DIR/config.cfg"
cp -f "$CONFIG_DIR/server.cfg" "$CONFIG_DIR/server_startup.cfg"

export DISPLAY=:99
Xvfb "$DISPLAY" -screen 0 1024x768x24 &
XVFB_PID=$!
export WINEPREFIX

for _ in {1..20}; do
    if [ -S "/tmp/.X11-unix/X99" ]; then
        break
    fi
    sleep 1
done

if [ ! -S "/tmp/.X11-unix/X99" ]; then
    echo "ERROR: Xvfb did not start on DISPLAY $DISPLAY"
    exit 1
fi

if [ ! -f "$WINEPREFIX/drive_c/windows/system32/kernel32.dll" ]; then
    echo "Wine prefix is missing kernel32.dll, recreating prefix"
    rm -rf "$WINEPREFIX"
fi

init_wine_prefix

cd "$GAME_DIR"
echo "Starting Risk of Rain 2 Dedicated Server..."

SERVER_ARGS="-batchmode -nographics $EXTRA_ARGS"
wine "Risk of Rain 2.exe" $SERVER_ARGS &
WINE_PID=$!

echo "Waiting for log file at: $LOG_PATH"

while [ ! -f "$LOG_PATH" ]; do
    if ! kill -0 "$WINE_PID" 2>/dev/null; then
        echo "Wine process died before creating log file"
        exit 1
    fi
    sleep 2
done

echo "Log file found, tailing output..."
tail -n +1 -F "$LOG_PATH" &
TAIL_PID=$!

set +e
wait "$WINE_PID"
WINE_EXIT=$?
set -e

echo "Wine process exited with code $WINE_EXIT"
exit "$WINE_EXIT"
