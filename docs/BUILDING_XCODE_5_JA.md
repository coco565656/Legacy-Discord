# Xcode 5.0.2 / OS X Mountain Lion でのビルド

## 準備

1. プロジェクト一式をMountain LionのMacへコピーする。
2. パスの途中に日本語や極端に長い名前を含めない場所へ置く。
3. `Discord Lite.xcodeproj`をダブルクリックしてXcode 5.0.2で開く。
4. Xcodeがプロジェクト設定の更新を提案しても、最初のビルドでは
   `Perform Changes`を押さずに閉じる。

## Xcode上の設定確認

1. 左側Project Navigator最上部の青い`Discord Lite`を選択する。
2. 中央の`TARGETS`から`Discord Lite`を選択する。
3. `Build Settings`を開き、表示を`All`にする。
4. 次を確認する。
   - Architectures: `x86_64`
   - Base SDK: `Latest OS X (OS X 10.9)`
   - OS X Deployment Target: `OS X 10.7`
   - Build Active Architecture Only: `No`
   - Code Signing Identity: 空欄または`Don't Code Sign`
5. 画面左上のSchemeが`Discord Lite > My Mac 64-bit`になっていることを確認する。

## 初回ビルド

1. `Product > Clean`を実行する。
2. `Product > Build`、またはCommand+Bを押す。
3. 成功したら`Product > Run`、またはCommand+Rで起動する。
4. ビルド済みアプリをFinderで確認する場合は、Productsグループの
   `Discord Lite.app`を右クリックして`Show in Finder`を選ぶ。

## ターミナルからのビルド

プロジェクトのあるフォルダへ移動し、次を実行する。

```sh
xcodebuild -project "Discord Lite.xcodeproj" \
  -scheme "Discord Lite" \
  -configuration Debug \
  -sdk macosx \
  ARCHS=x86_64 \
  MACOSX_DEPLOYMENT_TARGET=10.7 \
  CODE_SIGN_IDENTITY="" \
  build
```

生成先を分かりやすく固定する場合は末尾へ次を追加する。

```sh
SYMROOT="$PWD/build"
```

この場合、アプリは通常`build/Debug/Discord Lite.app`へ生成される。

## SSH経由の自動ビルド

ローカル側でSSHホスト名`mountainlion`が設定されている場合は、プロジェクト
ルートから次を実行する。

```sh
scripts/remote-build-mountainlion.sh
```

ソースはMountain Lion側の
`~/Developer/legacy-discordClient-remote`へ同期され、Xcode 5でビルドされる。
成功すると、アプリとログがローカルの次の場所へ回収される。

```text
artifacts/mountainlion/Debug/Discord Lite.app
artifacts/mountainlion/Debug/xcodebuild.log
```

ビルド後にMountain Lion側でアプリを起動する場合：

```sh
scripts/remote-build-mountainlion.sh --run
```

`--run`はログイン中のFinderと同じAqua bootstrap sessionでの起動を試みるが、
OS X 10.8ではSSH由来のアプリに対してKeychainが`OSStatus -25308`を返す場合が
ある。初回ログインとセッション維持の試験では、ビルド後にMountain Lion側の
Finderから`~/Developer/legacy-discordClient-remote/build/Debug/Discord Lite.app`
を直接開く。

ソース同期を省略して再ビルドする場合：

```sh
scripts/remote-build-mountainlion.sh --no-sync
```

Releaseビルドの場合：

```sh
scripts/remote-build-mountainlion.sh --release
```

公開鍵認証を設定していない場合、同期・ビルド・成果物回収の各接続でSSH
パスワードを求められることがある。Mountain Lionの古いSSHサーバーで
`Master refused session request: Permission denied`が出るのを避けるため、
接続共有は使用していない。継続的な自動テストには公開鍵認証を推奨する。

## 最初に確認する項目

1. ログイン画面が描画される。
2. Console.appにトークンが表示されない。
3. Keychain Accessに`org.legacydiscord.client`が作成される。
4. ログイン後、サーバーとDM一覧が表示される。
5. 終了して再起動してもセッションが復元される。

ビルドが失敗した場合は、Issue Navigatorの一番上にある赤いエラーを
展開し、その完全な本文を記録する。後続エラーは最初のエラーが原因で
連鎖していることが多い。
