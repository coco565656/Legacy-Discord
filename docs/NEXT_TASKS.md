# 次の作業指示（2026-10-18 時点）

> **最優先の注意（2026-10-21）**: Legacy Discord でのログイン後にアカウントが無効化される事象がありました。
> 作業前に必ず `docs/ACCOUNT_SAFETY.md` を読み、**テストは必ずテスト用アカウントで、1 台ずつ** 行ってください。
> 接続まわり（ヘッダー、IDENTIFY、再接続）を変えるときは、その文書の対策を崩さないこと。


対象: 開発を引き継ぐエージェント。`CLAUDE.md` と `agent.md` の規則に従ったうえで、上から順に進めてください。
現在のリリースは `v0.1.0-beta1`（ボイスチャットなし）です。**ボイスチャット（VC）にはまだ着手しないでください。**
VC はユーザーの指示があってから再開します（`docs/VOICE_PLAN.md`）。

## 進め方の約束

- 1 タスクごとに: 実装 → ローカルビルド（`scripts/local-build-dev.sh`）→ 実機ビルド（ML: `scripts/remote-build-mountainlion.sh --host MBP2012 --release`、
  SL: `scripts/remote-build-snow-leopard.sh --run`）→ 実機で目視確認 → コミット → **push**（`agent/mavericks-remote-build` と `main` の両方。force push 禁止）。
  （2026-10-19 時点で両ブランチは 0fbe064 で一致済み）
- SL のビルドスクリプトは git 管理下のファイルだけを転送します。新しいファイルは先に `git add` してください。
- ML でアプリを起動するときは ssh の `open` ではなく Finder 経由で起動します（Keychain が -25308 になるため）。手順は `docs/REAL_DEVICE_TESTING.md`。
- 実際に Discord へ書き込む操作（送信、ピン留め、スレッド作成、招待作成、チャンネル作成・編集・削除、ニックネーム変更、サーバー脱退、アカウント設定の変更）は、
  **ユーザーの許可を得てから**、ユーザーのサーバー「イワシの缶詰」でだけ行います。Return キーを連続で送らないこと。
- 実機で確認していないものは「未検証」と書きます。

## 前回のレビューで指摘した点（同じ誤りを繰り返さないこと）

1. **NSTimer の所有権**: `timerWithTimeInterval:` の戻り値は autorelease です。ivar に保持して後で `release` するなら `retain` してください（keepalive タイマーで過剰解放がありました）。
2. **スレッド**: `AsyncHTTPRequest` の `start` と `AsyncHTTPRequestSequencer` はメインスレッド専用です（ロックなし）。`channelsForServer:` などバックグラウンドスレッドから呼ばれる処理の中でリクエストを開始しないでください。
3. **リクエストキューは先着順**です。大量の先読みを積むとメッセージの読み込みが遅れます。先読みは遅延・件数上限・少量ずつにしてください。
4. **TLS の信頼**: 証明書を信頼する処理を変えるときは、ユーザーが「信頼しない」にした証明書を信頼しないこと。検証（VERIFYPEER / VERIFYHOST）を緩めないこと。

## タスク（優先順）

### 1. P0: 起動直後に Gateway へ接続できなかった場合に再接続しない【完了 2026-10-19】
- 症状（ML で観測）: 起動直後にネットワークが不安定だと「Websocket Closed」が 1 回出たきり、2 分以上ログインしないまま待ち続けることがありました。
  サンプルでは `DLWSController checkNetworkReachability:` のタイマーだけが動いていました。
- 対応: reachability タイマーをウォッチドッグ化（接続中もスケジュール済みもないときに scheduleReconnect を再装填）、
  再試行の指数バックオフ（2〜60 秒、Hello 受信でリセット）、世代トークンで失効した遅延再試行と
  旧セッションのハートビット/レジューム確認を無効化、未確認レジュームのセッションを破棄して
  identify し直すようにしました。さらに `DLController.wsDidLoadAllDataAfterReconnection:` で
  初回データ未取得の場合は再接続フラグ付き READY でも initial UI を構築します
  （起動時に失敗を重ねたあと UI が空のまま残る既存不具合の修正）。
- 実機確認: ML(MBP2012 10.8.5) / SL(MacBook 10.6.8) ともに AquaProxy を一時停止して起動 →
  失敗が 2→4→8→16→32→60 秒バックオフで続く → プロキシ復旧後の自動再接続で identify → READY →
  サーバー/DM/フレンドが表示されること、および通常起動での非回帰なし。全回帰 PASS。
- 残作業（P5 相当・改善候補）: 2 秒ティックの境界でウォッチドッグの再装填が進行中の遅延再試行と
  競合し、まれに 1 回多く即時試行が出ます（収束はするため動作に影響なし。ログ上は
  「Watchdog: reconnect loop was lost」と「Retry dropped/firing」の組み合わせで観測）。

### 2. P1: 表示中のチャンネルを削除した後の画面
- `DLServerMenuController showDeleteChannelDialogForChannel:` で表示中のチャンネルを削除すると、チャット欄に削除済みのチャンネルが残ります。
- 期待: 削除後は同じサーバーの最初のテキストチャンネルを選択する（公式と同じ）。

### 3. P1: リアクションボタンを Discord 風のピルにする
- 現在は macOS 標準の Recessed ボタン（`ChatItemViewController` の reaction buttons）で、ライトのカラーテーマでは文字が読みにくいです。
- 期待: 公式と同じ角丸ピル。通常は `[DLUtil nativeSelectionColor]` 系、自分が付けたものは blurple の枠と淡い塗り。ダーク・ミッドナイト・オーロラ・Nitro の全テーマで読めること。
- 色は必ず `DLUtil` の関数経由で取ってください（Nitro テーマではパターンカラーになるため、`blendedColorWithFraction:` や `colorWithAlphaComponent:` は使わないこと。ホバーは `nativeHoverColor`）。

### 4. P2: 未翻訳の文言の洗い出し
- 日本語表示で英語のまま残っている箇所を実機で探し、`DLLocalizedString(@"...")` で包んで `Discord Lite/Localizable-ja.plist` に訳を追加してください。
- 複数形や語順のある文は、英語の部品をつなげず文全体をキーにします（`DLPluralSuffix` の使い方は既存コードを参照）。
- `isEqualToString:` などの比較に使う内部キーは翻訳しないこと。

### 5. P2: 書き込み系機能の実機テスト（ユーザーの許可を得てから）
- 「イワシの缶詰」で、次の操作を 1 回ずつ試して結果を `docs/REAL_DEVICE_TESTING.md` に記録してください。試した後は元に戻します（作ったものは削除）。
  - メッセージのピン留め / 解除、メッセージからのスレッド作成
  - 招待リンクの作成、チャンネル・カテゴリーの作成 / 編集 / 削除
  - サーバープロフィール（ニックネーム）の変更と解除
  - 通知設定（サーバー・チャンネル）とミュートしたチャンネルの非表示
  - 設定 › コンテンツ＆ソーシャルの各トグル（アカウント設定が変わるので、終わったら元の値に戻す）

### 6. P3: KNOWN_ISSUES の整理
- `docs/KNOWN_ISSUES.md` に、上のタスクで直したもの・残ったものを根拠（スクリーンショットのパス、ログ）付きで反映してください。

## 完了報告

各タスクの終わりに、日本語で「何を直したか・どの実機で何を確認したか・未検証のもの」を短く報告してください。
