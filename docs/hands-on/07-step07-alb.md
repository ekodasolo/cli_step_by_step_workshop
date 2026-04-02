# [0701] ALB を作成する

## About

Application Load Balancer（ALB）を作成する CLI 手順書。

ALB はインターネットからの HTTP リクエストを受け付け、背後の EC2 インスタンスに振り分ける。
本手順では ALB を作成し、作成完了を `wait` で待つ。

> **補足**: ALB は 3 つの要素で構成される。
> 1. **ALB 本体**: リクエストを受け付けるエンドポイント（DNS 名が払い出される）
> 2. **Target Group**: リクエストの転送先（EC2 インスタンスのグループ）
> 3. **Listener**: ALB のポートと Target Group を紐付けるルール
>
> この 3 つを順番に作成し、最後にターゲット（EC2）を登録する。

## When: 作業の条件

### Before: 事前前提条件

以下を作業の前提条件とする。
1. ネットワーク編が完了している（Step 01〜04）。
2. EC2 インスタンスが起動済みである（Step 06 完了）。

### After: 作業終了状況

以下が完了の条件。
1. ALB が作成され、`active` 状態になっている。
2. Target Group が作成されている。
3. Listener が作成されている。
4. EC2 インスタンスがターゲットとして登録されている。
5. ALB の DNS 名でブラウザからカレンダーページにアクセスできる。

## How: 以下は作業手順

### 1. 前処理

#### 1.1 処理パラメータの準備

パラメータの事後確認用ファイルの設定

```bash
RUNBOOK_TITLE="0701-create-alb"
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
ALB_NAME="cli-workshop-alb"
TG_NAME="cli-workshop-tg"
ALB_SG_NAME="cli-workshop-alb-sg"
INSTANCE_NAME="cli-workshop-web-server"
```

```bash
# 値を確認
cat << ETX
    AWS_REGION=${AWS_REGION}
    VPC_CIDR=${VPC_CIDR}
    ALB_NAME=${ALB_NAME}
    TG_NAME=${TG_NAME}
    ALB_SG_NAME=${ALB_SG_NAME}
    INSTANCE_NAME=${INSTANCE_NAME}

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
ALB_SG_ID=$(aws ec2 describe-security-groups \
    --filters \
        "Name=vpc-id,Values=${VPC_ID}" \
        "Name=group-name,Values=${ALB_SG_NAME}" \
    --query "SecurityGroups[].GroupId" \
    --region ${AWS_REGION} \
    --output text) && echo "ALB_SG_ID=${ALB_SG_ID}"
```

```bash
INSTANCE_ID=$(aws ec2 describe-instances \
    --filters \
        "Name=tag:Name,Values=${INSTANCE_NAME}" \
        "Name=instance-state-name,Values=running" \
    --query "Reservations[].Instances[].InstanceId" \
    --region ${AWS_REGION} \
    --output text) && echo "INSTANCE_ID=${INSTANCE_ID}"
```

すべての ID が表示されれば、期待通り。

### 2. 主処理

#### 2.1 ALB の作成

パラメータの最終確認

```bash
cat << EOF > ${FILE_PARAMETER}
aws elbv2 create-load-balancer \
    --name ${ALB_NAME} \
    --subnets ${SUBNET_1A_ID} ${SUBNET_1C_ID} \
    --security-groups ${ALB_SG_ID} \
    --scheme internet-facing \
    --type application \
    --tags Key=Name,Value=${ALB_NAME} \
    --region ${AWS_REGION}

EOF
cat ${FILE_PARAMETER}
```

ALB を作成する。

```bash
aws elbv2 create-load-balancer \
    --name ${ALB_NAME} \
    --subnets ${SUBNET_1A_ID} ${SUBNET_1C_ID} \
    --security-groups ${ALB_SG_ID} \
    --scheme internet-facing \
    --type application \
    --tags Key=Name,Value=${ALB_NAME} \
    --region ${AWS_REGION}
```

結果の例

```output
{
    "LoadBalancers": [
        {
            "LoadBalancerArn": "arn:aws:elasticloadbalancing:ap-northeast-1:123456789012:loadbalancer/app/cli-workshop-alb/0a1b2c3d4eEXAMPLE",
            "DNSName": "cli-workshop-alb-123456789.ap-northeast-1.elb.amazonaws.com",
            "CanonicalHostedZoneId": "Z14GRHDCWA56QT",
            "CreatedTime": "2026-04-02T10:20:00+00:00",
            "LoadBalancerName": "cli-workshop-alb",
            "Scheme": "internet-facing",
            "VpcId": "vpc-0a1b2c3d4eEXAMPLE",
            "State": {
                "Code": "provisioning"
            },
            "Type": "application",
            "AvailabilityZones": [
                {
                    "ZoneName": "ap-northeast-1a",
                    "SubnetId": "subnet-0a1b2c3d4eEXAMPLE"
                },
                {
                    "ZoneName": "ap-northeast-1c",
                    "SubnetId": "subnet-0f1e2d3c4bEXAMPLE"
                }
            ],
            "SecurityGroups": [
                "sg-0a1b2c3d4eEXAMPLE"
            ],
            "IpAddressType": "ipv4"
        }
    ]
}
```

> **注目**: 作成直後の `State.Code` は `provisioning`。`active` になるまで数分かかる。

ALB ARN をシェル変数に格納する。

```bash
ALB_ARN=$(aws elbv2 describe-load-balancers \
    --names ${ALB_NAME} \
    --query "LoadBalancers[].LoadBalancerArn" \
    --region ${AWS_REGION} \
    --output text) && echo ${ALB_ARN}
```

#### 2.2 ALB の作成完了を待つ

```bash
echo "ALB の作成完了を待っています（2〜3 分かかります）..."
aws elbv2 wait load-balancer-available \
    --load-balancer-arns ${ALB_ARN} \
    --region ${AWS_REGION}
echo "ALB が利用可能になりました。"
```

#### 2.3 Target Group の作成

```bash
aws elbv2 create-target-group \
    --name ${TG_NAME} \
    --protocol HTTP \
    --port 80 \
    --vpc-id ${VPC_ID} \
    --target-type instance \
    --health-check-protocol HTTP \
    --health-check-path / \
    --health-check-interval-seconds 30 \
    --healthy-threshold-count 2 \
    --unhealthy-threshold-count 5 \
    --tags Key=Name,Value=${TG_NAME} \
    --region ${AWS_REGION}
```

結果の例

```output
{
    "TargetGroups": [
        {
            "TargetGroupArn": "arn:aws:elasticloadbalancing:ap-northeast-1:123456789012:targetgroup/cli-workshop-tg/0a1b2c3d4eEXAMPLE",
            "TargetGroupName": "cli-workshop-tg",
            "Protocol": "HTTP",
            "Port": 80,
            "VpcId": "vpc-0a1b2c3d4eEXAMPLE",
            "HealthCheckProtocol": "HTTP",
            "HealthCheckPort": "traffic-port",
            "HealthCheckEnabled": true,
            "HealthCheckIntervalSeconds": 30,
            "HealthCheckTimeoutSeconds": 5,
            "HealthyThresholdCount": 2,
            "UnhealthyThresholdCount": 5,
            "HealthCheckPath": "/",
            "TargetType": "instance"
        }
    ]
}
```

Target Group ARN をシェル変数に格納する。

```bash
TG_ARN=$(aws elbv2 describe-target-groups \
    --names ${TG_NAME} \
    --query "TargetGroups[].TargetGroupArn" \
    --region ${AWS_REGION} \
    --output text) && echo ${TG_ARN}
```

#### 2.4 Listener の作成

ALB のポート 80 で受けたリクエストを Target Group に転送するリスナーを作成する。

```bash
aws elbv2 create-listener \
    --load-balancer-arn ${ALB_ARN} \
    --protocol HTTP \
    --port 80 \
    --default-actions Type=forward,TargetGroupArn=${TG_ARN} \
    --region ${AWS_REGION}
```

結果の例

```output
{
    "Listeners": [
        {
            "ListenerArn": "arn:aws:elasticloadbalancing:ap-northeast-1:123456789012:listener/app/cli-workshop-alb/0a1b2c3d4eEXAMPLE/0f1e2d3c4bEXAMPLE",
            "LoadBalancerArn": "arn:aws:elasticloadbalancing:ap-northeast-1:123456789012:loadbalancer/app/cli-workshop-alb/0a1b2c3d4eEXAMPLE",
            "Port": 80,
            "Protocol": "HTTP",
            "DefaultActions": [
                {
                    "Type": "forward",
                    "TargetGroupArn": "arn:aws:elasticloadbalancing:ap-northeast-1:123456789012:targetgroup/cli-workshop-tg/0a1b2c3d4eEXAMPLE"
                }
            ]
        }
    ]
}
```

#### 2.5 ターゲットの登録

EC2 インスタンスを Target Group に登録する。

```bash
aws elbv2 register-targets \
    --target-group-arn ${TG_ARN} \
    --targets Id=${INSTANCE_ID} \
    --region ${AWS_REGION}
```

このコマンドは成功しても出力がない（サイレント）。

### 3. 後処理

#### 3.1 ターゲットのヘルスチェック確認

ターゲットが `healthy` になるまで待つ。ヘルスチェックには 30 秒〜1 分程度かかる。

```bash
echo "ヘルスチェックの結果を確認しています..."
aws elbv2 describe-target-health \
    --target-group-arn ${TG_ARN} \
    --region ${AWS_REGION}
```

結果の例（healthy の場合）

```output
{
    "TargetHealthDescriptions": [
        {
            "Target": {
                "Id": "i-0a1b2c3d4eEXAMPLE",
                "Port": 80
            },
            "HealthCheckPort": "80",
            "TargetHealth": {
                "State": "healthy"
            }
        }
    ]
}
```

`State` が `initial`（まだチェック中）の場合は、30 秒ほど待ってから再実行する。
`healthy` になるまで繰り返す。

#### 3.2 ALB の DNS 名を取得してブラウザで確認

```bash
ALB_DNS=$(aws elbv2 describe-load-balancers \
    --names ${ALB_NAME} \
    --query "LoadBalancers[].DNSName" \
    --region ${AWS_REGION} \
    --output text) && echo "http://${ALB_DNS}"
```

出力例

```output
http://cli-workshop-alb-123456789.ap-northeast-1.elb.amazonaws.com
```

表示された URL をブラウザで開き、カレンダーページが表示されれば成功。

> **確認ポイント**:
> - タイトルが「AWS CLI Workshop」になっている
> - Instance ID と Private IP が表示されている
> - カレンダーが当月のものになっている

#### 3.99 中間リソースの削除

今回は特になし。

#### Navigation

Next: [Launch Template + ASG を作成する](./08-step08-asg.md)

# EOD
