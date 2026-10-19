#!/bin/bash
# 把 MijiaMac.app 打包成「拖到 Applications 即可安装」的 DMG。
#
# 零依赖：只用系统自带的 hdiutil，不装第三方工具、不触发 Finder 自动化权限弹窗。
# 做法与 hongguomac/make_dmg.sh 完全一致（同一套流程，只是换了工程名）。
#
# 用法：
#   ./make_dmg.sh              # 构建 Release 并打包
#   ./make_dmg.sh --skip-build # 跳过构建，用现有 Release 产物打包
#
# 产物：dist/MijiaMac-<版本>.dmg
#
# 签名说明：本项目用 ad-hoc 签名（无 Apple Developer ID 证书），
#          别人首次打开会被 Gatekeeper 拦截，只能右键→打开。DMG 内附了安装说明。

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$PROJECT_DIR/Apps/MijiaMac"
SCHEME="MijiaMac"
APP_NAME="MijiaMac"
CONFIG="Release"
BUILD_DIR="$PROJECT_DIR/build"
DIST_DIR="$PROJECT_DIR/dist"

SKIP_BUILD=0
[[ "${1:-}" == "--skip-build" ]] && SKIP_BUILD=1

# ── 1. 构建 Release ──────────────────────────────────────────────
if [[ $SKIP_BUILD -eq 0 ]]; then
    echo "▸ 构建 $CONFIG …"
    cd "$APP_DIR"
    # Xcode 工程是生成物（已在 .gitignore 中），缺失时先补齐
    [[ -f "$SCHEME.xcodeproj/project.pbxproj" ]] || xcodegen
    xcodebuild -project "$SCHEME.xcodeproj" \
               -scheme "$SCHEME" \
               -configuration "$CONFIG" \
               -derivedDataPath "$BUILD_DIR" \
               build | tail -3
fi

BUILT_APP="$BUILD_DIR/Build/Products/$CONFIG/$APP_NAME.app"
[[ -d "$BUILT_APP" ]] || { echo "✗ 找不到产物：$BUILT_APP"; exit 1; }

# ── 2. 读取版本号（缺失时回退 0.0.0）──────────────────────────
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
          "$BUILT_APP/Contents/Info.plist" 2>/dev/null || echo 0.0.0)"
echo "▸ 版本：$VERSION"

# ── 3. 组装暂存目录 ─────────────────────────────────────────────
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

cp -R "$BUILT_APP" "$STAGE/$APP_NAME.app"

# 右侧的 Applications 符号链接 —— 用户把 app 拖到这里
ln -s /Applications "$STAGE/Applications"

# 安装说明（ad-hoc 签名必须提醒右键打开）
cat > "$STAGE/安装说明.txt" <<'TXT'
安装 MijiaMac（米家 macOS 客户端）

1. 把左边的「MijiaMac」图标拖到右边的「Applications」（应用程序）文件夹。
2. 打开「应用程序」，双击「MijiaMac」使用。

如果双击后提示「无法打开，因为无法验证开发者」：
   → 右键点击「MijiaMac」→ 选择「打开」→ 再点「打开」。
   → 或：系统设置 → 隐私与安全性 → 向下找到提示 → 点「仍要打开」。

首次启动后，按提示用米家 App 扫码登录即可，凭据只保存在本机。
说明：本应用未使用付费 Apple Developer 证书签名（ad-hoc 签名），
     因此首次打开需要上述额外一步操作。
TXT

# ── 4. 生成 DMG ─────────────────────────────────────────────────
mkdir -p "$DIST_DIR"
DMG="$DIST_DIR/$APP_NAME-$VERSION.dmg"
rm -f "$DMG"

echo "▸ 生成 DMG …"
# UDZO = 压缩只读镜像；-ov 覆盖已存在；-fs HFS+ 兼容性最好
hdiutil create \
    -srcfolder "$STAGE" \
    -volname "$APP_NAME" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    "$DMG" >/dev/null

# ── 5. 后续拿到 Developer ID 时，在这里插入「签名 + 公证」──────────
# codesign --force --deep --options runtime \
#     --sign "Developer ID Application: <名字> (<TEAMID>)" "$DMG"
# xcrun notarytool submit "$DMG" --apple-id <mail> --team-id <TEAMID> \
#     --password <app-specific-password> --wait
# xcrun stapler staple "$DMG"

echo "✓ 完成：$DMG"
echo "  体积：$(du -h "$DMG" | awk '{print $1}')"
echo
echo "  提示：首次打开需右键→打开（ad-hoc 签名限制，详见 DMG 内安装说明）"
