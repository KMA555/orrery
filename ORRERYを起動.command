#!/bin/zsh
# ビルドして ~/Applications/Orrery.app を組み立ててから起動する。
# マイク・音声認識・画面収録の許可はアプリバンドル単位で記録されるため、素の実行ファイルでは使えない。
set -e
cd "$(dirname "$0")"

APP="$HOME/Applications/Orrery.app"

echo "ビルド中…"
swift build -c release

pkill -f "Orrery.app/Contents/MacOS/Orrery" 2>/dev/null || true

mkdir -p "$HOME/Applications"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp ".build/release/Orrery" "$APP/Contents/MacOS/Orrery"
cp "AppResources/Info.plist" "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
cp "AppResources/Orrery.icns" "$APP/Contents/Resources/Orrery.icns"
printf 'APPL????' > "$APP/Contents/PkgInfo"
# 署名を固定する。アドホック署名だとビルドごとに別アプリ扱いになり、
# 画面収録などの許可が毎回外れてしまう。
if security find-certificate -c "Orrery Dev" >/dev/null 2>&1; then
  codesign --force --sign "Orrery Dev" "$APP" >/dev/null
else
  echo "警告: 証明書 'Orrery Dev' が無いためアドホック署名にします（許可が毎回外れます）"
  codesign --force --sign - "$APP" >/dev/null
fi

echo "起動します: $APP"
open "$APP"
