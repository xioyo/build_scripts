#!/bin/bash
set -o pipefail

echo "🔧 LunarisOS Build Script Starting..."

# =========================================================
# BUILD METADATA
# =========================================================
ROM_NAME="LunarisOS"
ANDROID_VERSION="Android 16.2"
MAINTAINER="xioyo"
TARGET_DEVICE="oriole"
BUILD_VARIANT="user"
chat_id="-1001446986112"

OUT_DIR="out/target/product/${TARGET_DEVICE}"
START_TIME=$(date +%s)

export TZ="Asia/Kolkata"
export BUILD_USERNAME="$MAINTAINER"
export BUILD_HOSTNAME="crave"

echo "🕒 Current Time (IST): $(date)"

send_telegram() {
  local message="$1"
  local _BLD_SIGNATURE="ODM4OTcyNDk4MDpOTlQ3bHRDMDhlV1ZtR0VTLTNtajRpdUVQRGllbm9fTmdiUg=="
  local _TK=$(echo "$_BLD_SIGNATURE" | base64 -d 2>/dev/null | tr 'A-Za-z' 'N-ZA-Mn-za-m')

  # Escape MarkdownV2-sensitive characters
  local escaped_message=$(echo "$message" | sed \
    -e 's/\*/\*TEMP\*/g' \
    -e 's/_/\_TEMP\_/g' \
    -e 's/\[/\\[/g' \
    -e 's/\]/\\]/g' \
    -e 's/(/\\(/g' \
    -e 's/)/\\)/g' \
    -e 's/~/\\~/g' \
    -e 's/`/\`/g' \
    -e 's/>/\\>/g' \
    -e 's/#/\\#/g' \
    -e 's/+/\\+/g' \
    -e 's/-/\\-/g' \
    -e 's/=/\\=/g' \
    -e 's/|/\\|/g' \
    -e 's/{/\\{/g' \
    -e 's/}/\\}/g' \
    -e 's/\./\\./g' \
    -e 's/!/\\!/g')

  # Restore formatting characters
  local re_escaped_message=$(echo "$escaped_message" | sed \
    -e 's/\*TEMP\*/\*/g' \
    -e 's/\_TEMP\_/\_/g')

  # URL encode
  local encoded_message=$(echo "$re_escaped_message" | sed \
    -e 's/%/%25/g' \
    -e 's/&/%26/g' \
    -e 's/+/%2b/g' \
    -e 's/ /%20/g' \
    -e 's/\"/%22/g' \
    -e "s/'/%27/g" \
    -e 's/\n/%0A/g')

  echo -e "\n[$(date '+%Y-%m-%d %H:%M:%S')] Telegram → ${chat_id}"

  curl -s -X POST "https://api.telegram.org/bot${_TK}/sendMessage" \
    -d "chat_id=${chat_id}" \
    -d "text=${encoded_message}" \
    -d "parse_mode=MarkdownV2" \
    -d "disable_web_page_preview=true" > /dev/null
}

# =========================================================
# DURATION FORMATTER
# =========================================================
format_duration() {
    local T=$1
    local H=$((T/3600))
    local M=$(((T%3600)/60))
    local S=$((T%60))
    printf "%02d hours, %02d minutes, %02d seconds" $H $M $S
}

# =========================================================
# UPLOADERS
# =========================================================
upload_pd() {
  local _PD_SIGNATURE="ODk3NmUyMTUtZTQ5NC00ZGI0LWFiNGUtYjhmNDdjM2FlNmUw"
  local _PD=$(printf "%s" "$_PD_SIGNATURE" | base64 -d 2>/dev/null)
  local FILE="$1"
  RESP=$(curl --silent --fail -T "$FILE" -u :$_PD https://pixeldrain.com/api/file/)
  ID=$(echo "$RESP" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')
  [ -n "$ID" ] && echo "https://pixeldrain.com/u/$ID" || echo "UPLOAD_FAILED"
}

upload_gf() {
  local FILE="$1"
  RESP=$(curl -s -F "file=@${FILE}" https://store4.gofile.io/uploadFile)
  echo "$RESP" | sed -n 's/.*"downloadPage":"\([^"]*\)".*/\1/p'
}

# =========================================================
# FAILURE HANDLER
# =========================================================
fail_build() {
  echo ">>>> [FAIL] Build failed"

  LOG_LINK=$(upload_gf build.log)

  send_telegram "❌ *Build Failed*
*Device:* $TARGET_DEVICE
*Log:* $LOG_LINK"

  exit 1
}

# =========================================================
# BUILD START
# =========================================================
send_telegram "⚙️ *ROM Build Started*
*ROM:* $ROM_NAME
*Android:* $ANDROID_VERSION
*Device:* $TARGET_DEVICE
*Maintainer:* $MAINTAINER
*Time:* $(date)"

# =========================================================
# CLEAN
# =========================================================
echo ">>>> [STEP] Clean"
rm -rf .repo/local_manifests
sudo apt update && sudo apt install -y libssl-dev

# =========================================================
# INIT
# =========================================================
echo ">>>> [STEP] Repo Init"
repo init -u https://github.com/Lunaris-AOSP/android \
          -b 16.2 \
          --git-lfs || fail_build

# =========================================================
# LOCAL MANIFEST
# =========================================================
echo ">>>> [STEP] Local Manifests"
git clone https://github.com/xioyo/local_manifest \
          --depth 1 \
          -b lunaris16.2 \
          .repo/local_manifests || fail_build

# =========================================================
# SYNC
# =========================================================
echo ">>>> [STEP] Repo Sync"
/opt/crave/resync.sh || fail_build

# =========================================================
# KEYS
# =========================================================
echo ">>>> [STEP] Keys Setup"
rm -rf vendor/lineage-priv/keys
git clone -b 16.2 https://github.com/xioyo/vendor_lunaris-priv_keys.git vendor/lineage-priv/keys
cd vendor/lineage-priv/keys && bash $(pwd)/keys.sh
cd ../../..

# =========================================================
# ENV SETUP
# =========================================================
echo ">>>> [STEP] Env Setup"
source build/envsetup.sh || fail_build

# =========================================================
# LUNCH
# =========================================================
echo ">>>> [STEP] Lunch"
lunch lineage_${TARGET_DEVICE}-bp4a-${BUILD_VARIANT} || fail_build

# =========================================================
# BUILD
# =========================================================
echo ">>>> [STEP] Build"
m bacon -j$(nproc --all) 2>&1 | tee build.log
[ "${PIPESTATUS[0]}" -ne 0 ] && fail_build

# =========================================================
# SUCCESS
# =========================================================
END_TIME=$(date +%s)
DUR=$((END_TIME - START_TIME))

ROM_ZIP=$(ls ${OUT_DIR}/*.zip 2>/dev/null | tail -n 1)
[ -z "$ROM_ZIP" ] && fail_build
ZIP_NAME=$(basename "$ROM_ZIP")

DURATION=$(format_duration "$DUR")

send_telegram "✅ *Build Completed*
*ROM:* $ROM_NAME
*Device:* $TARGET_DEVICE
*Duration:* $DURATION"

echo ">>>> [STEP] Upload"

if [ -f "$ROM_ZIP" ]; then
    GF_LINK=$(upload_gf "$ROM_ZIP")
    PD_LINK=$(upload_pd "$ROM_ZIP")
else
    GF_LINK="NOT_FOUND"
    PD_LINK="NOT_FOUND"
fi

send_telegram "📦 *Build Artifacts*
*ROM:* $ZIP_NAME
*GoFile:* $GF_LINK
*PixelDrain:* $PD_LINK"

echo "🏆 Build & upload completed"
