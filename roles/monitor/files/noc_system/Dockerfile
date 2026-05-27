# =================================================================
# ステージ1: ビルド環境 (依存関係のコンパイルとダウンロード)
# =====================================================
# パッケージのコンパイルには大容量のgccやツールが必要なため、一時的な「 builder 」コンテナを立てます
FROM python:3.10-slim AS builder

WORKDIR /build

# C言語系のモジュール(PostgreSQLドライバ等)のビルドに必要なOSパッケージを最小限導入
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/* # 削除を徹底してステージ1のレイヤーも可能な限り節約

# pipのアップグレードと、必要なWeb/データ解析系ライブラリのコンパイルインストール
# --user フラグを付けることで、インストール先を「 /root/.local 」配下に統一します
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir --user \
    Flask==3.0.3 \
    requests==2.31.0 \
    pandas==2.2.2 \
    psycopg2-binary==2.9.9

# =====================================================
# ステージ2: 実行環境 (余計なゴミを排除した、超軽量な本番ランタイム)
# =====================================================
# 実際にServer Cで常駐して動き続けるのは、このクリーンな「 runner 」コンテナです
FROM python:3.10-slim AS runner

WORKDIR /app

# PostgreSQLの実行時に最低限必要な、軽量な共有ライブラリ(C言語ライブラリ)のみを導入
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq5 \
    && rm -rf /var/lib/apt/lists/*

# 💡マルチステージビルドの核心: ステージ1(builder)のコンテナから、コンパイル済みのPythonライブラリ成果物のみを「ピンポイントで抽出コピー」
COPY --from=builder /root/.local /root/.local

# コピーしたライブラリ群をPythonが正常に認識・実行できるように環境変数のパスを通す
ENV PATH=/root/.local/bin:$PATH
ENV TZ=Asia/Tokyo

# コマンドの実行は docker-compose 側で上書き・コントロールするため、ここではベースの環境定義のみ
CMD ["python3"]