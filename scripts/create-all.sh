#!/bin/bash
# 講師用: ワークショップの全リソースを一括作成するスクリプト
# 手順書の内容を自動実行する。デモ環境の事前準備や動作確認に使用。
set -euo pipefail

echo "=============================="
echo " CLI Workshop - 一括作成"
echo "=============================="

# --- 共通パラメータ ---
AWS_REGION="ap-northeast-1"
VPC_CIDR="10.0.0.0/16"
SUBNET_1A_CIDR="10.0.1.0/24"
SUBNET_1C_CIDR="10.0.2.0/24"
INSTANCE_TYPE="t2.micro"

# --- Step 01: VPC ---
echo ""
echo "[Step 01] VPC を作成..."
VPC_ID=$(aws ec2 create-vpc \
    --cidr-block ${VPC_CIDR} \
    --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=cli-workshop-vpc}]' \
    --query "Vpc.VpcId" \
    --region ${AWS_REGION} \
    --output text) && echo "  VPC_ID=${VPC_ID}"

aws ec2 modify-vpc-attribute \
    --vpc-id ${VPC_ID} \
    --enable-dns-hostnames '{"Value": true}' \
    --region ${AWS_REGION}
echo "  DNS ホスト名有効化完了"

# --- Step 02: Subnets ---
echo ""
echo "[Step 02] Subnet を作成..."
SUBNET_1A_ID=$(aws ec2 create-subnet \
    --vpc-id ${VPC_ID} \
    --cidr-block ${SUBNET_1A_CIDR} \
    --availability-zone ap-northeast-1a \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=cli-workshop-public-1a}]' \
    --query "Subnet.SubnetId" \
    --region ${AWS_REGION} \
    --output text) && echo "  SUBNET_1A_ID=${SUBNET_1A_ID}"

aws ec2 modify-subnet-attribute \
    --subnet-id ${SUBNET_1A_ID} \
    --map-public-ip-on-launch \
    --region ${AWS_REGION}

SUBNET_1C_ID=$(aws ec2 create-subnet \
    --vpc-id ${VPC_ID} \
    --cidr-block ${SUBNET_1C_CIDR} \
    --availability-zone ap-northeast-1c \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=cli-workshop-public-1c}]' \
    --query "Subnet.SubnetId" \
    --region ${AWS_REGION} \
    --output text) && echo "  SUBNET_1C_ID=${SUBNET_1C_ID}"

aws ec2 modify-subnet-attribute \
    --subnet-id ${SUBNET_1C_ID} \
    --map-public-ip-on-launch \
    --region ${AWS_REGION}

# --- Step 03: IGW + RouteTable ---
echo ""
echo "[Step 03] IGW + RouteTable を作成..."
IGW_ID=$(aws ec2 create-internet-gateway \
    --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=cli-workshop-igw}]' \
    --query "InternetGateway.InternetGatewayId" \
    --region ${AWS_REGION} \
    --output text) && echo "  IGW_ID=${IGW_ID}"

aws ec2 attach-internet-gateway \
    --internet-gateway-id ${IGW_ID} \
    --vpc-id ${VPC_ID} \
    --region ${AWS_REGION}

RT_ID=$(aws ec2 create-route-table \
    --vpc-id ${VPC_ID} \
    --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=cli-workshop-public-rt}]' \
    --query "RouteTable.RouteTableId" \
    --region ${AWS_REGION} \
    --output text) && echo "  RT_ID=${RT_ID}"

aws ec2 create-route \
    --route-table-id ${RT_ID} \
    --destination-cidr-block "0.0.0.0/0" \
    --gateway-id ${IGW_ID} \
    --region ${AWS_REGION} > /dev/null

aws ec2 associate-route-table \
    --subnet-id ${SUBNET_1A_ID} \
    --route-table-id ${RT_ID} \
    --region ${AWS_REGION} > /dev/null

aws ec2 associate-route-table \
    --subnet-id ${SUBNET_1C_ID} \
    --route-table-id ${RT_ID} \
    --region ${AWS_REGION} > /dev/null
echo "  ルーティング設定完了"

# --- Step 04: Security Groups ---
echo ""
echo "[Step 04] Security Group を作成..."
ALB_SG_ID=$(aws ec2 create-security-group \
    --group-name cli-workshop-alb-sg \
    --description "Security group for ALB - allows HTTP from internet" \
    --vpc-id ${VPC_ID} \
    --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=cli-workshop-alb-sg}]' \
    --query "GroupId" \
    --region ${AWS_REGION} \
    --output text) && echo "  ALB_SG_ID=${ALB_SG_ID}"

aws ec2 authorize-security-group-ingress \
    --group-id ${ALB_SG_ID} \
    --protocol tcp \
    --port 80 \
    --cidr "0.0.0.0/0" \
    --region ${AWS_REGION} > /dev/null

WEB_SG_ID=$(aws ec2 create-security-group \
    --group-name cli-workshop-web-sg \
    --description "Security group for EC2 - allows HTTP from ALB only" \
    --vpc-id ${VPC_ID} \
    --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=cli-workshop-web-sg}]' \
    --query "GroupId" \
    --region ${AWS_REGION} \
    --output text) && echo "  WEB_SG_ID=${WEB_SG_ID}"

aws ec2 authorize-security-group-ingress \
    --group-id ${WEB_SG_ID} \
    --protocol tcp \
    --port 80 \
    --source-group ${ALB_SG_ID} \
    --region ${AWS_REGION} > /dev/null

# --- Step 05: IAM ---
echo ""
echo "[Step 05] IAM Role + Instance Profile を作成..."
ROLE_NAME="cli-workshop-web-server-role"
INSTANCE_PROFILE_NAME="cli-workshop-web-server-profile"

cat << 'EOF' > /tmp/trust-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Service": "ec2.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF

aws iam create-role \
    --role-name ${ROLE_NAME} \
    --assume-role-policy-document file:///tmp/trust-policy.json \
    --tags Key=Name,Value=${ROLE_NAME} > /dev/null
echo "  ロール作成完了"

aws iam attach-role-policy \
    --role-name ${ROLE_NAME} \
    --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore

aws iam create-instance-profile \
    --instance-profile-name ${INSTANCE_PROFILE_NAME} > /dev/null

aws iam add-role-to-instance-profile \
    --instance-profile-name ${INSTANCE_PROFILE_NAME} \
    --role-name ${ROLE_NAME}
echo "  Instance Profile 作成完了"

rm -f /tmp/trust-policy.json

# Instance Profile の反映を待つ
echo "  Instance Profile の反映を待っています（10 秒）..."
sleep 10

# --- AMI ID 取得 ---
AMI_ID=$(aws ssm get-parameters \
    --names /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
    --query "Parameters[].Value" \
    --region ${AWS_REGION} \
    --output text) && echo "  AMI_ID=${AMI_ID}"

# --- UserData 作成 ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cat << 'USERDATA' > /tmp/userdata.sh
#!/bin/bash
set -euo pipefail
yum update -y
yum install -y httpd
systemctl start httpd
systemctl enable httpd

TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)
PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/local-ipv4)

YEAR=$(date +%Y)
MONTH=$(date +%m)
MONTH_NAME=$(date +"%B")
FIRST_DOW=$(date -d "${YEAR}-${MONTH}-01" +%w)
DAYS_IN_MONTH=$(cal "$MONTH" "$YEAR" | awk 'NF {DAYS = $NF} END {print DAYS}')
TODAY=$(date +%d | sed 's/^0//')

generate_calendar() {
  echo '<table class="calendar"><thead><tr>'
  for day in Sun Mon Tue Wed Thu Fri Sat; do echo "<th>${day}</th>"; done
  echo '</tr></thead><tbody><tr>'
  for ((i = 0; i < FIRST_DOW; i++)); do echo '<td></td>'; done
  cell=$FIRST_DOW
  for ((d = 1; d <= DAYS_IN_MONTH; d++)); do
    if [ "$d" -eq "$TODAY" ]; then echo "<td class=\"today\">${d}</td>"
    else echo "<td>${d}</td>"; fi
    cell=$((cell + 1))
    if [ $((cell % 7)) -eq 0 ] && [ "$d" -lt "$DAYS_IN_MONTH" ]; then echo '</tr><tr>'; fi
  done
  remaining=$(( (7 - (cell % 7)) % 7 ))
  for ((i = 0; i < remaining; i++)); do echo '<td></td>'; done
  echo '</tr></tbody></table>'
}
CALENDAR_HTML=$(generate_calendar)

cat > /var/www/html/index.html <<HTMLEOF
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>CLI Workshop</title>
  <style>
    *{margin:0;padding:0;box-sizing:border-box}body{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif;background:#f0f4f8;color:#1a202c;min-height:100vh;display:flex;justify-content:center;align-items:center;padding:2rem}.container{background:#fff;border-radius:16px;box-shadow:0 4px 24px rgba(0,0,0,.08);padding:2.5rem;max-width:520px;width:100%}h1{font-size:1.5rem;font-weight:700;text-align:center;margin-bottom:.5rem;color:#232f3e}.subtitle{text-align:center;color:#718096;font-size:.9rem;margin-bottom:2rem}.instance-info{background:#edf2f7;border-radius:8px;padding:1rem 1.25rem;margin-bottom:2rem;display:flex;gap:1.5rem;justify-content:center;flex-wrap:wrap}.info-item{text-align:center}.info-label{font-size:.7rem;text-transform:uppercase;letter-spacing:.05em;color:#718096;margin-bottom:.25rem}.info-value{font-family:"SF Mono","Fira Code",monospace;font-size:.85rem;font-weight:600;color:#2d3748}.month-title{text-align:center;font-size:1.1rem;font-weight:600;margin-bottom:1rem;color:#2d3748}.calendar{width:100%;border-collapse:collapse;table-layout:fixed}.calendar th{padding:.5rem;font-size:.75rem;font-weight:600;text-transform:uppercase;color:#a0aec0;text-align:center}.calendar td{padding:.6rem;text-align:center;font-size:.9rem;color:#4a5568;border-radius:8px}.calendar td.today{background:#ff9900;color:#fff;font-weight:700}.footer{text-align:center;margin-top:1.5rem;font-size:.75rem;color:#a0aec0}
  </style>
</head>
<body>
  <div class="container">
    <h1>AWS CLI Workshop</h1>
    <p class="subtitle">Served from EC2 via Auto Scaling + ALB</p>
    <div class="instance-info">
      <div class="info-item"><div class="info-label">Instance ID</div><div class="info-value">${INSTANCE_ID}</div></div>
      <div class="info-item"><div class="info-label">Private IP</div><div class="info-value">${PRIVATE_IP}</div></div>
    </div>
    <div class="month-title">${MONTH_NAME} ${YEAR}</div>
${CALENDAR_HTML}
    <div class="footer">Generated at $(date '+%Y-%m-%d %H:%M:%S %Z')</div>
  </div>
</body>
</html>
HTMLEOF
USERDATA

# --- Step 07: ALB ---
echo ""
echo "[Step 07] ALB + Target Group + Listener を作成..."
ALB_ARN=$(aws elbv2 create-load-balancer \
    --name cli-workshop-alb \
    --subnets ${SUBNET_1A_ID} ${SUBNET_1C_ID} \
    --security-groups ${ALB_SG_ID} \
    --scheme internet-facing \
    --type application \
    --tags Key=Name,Value=cli-workshop-alb \
    --query "LoadBalancers[].LoadBalancerArn" \
    --region ${AWS_REGION} \
    --output text) && echo "  ALB_ARN=${ALB_ARN}"

echo "  ALB の作成完了を待っています..."
aws elbv2 wait load-balancer-available \
    --load-balancer-arns ${ALB_ARN} \
    --region ${AWS_REGION}
echo "  ALB 利用可能"

TG_ARN=$(aws elbv2 create-target-group \
    --name cli-workshop-tg \
    --protocol HTTP \
    --port 80 \
    --vpc-id ${VPC_ID} \
    --target-type instance \
    --health-check-protocol HTTP \
    --health-check-path / \
    --health-check-interval-seconds 30 \
    --healthy-threshold-count 2 \
    --unhealthy-threshold-count 5 \
    --tags Key=Name,Value=cli-workshop-tg \
    --query "TargetGroups[].TargetGroupArn" \
    --region ${AWS_REGION} \
    --output text) && echo "  TG_ARN=${TG_ARN}"

aws elbv2 create-listener \
    --load-balancer-arn ${ALB_ARN} \
    --protocol HTTP \
    --port 80 \
    --default-actions Type=forward,TargetGroupArn=${TG_ARN} \
    --region ${AWS_REGION} > /dev/null
echo "  Listener 作成完了"

# --- Step 08: Launch Template + ASG ---
echo ""
echo "[Step 08] Launch Template + ASG を作成..."
USERDATA_BASE64=$(base64 -w 0 /tmp/userdata.sh)

LT_ID=$(aws ec2 create-launch-template \
    --launch-template-name cli-workshop-lt \
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
                \"Tags\": [{\"Key\": \"Name\", \"Value\": \"cli-workshop-web-server\"}]
            }
        ]
    }" \
    --query "LaunchTemplate.LaunchTemplateId" \
    --region ${AWS_REGION} \
    --output text) && echo "  LT_ID=${LT_ID}"

aws autoscaling create-auto-scaling-group \
    --auto-scaling-group-name cli-workshop-asg \
    --launch-template LaunchTemplateId=${LT_ID},Version='$Default' \
    --min-size 2 \
    --max-size 4 \
    --desired-capacity 2 \
    --vpc-zone-identifier "${SUBNET_1A_ID},${SUBNET_1C_ID}" \
    --target-group-arns ${TG_ARN} \
    --health-check-type ELB \
    --health-check-grace-period 300 \
    --region ${AWS_REGION}
echo "  ASG 作成完了"

rm -f /tmp/userdata.sh

# --- 完了 ---
ALB_DNS=$(aws elbv2 describe-load-balancers \
    --names cli-workshop-alb \
    --query "LoadBalancers[].DNSName" \
    --region ${AWS_REGION} \
    --output text)

echo ""
echo "=============================="
echo " 全リソース作成完了"
echo "=============================="
echo ""
echo " ALB URL: http://${ALB_DNS}"
echo ""
echo " ※ EC2 の起動・ヘルスチェック完了まで 2〜3 分かかります"
echo ""
