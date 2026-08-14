# ORRERY

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![License: MIT](https://img.shields.io/badge/License-MIT-green)
[![Release](https://img.shields.io/github/v/release/ito-ops/orrery)](https://github.com/ito-ops/orrery/releases/latest)

[English README →](README.en.md)

画面いっぱいに広がるHUDダッシュボードです。中央のアークリアクターがCodexの音声に反応し、まわりに日付・天気・株価・システム情報・Claudeの使用量が並びます。

![ORRERY](docs/screenshot-arc.png)

配色テーマは設定画面（⌘,）から切り替えられます。

| EMBER | MATRIX |
| --- | --- |
| ![EMBER](docs/screenshot-ember.png) | ![MATRIX](docs/screenshot-matrix.png) |

## インストール

### ダウンロードして使う

1. [Releases](https://github.com/ito-ops/orrery/releases/latest) から `Orrery-vX.X.X-macos.zip` をダウンロードして展開
2. `Orrery.app` を `~/Applications`（または `/Applications`）へ移動
3. 無料配布のため Apple の公証を通しておらず、初回は Gatekeeper にブロックされます。ターミナルで隔離属性を外してから開いてください:

```bash
xattr -cr ~/Applications/Orrery.app
```

（Finder で右クリック → 開く でも可。開けない場合は システム設定 › プライバシーとセキュリティ 最下部の「このまま開く」）

ソースはすべて公開されているので、気になる場合は次のソースビルドをどうぞ。

### ソースからビルドする

Xcode か Command Line Tools が入っていれば:

```bash
git clone https://github.com/ito-ops/orrery.git
```

```bash
cd orrery && ./ORRERYを起動.command
```

ビルドして `~/Applications/Orrery.app` を組み立ててから起動します。マイク・音声認識・画面収録の許可はアプリバンドル単位で記録されるため、`swift run` の素の実行ファイルでは音声機能が使えません。

終了は ⌘Q です。

### 必要な許可

| 許可 | 用途 | 求められるタイミング |
| --- | --- | --- |
| 画面収録 | Codexの音声レベルを取る（映像は保存しません） | 初回起動時 |
| アクセシビリティ | Codexへ ⌘N / ⌃⇧V を送る | 「CODEX と話す」を初めて押したとき |
| マイク・音声認識 | 声での起動 | 「音声起動」を初めてONにしたとき |

画面収録が未許可のときは中央に `SOURCE ▸ NO ACCESS` と出て、その下のボタンから設定画面を開けます。

**画面収録だけは手で追加する必要があります。** アドホック署名のアプリには macOS が自動の許可ダイアログを出さないため（`CGRequestScreenCaptureAccess()` が false を返す）、次の手順で追加してください。

1. システム設定 › プライバシーとセキュリティ › 画面収録
2. 「+」から `~/Applications/Orrery.app` を選ぶ
3. トグルをON
4. アプリを再起動

**ビルドし直すと署名（cdhash）が変わるため、この許可は外れます。** 毎回やり直すのが面倒な場合は、自己署名の証明書を作って署名を固定する方法があります。

## 音源の切り替え

上部の2つのボタンで、何の音に反応させるかを選べます。

| ボタン | 内容 |
| --- | --- |
| `CODEXのみ` / `全体の音` | Codexアプリだけの音か、システム全体の音か。Codexは内部で別プロセスが音を鳴らすため、`CODEXのみ`で拾えないことがあります |
| `自分の声` | マイクを混ぜます。**Codexと話しているときの自分の声はマイク経由**なので、これをONにしないと自分が喋っても反応しません |

システム音とマイクは、バンドごとに大きいほうを採用して合成しています。

## 画面の内容

| 場所 | 内容 |
| --- | --- |
| 左上 | 時計と日付 |
| 上部 | ホスト名 / IP / コア数 / 稼働時間、更新ボタン、重なり方の切り替え |
| 左 | CPU・メモリ・ストレージ・電源・通信量、Claudeの使用量（概算） |
| 中央 | ORRERYの文字とリング一式、CPU/メモリのセグメントゲージ、音声セッションのボタン |
| 右 | 天気（現在＋4日分の予報）、株価・為替 |
| 下部 | Codexの音に反応して流れる砂の帯 |

中央と下部の粒子は常にゆっくり流れ、Codexが喋っている間だけ色づいて大きく広がります。

## Codexの音だけを拾う

ScreenCaptureKitのフィルタを使い、Codex（`com.openai.codex`／表示名はChatGPT）とCodexBarの音だけを解析しています。対象アプリの起動・終了は6秒ごとに見張って自動で切り替わります。対象が1つも見つからないときはシステム全体の音にフォールバックし、中央に `SOURCE ▸ SYSTEM (対象なし)` と表示します。

## Codexと音声で話す

中央下の「CODEX と話す」を押すと、次の順に進みます。

1. Codexアプリ（`com.openai.codex`）を前面に出す
2. **⌘N**（`newTask`）で新しいチャットを作る
3. **⌃⇧V**（`composer.startVoiceMode`）で音声ライブを開く
4. HUDを**最前面**に切り替える

押すたびに新しいチャットから始まるので、前の会話が混ざりません。もう一度押すと元の重なり方に戻り、Codexアプリが前面に戻ります。

他アプリへキーを送るので、**システム設定 › プライバシーとセキュリティ › アクセシビリティ** でこのアプリの許可が必要です。初回は許可ダイアログが出ます。ビルドし直すと署名が変わるため、許可を求め直される場合があります。許可していない場合もアプリを前面に出すところまでは動くので、続きは Codex 側で ⌘N → ⌃⇧V を押してください。

## 声で起動する

上部右の「音声OFF」を押すと待ち受けが始まり、決めた言葉を聞き取るとボタンを押したのと同じ動作をします。

- 既定の合図: `オレリー` / `コーデックス` / `orrery` / `hey codex`
- 認識は**端末内だけ**（`requiresOnDeviceRecognition`）で行い、音声は保存も送信もしません
- セッション中は反応しません（Codexの声で誤って起動しないため）。一度反応すると6秒は次を受け付けません
- 聞き取れた文は上部に小さく出るので、反応しないときの手がかりになります
- 設定は記憶されるので、一度ONにすれば次の起動でも待ち受けます

初回のONで**マイク**と**音声認識**の許可を求められます。

## ウィンドウの扱い

ふつうのアプリと同じように扱えます。

| 操作 | 方法 |
| --- | --- |
| 移動 | 画面のどこでもドラッグ（タイトルバーが無いので背景でつかめます） |
| リサイズ | 端をドラッグ。最小 900×600 |
| 画面いっぱいに戻す | ⌘0 |
| 中央に小さく置く | ⌘9 |
| 最小化 / 閉じる / 終了 | ⌘M / ⌘W / ⌘Q |
| 重なり方の切り替え | ⌘T か上部右のボタン |

Mission Control、App Exposé、ウィンドウの整列（タイル表示）にも出ます。位置とサイズは次回起動時に復元されます。

## 重なり方

上部右のボタン（または ⌘T）で3段階に切り替わります。

| モード | 重なり | 移動 | Mission Control |
| --- | --- | --- | --- |
| **通常** | ふつうのウィンドウ | できる | 出る |
| **最前面** | 常に手前、全スペースに表示 | できる | 出る |
| **デスクトップ** | 壁紙の上・ウィンドウの後ろ | できない | 出ない |

## 設定画面

⌘,（または上部右の「設定」ボタン）で設定画面が開きます。設定は保存され、次回起動にも引き継がれます。

| タブ | 内容 |
| --- | --- |
| 一般 | 天気の地点、株価・為替の銘柄、声で起動する合図 |
| テーマ | 配色5種（ARC / EMBER / MATRIX / CRIMSON / MONO）＋カスタムカラー。1色選ぶと残りは自動で組み立てます |
| パネル | 各パネルと下部の砂の帯を個別にON/OFF。列ごと消すと中央が広がります |
| 負荷 | 粒子の数、更新頻度 |

## 環境変数

すべて設定画面から変えられますが、環境変数でも上書きできます。優先順は **環境変数 > 設定画面 > 既定値** です。

| 変数 | 既定値 | 内容 |
| --- | --- | --- |
| `HUD_CITY` | `TOKYO` | 天気パネルに出す地名 |
| `HUD_LAT` / `HUD_LON` | 東京の緯度経度 | 天気を取る地点 |
| `HUD_TICKERS` | 日経・ドル円など6銘柄 | 株価パネルの銘柄。「シンボル:表示名」をカンマ区切りで（例 `^N225:NIKKEI 225,BTC-USD:BITCOIN`） |
| `HUD_AUDIO_APPS` | `codex` | 音を拾う対象アプリ（アプリ名かバンドルIDの一部、カンマ区切り） |
| `HUD_WAKE_PHRASES` | `オレリー,コーデックス,orrery,hey codex` | 声で起動するときの合図（カンマ区切り） |
| `HUD_WAKE_LOCALE` | `ja-JP` | 音声認識の言語 |
| `HUD_GRAINS` | `1100` | 粒子の数（0で粒子なし） |
| `HUD_FPS` / `HUD_IDLE_FPS` | `30` / `12` | 音が出ている間 / 待機中の更新頻度 |
| `HUD_STATIC` | `0` | `1` で動く描画を止める（いちばん軽い） |
| `HUD_WINDOW` | なし | `1200x800` のように初期サイズを指定 |

例:

```bash
HUD_CITY=OSAKA HUD_LAT=34.6937 HUD_LON=135.5023 swift run
```

## 負荷について

全画面のCanvasを描き続けるので、待機中でCPUの約25〜30%（1コアぶん）を使います。10コアの機械なら全体の3%程度ですが、気になる場合は次で下げられます。

| やり方 | 効果 |
| --- | --- |
| ウィンドウを小さくする（⌘9） | 見た目の負担が減る |
| `HUD_STATIC=1` で起動 | 約7%まで下がる（粒子もリングも止まります） |
| 「音声起動」をOFF | 音声認識のぶんが減る |

計測したところ、粒子の数・フレームレート・ウィンドウサイズを変えても消費はほぼ変わらず、**SwiftUIのCanvasを再描画すること自体**が固定費でした。さらに下げるには描画をAppKit側（CoreGraphics）に移す必要があります。

## データの出どころ

- 天気: [Open-Meteo](https://open-meteo.com)（APIキー不要）
- 株価・為替: Yahoo Finance のチャートAPI（APIキー不要）
- システム情報: mach / IOKit / getifaddrs
- Claudeの使用量: `~/.claude/projects` のログ。usage・timestamp・model・requestId だけを読み、会話の本文は読みません

セッションを再開・分岐すると過去のやり取りが新しいログへ丸ごとコピーされるため、単純に足すと実際の2.5倍ほどになります。`requestId` でファイルをまたいだ重複を落としてから集計しています。

金額はモデル名から推定した単価による**概算**です。とくに `claude-fable-5` は公開単価を確認できなかったため仮の値で、実際の請求額とは一致しません。単価は `UsageService.swift` の `rate(for:)` にまとめてあります。

## 構成

| ファイル | 役割 |
| --- | --- |
| `App.swift` | ウィンドウの設定・重なり方・メニュー |
| `HUDView.swift` | 全体のレイアウトと上部バー |
| `HUDSettings.swift` | 設定画面の項目と保存（UserDefaults） |
| `HUDTheme.swift` | 配色テーマの定義とカスタムカラーの組み立て |
| `SettingsView.swift` | 設定画面（⌘,）のUI |
| `OrreryDial.swift` | 中央のリング一式 |
| `ParticleField.swift` | 粒子の配色と下部の砂の帯 |
| `CenterStage.swift` | 時計とCodexボタン |
| `HUDPanels.swift` | 各パネル |
| `HUDComponents.swift` | 共通の部品と配色 |
| `AudioSpectrum.swift` | 音声キャプチャと状態管理 |
| `WakeWordListener.swift` | 声での起動（端末内の音声認識） |
| `CodexLauncher.swift` | Codexアプリを開いて新規チャット＋音声ライブを立ち上げる |
| `SpectrumAnalyzer.swift` | FFT |
| `SystemMonitor.swift` / `WeatherService.swift` / `MarketService.swift` / `UsageService.swift` | 各データの取得 |
| `AppResources/Info.plist` | バンドルのInfo.plist（用途説明・アイコン指定） |
| `AppResources/Orrery.icns` | アプリアイコン |
| `tools/make-icon.swift` | アイコンを描き直すスクリプト |

見た目や反応の速さは `AudioSpectrum.swift` の `Tuning`、半径のバランスは `OrreryDial.swift` の `R` で調整できます。
