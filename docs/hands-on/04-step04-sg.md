# [0401] ALB 用 Security Group を作成する

## About

ALB（Application Load Balancer）用のセキュリティグループを作成する CLI 手順書。

本手順では、インターネットからの HTTP（ポート 80）アクセスを許可するセキュリティグループを作成する。

## When: 作業の条件

### Before: 事前前提条件

以下を作業の前提条件とする。
1. VPC が作成済みである（Step 01 完了）。

### After: 作業終了状況

以下が完了の条件。
1. ALB 用セキュリティグループが作成されている。
2. インバウンドルールで TCP ポート 80 が `0.0.0.0/0` から許可されている。

## How: 以下は作業手順

### 1. 前処理

#### 1.1 処理パラメータの準備

パラメータの事後確認用ファイルの設定

```bash
RUNBOOK_TITLE="0401-create-alb-sg"
DIR_PARAMETER="."
FILE_PARAMETER="${DIR_PARAMETER}/$(date +%Y-%m-%d)-${RUNBOOK_TITLE}.env" \
    && echo ${FILE_PARAMETER}
```

手順の実行パラメータ

```bash
# 変数に値をセット
AWS_REGION="ap-northeast-1"
VPC_CIDR="10.0.0.0/16"
ALB_SG_NAME="cli-workshop-alb-sg"
ALB_SG_DESCRIPTION="Security group for ALB - allows HTTP from internet"
```

```bash
# 値を確認
cat << ETX
    AWS_REGION=${AWS_REGION}
    VPC_CIDR=${VPC_CIDR}
    ALB_SG_NAME=${ALB_SG_NAME}
    ALB_SG_DESCRIPTION=${ALB_SG_DESCRIPTION}

ETX
```

#### 1.2 事前条件の確認

VPC ID を取得する。

```bash
VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=cidr,Values=${VPC_CIDR}" \
    --query "Vpcs[].VpcId" \
    --region ${AWS_REGION} \
    --output text) && echo ${VPC_ID}
```

出力例

```output
vpc-0a1b2c3d4eEXAMPLE
```

### 2. 主処理

#### 2.1 リソースの操作 (CREATE)

パラメータの最終確認

```bash
cat << EOF > ${FILE_PARAMETER}
aws ec2 create-security-group \
    --group-name ${ALB_SG_NAME} \
    --description "${ALB_SG_DESCRIPTION}" \
    --vpc-id ${VPC_ID} \
    --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=${ALB_SG_NAME}}]' \
    --region ${AWS_REGION}

EOF
cat ${FILE_PARAMETER}
```

セキュリティグループを作成する。

```bash
aws ec2 create-security-group \
    --group-name ${ALB_SG_NAME} \
    --description "${ALB_SG_DESCRIPTION}" \
    --vpc-id ${VPC_ID} \
    --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=${ALB_SG_NAME}}]' \
    --region ${AWS_REGION}
```

結果の例

```output
{
    "GroupId": "sg-0a1b2c3d4eEXAMPLE"
}
```

> **補足**: `create-security-group` のレスポンスは GroupId だけ返る。他の create 系コマンドと比べるとシンプル。

セキュリティグループ ID をシェル変数に格納する。

```bash
ALB_SG_ID=$(aws ec2 describe-security-groups \
    --filters \
        "Name=vpc-id,Values=${VPC_ID}" \
        "Name=group-name,Values=${ALB_SG_NAME}" \
    --query "SecurityGroups[].GroupId" \
    --region ${AWS_REGION} \
    --output text) && echo ${ALB_SG_ID}
```

出力例

```output
sg-0a1b2c3d4eEXAMPLE
```

#### 2.2 インバウンドルールの追加

インターネットからの HTTP（ポート 80）アクセスを許可するルールを追加する。

```bash
aws ec2 authorize-security-group-ingress \
    --group-id ${ALB_SG_ID} \
    --protocol tcp \
    --port 80 \
    --cidr "0.0.0.0/0" \
    --region ${AWS_REGION}
```

結果の例

```output
{
    "Return": true,
    "SecurityGroupRules": [
        {
            "SecurityGroupRuleId": "sgr-0a1b2c3d4eEXAMPLE",
            "GroupId": "sg-0a1b2c3d4eEXAMPLE",
            "GroupOwnerId": "123456789012",
            "IsEgress": false,
            "IpProtocol": "tcp",
            "FromPort": 80,
            "ToPort": 80,
            "CidrIpv4": "0.0.0.0/0"
        }
    ]
}
```

### 3. 後処理

#### 3.1 完了条件の結果確認

セキュリティグループとインバウンドルールを確認する。

```bash
aws ec2 describe-security-groups \
    --group-ids ${ALB_SG_ID} \
    --query "SecurityGroups[].[GroupId, GroupName, IpPermissions]" \
    --region ${AWS_REGION}
```

結果の例

```output
[
    [
        "sg-0a1b2c3d4eEXAMPLE",
        "cli-workshop-alb-sg",
        [
            {
                "FromPort": 80,
                "IpProtocol": "tcp",
                "IpRanges": [
                    {
                        "CidrIp": "0.0.0.0/0"
                    }
                ],
                "Ipv6Ranges": [],
                "PrefixListIds": [],
                "ToPort": 80,
                "UserIdGroupPairs": []
            }
        ]
    ]
]
```

TCP ポート 80 が `0.0.0.0/0` から許可されていれば期待通り。

#### 3.99 中間リソースの削除

今回は特になし。

#### Navigation

Next: [EC2 用 Security Group を作成する](./04-step04-sg.md#0402-ec2-用-security-group-を作成する)

---

# [0402] EC2 用 Security Group を作成する

## About

EC2（Web サーバー）用のセキュリティグループを作成する CLI 手順書。

本手順では、ALB からのみ HTTP（ポート 80）アクセスを許可するセキュリティグループを作成する。
インターネットから EC2 に直接アクセスすることはできず、必ず ALB を経由する構成になる。

## When: 作業の条件

### Before: 事前前提条件

以下を作業の前提条件とする。
1. VPC が作成済みである。
2. ALB 用セキュリティグループが作成済みである（Step 0401 完了）。

### After: 作業終了状況

以下が完了の条件。
1. EC2 用セキュリティグループが作成されている。
2. インバウンドルールで TCP ポート 80 が ALB セキュリティグループからのみ許可されている。

## How: 以下は作業手順

### 1. 前処理

#### 1.1 処理パラメータの準備

パラメータの事後確認用ファイルの設定

```bash
RUNBOOK_TITLE="0402-create-web-sg"
DIR_PARAMETER="."
FILE_PARAMETER="${DIR_PARAMETER}/$(date +%Y-%m-%d)-${RUNBOOK_TITLE}.env" \
    && echo ${FILE_PARAMETER}
```

手順の実行パラメータ

```bash
# 変数に値をセット
AWS_REGION="ap-northeast-1"
VPC_CIDR="10.0.0.0/16"
WEB_SG_NAME="cli-workshop-web-sg"
WEB_SG_DESCRIPTION="Security group for EC2 - allows HTTP from ALB only"
ALB_SG_NAME="cli-workshop-alb-sg"
```

```bash
# 値を確認
cat << ETX
    AWS_REGION=${AWS_REGION}
    VPC_CIDR=${VPC_CIDR}
    WEB_SG_NAME=${WEB_SG_NAME}
    WEB_SG_DESCRIPTION=${WEB_SG_DESCRIPTION}
    ALB_SG_NAME=${ALB_SG_NAME}

ETX
```

#### 1.2 事前条件の確認

VPC ID と ALB SG ID を取得する。

```bash
VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=cidr,Values=${VPC_CIDR}" \
    --query "Vpcs[].VpcId" \
    --region ${AWS_REGION} \
    --output text) && echo ${VPC_ID}
```

```bash
ALB_SG_ID=$(aws ec2 describe-security-groups \
    --filters \
        "Name=vpc-id,Values=${VPC_ID}" \
        "Name=group-name,Values=${ALB_SG_NAME}" \
    --query "SecurityGroups[].GroupId" \
    --region ${AWS_REGION} \
    --output text) && echo ${ALB_SG_ID}
```

出力例

```output
sg-0a1b2c3d4eEXAMPLE
```

ALB SG ID が表示されれば、期待通り。

### 2. 主処理

#### 2.1 リソースの操作 (CREATE)

パラメータの最終確認

```bash
cat << EOF > ${FILE_PARAMETER}
aws ec2 create-security-group \
    --group-name ${WEB_SG_NAME} \
    --description "${WEB_SG_DESCRIPTION}" \
    --vpc-id ${VPC_ID} \
    --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=${WEB_SG_NAME}}]' \
    --region ${AWS_REGION}

EOF
cat ${FILE_PARAMETER}
```

セキュリティグループを作成する。

```bash
aws ec2 create-security-group \
    --group-name ${WEB_SG_NAME} \
    --description "${WEB_SG_DESCRIPTION}" \
    --vpc-id ${VPC_ID} \
    --tag-specifications 'ResourceType=security-group,Tags=[{Key=Name,Value=${WEB_SG_NAME}}]' \
    --region ${AWS_REGION}
```

結果の例

```output
{
    "GroupId": "sg-0f1e2d3c4bEXAMPLE"
}
```

セキュリティグループ ID をシェル変数に格納する。

```bash
WEB_SG_ID=$(aws ec2 describe-security-groups \
    --filters \
        "Name=vpc-id,Values=${VPC_ID}" \
        "Name=group-name,Values=${WEB_SG_NAME}" \
    --query "SecurityGroups[].GroupId" \
    --region ${AWS_REGION} \
    --output text) && echo ${WEB_SG_ID}
```

出力例

```output
sg-0f1e2d3c4bEXAMPLE
```

#### 2.2 インバウンドルールの追加（SG 間参照）

ALB セキュリティグループからの HTTP（ポート 80）アクセスのみを許可する。

> **ポイント**: `--cidr` ではなく `--source-group` を使うことで、特定のセキュリティグループからのトラフィックのみを許可できる。これにより「ALB を経由したアクセスだけ許可する」という構成を実現する。

```bash
aws ec2 authorize-security-group-ingress \
    --group-id ${WEB_SG_ID} \
    --protocol tcp \
    --port 80 \
    --source-group ${ALB_SG_ID} \
    --region ${AWS_REGION}
```

結果の例

```output
{
    "Return": true,
    "SecurityGroupRules": [
        {
            "SecurityGroupRuleId": "sgr-0f1e2d3c4bEXAMPLE",
            "GroupId": "sg-0f1e2d3c4bEXAMPLE",
            "GroupOwnerId": "123456789012",
            "IsEgress": false,
            "IpProtocol": "tcp",
            "FromPort": 80,
            "ToPort": 80,
            "ReferencedGroupInfo": {
                "GroupId": "sg-0a1b2c3d4eEXAMPLE"
            }
        }
    ]
}
```

`ReferencedGroupInfo` に ALB SG の ID が入っていれば、SG 間参照が正しく設定されている。

### 3. 後処理

#### 3.1 完了条件の結果確認

EC2 用セキュリティグループのインバウンドルールを確認する。

```bash
aws ec2 describe-security-groups \
    --group-ids ${WEB_SG_ID} \
    --query "SecurityGroups[].IpPermissions" \
    --region ${AWS_REGION}
```

結果の例

```output
[
    [
        {
            "FromPort": 80,
            "IpProtocol": "tcp",
            "IpRanges": [],
            "Ipv6Ranges": [],
            "PrefixListIds": [],
            "ToPort": 80,
            "UserIdGroupPairs": [
                {
                    "GroupId": "sg-0a1b2c3d4eEXAMPLE",
                    "UserId": "123456789012"
                }
            ]
        }
    ]
]
```

- `IpRanges` が空（CIDR による許可なし）
- `UserIdGroupPairs` に ALB SG の ID がある（SG 間参照による許可）

であれば期待通り。

#### 3.2 ネットワーク編の完了確認

ここまでで、ネットワーク編（Step 01〜04）が完了。作成したリソースを一覧で確認する。

```bash
cat << ETX
    === ネットワーク編 完了 ===
    VPC ID:        ${VPC_ID}
    Subnet 1a ID:  $(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=cli-workshop-public-1a" --query "Subnets[].SubnetId" --region ${AWS_REGION} --output text)
    Subnet 1c ID:  $(aws ec2 describe-subnets --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=cli-workshop-public-1c" --query "Subnets[].SubnetId" --region ${AWS_REGION} --output text)
    IGW ID:        $(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=${VPC_ID}" --query "InternetGateways[].InternetGatewayId" --region ${AWS_REGION} --output text)
    RouteTable ID: $(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=cli-workshop-public-rt" --query "RouteTables[].RouteTableId" --region ${AWS_REGION} --output text)
    ALB SG ID:     ${ALB_SG_ID}
    Web SG ID:     ${WEB_SG_ID}

ETX
```

すべての ID が表示されていれば、ネットワーク編は完了。次はアプリケーション編に進む。

#### 3.99 中間リソースの削除

今回は特になし。

#### Navigation

Next: [IAM Role を作成する](./05-step05-iam.md)

# EOD
