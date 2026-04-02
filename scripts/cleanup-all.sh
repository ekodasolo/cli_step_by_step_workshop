#!/bin/bash
# 講師用: ワークショップの全リソースを一括削除するスクリプト
# 依存関係の逆順で削除する。
set -euo pipefail

echo "=============================="
echo " CLI Workshop - 一括削除"
echo "=============================="

AWS_REGION="ap-northeast-1"
VPC_CIDR="10.0.0.0/16"

# --- ID 取得 ---
echo ""
echo "リソース ID を取得中..."

VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=cidr,Values=${VPC_CIDR}" \
    --query "Vpcs[].VpcId" \
    --region ${AWS_REGION} \
    --output text)

if [ -z "${VPC_ID}" ]; then
    echo "VPC が見つかりません。既に削除済みの可能性があります。"
    exit 0
fi
echo "  VPC_ID=${VPC_ID}"

# --- Step 1: ASG 削除 ---
echo ""
echo "[1/11] Auto Scaling Group を削除..."
ASG_NAME="cli-workshop-asg"
if aws autoscaling describe-auto-scaling-groups \
    --auto-scaling-group-names ${ASG_NAME} \
    --query "AutoScalingGroups[].AutoScalingGroupName" \
    --region ${AWS_REGION} \
    --output text 2>/dev/null | grep -q "${ASG_NAME}"; then
    aws autoscaling delete-auto-scaling-group \
        --auto-scaling-group-name ${ASG_NAME} \
        --force-delete \
        --region ${AWS_REGION}
    echo "  ASG 削除開始。インスタンス終了を待っています..."
    sleep 30
    # インスタンスの終了を待つ
    while true; do
        RUNNING=$(aws ec2 describe-instances \
            --filters \
                "Name=tag:aws:autoscaling:groupName,Values=${ASG_NAME}" \
                "Name=instance-state-name,Values=running,shutting-down,pending" \
            --query "Reservations[].Instances[].InstanceId" \
            --region ${AWS_REGION} \
            --output text)
        if [ -z "${RUNNING}" ]; then
            break
        fi
        echo "  まだ終了中... (${RUNNING})"
        sleep 10
    done
    echo "  ASG 削除完了"
else
    echo "  ASG は存在しません。スキップ。"
fi

# --- Step 2: Launch Template 削除 ---
echo ""
echo "[2/11] Launch Template を削除..."
LT_NAME="cli-workshop-lt"
LT_ID=$(aws ec2 describe-launch-templates \
    --launch-template-names ${LT_NAME} \
    --query "LaunchTemplates[].LaunchTemplateId" \
    --region ${AWS_REGION} \
    --output text 2>/dev/null) || true
if [ -n "${LT_ID}" ]; then
    aws ec2 delete-launch-template \
        --launch-template-id ${LT_ID} \
        --region ${AWS_REGION} > /dev/null
    echo "  削除完了"
else
    echo "  存在しません。スキップ。"
fi

# --- Step 3: ALB Listener 削除 ---
echo ""
echo "[3/11] ALB Listener を削除..."
ALB_NAME="cli-workshop-alb"
ALB_ARN=$(aws elbv2 describe-load-balancers \
    --names ${ALB_NAME} \
    --query "LoadBalancers[].LoadBalancerArn" \
    --region ${AWS_REGION} \
    --output text 2>/dev/null) || true
if [ -n "${ALB_ARN}" ]; then
    LISTENER_ARNS=$(aws elbv2 describe-listeners \
        --load-balancer-arn ${ALB_ARN} \
        --query "Listeners[].ListenerArn" \
        --region ${AWS_REGION} \
        --output text 2>/dev/null) || true
    for LISTENER_ARN in ${LISTENER_ARNS}; do
        aws elbv2 delete-listener \
            --listener-arn ${LISTENER_ARN} \
            --region ${AWS_REGION}
        echo "  Listener 削除: ${LISTENER_ARN}"
    done
else
    echo "  ALB が存在しません。スキップ。"
fi

# --- Step 4: ALB 削除 ---
echo ""
echo "[4/11] ALB を削除..."
if [ -n "${ALB_ARN}" ]; then
    aws elbv2 delete-load-balancer \
        --load-balancer-arn ${ALB_ARN} \
        --region ${AWS_REGION}
    echo "  ALB 削除開始。完了を待っています..."
    aws elbv2 wait load-balancers-deleted \
        --load-balancer-arns ${ALB_ARN} \
        --region ${AWS_REGION}
    echo "  ALB 削除完了"
else
    echo "  存在しません。スキップ。"
fi

# --- Step 5: Target Group 削除 ---
echo ""
echo "[5/11] Target Group を削除..."
TG_NAME="cli-workshop-tg"
TG_ARN=$(aws elbv2 describe-target-groups \
    --names ${TG_NAME} \
    --query "TargetGroups[].TargetGroupArn" \
    --region ${AWS_REGION} \
    --output text 2>/dev/null) || true
if [ -n "${TG_ARN}" ]; then
    aws elbv2 delete-target-group \
        --target-group-arn ${TG_ARN} \
        --region ${AWS_REGION}
    echo "  削除完了"
else
    echo "  存在しません。スキップ。"
fi

# --- Step 6: 単体 EC2 がまだあれば削除 ---
echo ""
echo "[6/11] 残存 EC2 インスタンスを確認..."
REMAINING_INSTANCES=$(aws ec2 describe-instances \
    --filters \
        "Name=vpc-id,Values=${VPC_ID}" \
        "Name=instance-state-name,Values=running,pending,stopping,stopped" \
    --query "Reservations[].Instances[].InstanceId" \
    --region ${AWS_REGION} \
    --output text) || true
if [ -n "${REMAINING_INSTANCES}" ]; then
    echo "  残存インスタンスを終了: ${REMAINING_INSTANCES}"
    aws ec2 terminate-instances \
        --instance-ids ${REMAINING_INSTANCES} \
        --region ${AWS_REGION} > /dev/null
    echo "  終了を待っています..."
    aws ec2 wait instance-terminated \
        --instance-ids ${REMAINING_INSTANCES} \
        --region ${AWS_REGION}
    echo "  終了完了"
else
    echo "  残存インスタンスなし。スキップ。"
fi

# --- Step 7: IAM 削除 ---
echo ""
echo "[7/11] IAM を削除..."
ROLE_NAME="cli-workshop-web-server-role"
INSTANCE_PROFILE_NAME="cli-workshop-web-server-profile"

if aws iam get-instance-profile --instance-profile-name ${INSTANCE_PROFILE_NAME} 2>/dev/null; then
    aws iam remove-role-from-instance-profile \
        --instance-profile-name ${INSTANCE_PROFILE_NAME} \
        --role-name ${ROLE_NAME} 2>/dev/null || true
    aws iam delete-instance-profile \
        --instance-profile-name ${INSTANCE_PROFILE_NAME}
    echo "  Instance Profile 削除完了"
else
    echo "  Instance Profile は存在しません。"
fi

if aws iam get-role --role-name ${ROLE_NAME} 2>/dev/null; then
    aws iam detach-role-policy \
        --role-name ${ROLE_NAME} \
        --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore 2>/dev/null || true
    aws iam delete-role \
        --role-name ${ROLE_NAME}
    echo "  IAM ロール削除完了"
else
    echo "  IAM ロールは存在しません。"
fi

# --- Step 8: Security Groups 削除 ---
echo ""
echo "[8/11] Security Group を削除..."
WEB_SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=vpc-id,Values=${VPC_ID}" "Name=group-name,Values=cli-workshop-web-sg" \
    --query "SecurityGroups[].GroupId" \
    --region ${AWS_REGION} \
    --output text 2>/dev/null) || true
if [ -n "${WEB_SG_ID}" ]; then
    aws ec2 delete-security-group --group-id ${WEB_SG_ID} --region ${AWS_REGION}
    echo "  EC2 用 SG 削除完了"
fi

ALB_SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=vpc-id,Values=${VPC_ID}" "Name=group-name,Values=cli-workshop-alb-sg" \
    --query "SecurityGroups[].GroupId" \
    --region ${AWS_REGION} \
    --output text 2>/dev/null) || true
if [ -n "${ALB_SG_ID}" ]; then
    aws ec2 delete-security-group --group-id ${ALB_SG_ID} --region ${AWS_REGION}
    echo "  ALB 用 SG 削除完了"
fi

# --- Step 9: Route Table 削除 ---
echo ""
echo "[9/11] Route Table を削除..."
RT_ID=$(aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=cli-workshop-public-rt" \
    --query "RouteTables[].RouteTableId" \
    --region ${AWS_REGION} \
    --output text 2>/dev/null) || true
if [ -n "${RT_ID}" ]; then
    # 関連付け解除
    ASSOC_IDS=$(aws ec2 describe-route-tables \
        --route-table-ids ${RT_ID} \
        --query "RouteTables[].Associations[?!Main].RouteTableAssociationId" \
        --region ${AWS_REGION} \
        --output text) || true
    for ASSOC_ID in ${ASSOC_IDS}; do
        aws ec2 disassociate-route-table --association-id ${ASSOC_ID} --region ${AWS_REGION}
    done
    # ルート削除
    aws ec2 delete-route --route-table-id ${RT_ID} --destination-cidr-block "0.0.0.0/0" --region ${AWS_REGION} 2>/dev/null || true
    # テーブル削除
    aws ec2 delete-route-table --route-table-id ${RT_ID} --region ${AWS_REGION}
    echo "  削除完了"
else
    echo "  存在しません。スキップ。"
fi

# --- Step 10: IGW 削除 ---
echo ""
echo "[10/11] Internet Gateway を削除..."
IGW_ID=$(aws ec2 describe-internet-gateways \
    --filters "Name=attachment.vpc-id,Values=${VPC_ID}" \
    --query "InternetGateways[].InternetGatewayId" \
    --region ${AWS_REGION} \
    --output text 2>/dev/null) || true
if [ -n "${IGW_ID}" ]; then
    aws ec2 detach-internet-gateway --internet-gateway-id ${IGW_ID} --vpc-id ${VPC_ID} --region ${AWS_REGION}
    aws ec2 delete-internet-gateway --internet-gateway-id ${IGW_ID} --region ${AWS_REGION}
    echo "  削除完了"
else
    echo "  存在しません。スキップ。"
fi

# --- Step 11: Subnets + VPC 削除 ---
echo ""
echo "[11/11] Subnet + VPC を削除..."
for SUBNET_NAME in cli-workshop-public-1a cli-workshop-public-1c; do
    SUBNET_ID=$(aws ec2 describe-subnets \
        --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=${SUBNET_NAME}" \
        --query "Subnets[].SubnetId" \
        --region ${AWS_REGION} \
        --output text 2>/dev/null) || true
    if [ -n "${SUBNET_ID}" ]; then
        aws ec2 delete-subnet --subnet-id ${SUBNET_ID} --region ${AWS_REGION}
        echo "  ${SUBNET_NAME} 削除完了"
    fi
done

aws ec2 delete-vpc --vpc-id ${VPC_ID} --region ${AWS_REGION}
echo "  VPC 削除完了"

echo ""
echo "=============================="
echo " 全リソース削除完了"
echo "=============================="
