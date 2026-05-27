# Python 3.12-slimを採用し軽量化と堅牢性を両立
FROM python:3.12-slim

WORKDIR /app

# 依存ライブラリのインストール
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# ソースコードとレポート用ディレクトリの準備
COPY src/ ./src/
RUN mkdir -p /app/reports

# 日本時間に設定
ENV TZ=Asia/Tokyo

CMD ["python", "-u", "src/main.py"]