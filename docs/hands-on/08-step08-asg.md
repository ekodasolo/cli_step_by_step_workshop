# [0801] Launch Template を作成する

## About

EC2 の起動設定をテンプレート化する Launch Template を作成する CLI 手順書。

Launch Template には、AMI ID / インスタンスタイプ / セキュリティグループ / IAM プロファイル / UserData など、EC2 の起動に必要な設定をまとめて定義する。
Auto Scaling Group は、この Launch Template を元に EC2 インスタンスを自動で起動する。

## When: 作業の条件

### Before: 事前前提条件

以下を作業の前提条件とする。
1. ネットワーク編が完了している（Step 01〜04）。
2. IAM ロールと Instance Profile が作成済みである（Step 05 完了）。
3. ALB + Target Group + Listener が作成済みである（Step 07 完了）。

### After: 作業終了状況

以下が完了の条件。
1. Launch Template が作成されている。
2. Launch Template のパラメータが正しい（AMI, InstanceType, SG, IAM Profile, UserData）。

## How: 以下は作業手順

### 1. 前処理

#### 1.1 処理パラメータの準備

パラメータの事後確認用ファイルの設定

```bash
RUNBOOK_TITLE="0801-create-launch-template"
DIR_PARAMETER="."
FILE_PARAMETER="${DIR_PARAMETER}/$(date +%Y-%m-%d)-${RUNBOOK_TITLE}.env" \
    && echo ${FILE_PARAMETER}
```

手順の実行パラメータ

```bash
# 変数に値をセット
AWS_REGION="ap-northeast-1"
VPC_CIDR="10.0.0.0/16"
LT_NAME="cli-workshop-lt"
INSTANCE_TYPE="t2.micro"
INSTANCE_PROFILE_NAME="cli-workshop-web-server-profile"
WEB_SG_NAME="cli-workshop-web-sg"
```

```bash
# 値を確認
cat << ETX
    AWS_REGION=${AWS_REGION}
    LT_NAME=${LT_NAME}
    INSTANCE_TYPE=${INSTANCE_TYPE}
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
WEB_SG_ID=$(aws ec2 describe-security-groups \
    --filters \
        "Name=vpc-id,Values=${VPC_ID}" \
        "Name=group-name,Values=${WEB_SG_NAME}" \
    --query "SecurityGroups[].GroupId" \
    --region ${AWS_REGION} \
    --output text) && echo "WEB_SG_ID=${WEB_SG_ID}"
```

```bash
AMI_ID=$(aws ssm get-parameters \
    --names /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
    --query "Parameters[].Value" \
    --region ${AWS_REGION} \
    --output text) && echo "AMI_ID=${AMI_ID}"
```

#### 1.3 UserData スクリプトの準備

Step 06 と同じカレンダーアプリの UserData を用意する。

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

UserData を Base64 エンコードする。

> **補足**: `create-launch-template` の `--launch-template-data` で UserData を渡す場合、Base64 エンコードが必要。`run-instances` の `--user-data file://` とは異なるので注意。

```bash
USERDATA_BASE64=$(base64 -w 0 userdata.sh) && echo "Base64 エンコード完了（${#USERDATA_BASE64} 文字）"
```

### 2. 主処理

#### 2.1 リソースの操作 (CREATE)

Launch Template を作成する。`--launch-template-data` に JSON 形式でパラメータを渡す。

```bash
aws ec2 create-launch-template \
    --launch-template-name ${LT_NAME} \
    --launch-template-data "{
        \"ImageId\": \"${AMI_ID}\",
        \"InstanceType\": \"${INSTANCE_TYPE}\",
        \"SecurityGroupIds\": [\"${WEB_SG_ID}\"],
        \"IamInstanceProfile\": {
            \"Name\": \"${INSTANCE_PROFILE_NAME}\"
        },
        \"UserData\": \"${USERDATA_BASE64}\",
        \"TagSpecifications\": [
            {
                \"ResourceType\": \"instance\",
                \"Tags\": [
                    {
                        \"Key\": \"Name\",
                        \"Value\": \"cli-workshop-web-server\"
                    }
                ]
            }
        ]
    }" \
    --region ${AWS_REGION}
```

結果の例

```output
{
    "LaunchTemplate": {
        "LaunchTemplateId": "lt-0a1b2c3d4eEXAMPLE",
        "LaunchTemplateName": "cli-workshop-lt",
        "CreateTime": "2026-04-02T10:30:00+00:00",
        "CreatedBy": "arn:aws:iam::123456789012:user/workshop-user",
        "DefaultVersionNumber": 1,
        "LatestVersionNumber": 1
    }
}
```

Launch Template ID をシェル変数に格納する。

```bash
LT_ID=$(aws ec2 describe-launch-templates \
    --launch-template-names ${LT_NAME} \
    --query "LaunchTemplates[].LaunchTemplateId" \
    --region ${AWS_REGION} \
    --output text) && echo ${LT_ID}
```

### 3. 後処理

#### 3.1 完了条件の結果確認

Launch Template のパラメータを確認する。

```bash
aws ec2 describe-launch-template-versions \
    --launch-template-name ${LT_NAME} \
    --versions '$Default' \
    --query "LaunchTemplateVersions[].LaunchTemplateData.[ImageId, InstanceType, SecurityGroupIds[0], IamInstanceProfile.Name]" \
    --region ${AWS_REGION} \
    --output table
```

結果の例

```output
---------------------------------------------------------------------------
|                    DescribeLaunchTemplateVersions                        |
+--------------------------+----------+-------------------------+----------+
|  ami-0599b6e53ca798bb2   | t2.micro | sg-0f1e2d3c4bEXAMPLE    | cli-workshop-web-server-profile |
+--------------------------+----------+-------------------------+----------+
```

AMI ID、InstanceType、SG ID、IAM Profile Name が正しければ期待通り。

#### 3.99 中間リソースの削除

UserData スクリプトファイルを削除する。

```bash
rm -f userdata.sh
```

#### Navigation

Next: [Auto Scaling Group を作成する](./08-step08-asg.md#0802-auto-scaling-group-を作成する)

---

# [0802] Auto Scaling Group を作成する

## About

Auto Scaling Group（ASG）を作成し、Launch Template から EC2 インスタンスを自動起動させる CLI 手順書。

ASG は指定した台数の EC2 インスタンスを自動で管理する。インスタンスが異常終了しても、自動で新しいインスタンスを起動して台数を維持する。

## When: 作業の条件

### Before: 事前前提条件

以下を作業の前提条件とする。
1. Launch Template が作成済みである（Step 0801 完了）。
2. Target Group が作成済みである（Step 07 完了）。
3. 2 つのサブネットが作成済みである（Step 02 完了）。

### After: 作業終了状況

以下が完了の条件。
1. ASG が作成されている。
2. ASG から EC2 インスタンスが 2 台起動している。
3. 新しいインスタンスが Target Group に自動登録され、`healthy` になっている。
4. ALB の DNS 名でリロードすると、異なる Instance ID が表示される（ロードバランシングの確認）。

## How: 以下は作業手順

### 1. 前処理

#### 1.1 処理パラメータの準備

パラメータの事後確認用ファイルの設定

```bash
RUNBOOK_TITLE="0802-create-asg"
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
SUBNET_1C_CIDR="10.0.2.0/24"
ASG_NAME="cli-workshop-asg"
LT_NAME="cli-workshop-lt"
TG_NAME="cli-workshop-tg"
ASG_MIN_SIZE="2"
ASG_MAX_SIZE="4"
ASG_DESIRED_CAPACITY="2"
```

```bash
# 値を確認
cat << ETX
    AWS_REGION=${AWS_REGION}
    ASG_NAME=${ASG_NAME}
    LT_NAME=${LT_NAME}
    TG_NAME=${TG_NAME}
    ASG_MIN_SIZE=${ASG_MIN_SIZE}
    ASG_MAX_SIZE=${ASG_MAX_SIZE}
    ASG_DESIRED_CAPACITY=${ASG_DESIRED_CAPACITY}

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
SUBNET_1C_ID=$(aws ec2 describe-subnets \
    --filters \
        "Name=vpc-id,Values=${VPC_ID}" \
        "Name=cidrBlock,Values=${SUBNET_1C_CIDR}" \
    --query "Subnets[].SubnetId" \
    --region ${AWS_REGION} \
    --output text) && echo "SUBNET_1C_ID=${SUBNET_1C_ID}"
```

```bash
LT_ID=$(aws ec2 describe-launch-templates \
    --launch-template-names ${LT_NAME} \
    --query "LaunchTemplates[].LaunchTemplateId" \
    --region ${AWS_REGION} \
    --output text) && echo "LT_ID=${LT_ID}"
```

```bash
TG_ARN=$(aws elbv2 describe-target-groups \
    --names ${TG_NAME} \
    --query "TargetGroups[].TargetGroupArn" \
    --region ${AWS_REGION} \
    --output text) && echo "TG_ARN=${TG_ARN}"
```

### 2. 主処理

#### 2.1 リソースの操作 (CREATE)

パラメータの最終確認

```bash
cat << EOF > ${FILE_PARAMETER}
aws autoscaling create-auto-scaling-group \
    --auto-scaling-group-name ${ASG_NAME} \
    --launch-template LaunchTemplateId=${LT_ID},Version='\$Default' \
    --min-size ${ASG_MIN_SIZE} \
    --max-size ${ASG_MAX_SIZE} \
    --desired-capacity ${ASG_DESIRED_CAPACITY} \
    --vpc-zone-identifier "${SUBNET_1A_ID},${SUBNET_1C_ID}" \
    --target-group-arns ${TG_ARN} \
    --health-check-type ELB \
    --health-check-grace-period 300 \
    --region ${AWS_REGION}

EOF
cat ${FILE_PARAMETER}
```

ASG を作成する。

```bash
aws autoscaling create-auto-scaling-group \
    --auto-scaling-group-name ${ASG_NAME} \
    --launch-template LaunchTemplateId=${LT_ID},Version='$Default' \
    --min-size ${ASG_MIN_SIZE} \
    --max-size ${ASG_MAX_SIZE} \
    --desired-capacity ${ASG_DESIRED_CAPACITY} \
    --vpc-zone-identifier "${SUBNET_1A_ID},${SUBNET_1C_ID}" \
    --target-group-arns ${TG_ARN} \
    --health-check-type ELB \
    --health-check-grace-period 300 \
    --region ${AWS_REGION}
```

このコマンドは成功しても出力がない（サイレント）。

> **ポイント**:
> - `--vpc-zone-identifier`: 2 つのサブネットをカンマ区切りで指定。ASG はこれらのサブネットに EC2 を分散配置する
> - `--target-group-arns`: ASG が起動した EC2 を自動で Target Group に登録する
> - `--health-check-type ELB`: ALB のヘルスチェックを使ってインスタンスの健全性を判断する

### 3. 後処理

#### 3.1 完了条件1の結果確認

ASG が作成されていることを確認する。

```bash
aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names ${ASG_NAME} \
    --query "AutoScalingGroups[].[AutoScalingGroupName, MinSize, MaxSize, DesiredCapacity, length(Instances)]" \
    --region ${AWS_REGION} \
    --output table
```

結果の例

```output
----------------------------------------------------------------------
|                   DescribeAutoScalingGroups                         |
+---------------------+-----+-----+-----+---+
|  cli-workshop-asg   |  2  |  4  |  2  | 2 |
+---------------------+-----+-----+-----+---+
```

DesiredCapacity が 2 で、Instances の数も 2 であれば期待通り。

#### 3.2 完了条件2の結果確認

ASG が起動した EC2 インスタンスを確認する。

```bash
aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names ${ASG_NAME} \
    --query "AutoScalingGroups[].Instances[].[InstanceId, AvailabilityZone, LifecycleState, HealthStatus]" \
    --region ${AWS_REGION} \
    --output table
```

結果の例

```output
----------------------------------------------------------------------
|                   DescribeAutoScalingGroups                         |
+-------------------------+------------------+-----------+----------+
|  i-0new1instance1EXMPL  | ap-northeast-1a  | InService | Healthy  |
|  i-0new2instance2EXMPL  | ap-northeast-1c  | InService | Healthy  |
+-------------------------+------------------+-----------+----------+
```

> **注意**: インスタンスが `Pending` 状態の場合は、1〜2 分待ってから再実行する。

#### 3.3 完了条件3の結果確認

Target Group のヘルスチェックを確認する。

```bash
aws elbv2 describe-target-health \
    --target-group-arn ${TG_ARN} \
    --region ${AWS_REGION}
```

ASG のインスタンス 2 台 + Step 06 で作成した単体インスタンス 1 台 = 計 3 台が表示されるはず。
ASG のインスタンスが `healthy` になるまで待つ。

#### 3.4 単体 EC2 をターゲットから外して削除

Step 06 で作成した動作確認用の単体 EC2 は、ASG に置き換わったので不要になる。
ターゲットから外してから削除する。

単体 EC2 の ID を取得する。

```bash
# ASG が管理するインスタンス ID を取得
ASG_INSTANCE_IDS=$(aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names ${ASG_NAME} \
    --query "AutoScalingGroups[].Instances[].InstanceId" \
    --region ${AWS_REGION} \
    --output text)
echo "ASG インスタンス: ${ASG_INSTANCE_IDS}"

# cli-workshop-web-server タグの付いた全インスタンスのうち、ASG 管理外のものを特定
STANDALONE_INSTANCE_ID=$(aws ec2 describe-instances \
    --filters \
        "Name=tag:Name,Values=cli-workshop-web-server" \
        "Name=instance-state-name,Values=running" \
    --query "Reservations[].Instances[?!contains(\`${ASG_INSTANCE_IDS}\`, InstanceId)].InstanceId" \
    --region ${AWS_REGION} \
    --output text) && echo "単体 EC2: ${STANDALONE_INSTANCE_ID}"
```

> **注意**: 単体 EC2 の ID が正しいことを確認してから、次の手順に進む。

ターゲットから外す。

```bash
aws elbv2 deregister-targets \
    --target-group-arn ${TG_ARN} \
    --targets Id=${STANDALONE_INSTANCE_ID} \
    --region ${AWS_REGION}
```

単体 EC2 を終了（削除）する。

```bash
aws ec2 terminate-instances \
    --instance-ids ${STANDALONE_INSTANCE_ID} \
    --region ${AWS_REGION} \
    --query "TerminatingInstances[].[InstanceId, CurrentState.Name]" \
    --output table
```

結果の例

```output
------------------------------------------
|           TerminateInstances           |
+-------------------------+--------------+
|  i-0a1b2c3d4eEXAMPLE   | shutting-down|
+-------------------------+--------------+
```

#### 3.5 完了条件4の結果確認 — ロードバランシングの確認

ALB の DNS 名を確認する。

```bash
ALB_DNS=$(aws elbv2 describe-load-balancers \
    --names cli-workshop-alb \
    --query "LoadBalancers[].DNSName" \
    --region ${AWS_REGION} \
    --output text) && echo "http://${ALB_DNS}"
```

表示された URL をブラウザで開き、以下を確認する:

1. カレンダーページが表示される
2. ページをリロード（F5）すると、**Instance ID と Private IP が切り替わる**
3. 2 つの異なるインスタンスに交互に振り分けられている

これがロードバランシングの動作確認。ALB が 2 台の EC2 にリクエストを分散していることが確認できる。

> **補足**: ブラウザのキャッシュにより同じインスタンスに接続されることがある。その場合はスーパーリロード（Ctrl+Shift+R）を試す。

#### 3.99 中間リソースの削除

今回は特になし。

#### Navigation

Next: [クリーンアップ](./09-step09-cleanup.md)

# EOD
