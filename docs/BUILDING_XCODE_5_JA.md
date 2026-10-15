# Xcode 4.6.3 / Xcode 5.0.2 でのレガシービルド

本番バイナリの対象は64-bit Intelで、deployment targetはMac OS X 10.6です。
正式確認範囲は10.6.8 Snow Leopardから10.8.5 Mountain Lionまでとし、
10.9.5 Mavericksは可能な範囲で確認します。現行macOSのDevLocalビルドは、
この互換性を証明しません。

## 推奨ツールチェーン

最初に試す本番構成は、Mountain Lion上のXcode 4.6.3とOS X 10.8 SDKです。
Xcode 5.0.2は既存のMountain Lion検証を再確認するための補助構成として
残します。どちらもプロジェクト形式の自動変換は行いません。

Snow Leopard上のXcode 4.2も別の検証候補ですが、このプロジェクト全体と
現在の同梱ライブラリをビルドできることはまだ確認していません。

現行Xcodeは10.6指定でソースをコンパイルできても、古いObjective-C runtime
を補う`libarclite`を同梱していないため最終リンクに使用しません。この設定を
無効化したバイナリはSnow Leopard用の正式成果物として扱わないでください。

## Xcode上の設定確認

1. `Discord Lite.xcodeproj`を開く。
2. Xcodeが設定更新を提案しても`Perform Changes`を押さずに閉じる。
3. Project Navigator最上部の`Discord Lite`を選択する。
4. `TARGETS`から`Discord Lite`を選び、`Build Settings`を`All`表示にする。
5. 次を確認する。
   - Architectures: `x86_64`
   - Base SDK: `OS X 10.8`（Xcode 4.6.3の推奨構成）
   - OS X Deployment Target: `Mac OS X 10.6`
   - Build Active Architecture Only: `No`
   - Code Signing Identity: 空欄または`Don't Code Sign`
6. Schemeが`Discord Lite > My Mac 64-bit`になっていることを確認する。

## ビルド

Xcodeでは`Product > Build`を実行する。ターミナルではプロジェクトのある
フォルダから次を実行する。

```sh
xcodebuild -project "Discord Lite.xcodeproj" \
  -scheme "Discord Lite" \
  -configuration Debug \
  -sdk macosx10.8 \
  ARCHS=x86_64 \
  MACOSX_DEPLOYMENT_TARGET=10.6 \
  CODE_SIGN_IDENTITY="" \
  SYMROOT="$PWD/build" \
  build
```

成功後、実際に生成されたアプリの実行ファイルを確認する。

```sh
file "build/Debug/Legacy Discord.app/Contents/MacOS/Legacy Discord"
otool -l "build/Debug/Legacy Discord.app/Contents/MacOS/Legacy Discord"
```

`file`に`x86_64`が含まれ、`LC_VERSION_MIN_MACOSX`の`version`が`10.6`
であることを確認する。Xcodeやプロジェクトの状態により製品名が
`Discord Lite.app`になった場合は、その実際のパスへ読み替える。

## OS別の確認順

同じ成果物をコピーして、次の順番でFinderから直接起動する。

1. Mac OS X 10.6.8 Snow Leopard
2. Mac OS X 10.7.5 Lion
3. OS X 10.8.5 Mountain Lion
4. OS X 10.9.5 Mavericks（可能な範囲）

各OSでログイン画面、Keychain保存・復元・削除、チャンネル表示、メッセージ
送受信、画像、プロフィール、絵文字・スタンプ画面、終了時クラッシュを確認
する。同梱curl/OpenSSLのロードとTLS接続は、Snow Leopardで必ず実測する。

## 現行Macとの分離

現行macOSでは次だけを開発用プレビューとして使用する。

```sh
./scripts/local-build-all.sh
./scripts/test-local-regression.sh --quick --screenshots
```

これらは`DevLocal`またはコマンドライン限定の12.0 overrideを使い、本番の
x86_64 / 10.6設定を上書きしない。レガシーOS試験へ進めない場合も、現行Mac
の開発作業を止める理由にはしない。

## 最初に確認する項目

1. アプリが起動し、ログイン画面が描画される。
2. Console.appにトークンや認証情報が表示されない。
3. Keychain Accessに`org.legacydiscord.client`が作成される。
4. 終了して再起動してもセッションが復元される。
5. ログアウト後にKeychain項目が削除される。
6. プロフィール、絵文字、スタンプの各パネルが開閉できる。
7. アプリ終了時にクラッシュしない。

失敗時は、最初のビルドエラー、クラッシュログ、OSバージョン、実行ファイル
のload commandを保存する。トークン、メールアドレス、パスワード、本文、
ユーザー名、サーバー名、チャンネル名は共有ログから除外する。
