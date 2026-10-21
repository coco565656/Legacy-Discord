# アカウントの無効化（不正アクセス扱い）について

2026-10 に、Legacy Discord でログインした後に「不審な行動を検出したためアカウントを無効にした」というメールが届き、
全デバイスからログアウトさせられる事象が起きました。Discord は判定理由を公開していないため確定はできませんが、
コードを調べて原因の候補を絞り、対策を入れました。

## 原因の候補

1. **クライアントの名乗りが場面ごとに違っていた（最有力）**
   - ログインと REST: 「Discord デスクトップアプリ」を名乗る X-Super-Properties（2023 年の古いビルド番号 209354、
     Electron の User-Agent、OS は macOS 10.15 と申告しつつ os_version は実際の Darwin 10.x）に、
     Firefox 固有のヘッダー（DNT、Sec-GPC、TE: trailers）を付けていた。タイムゾーンは America/New_York 固定。
   - Gateway: IDENTIFY では `browser: "Legacy Discord"` と実際の OS バージョンを申告。
   - 同じトークンが数秒のうちに別々のクライアントとして現れるため、トークン流出（乗っ取り）と判定されやすい。
2. **新しいセッションの作り過ぎ**
   - 再接続でレジュームの確認を 2 秒しか待たず、失敗扱いにして IDENTIFY をやり直していた。
     バックオフも Hello 受信でリセットされていたため、プロキシ経由で切断が続くと短時間に何度も新しいセッション
     （設定の「デバイス」に出る項目）を作っていた可能性がある。
3. **プロキシによる通信の書き換え**
   - AquaProxy の MITM モードでは、Discord への HTTPS が AquaProxy で一度復号され、AquaProxy 自身の TLS で送り直される。
     AquaProxy はヘッダーを書き換える設定（`/Library/AquaProxy/headers.txt`）も持つ。
     その場合 Discord から見える通信は、名乗りと合わない別物になる。

4. **公式アプリが使わない通信（自動化ツールに見える）**（2026-10-21 追加調査）
   - サーバーを開くたびに、Bot 専用の `GET /guilds/{id}/threads/active` を呼び、毎回拒否されていた
     （ログの「Unable to load active threads」）。ユーザーのアカウントから Bot 専用 API を繰り返し呼ぶのは、セルフ Bot の典型的な特徴。
   - 自分のロール取得に、OAuth2 アプリ用の `GET /users/@me/guilds/{id}/member` を使っていた。
   - メンション候補の検索で、空の検索語のときにメンバーを 100 件・オンライン状態付きで要求する経路があった（メンバー一覧の吸い出しに似る）。
   - サーバー購読に、Web 版がもう使っていない op 14 を送っていた（Web 版は op 37 GUILD_SUBSCRIPTIONS_BULK）。

## 入れた対策（2026-10-21）

- **名乗りの統一**: ログイン、REST（GET を含む全 API リクエスト）、Gateway の IDENTIFY、WebSocket の接続ヘッダーが、
  すべて同じ「Mac の Chrome で動く Discord Web クライアント」を名乗る（`DLUtil clientProperties`）。
  - ビルド番号は公開ログインページ（`GLOBAL_ENV.BUILD_NUMBER`）から 1 日 1 回取得。取得できない場合は同梱の値（643186）。
  - Chrome のバージョン（現在 156）と同梱のビルド番号は、リリースごとに更新すること。
  - タイムゾーンと言語は Mac の実際の設定を送る。Firefox 固有のヘッダーは廃止し、Chrome と同じヘッダーにした。
  - API は Web 版と同じ v9 を使う。指紋取得は Web 版と同じ `GET /experiments` に変更。
- **新しいセッションの上限**: IDENTIFY は 10 分間に 3 回、1 時間に 8 回まで。超えたら待ってから再試行する。
  レジュームの確認は 20 秒待つ。バックオフは READY / RESUMED を受けたときにだけリセットする。
- **公式アプリと同じ通信だけにする**: スレッドは Gateway の購読（op 37、THREAD_LIST_SYNC）で受け取り、
  自分のロールは Gateway の op 8（user_ids 指定）で取得する。メンション検索は入力した文字があるときだけ 10 件で、
  オンライン状態は要求しない。メンバー一覧は Web 版と同じく最初の 100 件と表示中の範囲を購読する。
- **プロキシの書き換えを拒否**: Discord のホストへの接続は、同梱の Mozilla 証明書だけで検証する。
  MITM するプロキシは接続に失敗し（ログに案内を出す）、中継だけするプロキシ（CONNECT パススルー）は使える。
  AquaProxy を使う場合は、`/Library/AquaProxy/no-mitm.txt` に次を追記する（管理者権限が必要）。

  ```
  discord.com
  discord.gg
  discordapp.com
  discordapp.net
  discord.media
  ```

## まだ残るリスク

- TLS の指紋（OpenSSL を使う curl）は本物の Chrome と一致しない。Cloudflare 側から区別できる可能性がある。
- IDENTIFY の `capabilities` を送っていない（Web 版は送る）。送ると受信データの形式が変わるため、対応は未実装。
- Discord は非公式クライアントの利用を規約で認めていない。どんな対策をしても、検出されないことは保証できない。

## 確認方法（実機なし）

開発用ビルドで次を実行すると、送る名乗りとヘッダーを書き出す（Discord には接続しない）。
X-Super-Properties と IDENTIFY の properties が一致していることを確認できる。

```
"artifacts/local-dev/DerivedData/Build/Products/DevLocal/Legacy Discord Dev.app/Contents/MacOS/Legacy Discord Dev" --dump-client-identity
```

## 開発・テストのルール

- **開発とテストは必ずテスト用のアカウントで行う。** メインのアカウントでは試さない。
- 複数の Mac で同じアカウントを同時に起動しない（テストは 1 台ずつ）。
- 起動と終了を短時間に繰り返さない。再接続まわりを変えたら、ログの `[WS] Sending identify` の回数を確認する。
- 無効化のメールが来たら、パスワードを再設定して二要素認証を有効にし、原因を調べ終わるまで Legacy Discord でログインしない。
