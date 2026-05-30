#!/bin/bash
TARGET_IP="10.149.245.115"
TARGET_URL="http://${TARGET_IP}:80/"

echo "=========================================================="
echo "🚀 負荷テストツール(ApacheBench)の生存確認"
echo "=========================================================="
if ! command -v ab &> /dev/null; then
    sudo dnf install -y httpd-tools
fi

echo -e "\n=========================================================="
echo "🔥 【超・波状攻撃】サーバーB（115）へ50,000回アクセス爆撃開始！"
echo "=========================================================="
echo "⚠️ 同時接続150で超高負荷を注入中...（約10〜20秒間持続します）"

# 🌟 リクエスト数を50,000、同時接続を150に大幅強化！
# さらに、あえて「時間をかけて」CPUを痛めつけるために、裏で2連続で爆撃を走らせます
ab -n 25000 -c 150 ${TARGET_URL} > /dev/null &
ab -n 25000 -c 150 ${TARGET_URL} > /dev/null
wait

echo "🟢 爆撃完了。Prometheusにデータが届くまで【5秒間】待機します..."
sleep 5

echo -e "\n=========================================================="
echo "📊 監視塔(Server C)から直近のデータを抽出してDiscordへ送信..."
echo "=========================================================="

export PROM_URL="http://10.149.245.116:9090"
export PROMETHEUS_URL="http://10.149.245.116:9090"
export prometheus_internal_url="http://10.149.245.116:9090"
export RUN_ONCE="true"
export DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/1499223130726731940/UitJlpYN6ZJFHLliCoAKissCG4M2lDyDVIetqSNKRbF_IojY73yOCch44MF8qFV-zKAo"

# 表記の置換と時間軸のハック
sudo sed -i 's/平均負荷/平均CPU使用率/g' /opt/noc_bot/src/main.py
sudo sed -i 's/最大負荷/最大CPU使用率/g' /opt/noc_bot/src/main.py
sudo sed -i 's/days=1/minutes=5/g' /opt/noc_bot/src/main.py
sudo sed -i "s/params = {/params = {\n        'step': '5s',/g" /opt/noc_bot/src/main.py
sudo sed -i 's/過去24時間の稼働統計/負荷テスト実行中のリアルタイム稼働統計（直近5分間）/g' /opt/noc_bot/src/main.py

# NOCボットのプログラムを強制起動
python3 /opt/noc_bot/src/main.py

# 後片付け（元に戻す）
sudo sed -i 's/minutes=5/days=1/g' /opt/noc_bot/src/main.py
sudo sed -i "s/        'step': '5s',//g" /opt/noc_bot/src/main.py
sudo sed -i 's/負荷テスト実行中のリアルタイム稼働統計（直近5分間）/過去24時間の稼働統計/g' /opt/noc_bot/src/main.py
