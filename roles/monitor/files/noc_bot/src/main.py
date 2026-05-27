import os
import time
import schedule
import requests
import pandas as pd
from datetime import datetime, timedelta

# 環境変数（Ansibleから注入）
PROM_URL = os.getenv("PROMETHEUS_URL", "http://localhost:9090")
DISCORD_URL = os.getenv("DISCORD_WEBHOOK_URL")
REPORT_TIME = os.getenv("REPORT_TIME", "08:00")


def send_discord(content):
    if DISCORD_URL:
        try:
            requests.post(DISCORD_URL, json={"content": content})
        except Exception as e:
            print(f"Discord Send Error: {e}")


def check_realtime_alerts():
    """1分ごとの閾値監視[cite: 1]"""
    try:
        # CPU使用率の取得（直近5分平均）
        query = '100 - (avg by (instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)'
        resp = requests.get(f"{PROM_URL}/api/v1/query", params={"query": query})
        results = resp.json()["data"]["result"]

        for res in results:
            usage = float(res["value"][1])
            instance = res["metric"].get("instance", "unknown")
            if usage > 80:  # 閾値80%[cite: 1]
                send_discord(
                    f"🚨 **【NOC警報】高負荷検知**\n対象: {instance}\nCPU使用率: {usage:.1f}%"
                )
    except Exception as e:
        print(f"Alert Check Failed: {e}")


def generate_daily_report():
    """24時間の統計分析とレポート送信[cite: 1]"""
    print(f"Generating Daily Report at {datetime.now()}")
    try:
        # 過去24時間のデータを15分刻みで取得
        end_time = datetime.now()
        start_time = end_time - timedelta(days=1)
        query = '100 - (avg by (instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)'

        params = {
            "query": query,
            "start": start_time.timestamp(),
            "end": end_time.timestamp(),
            "step": "15m",
        }
        resp = requests.get(f"{PROM_URL}/api/v1/query_range", params=params)
        data = resp.json()["data"]["result"]

        report_msg = "📊 **【NOC日次レポート】過去24時間の稼働統計**\n"
        for entry in data:
            instance = entry["metric"].get("instance", "unknown")
            values = [float(v[1]) for v in entry["values"]]
            df = pd.Series(values)

            report_msg += (
                f"🔹 サーバー: {instance}\n"
                f"　 平均負荷: {df.mean():.1f}%\n"
                f"　 最大負荷: {df.max():.1f}%\n"
            )

        send_discord(report_msg)
    except Exception as e:
        send_discord(f"⚠️ 日次レポート生成に失敗しました: {e}")


# スケジュール登録[cite: 1]
schedule.every(1).minutes.do(check_realtime_alerts)
schedule.every().day.at(REPORT_TIME).do(generate_daily_report)

if __name__ == "__main__":
    send_discord(
        "✅ **NOC統合コンテナが起動しました**\nリアルタイム監視と統計レポート（毎日 "
        + REPORT_TIME
        + "）を開始します。"
    )
    while True:
        schedule.run_pending()
        time.sleep(1)
