# [0201] Subnet を作成する — Public Subnet 1a

## About

VPC 内にパブリックサブネットを作成する CLI 手順書。

本手順では、`ap-northeast-1a` にパブリックサブネットを作成し、パブリック IP の自動付与を有効化する。

## When: 作業の条件

### Before: 事前前提条件

以下を作業の前提条件とする。
1. VPC が作成済みである（Step 01 完了）。
2. 割り当てる CIDR 範囲と重複する既存のサブネットがない。

### After: 作業終了状況

以下が完了の条件。
1. サブネットが作成されている。
2. サブネットの CIDR 範囲は `10.0.1.0/24` である。
3. AZ は `ap-northeast-1a` である。
4. パブリック IP の自動付与が有効になっている。

## How: 以下は作業手順

### 1. 前処理

#### 1.1 処理パラメータの準備

パラメータの事後確認用ファイルの設定

```bash
RUNBOOK_TITLE="0201-create-subnet-1a"
DIR_PARAMETER="."
FILE_PARAMETER="${DIR_PARAMETER}/$(date +%Y-%m-%d)-${RUNBOOK_TITLE}.env" \
    && echo ${FILE_PARAMETER}
```

手順の実行パラメータ

```bash
# 変数に値をセット
AWS_REGION="ap-northeast-1"
VPC_CIDR="10.0.0.0/16"
SUBNET_CIDR="10.0.1.0/24"
SUBNET_AZ="ap-northeast-1a"
SUBNET_NAME="cli-workshop-public-1a"
```

```bash
# 値を確認
cat << ETX
    AWS_REGION=${AWS_REGION}
    VPC_CIDR=${VPC_CIDR}
    SUBNET_CIDR=${SUBNET_CIDR}
    SUBNET_AZ=${SUBNET_AZ}
    SUBNET_NAME=${SUBNET_NAME}

ETX
```

#### 1.2 事前条件1の確認

VPC が作成済みであることを確認し、VPC ID を取得する。

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

VPC ID が表示されれば、期待通り。

#### 1.3 事前条件2の確認

同じ CIDR のサブネットが存在しないことを確認する。

```bash
aws ec2 describe-subnets \
    --filters \
        "Name=vpc-id,Values=${VPC_ID}" \
        "Name=cidrBlock,Values=${SUBNET_CIDR}" \
    --region ${AWS_REGION}
```

結果の例

```output
{
    "Subnets": []
}
```

`Subnets` が空であれば、期待通り。

### 2. 主処理

#### 2.1 リソースの操作 (CREATE)

パラメータの最終確認

```bash
cat << EOF > ${FILE_PARAMETER}
aws ec2 create-subnet \
    --vpc-id ${VPC_ID} \
    --cidr-block ${SUBNET_CIDR} \
    --availability-zone ${SUBNET_AZ} \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=${SUBNET_NAME}}]' \
    --region ${AWS_REGION}

EOF
cat ${FILE_PARAMETER}
```

サブネットを作成する。

```bash
aws ec2 create-subnet \
    --vpc-id ${VPC_ID} \
    --cidr-block ${SUBNET_CIDR} \
    --availability-zone ${SUBNET_AZ} \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=${SUBNET_NAME}}]' \
    --region ${AWS_REGION}
```

結果の例

```output
{
    "Subnet": {
        "AvailabilityZone": "ap-northeast-1a",
        "AvailabilityZoneId": "apne1-az4",
        "AvailableIpAddressCount": 251,
        "CidrBlock": "10.0.1.0/24",
        "DefaultForAz": false,
        "MapPublicIpOnLaunch": false,
        "State": "available",
        "SubnetId": "subnet-0a1b2c3d4eEXAMPLE",
        "VpcId": "vpc-0a1b2c3d4eEXAMPLE",
        "OwnerId": "123456789012",
        "AssignIpv6AddressOnCreation": false,
        "Ipv6CidrBlockAssociationSet": [],
        "Tags": [
            {
                "Key": "Name",
                "Value": "cli-workshop-public-1a"
            }
        ],
        "SubnetArn": "arn:aws:ec2:ap-northeast-1:123456789012:subnet/subnet-0a1b2c3d4eEXAMPLE",
        "EnableDns64": false,
        "Ipv6Native": false,
        "PrivateDnsNameOptionsOnLaunch": {
            "HostnameType": "ip-name",
            "EnableResourceNameDnsARecord": false,
            "EnableResourceNameDnsAAAARecord": false
        }
    }
}
```

サブネット ID をシェル変数に格納する。

```bash
SUBNET_1A_ID=$(aws ec2 describe-subnets \
    --filters \
        "Name=vpc-id,Values=${VPC_ID}" \
        "Name=cidrBlock,Values=${SUBNET_CIDR}" \
    --query "Subnets[].SubnetId" \
    --region ${AWS_REGION} \
    --output text) && echo ${SUBNET_1A_ID}
```

出力例

```output
subnet-0a1b2c3d4eEXAMPLE
```

#### 2.2 パブリック IP 自動付与の有効化

サブネットで起動する EC2 インスタンスに、パブリック IP アドレスが自動的に付与されるようにする。

> **補足**: サブネット作成時の `MapPublicIpOnLaunch` はデフォルトで `false`。ALB 配下の EC2 にパブリック IP は不要だが、SSM Session Manager での接続やセットアップのために有効化しておく。

```bash
aws ec2 modify-subnet-attribute \
    --subnet-id ${SUBNET_1A_ID} \
    --map-public-ip-on-launch \
    --region ${AWS_REGION}
```

このコマンドは成功しても出力がない（サイレント）。

### 3. 後処理

#### 3.1 完了条件の結果確認

サブネットが作成されており、CIDR 範囲、AZ、パブリック IP 自動付与が正しいことを確認する。

```bash
aws ec2 describe-subnets \
    --subnet-ids ${SUBNET_1A_ID} \
    --query "Subnets[].[SubnetId, CidrBlock, AvailabilityZone, MapPublicIpOnLaunch]" \
    --region ${AWS_REGION} \
    --output table
```

結果の例

```output
-----------------------------------------------------------------------
|                          DescribeSubnets                            |
+----------------------------+--------------+------------------+------+
|  subnet-0a1b2c3d4eEXAMPLE |  10.0.1.0/24 | ap-northeast-1a  | True |
+----------------------------+--------------+------------------+------+
```

`MapPublicIpOnLaunch` が `True` であれば期待通り。

#### 3.99 中間リソースの削除

今回は特になし。

#### Navigation

Next: [Subnet を作成する — Public Subnet 1c](./02-step02-subnets.md#0202-subnet-を作成する--public-subnet-1c)

---

# [0202] Subnet を作成する — Public Subnet 1c

## About

VPC 内に 2 つ目のパブリックサブネットを作成する CLI 手順書。

本手順では、`ap-northeast-1c` にパブリックサブネットを作成する。
Step 0201 と同じ手順を、異なるパラメータ（CIDR、AZ）で実施する。

## When: 作業の条件

### Before: 事前前提条件

以下を作業の前提条件とする。
1. VPC が作成済みである。
2. 1 つ目のサブネット（1a）が作成済みである（Step 0201 完了）。
3. 割り当てる CIDR 範囲と重複する既存のサブネットがない。

### After: 作業終了状況

以下が完了の条件。
1. サブネットが作成されている。
2. サブネットの CIDR 範囲は `10.0.2.0/24` である。
3. AZ は `ap-northeast-1c` である。
4. パブリック IP の自動付与が有効になっている。

## How: 以下は作業手順

### 1. 前処理

#### 1.1 処理パラメータの準備

パラメータの事後確認用ファイルの設定

```bash
RUNBOOK_TITLE="0202-create-subnet-1c"
DIR_PARAMETER="."
FILE_PARAMETER="${DIR_PARAMETER}/$(date +%Y-%m-%d)-${RUNBOOK_TITLE}.env" \
    && echo ${FILE_PARAMETER}
```

手順の実行パラメータ

```bash
# 変数に値をセット
AWS_REGION="ap-northeast-1"
VPC_CIDR="10.0.0.0/16"
SUBNET_CIDR="10.0.2.0/24"
SUBNET_AZ="ap-northeast-1c"
SUBNET_NAME="cli-workshop-public-1c"
```

```bash
# 値を確認
cat << ETX
    AWS_REGION=${AWS_REGION}
    VPC_CIDR=${VPC_CIDR}
    SUBNET_CIDR=${SUBNET_CIDR}
    SUBNET_AZ=${SUBNET_AZ}
    SUBNET_NAME=${SUBNET_NAME}

ETX
```

#### 1.2 事前条件1の確認

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

#### 1.3 事前条件2の確認

1 つ目のサブネット（1a）が作成済みであることを確認する。

```bash
aws ec2 describe-subnets \
    --filters \
        "Name=vpc-id,Values=${VPC_ID}" \
        "Name=tag:Name,Values=cli-workshop-public-1a" \
    --query "Subnets[].SubnetId" \
    --region ${AWS_REGION} \
    --output text
```

出力例

```output
subnet-0a1b2c3d4eEXAMPLE
```

サブネット ID が表示されれば、期待通り。

#### 1.4 事前条件3の確認

同じ CIDR のサブネットが存在しないことを確認する。

```bash
aws ec2 describe-subnets \
    --filters \
        "Name=vpc-id,Values=${VPC_ID}" \
        "Name=cidrBlock,Values=${SUBNET_CIDR}" \
    --region ${AWS_REGION}
```

結果の例

```output
{
    "Subnets": []
}
```

### 2. 主処理

#### 2.1 リソースの操作 (CREATE)

パラメータの最終確認

```bash
cat << EOF > ${FILE_PARAMETER}
aws ec2 create-subnet \
    --vpc-id ${VPC_ID} \
    --cidr-block ${SUBNET_CIDR} \
    --availability-zone ${SUBNET_AZ} \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=${SUBNET_NAME}}]' \
    --region ${AWS_REGION}

EOF
cat ${FILE_PARAMETER}
```

サブネットを作成する。

```bash
aws ec2 create-subnet \
    --vpc-id ${VPC_ID} \
    --cidr-block ${SUBNET_CIDR} \
    --availability-zone ${SUBNET_AZ} \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=${SUBNET_NAME}}]' \
    --region ${AWS_REGION}
```

結果の例

```output
{
    "Subnet": {
        "AvailabilityZone": "ap-northeast-1c",
        "AvailabilityZoneId": "apne1-az1",
        "AvailableIpAddressCount": 251,
        "CidrBlock": "10.0.2.0/24",
        "DefaultForAz": false,
        "MapPublicIpOnLaunch": false,
        "State": "available",
        "SubnetId": "subnet-0f1e2d3c4bEXAMPLE",
        "VpcId": "vpc-0a1b2c3d4eEXAMPLE",
        "OwnerId": "123456789012",
        "AssignIpv6AddressOnCreation": false,
        "Ipv6CidrBlockAssociationSet": [],
        "Tags": [
            {
                "Key": "Name",
                "Value": "cli-workshop-public-1c"
            }
        ],
        "SubnetArn": "arn:aws:ec2:ap-northeast-1:123456789012:subnet/subnet-0f1e2d3c4bEXAMPLE",
        "EnableDns64": false,
        "Ipv6Native": false,
        "PrivateDnsNameOptionsOnLaunch": {
            "HostnameType": "ip-name",
            "EnableResourceNameDnsARecord": false,
            "EnableResourceNameDnsAAAARecord": false
        }
    }
}
```

サブネット ID をシェル変数に格納する。

```bash
SUBNET_1C_ID=$(aws ec2 describe-subnets \
    --filters \
        "Name=vpc-id,Values=${VPC_ID}" \
        "Name=cidrBlock,Values=${SUBNET_CIDR}" \
    --query "Subnets[].SubnetId" \
    --region ${AWS_REGION} \
    --output text) && echo ${SUBNET_1C_ID}
```

出力例

```output
subnet-0f1e2d3c4bEXAMPLE
```

#### 2.2 パブリック IP 自動付与の有効化

```bash
aws ec2 modify-subnet-attribute \
    --subnet-id ${SUBNET_1C_ID} \
    --map-public-ip-on-launch \
    --region ${AWS_REGION}
```

このコマンドは成功しても出力がない（サイレント）。

### 3. 後処理

#### 3.1 完了条件の結果確認

2 つのサブネットがすべて正しく作成されていることを、一覧で確認する。

```bash
aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query "Subnets[].[SubnetId, CidrBlock, AvailabilityZone, MapPublicIpOnLaunch, Tags[?Key=='Name'].Value | [0]]" \
    --region ${AWS_REGION} \
    --output table
```

結果の例

```output
------------------------------------------------------------------------------------------
|                                    DescribeSubnets                                     |
+----------------------------+--------------+------------------+------+-------------------+
|  subnet-0a1b2c3d4eEXAMPLE |  10.0.1.0/24 | ap-northeast-1a  | True | cli-workshop-public-1a |
|  subnet-0f1e2d3c4bEXAMPLE |  10.0.2.0/24 | ap-northeast-1c  | True | cli-workshop-public-1c |
+----------------------------+--------------+------------------+------+-------------------+
```

2 つのサブネットが異なる AZ に作成され、どちらも `MapPublicIpOnLaunch` が `True` であれば期待通り。

#### 3.99 中間リソースの削除

今回は特になし。

#### Navigation

Next: [IGW + RouteTable を作成する](./03-step03-igw-routes.md)

# EOD
