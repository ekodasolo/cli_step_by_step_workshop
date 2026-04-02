# [0601] EC2 インスタンスを作成する

## About

EC2 インスタンスを 1 台作成し、カレンダーアプリを動かす CLI 手順書。

本手順では、UserData を使って httpd のインストールとカレンダーページの生成を自動化する。
作成後に SSM Session Manager で接続し、HTTP レスポンスを確認する。

> **補足**: この EC2 は動作確認用の単体インスタンス。Step 08 で Auto Scaling Group に置き換える際に削除する。

## When: 作業の条件

### Before: 事前前提条件

以下を作業の前提条件とする。
1. ネットワーク編が完了している（Step 01〜04）。
2. IAM ロールと Instance Profile が作成済みである（Step 05 完了）。

### After: 作業終了状況

以下が完了の条件。
1. EC2 インスタンスが起動している（`running` 状態）。
2. SSM Session Manager で接続できる。
3. `curl localhost` でカレンダーページの HTML が返る。

## How: 以下は作業手順

### 1. 前処理

#### 1.1 処理パラメータの準備

パラメータの事後確認用ファイルの設定

```bash
RUNBOOK_TITLE="0601-create-ec2"
DIR_PARAMETER="."
FILE_PARAMETER="${DIR_PARAMETER}/$(date +%Y-%m-%d)-${RUNBOOK_TITLE}.env" \
    && echo ${FILE_PARAMETER}
```

手順の実行パラメータ

```bash
# 変数に値をセット
AWS_REGION="ap-northeast-1"
VPC_CIDR="10.0.0.0/16"
SUBNET_1A_CIDR="10.0.1.0/24"
INSTANCE_TYPE="t2.micro"
INSTANCE_NAME="cli-workshop-web-server"
INSTANCE_PROFILE_NAME="cli-workshop-web-server-profile"
WEB_SG_NAME="cli-workshop-web-sg"
```

```bash
# 値を確認
cat << ETX
    AWS_REGION=${AWS_REGION}
    VPC_CIDR=${VPC_CIDR}
    SUBNET_1A_CIDR=${SUBNET_1A_CIDR}
    INSTANCE_TYPE=${INSTANCE_TYPE}
    INSTANCE_NAME=${INSTANCE_NAME}
    INSTANCE_PROFILE_NAME=${INSTANCE_PROFILE_NAME}
    WEB_SG_NAME=${WEB_SG_NAME}

ETX
```

#### 1.2 前提リソースの ID 取得

```bash
VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=cidr,Values=${VPC_CIDR}" \
    --query "Vpcs[].VpcId" \
    --region ${AWS_REGION} \
    --output text) && echo "VPC_ID=${VPC_ID}"
```

```bash
SUBNET_1A_ID=$(aws ec2 describe-subnets \
    --filters \
        "Name=vpc-id,Values=${VPC_ID}" \
        "Name=cidrBlock,Values=${SUBNET_1A_CIDR}" \
    --query "Subnets[].SubnetId" \
    --region ${AWS_REGION} \
    --output text) && echo "SUBNET_1A_ID=${SUBNET_1A_ID}"
```

```bash
WEB_SG_ID=$(aws ec2 describe-security-groups \
    --filters \
        "Name=vpc-id,Values=${VPC_ID}" \
        "Name=group-name,Values=${WEB_SG_NAME}" \
    --query "SecurityGroups[].GroupId" \
    --region ${AWS_REGION} \
    --output text) && echo "WEB_SG_ID=${WEB_SG_ID}"
```

すべての ID が表示されれば、期待通り。

#### 1.3 AMI ID の取得

SSM パラメータストアから、最新の Amazon Linux 2023 の AMI ID を取得する。

> **補足**: AMI ID はリージョンや時期によって変わる。SSM パラメータストアには常に最新の AMI ID が格納されているので、ハードコードせずにここから取得するのがベストプラクティス。

```bash
AMI_ID=$(aws ssm get-parameters \
    --names /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
    --query "Parameters[].Value" \
    --region ${AWS_REGION} \
    --output text) && echo "AMI_ID=${AMI_ID}"
```

出力例

```output
AMI_ID=ami-0599b6e53ca798bb2
```

#### 1.4 UserData スクリプトの準備

EC2 起動時に自動実行されるスクリプトを作成する。
httpd をインストール・起動し、カレンダーページの HTML を生成する。

```bash
cat << 'USERDATA' > userdata.sh
#!/bin/bash
set -euo pipefail

# --- httpd インストール・起動 ---
yum update -y
yum install -y httpd
systemctl start httpd
systemctl enable httpd

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
FIRST_DOW=$(date -d "${YEAR}-${MONTH}-01" +%w)
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

  for ((i = 0; i < FIRST_DOW; i++)); do
    echo '      <td></td>'
  done

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
  <title>CLI Workshop</title>
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
    .info-item { text-align: center; }
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
USERDATA
```

ファイルが正しく作成されたことを確認する。

```bash
head -5 userdata.sh
```

```output
#!/bin/bash
set -euo pipefail

# --- httpd インストール・起動 ---
yum update -y
```

### 2. 主処理

#### 2.1 リソースの操作 (CREATE)

パラメータの最終確認

```bash
cat << EOF > ${FILE_PARAMETER}
aws ec2 run-instances \
    --image-id ${AMI_ID} \
    --instance-type ${INSTANCE_TYPE} \
    --subnet-id ${SUBNET_1A_ID} \
    --security-group-ids ${WEB_SG_ID} \
    --iam-instance-profile Name=${INSTANCE_PROFILE_NAME} \
    --user-data file://userdata.sh \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=${INSTANCE_NAME}}]' \
    --region ${AWS_REGION}

EOF
cat ${FILE_PARAMETER}
```

EC2 インスタンスを作成する。

```bash
aws ec2 run-instances \
    --image-id ${AMI_ID} \
    --instance-type ${INSTANCE_TYPE} \
    --subnet-id ${SUBNET_1A_ID} \
    --security-group-ids ${WEB_SG_ID} \
    --iam-instance-profile Name=${INSTANCE_PROFILE_NAME} \
    --user-data file://userdata.sh \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=${INSTANCE_NAME}}]' \
    --region ${AWS_REGION}
```

結果の例（長いため一部抜粋）

```output
{
    "Groups": [],
    "Instances": [
        {
            "InstanceId": "i-0a1b2c3d4eEXAMPLE",
            "InstanceType": "t2.micro",
            "LaunchTime": "2026-04-02T10:10:00+00:00",
            "State": {
                "Code": 0,
                "Name": "pending"
            },
            "SubnetId": "subnet-0a1b2c3d4eEXAMPLE",
            "VpcId": "vpc-0a1b2c3d4eEXAMPLE",
            ...
        }
    ]
}
```

> **注目**: 作成直後の `State.Name` は `pending`。`running` になるまで待つ必要がある。

インスタンス ID をシェル変数に格納する。

```bash
INSTANCE_ID=$(aws ec2 describe-instances \
    --filters \
        "Name=tag:Name,Values=${INSTANCE_NAME}" \
        "Name=instance-state-name,Values=pending,running" \
    --query "Reservations[].Instances[].InstanceId" \
    --region ${AWS_REGION} \
    --output text) && echo ${INSTANCE_ID}
```

出力例

```output
i-0a1b2c3d4eEXAMPLE
```

#### 2.2 インスタンスの起動完了を待つ

`wait` コマンドで、インスタンスが `running` になるまで待つ。

```bash
echo "インスタンスの起動を待っています..."
aws ec2 wait instance-running \
    --instance-ids ${INSTANCE_ID} \
    --region ${AWS_REGION}
echo "インスタンスが起動しました。"
```

> **補足**: `wait` はポーリングで状態を監視し、条件を満たすと正常終了する。EC2 の起動には通常 1〜2 分かかる。

### 3. 後処理

#### 3.1 完了条件1の結果確認

EC2 インスタンスが `running` 状態であることを確認する。

```bash
aws ec2 describe-instances \
    --instance-ids ${INSTANCE_ID} \
    --query "Reservations[].Instances[].[InstanceId, State.Name, PrivateIpAddress, PublicIpAddress]" \
    --region ${AWS_REGION} \
    --output table
```

結果の例

```output
---------------------------------------------------------------------
|                        DescribeInstances                          |
+-------------------------+---------+---------------+---------------+
|  i-0a1b2c3d4eEXAMPLE   | running | 10.0.1.42     | 54.xx.xx.xx   |
+-------------------------+---------+---------------+---------------+
```

`State` が `running` であれば期待通り。

#### 3.2 完了条件2の結果確認 — SSM 接続

SSM Session Manager でインスタンスに接続できるか確認する。

> **注意**: SSM エージェントが起動するまで、インスタンスが `running` になってからさらに 1〜2 分かかる場合がある。接続できない場合は少し待ってからリトライする。

```bash
aws ssm start-session \
    --target ${INSTANCE_ID} \
    --region ${AWS_REGION}
```

シェルプロンプトが表示されれば接続成功。

#### 3.3 完了条件3の結果確認 — HTTP レスポンス

SSM セッション内で、カレンダーページが生成されているか確認する。

```bash
curl -s localhost | head -20
```

HTML が返り、`<title>CLI Workshop</title>` が含まれていれば期待通り。

確認が終わったら、SSM セッションを終了する。

```bash
exit
```

#### 3.99 中間リソースの削除

UserData スクリプトファイルを削除する。

```bash
rm -f userdata.sh
```

> **注意**: この EC2 インスタンスは Step 08（ASG 作成）で削除するので、ここでは残しておく。

#### Navigation

Next: [ALB を作成する](./07-step07-alb.md)

# EOD
