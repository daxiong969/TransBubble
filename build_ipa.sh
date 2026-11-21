#!/bin/bash
#
# TransBubble 一键构建 IPA 脚本（必须在 macOS 上运行）
#
# 用法：
#   1) 签名构建（可安装到真机，需要 Apple 开发者账号）：
#      TEAM_ID=你的团队ID ./build_ipa.sh
#      （免费个人 Apple ID 也可以，在 Xcode 登录后即可拿到 Team ID）
#
#   2) 免签名构建（产出 unsigned IPA，供 AltStore / Sideloadly / TrollStore 自签安装）：
#      UNSIGNED=1 ./build_ipa.sh
#
set -e
cd "$(dirname "$0")"

echo "==> [1/4] 检查 XcodeGen ..."
if ! command -v xcodegen >/dev/null 2>&1; then
  echo "    未安装 xcodegen，尝试通过 Homebrew 安装..."
  if ! command -v brew >/dev/null 2>&1; then
    echo "错误：请先安装 Homebrew（https://brew.sh），然后重试。"
    exit 1
  fi
  brew install xcodegen
fi

echo "==> [2/4] 生成 Xcode 工程 ..."
xcodegen generate

echo "==> [3/4] 编译归档（Release）..."
BUILD_DIR="build"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

if [ "$UNSIGNED" = "1" ]; then
  # 免签名：仅编译 .app，之后手工打包成 ipa
  xcodebuild -project TransBubble.xcodeproj \
    -scheme TransBubble \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    -sdk iphoneos \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    build

  APP_PATH=$(find "$BUILD_DIR/DerivedData/Build/Products/Release-iphoneos" -maxdepth 1 -name "*.app" | head -n 1)
  if [ -z "$APP_PATH" ]; then
    echo "错误：未找到编译产物 .app"
    exit 1
  fi

  echo "==> [4/4] 打包免签名 IPA ..."
  rm -rf "$BUILD_DIR/Payload"
  mkdir -p "$BUILD_DIR/Payload"
  cp -R "$APP_PATH" "$BUILD_DIR/Payload/"
  cd "$BUILD_DIR" && zip -qry TransBubble-unsigned.ipa Payload && cd ..
  echo ""
  echo "✅ 完成：$(pwd)/$BUILD_DIR/TransBubble-unsigned.ipa"
  echo "   该 IPA 未签名，可用 AltStore / Sideloadly / TrollStore 自签后安装。"
else
  if [ -z "$TEAM_ID" ]; then
    echo "错误：签名构建需要设置 TEAM_ID，例如：TEAM_ID=ABC123XYZ ./build_ipa.sh"
    echo "      或使用免签名模式：UNSIGNED=1 ./build_ipa.sh"
    exit 1
  fi

  # 生成导出配置
  cat > "$BUILD_DIR/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>${EXPORT_METHOD:-development}</string>
  <key>teamID</key>
  <string>${TEAM_ID}</string>
  <key>compileBitcode</key>
  <false/>
</dict>
</plist>
EOF

  xcodebuild -project TransBubble.xcodeproj \
    -scheme TransBubble \
    -configuration Release \
    -archivePath "$BUILD_DIR/TransBubble.xcarchive" \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    archive

  echo "==> [4/4] 导出签名 IPA ..."
  xcodebuild -exportArchive \
    -archivePath "$BUILD_DIR/TransBubble.xcarchive" \
    -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
    -exportPath "$BUILD_DIR/export" \
    -allowProvisioningUpdates

  IPA_PATH=$(find "$BUILD_DIR/export" -name "*.ipa" | head -n 1)
  echo ""
  echo "✅ 完成：$IPA_PATH"
  echo "   可通过 Xcode 的 Devices 或 Apple Configurator 安装到真机。"
fi
