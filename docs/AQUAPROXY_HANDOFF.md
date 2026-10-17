# AquaProxy 対応の引き継ぎメモ (2026-10-17)

後続エージェント (Claude など) が AquaProxy 対応を引き継ぐためのメモ。
背景・技術判断・実装内容・未完了の実機検証手順を記す。

## 背景

- ユーザーレポート: Snow Leopard 環境で「AquaProxy が導入済みのため
  Discord サーバーと通信できない」。
- 0.1.0-beta1 の既知の制限
  (`docs/release-notes/0.1.0-beta1.md`): 「AquaProxy などの HTTPS
  プロキシ経由でしか通信できない環境では接続できません。DNS が使える
  ネットワーク設定が必要です」。つまりこれまでの実装は
  システムプロキシ非対応。
- 多くのレガシー Mac ユーザーは AquaProxy を常時導入しており、
  「OFF にしてから使え」は現実的な案内ではない。
  → AquaProxy 導入済みの状態で通信できることが目標。

## AquaProxy の仕組み (根拠)

- 作者是 Wowfunhappy
  (MacRumors: "Aqua Proxy: Fix connection issues on OS X 10.6 – 10.9" /
  GitHub: Wowfunhappy/AquaProxy。2026-09 にリポジトリは read-only 化)。
- ローカル MITM HTTP プロキシ (kr/mitm ベースの Go 実装)。既定の待ち受けは
  `127.0.0.1:6531`。macOS のシステムプロキシ設定
  (Network > Advanced > Proxies の Web プロキシと Secure Web プロキシ) を
  指す形で使う。CFNetwork 系アプリ (Safari / Mail / Dictionary など) は
  これに従う。
- MITM 用ルート証明書はユーザーごとに生成され、ユーザーが Keychain に
  信任登録する。
- AquaProxy は ClientHello を検査し、アプリの TLS が現代的と判断した
  接続は MITM せず素通しする。
- 本アプリは curl 8.11 + OpenSSL 3 (TLS 1.3) なので原則素通し見込み。
  ただし環境によっては (ネットワーク全体がプロキシ経由必須の構成など)
  MITM 前提の
  設定があるため、MITM 時にも厳格検証で通るようにする。

## 動作の仕組みと診断に使った知見 (要約)

- AquaProxy は ClientHello を検査し、`isModernClient =
  supportsTLS13 || supportsHTTP2` (http.go:147, 1398) なら
  **passthrough**: AquaProxy 自身が目的のホスト名を DNS 解決して
  直接ダイヤルし、以後は素通しする。本アプリの curl 8.11 + OpenSSL 3
  (TLS 1.3) はこれに該当し、実運用では MITM されない。
- MITM されるのは古い TLS (10.6 のシステム curl など) のみ。MITM 経路
  であっても `effectiveCAPath` に Keychain アンカーを連結しているので
  厳格検証で通る (REST はこの経路で動作確認済みだった日がある)。
- 本機の DNS が壊れていると **passthrough 経路が AquaProxy 内で死ぬ**
  (`Failed to connect to upstream host gateway.discord.gg:443:
  dial tcp: lookup gateway.discord.gg: no such host`)。アプリ側では
  TLS connect error に見えるため切り分けには AquaProxy のログ
  (`/tmp/AquaProxy.error.log`, LaunchAgent `Wowfunhappy.AquaProxy.Proxy`
  の StandardErrorPath) を見ること。いかなる実装でも AquaProxy 自身の
  解決が失敗すると全体が不通になるため、**プロキシ環境では
  健全な DNS 設定が前提条件**。
- AquaProxy の MITM 経路はアイドル 60 秒で再利用接続を回収する
  (`mitmIdleTimeout`)。passthrough トンネルのタイムアウトは不明だが
  約 30 秒で落ちる観察があったため、クライアント側 15 秒 keepalive で
  常に接続を保ち、アイドル切断を防いでいる (下記 4 参照)。

## 診断に使った手順 (要点だけ残す)

1. アプリ側ログは `/var/log/system.log` (`grep "Legacy Discord"`)。
   WS 接続失敗は `NSLog` (`printf` は `open` 起動の GUI では
   stderr が破棄されて見えないので不可)。
2. `CURLOPT_ERRORBUFFER` を WS ハンドルに設定済み。failure 行に
   curl コード + 詳細エラーが出る
   (例: `SSL connect error (TLS connect error: ...)`)。
3. AquaProxy 側は `/tmp/AquaProxy.error.log` すべて
   (Go の log.Printf は stderr 出力。`/tmp/AquaProxy.log` は空)。
4. 実機: SSH を張った 2 台の出力は post-quantum 警告で汚れるため
   `grep -vE "post-quantum|store now|OpenSSH"` でフィルタ。

## 実装した対処

方針: システムのプロキシ設定を尊重することで AquaProxy を
「迂回対象」ではなく「経路」として使い、TLS 検証は緩めない。

1. **システム HTTP(S) プロキシ対応 (新規)**
   - `Discord Lite/DLUtil.m`
     - `+(void)applySystemProxyToCurlHandle:(void *)curlHandle url:(NSString *)url`
       - `SCDynamicStoreCopyProxies` で Secure Web / Web プロキシ
         (`kSCPropNetProxiesHTTPS*` / `kSCPropNetProxiesHTTP*`) を読み、
         curl に `CURLOPT_PROXY` を設定。スキームが https/wss の場合は
         `CURLOPT_HTTPPROXYTUNNEL=1` (CONNECT トンネル)。
         プレーン HTTP は通常のプロキシ形式で送る (MITM プロキシは
         ポート 80 への CONNECT を扱わない可能性があるため)。
       - 「これらのホストとドメインではプロキシを使用しない」例外リスト
         (`kSCPropNetProxiesExceptionsList`, `.example.com` /
         `*.example.com` 形式) を `+hostIsInSystemProxyBypassList:` で判定
         し、バイパス対象にはプロキシを設定しない。
       - システムプロキシが未設定なら何も設定しない (既存の挙動・環境変数
         `http_proxy` 運用も不変)。
     - `+(NSString *)systemProxyInfoValue:` / `refreshSystemProxyInfoCache:`
       — 10 秒 TTL のキャッシュ。pthread mutex で REST / Gateway /
       voice スレッドから安全に読める。
   - 適用場所 (curl 接続の全起点):
     - `Discord Lite/AsyncHTTPRequest.m` `initializeRequest` — REST 全般
       (GET / POST / ファイルダウンロードはここを経由する)
     - `Discord Lite/DLWSController.m` `startWebSocketThread` — Gateway WSS
     - `Discord Lite/DLVoiceConnection.m` — voice ゲートウェイ WSS
   - `Discord Lite/DLUtil.h` に宣言を追加。curl 型はヘッダに露出させない
     (引数は `void *`)。
2. **Keychain アンカーを含む CA バンドル (新規)**
   - `DLUtil.m` `+(NSString *)effectiveCAPath`
     - 同梱 `Discord Lite/cacert.pem` (Mozilla ルート群) に、macOS の
       trust settings (System / ユーザー keychain の
       `SecTrustSettingsCopyCertificates`) を PEM 化したものを連結し、
       `~/Library/Caches/LegacyDiscord-ca.pem` に書き出して
       `CURLOPT_CAINFO` に使う。起動中に 1 回のみ構築 (static キャッシュ)。
     - アンカーが取れない・空なら従来どおり同梱バンドルのみを指すので、
       挙動変化なし。
     - 意図: AquaProxy が MITM を行う環境でも、ユーザー自身が Keychain に
       信任した AquaProxy ルートで厳格検証が通る。
       `CURLOPT_SSL_VERIFYPEER=0` など検証の緩和は一切していない。
   - base64 は既存 `+[NSString encodeBase64WithData:]`
     (NSString+Base64) を使用。単一行 base64 を 64 文字折り返しに整える
     `wrappedPEMBodyOfBase64String:` を追加。
   - 変換先を利用する 3 箇所 (`AsyncHTTPRequest.m` / `DLWSController.m` /
     `DLVoiceConnection.m`) は `caBundlePath` → `effectiveCAPath` に変更。
 3. **Gateway リーチャビリティのプロキシ配慮**
    - `DLWSController.m` `isDiscordNetworkReachable`: 最初に
      `+[DLUtil systemProxyServesHost:@"discord.com"]` を確認し、YES なら
      直接経路の flags を見ない。プロキシ必須のネットワークでは
      `kSCNetworkReachabilityFlagsConnectionRequired` が立つため、修正前は
      Gateway が誤って永久 Reconnecting 表示になる可能性があった。
 4. **Gateway WS の keepalive ping と診断整備**
    - AquaProxy 側のトンネルはアイドル約 30 秒で回収されるのに対し
      Discord の最初の heartbeat は HELLO から約 41 秒後に来るため、
      接続後そのままでは WS がプロキシに切られる。
       - ping 送信も既存設計 (すべての curl_ws_send は WS スレッド上) を
        守るため、`GatewayKeepalivePingMarker` (文字列マーカー) を
        `outgoingFrames` に 15 秒ごとに入れ、`sendQueuedFramesOnHandle:`
        がそのマーカーを見つけたら WS スレッド上で `curl_ws_send(...,
        CURLWS_PING)` を送る (メインスレッドの
        `scheduleGatewayKeepalive` / `gatewayKeepaliveTick:` /
        `invalidateGatewayKeepalive`; 接続開始時に schedule、
        スレッド終了と `stop` で invalidate)。
      - 受信ループは CURLWS_PONG をアプリ用メッセージとして
        buffer に追加しない (message 汚染防止)。サーバーからの
        CURLWS_PING には同 payload で CURLWS_PONG を返す。
      - 切断診断: close フレームの close code (curl 8.11 の
        `curl_ws_frame` には close code フィールドがないため payload
        先頭 2 バイト big-endian で自前解析) と接続経過秒数を
        NSLog。`WebSocket connect failed:` 行は printf → NSLog に
        変更し、`CURLOPT_ERRORBUFFER` の詳細も併記。
      - WS ハンドルに `CURLOPT_HTTP_VERSION = CURL_HTTP_VERSION_1_1`
        を設定 (アップグレードハンドシェイクは h2 不可のため)。

 - SSL 検証 (`CURLOPT_SSL_VERIFYPEER=1` / `VERIFYHOST=2`) は全経路で維持。
 - 今回の変更ファイル: `DLUtil.h`, `DLUtil.m`, `AsyncHTTPRequest.m`,
   `DLWSController.m`, `DLVoiceConnection.m`。

## 検証状況 (2026-10-17 時点の最終結果)

- `sh scripts/verify-source.sh` は exit 0。
- **Snow Leopard 10.6.8 (MacBook, AquaProxy 有効のまま) 実機 PASS**
  - 最初の実行では WS が「SSL connect error (TLS connect error)」を
    ~2 秒ごとに返し失敗。原因は AquaProxy 側で、本機のシステム
    resolver が空 (`scutil --dns` の resolver #1 に nameserver なし)
    のため passthrough の直接ダイヤルが `no such host`。
    これは AquaProxy のログ (`/tmp/AquaProxy.error.log`) で判明。
  - ユーザーが実機上で DNS を設定
    (`sudo networksetup -setdnsservers AirPort 192.168.11.1 8.8.8.8`)
    したところ、再実行で `Gateway connection established.` 以降
    切断なし。REST ポストも実データが届き、08:35 の実機
    スクリーンショットでログイン中のセッション
    (DM 一覧 / フレンドのプレゼンス / 日本語 UI) を確認:
    `artifacts/snow-leopard/screenshots/20261017-083503-62669.png`。
  - 検証時間: 接続確立から 3 分以上継続、30 秒切断の再発なし。
- **Mountain Lion 10.8.5 (MBP2012, AquaProxy 有効) 実機 PASS (WS)**
  - 1 回目の接続だけ 20 秒タイムアウト、2 回目で
    `Gateway connection established.`。REST / UI データ読み込みは
    正常。DNS が健全な構成では問題なし。

## 実機検証手順 (後続エージェント用) — 完了済みの記録も兼ねる

### 0. 到達と前提

```sh
ssh -o ConnectTimeout=5 MacBook 'sw_vers; uname -m'   # 10.6.8 / x86_64
ssh -o ConnectTimeout=5 MBP2012 'sw_vers; uname -m'   # 10.8.5 / x86_64
```

実機ホスト名は `MacBook` (Snow Leopard) と `MBP2012` (Mountain Lion)。
Mountain Lion 用スクリプトは既定値 `mountainlion` ではなく
`--host MBP2012` を付けて呼ぶこと
(`./scripts/remote-build-mountainlion.sh --host MBP2012 --run`)。

### 1. AquaProxy の状態把握

```sh
ssh MacBook 'scutil --proxy; networksetup -getsecurewebproxy "Wi-Fi"; networksetup -getwebproxy "Wi-Fi"'
ssh MacBook 'ps auxww | grep -i "[A]quaProxy"'
```

`scutil --proxy` に `HTTPEnable : 1` / `HTTPProxy : 127.0.0.1` /
`HTTPPort : 6531` (および HTTPS の同様) があれば AquaProxy 構成。

### 2. AquaProxy 越しの通信と MITM の種別確認

システム curl (10.6 は TLS 1.0) は「古い」ため、AquaProxy に
MITM される挙動の観察に使える。

```sh
ssh MacBook 'curl -sx http://127.0.0.1:6531 -D - -o /dev/null https://discord.com 2>&1 | head -10'
ssh MacBook 'curl -kvx http://127.0.0.1:6531 https://discord.com 2>&1 | grep -iE "issuer|subject:|SSL|TLS"'
```

- 出力に AquaProxy 由来の issuer が見えれば MITM 型環境。
  このルートが Keychain に信任されていることが本修正の
  `effectiveCAPath` が値をくれる前提。
- AquaProxy が素通しする構成なら、issuer は Let's Encrypt など本来の
  issuer になる (本アプリの接続はこの挙動)。その場合、strict 検証は
  同梱 cacert.pem だけで通る。

### 3. ビルドと実効確認

```sh
./scripts/remote-build-snow-leopard.sh --run   # Snow Leopard (MacBook)
./scripts/remote-build-mountainlion.sh --run  # Mountain Lion (MBP2012)
```

確認観点 (AquaProxy を有効のまま):

- ログイン → サーバー/DM の読み込み → メッセージ送受信。
- Gateway 状態ドットが接続状態に落ち着き、無限 Reconnecting にならない。
- `~/Library/Caches/LegacyDiscord-ca.pem` の生成 (アンカーが 1 枚以上
  ある環境のみ)。
- コンソールへ curl エラーが出ない
  (`HTTP request failed (curl error N)`: 5=プロキシ解決失敗, 7=接続失敗,
  `35 SSL connect error`, `97 proxy handshake error` は切り分け手がかり)。
- 逆方向リグレッション: AquaProxy を一時停止した環境でも
  ログインとメッセージが従来どおり機能する。
- 設定 / テーマ / 絵文字など既存機能が無影響であること。

### 4. 検証後の文書反映 — 実施済み

- `docs/KNOWN_ISSUES.md` に LD-2026-025 を追加済み
  (初回作成時は LD-2026-003 だったが、既存の LD-2026-003 と重複したため
  リナンバーした。検証結果・証拠・スクリーンショット付き)。
- `docs/release-notes/0.1.0-beta1.md` の既知の制限の行は、出荷済み
  beta1 の正確な記述なので触らない。次回リリースのノートで
  「AquaProxy 対応済み」と明記すること。
- AquaProxy を OFF にした無リグレッション確認は未実施
  (次回の実機メンテ時に推奨)。

## 残る既知の限界

- **Voice の UDP は HTTP プロキシを通れない**。voice の WSS シグナリング
  は通るが、RTP/Opus の UDP は CONNECT プロキシ経由不可なので、
  ネットワーク全体がプロキシ必須な環境ではボイスは従来どおり不可。
- **AquaProxy 経路には健全な DNS が必要** (passthrough で AquaProxy 自身が
  ダイヤルするため)。resolver が空のマシンではプロキシ有無にかかわらず
  通信不能。`networksetup -setdnsservers <service> <dns...>` は sudo が
  必要で、ユーザー自身に実行してもらうしかない。
- `systemProxyInfo` は 10 秒キャッシュ。設定変更の反映に最大 10 秒かかる。
- `effectiveCAPath` は起動中にアンカー変化を拾わない (再起動で反映)。
- `SecTrustSettingsDomainAdmin` ドメインは未走査 (特殊構成のみ影響の見込み)。
- 手動プロキシ上書きの設定 UI は未実装 (システム設定を自動的に尊重する
  形のみ)。必要なら Preferences (XIB の proxy controls) での
  手動対応を別チケに。

## 引き継ぎ時の注意

- コードは未コミット。リポジトリには以前からの WIP (`(1)` 重複ファイル
  群, 34 ファイル分) があり、本件変更と混在している。
  AquaProxy 関係の 5 ファイル (上記) を別コミットに分けることを推奨。
- `agent.md` の資務を引き続き守ること: 誠実な実機検証報告 (§14, §37)、
  GUI バグ修正前は P0/P1 を優先 (§1)、KNOWN_ISSUES は根拠付き (§11)、
  大規模な speculative リファクタ禁止 (§42)。
- 実機が到達可能になったら、まず旧挙動との差分比較として、
  AquaProxy を OFF にした状態での無リグレッション確認を先に行う。
