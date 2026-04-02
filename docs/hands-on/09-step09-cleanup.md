# [0901] クリーンアップ — 全リソースを削除する

## About

ワークショップで作成した全リソースを削除する CLI 手順書。

CLI で作成したリソースは、**依存関係の逆順で 1 つずつ削除する**必要がある。
CloudFormation ならスタック削除 1 回で完了するが、CLI では自分で順序を管理する。
これが CLI ならではの学びポイント。

> **重要**: 削除順序を間違えると `DependencyViolation` エラーが発生する。
> 例えば、サブネットに EC2 がまだ存在する状態でサブネットを削除しようとするとエラーになる。

## When: 作業の条件

### Before: 事前前提条件

以下を作業の前提条件とする。
1. ワークショップの全ステップ（Step 01〜08）が完了している。

### After: 作業終了状況

以下が完了の条件。
1. ワークショップで作成した全リソースが削除されている。
2. VPC が削除されている（最後に削除される）。

## How: 以下は作業手順

### 1. 前処理

#### 1.1 処理パラメータの準備

```bash
RUNBOOK_TITLE="0901-cleanup"
DIR_PARAMETER="."
FILE_PARAMETER="${DIR_PARAMETER}/$(date +%Y-%m-%d)-${RUNBOOK_TITLE}.env" \
    && echo ${FILE_PARAMETER}
```

```bash
# 変数に値をセット
AWS_REGION="ap-northeast-1"
VPC_CIDR="10.0.0.0/16"
```

#### 1.2 全リソースの ID を取得

削除対象のリソース ID をまとめて取得する。

```bash
# VPC
VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=cidr,Values=${VPC_CIDR}" \
    --query "Vpcs[].VpcId" \
    --region ${AWS_REGION} \
    --output text) && echo "VPC_ID=${VPC_ID}"
```

```bash
# ASG
ASG_NAME="cli-workshop-asg"
aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names ${ASG_NAME} \
    --query "AutoScalingGroups[].AutoScalingGroupName" \
    --region ${AWS_REGION} \
    --output text && echo "(ASG 確認OK)"
```

```bash
# Launch Template
LT_NAME="cli-workshop-lt"
LT_ID=$(aws ec2 describe-launch-templates \
    --launch-template-names ${LT_NAME} \
    --query "LaunchTemplates[].LaunchTemplateId" \
    --region ${AWS_REGION} \
    --output text) && echo "LT_ID=${LT_ID}"
```

```bash
# ALB
ALB_NAME="cli-workshop-alb"
ALB_ARN=$(aws elbv2 describe-load-balancers \
    --names ${ALB_NAME} \
    --query "LoadBalancers[].LoadBalancerArn" \
    --region ${AWS_REGION} \
    --output text) && echo "ALB_ARN=${ALB_ARN}"
```

```bash
# Listener ARN
LISTENER_ARN=$(aws elbv2 describe-listeners \
    --load-balancer-arn ${ALB_ARN} \
    --query "Listeners[].ListenerArn" \
    --region ${AWS_REGION} \
    --output text) && echo "LISTENER_ARN=${LISTENER_ARN}"
```

```bash
# Target Group
TG_NAME="cli-workshop-tg"
TG_ARN=$(aws elbv2 describe-target-groups \
    --names ${TG_NAME} \
    --query "TargetGroups[].TargetGroupArn" \
    --region ${AWS_REGION} \
    --output text) && echo "TG_ARN=${TG_ARN}"
```

```bash
# Security Groups
ALB_SG_ID=$(aws ec2 describe-security-groups \
    --filters \
        "Name=vpc-id,Values=${VPC_ID}" \
        "Name=group-name,Values=cli-workshop-alb-sg" \
    --query "SecurityGroups[].GroupId" \
    --region ${AWS_REGION} \
    --output text) && echo "ALB_SG_ID=${ALB_SG_ID}"

WEB_SG_ID=$(aws ec2 describe-security-groups \
    --filters \
        "Name=vpc-id,Values=${VPC_ID}" \
        "Name=group-name,Values=cli-workshop-web-sg" \
    --query "SecurityGroups[].GroupId" \
    --region ${AWS_REGION} \
    --output text) && echo "WEB_SG_ID=${WEB_SG_ID}"
```

```bash
# Route Table
RT_ID=$(aws ec2 describe-route-tables \
    --filters \
        "Name=vpc-id,Values=${VPC_ID}" \
        "Name=tag:Name,Values=cli-workshop-public-rt" \
    --query "RouteTables[].RouteTableId" \
    --region ${AWS_REGION} \
    --output text) && echo "RT_ID=${RT_ID}"
```

```bash
# IGW
IGW_ID=$(aws ec2 describe-internet-gateways \
    --filters "Name=attachment.vpc-id,Values=${VPC_ID}" \
    --query "InternetGateways[].InternetGatewayId" \
    --region ${AWS_REGION} \
    --output text) && echo "IGW_ID=${IGW_ID}"
```

```bash
# Subnets
SUBNET_1A_ID=$(aws ec2 describe-subnets \
    --filters \
        "Name=vpc-id,Values=${VPC_ID}" \
        "Name=tag:Name,Values=cli-workshop-public-1a" \
    --query "Subnets[].SubnetId" \
    --region ${AWS_REGION} \
    --output text) && echo "SUBNET_1A_ID=${SUBNET_1A_ID}"

SUBNET_1C_ID=$(aws ec2 describe-subnets \
    --filters \
        "Name=vpc-id,Values=${VPC_ID}" \
        "Name=tag:Name,Values=cli-workshop-public-1c" \
    --query "Subnets[].SubnetId" \
    --region ${AWS_REGION} \
    --output text) && echo "SUBNET_1C_ID=${SUBNET_1C_ID}"
```

```bash
# IAM
ROLE_NAME="cli-workshop-web-server-role"
INSTANCE_PROFILE_NAME="cli-workshop-web-server-profile"
```

全 ID を一覧で確認する。

```bash
cat << ETX
    === 削除対象リソース ===
    ASG_NAME:              ${ASG_NAME}
    LT_ID:                 ${LT_ID}
    LISTENER_ARN:          ${LISTENER_ARN}
    ALB_ARN:               ${ALB_ARN}
    TG_ARN:                ${TG_ARN}
    INSTANCE_PROFILE_NAME: ${INSTANCE_PROFILE_NAME}
    ROLE_NAME:             ${ROLE_NAME}
    WEB_SG_ID:             ${WEB_SG_ID}
    ALB_SG_ID:             ${ALB_SG_ID}
    RT_ID:                 ${RT_ID}
    IGW_ID:                ${IGW_ID}
    SUBNET_1A_ID:          ${SUBNET_1A_ID}
    SUBNET_1C_ID:          ${SUBNET_1C_ID}
    VPC_ID:                ${VPC_ID}

ETX
```

### 2. 主処理 — 逆順で削除

#### 2.1 Auto Scaling Group の削除

ASG を削除すると、管理下の EC2 インスタンスも自動的に終了される。

```bash
aws autoscaling delete-auto-scaling-group \
    --auto-scaling-group-name ${ASG_NAME} \
    --force-delete \
    --region ${AWS_REGION}
echo "ASG 削除を開始しました。インスタンスの終了を待っています..."
```

> **補足**: `--force-delete` を付けると、インスタンスを終了してから ASG を削除する。付けないと、DesiredCapacity を 0 にしてからでないと削除できない。

ASG 内のインスタンスが完全に終了するまで待つ。

```bash
echo "インスタンスの終了を待っています（1〜2 分）..."
aws ec2 wait instance-terminated \
    --filters \
        "Name=tag:aws:autoscaling:groupName,Values=${ASG_NAME}" \
        "Name=instance-state-name,Values=shutting-down,running" \
    --region ${AWS_REGION} 2>/dev/null || true
echo "完了。"
```

> **注意**: `wait` はインスタンスが見つからない場合にエラーを返すことがあるため `|| true` で吸収する。

#### 2.2 Launch Template の削除

```bash
aws ec2 delete-launch-template \
    --launch-template-id ${LT_ID} \
    --region ${AWS_REGION} \
    --query "LaunchTemplate.LaunchTemplateName" \
    --output text
```

出力例

```output
cli-workshop-lt
```

#### 2.3 ALB Listener の削除

```bash
aws elbv2 delete-listener \
    --listener-arn ${LISTENER_ARN} \
    --region ${AWS_REGION}
echo "Listener 削除完了"
```

#### 2.4 ALB の削除

```bash
aws elbv2 delete-load-balancer \
    --load-balancer-arn ${ALB_ARN} \
    --region ${AWS_REGION}
echo "ALB 削除を開始しました。完了を待っています..."
```

ALB の削除完了を待つ。

```bash
aws elbv2 wait load-balancers-deleted \
    --load-balancer-arns ${ALB_ARN} \
    --region ${AWS_REGION}
echo "ALB 削除完了。"
```

#### 2.5 Target Group の削除

```bash
aws elbv2 delete-target-group \
    --target-group-arn ${TG_ARN} \
    --region ${AWS_REGION}
echo "Target Group 削除完了"
```

#### 2.6 IAM の削除

IAM リソースは以下の順序で削除する必要がある:
1. Instance Profile からロールを除去
2. Instance Profile を削除
3. ロールからポリシーをデタッチ
4. ロールを削除

```bash
# 1. Instance Profile からロールを除去
aws iam remove-role-from-instance-profile \
    --instance-profile-name ${INSTANCE_PROFILE_NAME} \
    --role-name ${ROLE_NAME}
echo "Instance Profile からロール除去完了"
```

```bash
# 2. Instance Profile を削除
aws iam delete-instance-profile \
    --instance-profile-name ${INSTANCE_PROFILE_NAME}
echo "Instance Profile 削除完了"
```

```bash
# 3. ロールからポリシーをデタッチ
aws iam detach-role-policy \
    --role-name ${ROLE_NAME} \
    --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
echo "ポリシーデタッチ完了"
```

```bash
# 4. ロールを削除
aws iam delete-role \
    --role-name ${ROLE_NAME}
echo "IAM ロール削除完了"
```

#### 2.7 Security Group の削除

EC2 用 SG を先に削除する（ALB SG を参照しているため）。

> **補足**: EC2 用 SG のインバウンドルールが ALB SG を参照しているが、SG の削除時にルールも一緒に消えるので、先にルールを削除する必要はない。ただし、**参照されている側（ALB SG）を先に消そうとするとエラーになる**ため、EC2 SG → ALB SG の順で削除する。

```bash
aws ec2 delete-security-group \
    --group-id ${WEB_SG_ID} \
    --region ${AWS_REGION}
echo "EC2 用 SG 削除完了"
```

```bash
aws ec2 delete-security-group \
    --group-id ${ALB_SG_ID} \
    --region ${AWS_REGION}
echo "ALB 用 SG 削除完了"
```

#### 2.8 Route Table の削除

サブネットとの関連付けを解除してから、ルートを削除し、最後にルートテーブルを削除する。

```bash
# サブネットとの関連付けを解除
ASSOC_IDS=$(aws ec2 describe-route-tables \
    --route-table-ids ${RT_ID} \
    --query "RouteTables[].Associations[?!Main].RouteTableAssociationId" \
    --region ${AWS_REGION} \
    --output text)

for ASSOC_ID in ${ASSOC_IDS}; do
    aws ec2 disassociate-route-table \
        --association-id ${ASSOC_ID} \
        --region ${AWS_REGION}
    echo "関連付け解除: ${ASSOC_ID}"
done
```

```bash
# デフォルトルートを削除
aws ec2 delete-route \
    --route-table-id ${RT_ID} \
    --destination-cidr-block "0.0.0.0/0" \
    --region ${AWS_REGION}
echo "デフォルトルート削除完了"
```

```bash
# ルートテーブルを削除
aws ec2 delete-route-table \
    --route-table-id ${RT_ID} \
    --region ${AWS_REGION}
echo "RouteTable 削除完了"
```

#### 2.9 Internet Gateway の削除

IGW を VPC からデタッチしてから削除する。

```bash
# IGW を VPC からデタッチ
aws ec2 detach-internet-gateway \
    --internet-gateway-id ${IGW_ID} \
    --vpc-id ${VPC_ID} \
    --region ${AWS_REGION}
echo "IGW デタッチ完了"
```

```bash
# IGW を削除
aws ec2 delete-internet-gateway \
    --internet-gateway-id ${IGW_ID} \
    --region ${AWS_REGION}
echo "IGW 削除完了"
```

#### 2.10 Subnet の削除

```bash
aws ec2 delete-subnet \
    --subnet-id ${SUBNET_1A_ID} \
    --region ${AWS_REGION}
echo "Subnet 1a 削除完了"
```

```bash
aws ec2 delete-subnet \
    --subnet-id ${SUBNET_1C_ID} \
    --region ${AWS_REGION}
echo "Subnet 1c 削除完了"
```

#### 2.11 VPC の削除

最後に VPC を削除する。VPC 内のリソースがすべて削除されていないとエラーになる。

```bash
aws ec2 delete-vpc \
    --vpc-id ${VPC_ID} \
    --region ${AWS_REGION}
echo "VPC 削除完了"
```

### 3. 後処理

#### 3.1 完了条件の結果確認

VPC が削除されていることを確認する。

```bash
aws ec2 describe-vpcs \
    --filters "Name=cidr,Values=${VPC_CIDR}" \
    --query "Vpcs[].VpcId" \
    --region ${AWS_REGION} \
    --output text
```

何も表示されなければ、VPC は削除されている。

IAM リソースが削除されていることを確認する。

```bash
aws iam get-role --role-name ${ROLE_NAME} 2>&1 || true
```

`NoSuchEntity` エラーが返れば、ロールは削除されている。

```bash
cat << ETX

    ==============================
    クリーンアップ完了
    全リソースが削除されました。
    ==============================

ETX
```

#### 3.2 削除した .env ファイルの確認

ワークショップ中に作成したパラメータ確認用ファイルが残っている場合は削除する。

```bash
ls -la *.env 2>/dev/null && echo "上記の .env ファイルを削除してください" || echo ".env ファイルはありません"
```

```bash
# 必要に応じて削除
rm -f *.env
```

#### 3.99 中間リソースの削除

今回は特になし。

#### Navigation

お疲れさまでした。[ハンズオン概要](./00-overview.md) に戻る。

# EOD
