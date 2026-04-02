#!/bin/bash
# EC2 インスタンス上で実行し、カレンダーページの HTML を生成するスクリプト
# cron で毎日 0 時に再生成し、月が変わるとカレンダーも切り替わる

set -euo pipefail

# --- メタデータ取得（IMDSv2） ---
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)
PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/local-ipv4)

# --- 日付情報 ---
YEAR=$(date +%Y)
MONTH=$(date +%m)
MONTH_NAME=$(date +"%B")

# --- カレンダー計算 ---
# 月の初日の曜日（0=日, 1=月, ..., 6=土）
FIRST_DOW=$(date -d "${YEAR}-${MONTH}-01" +%w 2>/dev/null \
  || date -j -f "%Y-%m-%d" "${YEAR}-${MONTH}-01" +%w)

# 月の日数
DAYS_IN_MONTH=$(cal "$MONTH" "$YEAR" | awk 'NF {DAYS = $NF} END {print DAYS}')

TODAY=$(date +%d | sed 's/^0//')

# --- カレンダー HTML 生成 ---
generate_calendar() {
  echo '<table class="calendar">'
  echo '  <thead>'
  echo '    <tr>'
  for day in Sun Mon Tue Wed Thu Fri Sat; do
    echo "      <th>${day}</th>"
  done
  echo '    </tr>'
  echo '  </thead>'
  echo '  <tbody>'
  echo '    <tr>'

  # 月初までの空セル
  for ((i = 0; i < FIRST_DOW; i++)); do
    echo '      <td></td>'
  done

  # 日付セル
  cell=$FIRST_DOW
  for ((d = 1; d <= DAYS_IN_MONTH; d++)); do
    if [ "$d" -eq "$TODAY" ]; then
      echo "      <td class=\"today\">${d}</td>"
    else
      echo "      <td>${d}</td>"
    fi
    cell=$((cell + 1))
    if [ $((cell % 7)) -eq 0 ] && [ "$d" -lt "$DAYS_IN_MONTH" ]; then
      echo '    </tr>'
      echo '    <tr>'
    fi
  done

  # 月末の空セル
  remaining=$(( (7 - (cell % 7)) % 7 ))
  for ((i = 0; i < remaining; i++)); do
    echo '      <td></td>'
  done

  echo '    </tr>'
  echo '  </tbody>'
  echo '</table>'
}

CALENDAR_HTML=$(generate_calendar)

# --- HTML 出力 ---
cat > /var/www/html/index.html <<HTMLEOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>AWS CLI Workshop</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }

    body {
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      background: #f0f4f8;
      color: #1a202c;
      min-height: 100vh;
      display: flex;
      justify-content: center;
      align-items: center;
      padding: 2rem;
    }

    .container {
      background: #fff;
      border-radius: 16px;
      box-shadow: 0 4px 24px rgba(0, 0, 0, 0.08);
      padding: 2.5rem;
      max-width: 520px;
      width: 100%;
    }

    h1 {
      font-size: 1.5rem;
      font-weight: 700;
      text-align: center;
      margin-bottom: 0.5rem;
      color: #232f3e;
    }

    .subtitle {
      text-align: center;
      color: #718096;
      font-size: 0.9rem;
      margin-bottom: 2rem;
    }

    .instance-info {
      background: #edf2f7;
      border-radius: 8px;
      padding: 1rem 1.25rem;
      margin-bottom: 2rem;
      display: flex;
      gap: 1.5rem;
      justify-content: center;
      flex-wrap: wrap;
    }

    .info-item {
      text-align: center;
    }

    .info-label {
      font-size: 0.7rem;
      text-transform: uppercase;
      letter-spacing: 0.05em;
      color: #718096;
      margin-bottom: 0.25rem;
    }

    .info-value {
      font-family: "SF Mono", "Fira Code", monospace;
      font-size: 0.85rem;
      font-weight: 600;
      color: #2d3748;
    }

    .month-title {
      text-align: center;
      font-size: 1.1rem;
      font-weight: 600;
      margin-bottom: 1rem;
      color: #2d3748;
    }

    .calendar {
      width: 100%;
      border-collapse: collapse;
      table-layout: fixed;
    }

    .calendar th {
      padding: 0.5rem;
      font-size: 0.75rem;
      font-weight: 600;
      text-transform: uppercase;
      color: #a0aec0;
      text-align: center;
    }

    .calendar td {
      padding: 0.6rem;
      text-align: center;
      font-size: 0.9rem;
      color: #4a5568;
      border-radius: 8px;
    }

    .calendar td.today {
      background: #ff9900;
      color: #fff;
      font-weight: 700;
    }

    .footer {
      text-align: center;
      margin-top: 1.5rem;
      font-size: 0.75rem;
      color: #a0aec0;
    }
  </style>
</head>
<body>
  <div class="container">
    <h1>AWS CLI Workshop</h1>
    <p class="subtitle">Served from EC2 via Auto Scaling + ALB</p>

    <div class="instance-info">
      <div class="info-item">
        <div class="info-label">Instance ID</div>
        <div class="info-value">${INSTANCE_ID}</div>
      </div>
      <div class="info-item">
        <div class="info-label">Private IP</div>
        <div class="info-value">${PRIVATE_IP}</div>
      </div>
    </div>

    <div class="month-title">${MONTH_NAME} ${YEAR}</div>
${CALENDAR_HTML}

    <div class="footer">Generated at $(date '+%Y-%m-%d %H:%M:%S %Z')</div>
  </div>
</body>
</html>
HTMLEOF
