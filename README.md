# 🎓 卒業制作：インフラ自動構築・監視通知＆要塞化マルチコンテナNOCシステム 技術仕様書 (`infrastructure-repo-actual`)

本リポジトリは、卒業制作におけるネットワーク管制システム（NOC: Network Operation Center）および統合監視通知基盤が、本番VPS環境において24時間365日、安全かつ高い可用性を維持して稼働するためのサーバー環境（インフラ基盤）を、Ansible（Infrastructure as Code）を用いてボタン一つで完全自動構築するためのインフラ・マスターコードである。

「パブリッククラウド環境での堅牢な境界防御設計」と「IaCによる環境パリティ（開発環境・本番環境の完全一致）」を両立させ、実務レベルの運用に耐えうる要塞化インフラシステムを定義している。

---

# 1. システムアーキテクチャ概要 (Architecture Overview)

本システムは、単一障害点（SPOF）を排除し、セキュリティドメインを明確に分離するため、インフラの機能ごとにサーバーを独立させた**「疎結合型マルチノード構成（3台構成）」**を採用している。

手動によるブラックボックスな設定作業を排し、すべてのミドルウェア配置、ネットワーク制御、セキュリティポリシー適用をプログラム化（コード化）することで、ローカル仮想環境（Vagrant/VirtualBox）から本番クラウド環境（さくらVPS等）への移行をシームレスに行える設計としている。

## 👥 ノード役割定義・IPトポロジー

各サーバーはプライベートIPアドレスによって静的にマッピングされ、厳格なポート制御とアクセス元制限が敷かれている。

| ノード名 | インフラ上の役割 | 開発環境IP | 主な稼働コンテナ・ミドルウェア / 開放ポート |
| :--- | :--- | :--- | :--- |
| **Server A** | **Control Node（中央司令塔）**<br>・構成管理・IaC実行環境<br>・バックアップデータの遠隔集約・一元管理 | `10.149.245.110` | ・Ansible Core (構築自動化エンジン)<br>・Git / SSH認証クライアント<br>・Node Exporter (OSリソース測定 / 9100/tcp) |
| **Server B** | **App/DB Node（汎用実行環境）**<br>・各種コアアプリケーションの稼働コンテナ基盤 | `10.149.245.115` | ・Docker Engine (コンテナ実行環境)<br>・Node Exporter (OSリソース測定 / 9100/tcp) |
| **Server C** | **Monitor & NOC Node（監視管制・中央運用塔）**<br>・全台のテレメトリデータ一括収集・可視化<br>・管理者専用NOCダッシュボードのセキュアホスト | `10.149.245.116` | ・Docker Engine (コンテナ実行環境)<br>・**8080/tcp** (NOCシステム Web公開ポート)<br>・**3000/tcp** (Grafana可視化画面)<br>・**9090/tcp** (Prometheus時系列DB)<br>・`noc_bot` (Discordアラート通知コンテナ)<br>・Node Exporter (OSリソース測定 / 9100/tcp) |

---

# 2. コンテナ配置 & ネットワーク要塞化トポロジー (Security & Container Topology)

本システムのコアである **Server C（監視管制・中央運用塔）** の内部は、OSネイティブなセキュリティ（Firewalld / SELinux）と、Dockerのバーチャルネットワーク分離技術を高度に組み合わせた**多層防御（Defense in Depth）アーキテクチャ**が構築されている。

## 🛡️ Dockerネットワークの論理分離と境界防御設計

内製Webアプリケーション群は、ソースコードおよびフロントエンド資材を `src/` ディレクトリ配下にクリーンに一元化。コンテナ配置のポータビリティとディレクトリの対称性を極限まで高めている。

## 1. **フロントエンド：`noc_web` (nginx:1.25-alpine)**
   * 外部からの管理者アクセスを唯一待ち受けるリバースプロキシ。ホスト側から独自のプロキシ転送設定（`/opt/noc-system/nginx.conf`）を読み込み専用（`:ro`）でコンテナ内の公式自動読み込みパス（`/etc/nginx/conf.d/default.conf`）へマウント。さらに、構造化されたフロントエンド資材（`/opt/noc-system/src/templates`）を直接安全にマウントすることで、不正な改ざんやインジェクション攻撃を遮断している。

## 2. **バックエンド：`noc_analyzer` (内製 Python / Flask)**
   * 厳格なセッション認証（ゲートキーパー設計）が実装されたコア・アプリケーション。マルチステージビルド化された超軽量コンテナ（`python:3.10-slim`）で稼働。ホストOSの `/opt/noc-system/src` をコンテナ内の `/app/src` にクリーンにマウントし、実行起点ポートを完全に制御。同じホスト上のPrometheus APIと連携し、監査メトリクスの解析、HTML動的レンダリング、およびCSVデータのオンデマンドエクスポートを司る。

## 3. **データベース：`noc_db` (postgres:15-alpine)**
   * 時系列監査データを格納する堅牢化データベース。Compose定義において **`ports`（ホストへのポート紐付け）を一切記述しない** ことにより、外部から5432ポートを直接スキャン・攻撃するルートを物理的に封印。コンテナ間隔離LAN（`noc-backend-net`）経由で、Flaskアプリからのみ接続を許可する。

---

# 3. インフラ基盤構成 ミドルウェア仕様・技術選定理由 (Technical Selection)

実務の現場におけるシステム選定基準に準拠し、各サーバーに自動導入されるミドルウェア・エージェントのバージョンおよび選定理由は以下の通りである。

## 3.1 全台共通基盤

* **OS: AlmaLinux release 9.x (linux/amd64)**
  * **選定理由**: エンタープライズLinuxの事実上の世界標準である「RHEL（Red Hat Enterprise Linux）9」の完全互換ディストリビューション。実務における長期サポート（LTS）、安定性、および高度なセキュリティ（SELinux等）を享受するために選定。
* **リソース測定器: Node Exporter 1.8.1**
  * **選定理由**: ハードウェアおよびOSのカーネルメトリクス（CPU、メモリ、ディスク、ネットワーク）を非特権で正確にエクスポートする常駐デーモン。Server CのPrometheusから15秒に1回の間隔でスクレイピング（Pull収集）される。
* **パケット制御: Firewalld (OS標準) & SSH要塞化**
  * **選定理由**: ブルートフォース攻撃（無差別ログイン攻撃）の標的になりやすいウェルノウンポート（22番）を排除し、接続待受ポートを **2222番** に隠蔽。FirewalldによるIPホワイトリスト制御と組み合わせて要塞化を完了している。

## 3.2 Server A：司令塔 (Control Node)

* **構成管理エンジン: Ansible Core 2.14.18 (Python 3.9系)**
  * **選定理由**: AlmaLinux 9に標準追従する極めて安定した構成管理ツール。対象となる作業対象サーバー側に常駐エージェント（ソフト）をインストールする必要がない「エージェントレス（SSH通信ベース）」アーキテクチャであるため、インフラの攻撃対象領域（Attack Surface）を最小限に抑えられる利点がある。
* **Dockerランタイムの排除**: 司令塔の役割に特化させ、余計なコンテナランタイムをインストールしないことで、「最小特権の原則」を徹底している。

## 3.3 Server B：コアアプリケーション実行環境 (App/DB Node)

* **コンテナエンジン: Docker Engine / CLI 29.4.3**
* **コンテナランタイム: containerd.io 1.7.27**
  * **選定理由**: 開発班がPCローカル環境で検証に使用しているバージョンとサーバー環境を完全に同一化（パリティ担保）。「開発環境では動いたが、本番サーバーに載せたらライブラリやランタイムのマイナーバージョンの差で予期せぬエラーを起こす」という、デプロイメントの先祖返り事故を論理的に根絶する。

## 3.4 Server C：監視管制・中央運用塔 (Monitor & NOC Node)

* **設計思想: 「オール・イン・コンテナ（All-in-Container）」構成への最適化**
  * **選定理由**: 監視システム（Prometheus/Grafana）、通知エージェント、NOCシステムのWeb・AP・DB構成にいたるまで、すべてのコンポーネントをホストOSに直接インストールせず、Dockerコンテナとして独立パッケージ化（カプセル化）。これにより、OSを汚さないステートレスな運用を実現し、将来のスケールアウトやクラウド移設を容易にしている。
* **時系列監視データベース: Prometheusコンテナ (prom/prometheus:v2.51.0)**
  * **選定理由**: 各ノードのNode Exporterから、超軽量なテキストプロトコルで自律的にデータを回収・保存する世界標準のプル型時系列DB。
* **統合可視化モニター: Grafanaコンテナ (grafana/grafana-oss:latest)**
  * **選定理由**: Prometheusが蓄積した膨大な時系列データを、直感的かつグラフィカルなダッシュボードへと動的に変換・出力する分析プラットフォーム。
* **警備スクリプト: NOC統合通知ボットコンテナ (noc-integrated-bot:latest)**
  * **選定理由**: インフラ班内製のPythonコンテナ。3台のサーバーの負荷状況を常時パトロールし、リソースの突発的な枯渇（CPU/メモリ閾値超過）を検知した瞬間、Discordの特定チャンネルへリッチなアラートカードを即座に自動POSTする。
  * **可読性向上リファクタリング**: 取得したインスタンスのターゲット文字列を条件分岐させ、生IPアドレスの前に「サーバーA」「サーバーB」「サーバーC」という運用ホスト識別名を動的に付与・改信。インフラ管制レポートとしての視認性を跳ね上げている。

---

# 4. プロの運用を支えるインフラ堅牢化設計 (Hardening Features)

## ① データの永続化とSELinuxセキュリティラベル（`:Z` フラグの適用）
コンテナは本来使い捨て（ステートレス）の性質を持つため、コンテナの再起動や破損によって過去のメトリクスや監査DBログが消滅するリスクがある。本システムでは、データの保存先をホストOS側のファイルシステム（`/opt/noc-system/db_data` 等）へ安全にマウント（Volume Mounting）している。
その際、AlmaLinux 9のカーネル標準セキュリティ機能である **SELinux（Security-Enhanced Linux）** によるコンテナからの書き込み拒否（アクセス権限エラー）を根本解決するため、Ansibleタスク内でディレクトリにコンテキストを自動適用。マウントオプションに **`:Z`** フラグを明示し、コンテナ内部のプロセスに固有のセキュリティラベルを自動付与する堅牢なファイル共有設計を施している。

## ② 暴走ストッパー設定（Resource Quotasによる共倒れ防止）
万が一、アプリケーションや内製通知ボットのコードに未知のバグ（無限ループやメモリリーク等）が発生した場合でも、Server C全体のOSや他の最重要監視コンテナを巻き添えにしてサーバーがハングアップ（共倒れ）するのを防群に防ぐため、Docker Composeにてリソースの上限を厳格に制限。
各コンテナに対し `memory: 512M` / `cpus: 0.5` などの**計算資源クォータ（制限枠）**を課し、一過性のプログラム暴走がインフラ全体の死に直結しない防御策を敷いている。

## ③ 環境依存変数のインベントリ分離 ＆ 秘匿情報の Vault 暗号化
実務におけるポータビリティ設計に基づき、タスクコードから特定のIPアドレスや生の接続URLなどのハードコード（ベタ書き）を完全に追放。環境依存のIPアドレスやプロファイルスイッチ（`is_production`）は `inventories/*/hosts.ini` に変数として分離。流出してはならない Discord Webhook URL は **Ansible Vault（AES-256暗号化金庫）** で高度に保護。デプロイメント時に `--vault-password-file` を介して動的に復号してインフラに焼き付ける最高峰のセキュリティプロトコルを実装している。

---

# 5. 詳細ディレクトリ構成（全ファイル完全マスターマップ）

リポジトリ内のアセット配置を機能ごとに一元管理し、アプリケーションコード一式を `src/` 配下に完全構造化。Ansibleの `copy` モジュールによって構造を維持したまま `/opt/noc-system/` 直下へ一発でクレンジング同期させる設計を採用。これにより、ファイル配置ミスによるパスのすれ違いやコンテナの起動エラーを物理的に排除している。

```plaintext
infrastructure-repo/
├── .gitattributes             # WindowsとLinux間の改行コード不整合(CRLF/LF)をGitコミット時に自動解決する盾
├── .gitignore                 # パスワードや一時ファイル(`.vagrant/`)をGitHubに誤爆アップロードしないための除外リスト
├── .vault_password            # 暗号化された secrets.yml を解読するためのAnsible Vaultローカルパスワードファイル
├── ansible.cfg                # Ansibleの動作環境設定（金庫のパスワード読み込み先やエラー回避設定を定義）
├── bootstrap.yml              # OSネイティブな初期設定や初期依存パッケージを流し込むための事前タスク指示書
├── cd                         # 継続的デリバリー（CD）または環境移行時に使用する検証用の一時ファイル/コマンドスクリプト
├── db_backup.yml              # オンデマンドでデータベースを遠隔バックアップ・Server Aへ回収するための専用指示書
├── kickoff.sh                 # サーバーAの中で自動鍵配布から疎通テストまでを一撃でこなす初期化スクリプト
├── README.md                  # 本技術仕様書（インフラデザインドキュメント）
├── requirements.yml           # Ansibleで高度なシステム操作(Swap領域やSELinux制御)を行うための外部部品プラグインリスト
├── site.yml                   # インフラ全体の自動構築・構成管理を統括するメインのプレイブック指示書
├── vagrant                    # Vagrant環境用のコマンドエイリアスまたは環境識別用プロファイル
├── Vagrantfile                # パソコン内にAlmaLinux 9の仮想サーバーを3台同時ブートするスペック定義書
├── .vagrant/                  # Vagrantが起動した3台の仮想マシンの内部識別IDやSSH秘密鍵を保持する自動生成フォルダ
├── group_vars/                # サーバーの設定値（ポート番号や機密URLなど）が集まる最重要変数フォルダ
│   ├── all.yml                # 全サーバー共通の基本仕様（要塞化SSHポート: 2222, スワップ: 2048MB, 時刻同期）
│   ├── vagrant.yml            # ローカルテスト環境であることを示す目印ファイル (`is_production: false`)
│   ├── prod.yml               # さくらVPS本番環境であることを示す目印ファイル (`is_production: true`)
│   └── secrets.yml            # 暗号化されたDiscordのWebhook URLなどの秘匿情報を厳重保管する金庫ファイル
├── inventories/               # 各対象サーバーの「住所（IPアドレス）」や接続方法を管理するフォルダ
│   ├── prod/
│   │   └── hosts.ini          # さくらVPS本番環境用の住所録。rootユーザーで22番ポートから突入するための定義
│   └── vagrant/
│       └── hosts.ini          # テスト環境用の住所録。IP(10.149...)や標準パスワード(vagrant)が記載
└── roles/                     # 手順書を機能ごとにコンポーネント化（役割分担）して格納するAnsibleの作法フォルダ
    ├── app/                   # 将来的に開発班が作ったアプリケーションコンテナを自動起動するための連携窓口
    │   └── tasks/
    │       └── main.yml       # 将来拡張用の空のタスクベースファイル
    ├── backup/                # Server Bのデータを固めてServer Aへ回収するバックアップ運用手順
    │   ├── tasks/
    │   │   └── main.yml       # バックアップ用スクリプトの配置、毎日深夜03:00の定期実行(Cron)登録、Server Aへの遠隔回収
    │   └── templates/
    │       └── backup_volumes.sh.j2 # Dockerのボリュームデータを根こそぎ安全な圧縮ファイルにするためのシェルスクリプト
    ├── common/                # 全台共通で動作させるべき最下層のインフラ土台を作る手順
    │   ├── handlers/
    │   │   └── main.yml       # 時刻同期（Chrony）やSSHDの設定が書き換わった時に、安全に再起動をかけるトリガー
    │   ├── tasks/
    │   │   └── main.yml       # スワップ領域の確保、Chronyインストール、Node Exporter（負荷測定器）の自動配置
    │   └── templates/
    │       └── chrony.conf.j2 # 日本標準時(NICT)のサーバーへ正確に時計を合わせるための動的設定テンプレート
    ├── docker/                # アプリケーションをカプセル化して動かすための環境を作る手順
    │   ├── handlers/
    │   │   └── main.yml       # Dockerのシステム設定（daemon.json）が変わった時だけコンテナエンジンを再起動する仕組み
    │   ├── tasks/
    │   │   └── main.yml       # Docker Engine本体、Composeプラグインの導入と、アプリ用ネットワーク(app_network)の自動作成
    │   └── templates/
    │       └── daemon.json.j2 # Dockerコンテナが出力するログの容量が溢れないよう、10MB×3世代に制限する設定書
    ├── security/              # 不正なアクセスを鉄壁の防御でシャットアウトするセキュリティ手順
    │   └── tasks/
    │       └── main.yml       # Firewalldの導入、接続フリーズを回避する非同期起動、および接続遮断防止
    └── monitor/               # 💡【本リポジトリの核心】監視システムおよび要塞化NOCダッシュボードの自動起動手順
        ├── files/             # 🛠️ プログラムソース・固定資産を一元管理する領域
        │   ├── noc_bot/       # Discord通知ボットのビルド一式（Dockerfile, Pythonソースコード）
        │   │   ├── Dockerfile
        │   │   ├── requirements.txt
        │   │   └── src/
        │   │       └── main.py # 🔹[リファクタリング版] IPをサーバー名(A/B/C)に動的パース・改行成形する通知コア
        │   └── noc_system/    # 🛡️ NOCダッシュボードアプリケーションの資材一式
        │       ├── Dockerfile # [マルチステージビルド] 実行環境から無駄なgcc等を排除した超軽量Dockerfile
        │       ├── dummy_log.csv
        │       └── src/       # 🆕【構造化エリア】ソースコードとテンプレートの完全カプセル化
        │           ├── app.py # ゲートキーパーセッション認証・Prometheus APIデータ解析を行うメインプログラム
        │           └── templates/ # 🎨 完全に日本語ローカライズを完了させたサイバーUI画面群
        │               ├── login.html   # 近未来サイバーUIを搭載した、日本語ログイン画面
        │               ├── search.html  # オペレーションセンター風の日本語レポート管理・日付検索画面
        │               └── result.html  # 監査ログ・メトリクスを美しく表形式で出力するデータストリーム画面
        ├── handlers/
        │   └── main.yml       # Prometheusの設定が更新された時に、監視デーモンを自動リロードするトリガー
        ├── tasks/
        │   └── main.yml       # [構造維持配布タスク] フォルダ直下展開へパス調整。完全自動ビルドを支える指示書
        └── templates/
            ├── backup_script.sh.j2     # バックアップ処理自体の異常を検知し、失敗時に直接DiscordへSOSを投げる緊急スクリプト
            ├── discord_bot.py.j2       # 【Native版の名残】Prometheusデータを監視するPythonプログラム
            ├── discord_bot.service.j2  # 【Native版の名残】OS起動時にバックグラウンドで自動常駐させるための定義書
            ├── noc_docker-compose.yml.j2 # [新src対応] コンテナ間ネットワーク完全分離・コンテナ内/app配置同期マウント定義書
            ├── noc_nginx.conf.j2       # Nginxリバースプロキシの管理者専用プロキシ転送ルール設定書
            ├── prometheus.service.j2   # PrometheusをOS上でネイティブ常駐させるための旧管理設定ファイル
            └── prometheus.yml.j2       # 3台のサーバーの「10.149...:9100」を15秒に1回見に行く監視設定テンプレート
```

# 6. インフラ自動構築プロトコル ＆ システム運用マニュアル
6.1 開発環境（Vagrant/VirtualBox）「黄金の3ステップ」完全再構築手順
本ドキュメントは、開発環境を完全に初期化した状態（更地）から、各種ミドルウェアの展開、セキュリティ要塞化、要塞化NOCダッシュボードおよび監視管制塔（Grafana）の開通までを、ヒューマンエラーを完全排除して最短で完結させるための運用プロトコルである。

🏃 実行手順（黄金の3ステップ）

## 1️⃣ Step 1: ホストOS（Windows）での完全クリーン起動
WindowsのPowerShellを開き、プロジェクトのルートディレクトリ（Vagrantfile がある場所）で以下を実行し、ゾンビプロセスやセッションロックを排除したまっさらな状態で仮想マシンを起動する。


1. 既存の仮想マシン（ゾンビプロセスやセッションロック含む）を強制全破棄
```Bash
vagrant destroy -f
```
2. 初期状態の仮想マシンを3台まとめて起動（全員ポート22番でファースト着地）
```Bash
vagrant up --no-provision
```
3. 司令塔（Server A）へ初期SSHログイン
```Bash
vagrant ssh server-a
```
### 2️⃣ Step 2: ゲストOS（Server A）での初期セットアップと自動鍵配布
サーバーAにログイン後（プロンプトが [vagrant@server-a ~]$ になっている状態）、以下のコマンド群をまとめてコピー＆ペーストして実行し、全台へSSH鍵の配布と通信疎通テスト（Ping）をフルオートで行う。

共有フォルダへ移動
```Bash
cd /vagrant
```

キックオフスクリプト（kickoff.sh）の自動生成
```Bash
cat << 'EOF' > kickoff.sh
#!/bin/bash
set -e

INIT_PASS="vagrant"
INVENTORY="inventories/vagrant/hosts.ini"
VAULT_SOURCE=".vault_password"
VAULT_DEST="$HOME/.vault_password"
PUB_KEY="$HOME/.ssh/id_rsa.pub"

echo "=== [1/5] OSパッケージ・sshpass の導入 ==="
sudo dnf install -y epel-release
sudo dnf install -y ansible-core git sshpass

echo "=== [2/5] 依存コレクションの一括導入 ==="
ansible-galaxy collection install ansible.posix community.docker community.general

echo "=== [3/5] 司令塔用 SSHキーペアの生成 ==="
if [ ! -f "$HOME/.ssh/id_rsa" ]; then
    ssh-keygen -t rsa -b 4096 -N "" -f "$HOME/.ssh/id_rsa"
    echo "✔ SSH鍵を新規作成しました。"
else
    echo "✔ SSH鍵は既に存在します。"
fi

echo "=== [4/5] Ansible Vault パスワードファイルのセキュア隔離 ==="
if [ -f "$VAULT_SOURCE" ]; then
    cp "$VAULT_SOURCE" "$VAULT_DEST"
    chmod 600 "$VAULT_DEST"
    echo "✔ Vaultパスワードの権限正常化(600)を完了しました。"
else
    echo "❌ エラー: $VAULT_SOURCE が存在しません。"
    exit 1
fi

echo "=== [5/5] sshpass による公開鍵の全台フルオート配布 ==="
export ANSIBLE_HOST_KEY_CHECKING=False
SSHPASS=$INIT_PASS ansible all -i "$INVENTORY" \
  -m ansible.posix.authorized_key \
  -a "user=vagrant state=present key='{{ lookup('file', '$PUB_KEY') }}'" \
  -c ssh --extra-vars "ansible_password=$INIT_PASS ansible_port=22" \
  -k

echo "================================================================="
echo " 🎉 鍵配布完了！初期ポート(22番)での通信テストを開始します。"
echo "================================================================="
ansible all -i "$INVENTORY" -m ping --extra-vars "ansible_port=22"
EOF
```
実行権限を付与して実行
```Bash
chmod +x kickoff.sh
./kickoff.sh
```
⚠️ 確認: スクリプトの最後に、全てのノードから緑色の "ping": "pong" が返ってきれば大成功です。

### 3️⃣ Step 3: メインPlaybookによる一括全自動インフラ＆コンテナデプロイ
鍵の配布が完了したら、そのままサーバーAの画面でメインPlaybookをキックする。Windows側で修正・整理した最新のNOCシステムアセット（日本語版HTML/プログラム一式）が、Server Cの指定された永続化ディレクトリへと構造を維持したまま一括同期され、マルチコンテナが自動ビルドされバックグラウンドで一斉起動する。

共有フォルダの権限制限をバイパスする環境変数を指定
```Bash
export ANSIBLE_CONFIG=./ansible.cfg
隔離した金庫のパスワードを指定し、インフラ全体のフルオート構築・要塞化を開始
```

```Bash
ansible-playbook -i inventories/vagrant/hosts.ini site.yml --vault-password-file ~/.vault_password
⚠️ 確認: 対策済みのPlaybookなので、未定義エラーやDockerのタイムアウトを起こすことなく、一気に最後までノンストップで駆け抜けてオールグリーン（failed=0）を叩き出します。これですべての工程が完全自動で復元されました！
```
🛠️ 付録：もしコマンドの途中でフリーズ・停止した場合の強制脱出（デバッグ）
VagrantやVirtualBoxの処理を途中で強制終了（Ctrl + C）した際、Windowsのメモリにプロセスの幽霊（ロック）が残って動かなくなった場合は、WindowsのPowerShellで以下をそのまま実行してゾンビプロセスを一掃してください。

1. Vagrant(Ruby)の幽霊プロセスを強制終了して排他ロックを解除
```PowerShell
taskkill /F /IM ruby.exe /T
```
2. VirtualBoxの黒幕プロセスを強制終了してセッションロックを解放
```PowerShell
taskkill /F /IM VBoxHeadless.exe /T
taskkill /F /IM VBoxManage.exe /T
taskkill /F /IM VBoxSVC.exe /T
taskkill /F /IM VirtualBox.exe /T
```
💡 アドバイス: 上記を実行した後、再度 vagrant destroy -f を叩けば、PCを再起動せずとも100%確実に安全な状態からリトライできます。

## 6.2 最終稼働テスト ＆ 各種Webインターフェースへのアクセス (Endpoints)
Playbookによる自動構築が正常に終了したら、WindowsのWebブラウザを立ち上げ、実機サーバー環境を忠実に踏襲した実IPアドレス（10.149.245.116）を介して各サービスへアクセスし、システムが正常稼働していることを確認する。

🛡️ 要塞化NOC管理者ログイン窓口 (Nginx経由): http://10.149.245.116:8080

アクセスすると、近未来仕様にローカライズされた日本語版ログイン画面が出現します。以下の初期管理者認証情報を入力してコントロールパネルに突入します。

管理者ユーザーID: admin / セキュリティパスワード: password123

📊 監視管制画面（Grafanaプラットフォーム）: http://10.149.245.116:3000

初期ID/PW: admin / admin

## 6.3 監視管制塔（Grafana）初期データソース登録・インポート手順
### 🛠️ Step 1: Prometheusコンテナの疎通・ターゲット確認
データ元（Prometheus）が、分離された各サーバーから正常に健康データをスクレイピングできているか確認します。

ブラウザで http://10.149.245.116:9090/targets にアクセスします。

ターゲット一覧内の server-a, server-b, server-c などのステータスがすべて 「UP」（緑色） になっていればデータ収集基盤は完璧です。

### 🛠️ Step 2: Grafanaに対する時系列データソース（Prometheus）のバインド
Grafanaに「データはServer CのPrometheusコンテナから取ってきてね」と紐付けを行います。

Grafana（http://10.149.245.116:3000）にログイン。

左メニューの [Connections] ➔ [Data sources] をクリック。

[Add data source] ボタンを押し、一覧から Prometheus を選択。

Connection (URL) の欄に、Server CのプライベートIPをベースとした以下のアドレスを入力します。
http://10.149.245.116:9090

最下部にある [Save & test] をクリック。画面に 「Successfully queried the Prometheus API.」 と緑色のポップアップが出ればデータソース接続は成功です。

### 🛠️ Step 3: 完成済み監視テンプレート（ダッシュボード）のインポート
世界中で広く実戦投入されている、洗練された「Node Exporter Full」ダッシュボードを導入し、可視化を即座に開始します。

左メニューの [Dashboards] を開き、[New] ➔ [Import] をクリック。

[Import via grafana.com] の入力フィールドに、世界共通のテンプレート識別IDである魔法の数字 1860 を入力して [Load] を押します。

次の構成画面の下部にある「Prometheus」の選択欄で、先ほどStep 2で作成したデータソースを選択。

[Import] をクリックします。

💡 なぜこれでグラフが見れるようになるのか？（監視アーキテクチャの三位一体）
Grafana自体はデータを保持する能力を持っていません。以下の3つの異なるコンポーネントが役割分担して連携することで、初めて動的なグラフが実現します。

Node Exporter: 各サーバー（A/B/C）のOS上で、CPU使用率などの「生のリソースメーター」を露出させる。

Prometheus: それらのメーターから15秒に1回データを引き抜き、時系列データベースへ「蓄積」する。

Grafana: Prometheusに「現在のメモリ残量の推移を頂戴」とリクエスト（PromQLクエリ）を投げ、それを「最高にかっこいいグラフ」に描画する。

🚀 セットアップ完了！ インポートしたダッシュボードにより、Server A, B, C の負荷状況がリアルタイムに、かつ美しく波打ち始めます。
## 6.4 サーバーA（Control Node）へのセキュア再ログイン手順
### 1. 概要
Ansibleによる全体インフラ構築が完了した後は、全サーバー共通のセキュリティ要塞化ポリシーに基づき、標準の22番ポートが遮断され、SSH待受ポートが 2222 番へと変更されています。
このポート要塞化制限を維持したまま、ホストOS（Windows）から司令塔Server A（10.149.245.110）へ安全に再アクセスするための管理者専用コマンドプロトコルです。

### 2. 接続詳細（設定値・パラメーター）
対象対象ノード: server-a (Control Node)

接続先IPアドレス: 10.149.245.110

SSH接続ポート: 2222

認証方式: 鍵認証（Vagrantがプロビジョニング時に自動生成・隔離した秘密鍵を使用）

接続ユーザー名: vagrant

## 3. 実裝ガイド（再接続コマンド）
ホストOS（Windows）のPowerShellを開き、プロジェクトのルートディレクトリ（infrastructure-repo）にいることを確認して、以下のコマンドを実行します。

変更後のセキュアポート2222と、Vagrantが内部で保持しているServer A専用の秘密鍵を直接明示してログイン
```PowerShell
ssh -p 2222 -i .vagrant/machines/server-a/virtualbox/private_key vagrant@10.149.245.110
💡 初回接続時の警告（Host Key Verification）が表示された場合
インフラ要塞化によってサーバー側の鍵識別情報が変わるため、再ログイン時に以下のセキュリティメッセージが必ず1度だけ表示されます。
```

```Plaintext
Are you sure you want to continue connecting (yes/no/[fingerprint])?
```
これは不具合ではなくSSHの正常な仕様（仕様通り）ですので、落ち着いて yes と直接タイピングしてエンターキーを押してください。ホスト検証が更新され、自動的にサーバーAのプロンプトへログインが完了します。

# 8. 最終テスト稼働確認先一覧 (Endpoints)
すべての自動プロビジョニングおよびマルチコンテナデプロイが完了した際、ホストOS（Windows）のWebブラウザから実IPで直接叩くことができる、インフラ開通確認用のエンドポイント一覧である。

## 🛡️ NOC管理者ログイン窓口 (Nginxリバースプロキシ経由): http://10.149.245.116:8080

## 📊 統合監視管制画面（Grafanaプラットフォーム）: http://10.149.245.116:3000

## 🗄️ 時系列メトリクスデータ蓄積サーバー（Prometheus DB）: http://10.149.245.116:9090

# 9. インフラデバッグ＆トラブルシューティングの軌跡 (Troubleshooting Logs)
本システムの構築にあたり、実機検証（インフラ統合テスト）において直面し、解決に至ったコアなエンジニアリングログである。

## ① Nginxコンテナの即死ループ（"server" directive is not allowed here）の解消
エラー現象: docker ps を実行すると、Nginxコンテナ（noc_web）のステータスが Restarting (1) 3 seconds ago となり、起動直後にエラーを吐いてコンテナが強制終了と再起動を繰り返す無限ループが発生。外部ブラウザからの通信が Connection refused で弾かれる現象に直面。

原因の特定: docker logs noc_web で生のコンテナエラーをあぶり出したところ、[emerg] 1#1: "server" directive is not allowed here in /etc/nginx/nginx.conf が発覚。本システムで用意していた login.html 等のルーティング定義ファイルは、server { ... } から記述が始まる「子設定（バーチャルホスト設定）スタイル」であった。それに対し、Docker Composeのボリュームマウントにて、Nginxの親玉設定であるメイン設定ファイル（/etc/nginx/nginx.conf）に直接上書き注入してしまったため、Nginx本体が構文エラー（Syntax Error）を起こしてパニック死していた。

解決策: Docker Composeファイル（noc_docker-compose.yml.j2）のボリュームマウント先を、公式Nginxイメージが子設定を自動スキャンして安全にインクルード（内包）するために用意している正規のスロット /etc/nginx/conf.d/default.conf へと修正。これによりメイン設定（イベントループ等）と独自の子設定（プロキシ転送ルール）が綺麗に融合し、コンテナの即死ループが100%完全解決した。

## ② Windows編集環境に起因するCRLF改行コード混入エラーの完全遮断
エラー現象: WindowsのVS Code等でHTMLアセットやPythonスクリプトを編集してデプロイした際、Linuxコンテナ（Server C）側でスクリプト内の見えない文字がノイズとなり、プログラムが正常に解釈されず、コンテナの内部エラー（Errno 2: No such file or directory）を誘発するインフラの深い沼に直面した。

原因の特定: WindowsとLinuxでは、テキストファイルの行末を意味する「改行マーク」のバイナリ仕様が異なる（Windows = CRLF, Linux = LF）。Windows環境で保存したファイルをそのままLinuxコンテナへ流し込んだため、Linux側が「行末に変なゴミ文字（\r）がくっついている」と勘違いし、パスやコマンドの解釈に失敗していた。

解決策: リポジトリのルート直下に .gitattributes を新規配備。これにより、Windows上でファイルをどのように編集したとしても、Gitへ git add . してコミットするタイミングで、Gitが裏側で行末の改行コードをLinux標準の LF コードへとフルオートでクレンジング・強制統一するフィルタリングレイヤーを敷くことで、OS間の改行不整合トラブルを根本から封印した。

## ③ 🆕 クリーンビルド時における Docker Compose ビルドパス（context）の不整合不具合
エラー現象: アプリケーション資材構造を src/ 配下にカプセル化・最適化したのち、ホストOS（Windows）を再起動して完全にキャッシュを抹消した「クリーンビルド・テスト」を実施した際、Server CのDocker一括ビルドタスクにて lstat /opt/noc-system/noc_system: no such file or directory が発生し、デプロイが強制停止した。

原因の特定: Ansibleのデプロイタスク側は、Windows側の新しい src/ フォルダ構成を /opt/noc-system/ の直下にそのまま展開するようにパスをリファクタリング（最適化）していた。しかし、コンテナを統括する noc_docker-compose.yml.j2 内部の build: セクションに、古い配置の痕跡である context: ./noc_system および dockerfile: noc_system/Dockerfile という旧パスが残存。まっさらな環境になったことで存在しない古いパスをDockerが厳格に検知し、ビルドエラーを引き起こしていた。

解決策: noc_docker-compose.yml.j2 のビルドコンテキストを /opt/noc-system （直下）へ修正し、dockerfile の指定を Dockerfile へと1対1で完全同期。コンテナ内のワークディレクトリ（/app）および Flask の実行パス（src/app.py）を完全に適合させることで、まっさらな更地からでもボタン一つで100%確実にマルチコンテナが焼き上がる「完全自律IaC」の確立に成功した。
