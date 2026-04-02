# [0301] Internet Gateway を作成・アタッチする

## About

Internet Gateway（IGW）を作成し、VPC にアタッチする CLI 手順書。

IGW を VPC にアタッチすることで、VPC 内のリソースがインターネットと通信できるようになる。

## When: 作業の条件

### Before: 事前前提条件

以下を作業の前提条件とする。
1. VPC が作成済みである（Step 01 完了）。
2. VPC に IGW がアタッチされていない。

### After: 作業終了状況

以下が完了の条件。
1. IGW が作成されている。
2. IGW が VPC にアタッチされている。

## How: 以下は作業手順

### 1. 前処理

#### 1.1 処理パラメータの準備

パラメータの事後確認用ファイルの設定

```bash
RUNBOOK_TITLE="0301-create-igw"
DIR_PARAMETER="."
FILE_PARAMETER="${DIR_PARAMETER}/$(date +%Y-%m-%d)-${RUNBOOK_TITLE}.env" \
    && echo ${FILE_PARAMETER}
```

手順の実行パラメータ

```bash
# 変数に値をセット
AWS_REGION="ap-northeast-1"
VPC_CIDR="10.0.0.0/16"
IGW_NAME="cli-workshop-igw"
```

```bash
# 値を確認
cat << ETX
    AWS_REGION=${AWS_REGION}
    VPC_CIDR=${VPC_CIDR}
    IGW_NAME=${IGW_NAME}

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

VPC に IGW がアタッチされていないことを確認する。

```bash
aws ec2 describe-internet-gateways \
    --filters "Name=attachment.vpc-id,Values=${VPC_ID}" \
    --region ${AWS_REGION}
```

結果の例

```output
{
    "InternetGateways": []
}
```

`InternetGateways` が空であれば、期待通り。

### 2. 主処理

#### 2.1 リソースの操作 (CREATE)

パラメータの最終確認

```bash
cat << EOF > ${FILE_PARAMETER}
aws ec2 create-internet-gateway \
    --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=${IGW_NAME}}]' \
    --region ${AWS_REGION}

EOF
cat ${FILE_PARAMETER}
```

IGW を作成する。

```bash
aws ec2 create-internet-gateway \
    --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=${IGW_NAME}}]' \
    --region ${AWS_REGION}
```

結果の例

```output
{
    "InternetGateway": {
        "Attachments": [],
        "InternetGatewayId": "igw-0a1b2c3d4eEXAMPLE",
        "OwnerId": "123456789012",
        "Tags": [
            {
                "Key": "Name",
                "Value": "cli-workshop-igw"
            }
        ]
    }
}
```

IGW ID をシェル変数に格納する。

```bash
IGW_ID=$(aws ec2 describe-internet-gateways \
    --filters "Name=tag:Name,Values=${IGW_NAME}" \
    --query "InternetGateways[].InternetGatewayId" \
    --region ${AWS_REGION} \
    --output text) && echo ${IGW_ID}
```

出力例

```output
igw-0a1b2c3d4eEXAMPLE
```

#### 2.2 IGW を VPC にアタッチ

```bash
aws ec2 attach-internet-gateway \
    --internet-gateway-id ${IGW_ID} \
    --vpc-id ${VPC_ID} \
    --region ${AWS_REGION}
```

このコマンドは成功しても出力がない（サイレント）。

### 3. 後処理

#### 3.1 完了条件の結果確認

IGW が VPC にアタッチされていることを確認する。

```bash
aws ec2 describe-internet-gateways \
    --internet-gateway-ids ${IGW_ID} \
    --query "InternetGateways[].Attachments" \
    --region ${AWS_REGION}
```

結果の例

```output
[
    [
        {
            "State": "available",
            "VpcId": "vpc-0a1b2c3d4eEXAMPLE"
        }
    ]
]
```

`State` が `available` で、`VpcId` が自分の VPC であれば期待通り。

#### 3.99 中間リソースの削除

今回は特になし。

#### Navigation

Next: [RouteTable を作成する](./03-step03-igw-routes.md#0302-routetable-を作成する)

---

# [0302] RouteTable を作成する

## About

パブリックサブネット用のルートテーブルを作成し、インターネット向けのデフォルトルート（`0.0.0.0/0` → IGW）を追加する CLI 手順書。

## When: 作業の条件

### Before: 事前前提条件

以下を作業の前提条件とする。
1. VPC が作成済みである。
2. IGW が作成済みで、VPC にアタッチされている（Step 0301 完了）。

### After: 作業終了状況

以下が完了の条件。
1. ルートテーブルが作成されている。
2. デフォルトルート（`0.0.0.0/0` → IGW）が追加されている。

## How: 以下は作業手順

### 1. 前処理

#### 1.1 処理パラメータの準備

パラメータの事後確認用ファイルの設定

```bash
RUNBOOK_TITLE="0302-create-route-table"
DIR_PARAMETER="."
FILE_PARAMETER="${DIR_PARAMETER}/$(date +%Y-%m-%d)-${RUNBOOK_TITLE}.env" \
    && echo ${FILE_PARAMETER}
```

手順の実行パラメータ

```bash
# 変数に値をセット
AWS_REGION="ap-northeast-1"
VPC_CIDR="10.0.0.0/16"
RT_NAME="cli-workshop-public-rt"
```

```bash
# 値を確認
cat << ETX
    AWS_REGION=${AWS_REGION}
    VPC_CIDR=${VPC_CIDR}
    RT_NAME=${RT_NAME}

ETX
```

#### 1.2 事前条件の確認

VPC ID と IGW ID を取得する。

```bash
VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=cidr,Values=${VPC_CIDR}" \
    --query "Vpcs[].VpcId" \
    --region ${AWS_REGION} \
    --output text) && echo ${VPC_ID}
```

```bash
IGW_ID=$(aws ec2 describe-internet-gateways \
    --filters "Name=attachment.vpc-id,Values=${VPC_ID}" \
    --query "InternetGateways[].InternetGatewayId" \
    --region ${AWS_REGION} \
    --output text) && echo ${IGW_ID}
```

どちらも ID が表示されれば、期待通り。

### 2. 主処理

#### 2.1 ルートテーブルの作成

パラメータの最終確認

```bash
cat << EOF > ${FILE_PARAMETER}
aws ec2 create-route-table \
    --vpc-id ${VPC_ID} \
    --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=${RT_NAME}}]' \
    --region ${AWS_REGION}

EOF
cat ${FILE_PARAMETER}
```

ルートテーブルを作成する。

```bash
aws ec2 create-route-table \
    --vpc-id ${VPC_ID} \
    --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=${RT_NAME}}]' \
    --region ${AWS_REGION}
```

結果の例

```output
{
    "RouteTable": {
        "Associations": [],
        "PropagatingVgws": [],
        "RouteTableId": "rtb-0a1b2c3d4eEXAMPLE",
        "Routes": [
            {
                "DestinationCidrBlock": "10.0.0.0/16",
                "GatewayId": "local",
                "Origin": "CreateRouteTable",
                "State": "active"
            }
        ],
        "Tags": [
            {
                "Key": "Name",
                "Value": "cli-workshop-public-rt"
            }
        ],
        "VpcId": "vpc-0a1b2c3d4eEXAMPLE",
        "OwnerId": "123456789012"
    }
}
```

> **補足**: ルートテーブル作成直後は、VPC の CIDR 宛のローカルルート（`10.0.0.0/16` → `local`）だけが自動で入っている。これは VPC 内部の通信用で、削除できない。

ルートテーブル ID をシェル変数に格納する。

```bash
RT_ID=$(aws ec2 describe-route-tables \
    --filters \
        "Name=vpc-id,Values=${VPC_ID}" \
        "Name=tag:Name,Values=${RT_NAME}" \
    --query "RouteTables[].RouteTableId" \
    --region ${AWS_REGION} \
    --output text) && echo ${RT_ID}
```

出力例

```output
rtb-0a1b2c3d4eEXAMPLE
```

#### 2.2 デフォルトルートの追加

インターネット向けのデフォルトルート（`0.0.0.0/0` → IGW）を追加する。

```bash
aws ec2 create-route \
    --route-table-id ${RT_ID} \
    --destination-cidr-block "0.0.0.0/0" \
    --gateway-id ${IGW_ID} \
    --region ${AWS_REGION}
```

結果の例

```output
{
    "Return": true
}
```

`Return` が `true` であれば、ルート追加成功。

### 3. 後処理

#### 3.1 完了条件の結果確認

ルートテーブルにデフォルトルートが追加されていることを確認する。

```bash
aws ec2 describe-route-tables \
    --route-table-ids ${RT_ID} \
    --query "RouteTables[].Routes" \
    --region ${AWS_REGION}
```

結果の例

```output
[
    [
        {
            "DestinationCidrBlock": "10.0.0.0/16",
            "GatewayId": "local",
            "Origin": "CreateRouteTable",
            "State": "active"
        },
        {
            "DestinationCidrBlock": "0.0.0.0/0",
            "GatewayId": "igw-0a1b2c3d4eEXAMPLE",
            "Origin": "CreateRoute",
            "State": "active"
        }
    ]
]
```

`0.0.0.0/0` → IGW のルートが `active` であれば期待通り。

#### 3.99 中間リソースの削除

今回は特になし。

#### Navigation

Next: [Subnet を RouteTable に関連付ける](./03-step03-igw-routes.md#0303-subnet-を-routetable-に関連付ける)

---

# [0303] Subnet を RouteTable に関連付ける

## About

2 つのパブリックサブネットを、作成したルートテーブルに関連付ける CLI 手順書。

> **補足**: サブネットは作成時にVPC のメインルートテーブルに暗黙的に関連付けられている。明示的にカスタムルートテーブルに関連付けることで、IGW へのルーティングが有効になる。

## When: 作業の条件

### Before: 事前前提条件

以下を作業の前提条件とする。
1. 2 つのサブネットが作成済みである（Step 02 完了）。
2. ルートテーブルが作成済みで、デフォルトルートが追加されている（Step 0302 完了）。

### After: 作業終了状況

以下が完了の条件。
1. サブネット 1a がルートテーブルに関連付けられている。
2. サブネット 1c がルートテーブルに関連付けられている。

## How: 以下は作業手順

### 1. 前処理

#### 1.1 処理パラメータの準備

```bash
RUNBOOK_TITLE="0303-associate-route-table"
DIR_PARAMETER="."
FILE_PARAMETER="${DIR_PARAMETER}/$(date +%Y-%m-%d)-${RUNBOOK_TITLE}.env" \
    && echo ${FILE_PARAMETER}
```

手順の実行パラメータ

```bash
AWS_REGION="ap-northeast-1"
VPC_CIDR="10.0.0.0/16"
SUBNET_1A_CIDR="10.0.1.0/24"
SUBNET_1C_CIDR="10.0.2.0/24"
```

#### 1.2 事前条件の確認

各リソースの ID を取得する。

```bash
VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=cidr,Values=${VPC_CIDR}" \
    --query "Vpcs[].VpcId" \
    --region ${AWS_REGION} \
    --output text) && echo ${VPC_ID}
```

```bash
SUBNET_1A_ID=$(aws ec2 describe-subnets \
    --filters \
        "Name=vpc-id,Values=${VPC_ID}" \
        "Name=cidrBlock,Values=${SUBNET_1A_CIDR}" \
    --query "Subnets[].SubnetId" \
    --region ${AWS_REGION} \
    --output text) && echo ${SUBNET_1A_ID}
```

```bash
SUBNET_1C_ID=$(aws ec2 describe-subnets \
    --filters \
        "Name=vpc-id,Values=${VPC_ID}" \
        "Name=cidrBlock,Values=${SUBNET_1C_CIDR}" \
    --query "Subnets[].SubnetId" \
    --region ${AWS_REGION} \
    --output text) && echo ${SUBNET_1C_ID}
```

```bash
RT_ID=$(aws ec2 describe-route-tables \
    --filters \
        "Name=vpc-id,Values=${VPC_ID}" \
        "Name=tag:Name,Values=cli-workshop-public-rt" \
    --query "RouteTables[].RouteTableId" \
    --region ${AWS_REGION} \
    --output text) && echo ${RT_ID}
```

すべての ID が表示されれば、期待通り。

### 2. 主処理

#### 2.1 サブネット 1a の関連付け

```bash
aws ec2 associate-route-table \
    --subnet-id ${SUBNET_1A_ID} \
    --route-table-id ${RT_ID} \
    --region ${AWS_REGION}
```

結果の例

```output
{
    "AssociationId": "rtbassoc-0a1b2c3d4eEXAMPLE",
    "AssociationState": {
        "State": "associated"
    }
}
```

#### 2.2 サブネット 1c の関連付け

```bash
aws ec2 associate-route-table \
    --subnet-id ${SUBNET_1C_ID} \
    --route-table-id ${RT_ID} \
    --region ${AWS_REGION}
```

結果の例

```output
{
    "AssociationId": "rtbassoc-0f1e2d3c4bEXAMPLE",
    "AssociationState": {
        "State": "associated"
    }
}
```

### 3. 後処理

#### 3.1 完了条件の結果確認

ルートテーブルの関連付けを確認する。

```bash
aws ec2 describe-route-tables \
    --route-table-ids ${RT_ID} \
    --query "RouteTables[].Associations[].[SubnetId, RouteTableAssociationId, AssociationState.State]" \
    --region ${AWS_REGION} \
    --output table
```

結果の例

```output
----------------------------------------------------------------------
|                       DescribeRouteTables                          |
+----------------------------+-------------------------------+-------+
|  subnet-0a1b2c3d4eEXAMPLE |  rtbassoc-0a1b2c3d4eEXAMPLE  | associated |
|  subnet-0f1e2d3c4bEXAMPLE |  rtbassoc-0f1e2d3c4bEXAMPLE  | associated |
+----------------------------+-------------------------------+-------+
```

2 つのサブネットがどちらも `associated` であれば期待通り。

これでネットワークのルーティングが完成した。VPC 内のサブネットからインターネットへのルートが確立されている。

#### 3.99 中間リソースの削除

今回は特になし。

#### Navigation

Next: [Security Group を作成する](./04-step04-sg.md)

# EOD
