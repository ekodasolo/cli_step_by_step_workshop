# [0100] VPC を作成する

## About

AWS CLI で VPC を作成する手順書。

本手順では、CIDR `10.0.0.0/16` の VPC を作成し、DNS サポートと DNS ホスト名を有効化する。
これがワークショップ全体のネットワーク基盤となる。

## When: 作業の条件

### Before: 事前前提条件

以下を作業の前提条件とする。
1. CloudShell にログイン済みである。
2. リージョンが `ap-northeast-1` になっている。

### After: 作業終了状況

以下が完了の条件。
1. VPC が作成されている。
2. VPC の CIDR 範囲は `10.0.0.0/16` である。
3. DNS サポートと DNS ホスト名が有効になっている。
4. Name タグが `cli-workshop-vpc` になっている。

## How: 以下は作業手順

### 1. 前処理

#### 1.1 処理パラメータの準備

パラメータの事後確認用ファイルの設定

```bash
RUNBOOK_TITLE="0100-create-vpc"
DIR_PARAMETER="."
FILE_PARAMETER="${DIR_PARAMETER}/$(date +%Y-%m-%d)-${RUNBOOK_TITLE}.env" \
    && echo ${FILE_PARAMETER}
```

手順の実行パラメータ

```bash
# 変数に値をセット
AWS_REGION="ap-northeast-1"
VPC_CIDR="10.0.0.0/16"
VPC_NAME="cli-workshop-vpc"
```

```bash
# 値を確認
cat << ETX
    AWS_REGION=${AWS_REGION}
    VPC_CIDR=${VPC_CIDR}
    VPC_NAME=${VPC_NAME}

ETX
```

#### 1.2 事前条件1の確認

CloudShell にログイン済みで、リージョンが `ap-northeast-1` になっていることを確認する。

```bash
aws configure get region
```

```output
ap-northeast-1
```

`ap-northeast-1` が表示されれば、期待通り。

#### 1.3 事前条件2の確認

同じ CIDR の VPC が既に存在しないことを確認する。

```bash
aws ec2 describe-vpcs \
    --filters "Name=cidr,Values=${VPC_CIDR}" \
    --query "Vpcs[].VpcId" \
    --region ${AWS_REGION} \
    --output text
```

何も表示されなければ、期待通り（既存の VPC がない）。

### 2. 主処理

#### 2.1 リソースの操作 (CREATE)

パラメータの最終確認

```bash
cat << EOF > ${FILE_PARAMETER}
aws ec2 create-vpc \
    --cidr-block ${VPC_CIDR} \
    --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=${VPC_NAME}}]' \
    --region ${AWS_REGION}

EOF
cat ${FILE_PARAMETER}
```

VPC を作成する。

```bash
aws ec2 create-vpc \
    --cidr-block ${VPC_CIDR} \
    --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=${VPC_NAME}}]' \
    --region ${AWS_REGION}
```

結果の例

```output
{
    "Vpc": {
        "CidrBlock": "10.0.0.0/16",
        "DhcpOptionsId": "dopt-0a1b2c3d4eEXAMPLE",
        "State": "available",
        "VpcId": "vpc-0a1b2c3d4eEXAMPLE",
        "OwnerId": "123456789012",
        "InstanceTenancy": "default",
        "Ipv6CidrBlockAssociationSet": [],
        "CidrBlockAssociationSet": [
            {
                "AssociationId": "vpc-cidr-assoc-0a1b2c3d4eEXAMPLE",
                "CidrBlock": "10.0.0.0/16",
                "CidrBlockState": {
                    "State": "associated"
                }
            }
        ],
        "IsDefault": false,
        "Tags": [
            {
                "Key": "Name",
                "Value": "cli-workshop-vpc"
            }
        ]
    }
}
```

VPC ID をシェル変数に格納する。

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

#### 2.2 DNS ホスト名の有効化

VPC の DNS ホスト名を有効化する。これにより、VPC 内の EC2 インスタンスに DNS ホスト名が割り当てられる。

> **補足**: VPC 作成時に `EnableDnsSupport` はデフォルトで `true` だが、`EnableDnsHostnames` はデフォルトで `false` のため、別途有効化する必要がある。

```bash
aws ec2 modify-vpc-attribute \
    --vpc-id ${VPC_ID} \
    --enable-dns-hostnames '{"Value": true}' \
    --region ${AWS_REGION}
```

このコマンドは成功しても出力がない（サイレント）。

### 3. 後処理

#### 3.1 完了条件1、2の結果確認

VPC が作成されており、CIDR 範囲が `10.0.0.0/16` であることを確認する。

```bash
aws ec2 describe-vpcs \
    --vpc-ids ${VPC_ID} \
    --region ${AWS_REGION}
```

結果の例

```output
{
    "Vpcs": [
        {
            "CidrBlock": "10.0.0.0/16",
            "DhcpOptionsId": "dopt-0a1b2c3d4eEXAMPLE",
            "State": "available",
            "VpcId": "vpc-0a1b2c3d4eEXAMPLE",
            "OwnerId": "123456789012",
            "InstanceTenancy": "default",
            "Ipv6CidrBlockAssociationSet": [],
            "CidrBlockAssociationSet": [
                {
                    "AssociationId": "vpc-cidr-assoc-0a1b2c3d4eEXAMPLE",
                    "CidrBlock": "10.0.0.0/16",
                    "CidrBlockState": {
                        "State": "associated"
                    }
                }
            ],
            "IsDefault": false,
            "Tags": [
                {
                    "Key": "Name",
                    "Value": "cli-workshop-vpc"
                }
            ]
        }
    ]
}
```

`State` が `available`、`CidrBlock` が `10.0.0.0/16` であれば期待通り。

#### 3.2 完了条件3の結果確認

DNS サポートと DNS ホスト名が有効になっていることを確認する。

```bash
# DNS サポートの確認
aws ec2 describe-vpc-attribute \
    --vpc-id ${VPC_ID} \
    --attribute enableDnsSupport \
    --region ${AWS_REGION} \
    --query "EnableDnsSupport.Value" \
    --output text
```

```output
True
```

```bash
# DNS ホスト名の確認
aws ec2 describe-vpc-attribute \
    --vpc-id ${VPC_ID} \
    --attribute enableDnsHostnames \
    --region ${AWS_REGION} \
    --query "EnableDnsHostnames.Value" \
    --output text
```

```output
True
```

どちらも `True` であれば期待通り。

#### 3.3 完了条件4の結果確認

Name タグが正しいことを確認する。

```bash
aws ec2 describe-vpcs \
    --vpc-ids ${VPC_ID} \
    --query "Vpcs[].Tags[?Key=='Name'].Value" \
    --region ${AWS_REGION} \
    --output text
```

```output
cli-workshop-vpc
```

#### 3.99 中間リソースの削除

今回は特になし。

#### Navigation

Next: [Subnet を作成する](./02-step02-subnets.md)

# EOD
