# [0501] IAM Role を作成する

## About

EC2 インスタンスに割り当てる IAM ロールを作成する CLI 手順書。

本手順では、SSM Session Manager で EC2 に接続できるようにするための IAM ロールを作成する。
EC2 にキーペアを設定せず、SSM 経由で安全にアクセスする構成とする。

> **補足**: IAM ロールを作成するには「信頼ポリシー」が必要。信頼ポリシーとは「誰がこのロールを引き受けられるか」を定義する JSON ドキュメント。今回は EC2 サービス（`ec2.amazonaws.com`）がロールを引き受けることを許可する。

## When: 作業の条件

### Before: 事前前提条件

以下を作業の前提条件とする。
1. IAM の操作権限を持つユーザーでログインしている。

### After: 作業終了状況

以下が完了の条件。
1. IAM ロールが作成されている。
2. `AmazonSSMManagedInstanceCore` ポリシーがアタッチされている。

## How: 以下は作業手順

### 1. 前処理

#### 1.1 処理パラメータの準備

パラメータの事後確認用ファイルの設定

```bash
RUNBOOK_TITLE="0501-create-iam-role"
DIR_PARAMETER="."
FILE_PARAMETER="${DIR_PARAMETER}/$(date +%Y-%m-%d)-${RUNBOOK_TITLE}.env" \
    && echo ${FILE_PARAMETER}
```

手順の実行パラメータ

```bash
# 変数に値をセット
AWS_REGION="ap-northeast-1"
ROLE_NAME="cli-workshop-web-server-role"
POLICY_ARN="arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
```

```bash
# 値を確認
cat << ETX
    AWS_REGION=${AWS_REGION}
    ROLE_NAME=${ROLE_NAME}
    POLICY_ARN=${POLICY_ARN}

ETX
```

#### 1.2 事前条件の確認

同名のロールが既に存在しないことを確認する。

```bash
aws iam get-role \
    --role-name ${ROLE_NAME} 2>&1 || true
```

`NoSuchEntity` エラーが返れば、ロールは存在しない（期待通り）。

### 2. 主処理

#### 2.1 信頼ポリシーの作成

EC2 サービスがこのロールを引き受けることを許可する信頼ポリシーを JSON ファイルとして作成する。

```bash
cat << 'EOF' > trust-policy.json
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
```

> **ポイント**: ヒアドキュメントのマーカーを `'EOF'`（シングルクォートで囲む）にすることで、`$` などが変数展開されずにそのまま書き込まれる。JSON 内に `${...}` がある場合に重要。

ファイルの内容を確認する。

```bash
cat trust-policy.json
```

```output
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
```

#### 2.2 IAM ロールの作成

パラメータの最終確認

```bash
cat << EOF > ${FILE_PARAMETER}
aws iam create-role \
    --role-name ${ROLE_NAME} \
    --assume-role-policy-document file://trust-policy.json \
    --tags Key=Name,Value=${ROLE_NAME}

EOF
cat ${FILE_PARAMETER}
```

ロールを作成する。

```bash
aws iam create-role \
    --role-name ${ROLE_NAME} \
    --assume-role-policy-document file://trust-policy.json \
    --tags Key=Name,Value=${ROLE_NAME}
```

結果の例

```output
{
    "Role": {
        "Path": "/",
        "RoleName": "cli-workshop-web-server-role",
        "RoleId": "AROA0A1B2C3D4EEXAMPLE",
        "Arn": "arn:aws:iam::123456789012:role/cli-workshop-web-server-role",
        "CreateDate": "2026-04-02T10:00:00+00:00",
        "AssumeRolePolicyDocument": {
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
        },
        "Tags": [
            {
                "Key": "Name",
                "Value": "cli-workshop-web-server-role"
            }
        ]
    }
}
```

#### 2.3 マネージドポリシーのアタッチ

SSM Session Manager の接続に必要なポリシーをロールにアタッチする。

```bash
aws iam attach-role-policy \
    --role-name ${ROLE_NAME} \
    --policy-arn ${POLICY_ARN}
```

このコマンドは成功しても出力がない（サイレント）。

### 3. 後処理

#### 3.1 完了条件1の結果確認

ロールが作成されていることを確認する。

```bash
aws iam get-role \
    --role-name ${ROLE_NAME} \
    --query "Role.[RoleName, Arn]" \
    --output text
```

出力例

```output
cli-workshop-web-server-role	arn:aws:iam::123456789012:role/cli-workshop-web-server-role
```

#### 3.2 完了条件2の結果確認

ポリシーがアタッチされていることを確認する。

```bash
aws iam list-attached-role-policies \
    --role-name ${ROLE_NAME}
```

結果の例

```output
{
    "AttachedPolicies": [
        {
            "PolicyName": "AmazonSSMManagedInstanceCore",
            "PolicyArn": "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
        }
    ]
}
```

`AmazonSSMManagedInstanceCore` が表示されれば期待通り。

#### 3.99 中間リソースの削除

信頼ポリシーの JSON ファイルを削除する。

```bash
rm -f trust-policy.json
```

#### Navigation

Next: [Instance Profile を作成する](./05-step05-iam.md#0502-instance-profile-を作成する)

---

# [0502] Instance Profile を作成する

## About

EC2 インスタンスに IAM ロールを割り当てるための Instance Profile を作成する CLI 手順書。

> **補足**: EC2 に直接 IAM ロールを割り当てることはできない。「Instance Profile」という入れ物にロールを入れ、その Instance Profile を EC2 に関連付ける仕組みになっている。CloudFormation やマネジメントコンソールではこの手順が自動化されているが、CLI では明示的に行う必要がある。

## When: 作業の条件

### Before: 事前前提条件

以下を作業の前提条件とする。
1. IAM ロールが作成済みである（Step 0501 完了）。

### After: 作業終了状況

以下が完了の条件。
1. Instance Profile が作成されている。
2. IAM ロールが Instance Profile に追加されている。

## How: 以下は作業手順

### 1. 前処理

#### 1.1 処理パラメータの準備

パラメータの事後確認用ファイルの設定

```bash
RUNBOOK_TITLE="0502-create-instance-profile"
DIR_PARAMETER="."
FILE_PARAMETER="${DIR_PARAMETER}/$(date +%Y-%m-%d)-${RUNBOOK_TITLE}.env" \
    && echo ${FILE_PARAMETER}
```

手順の実行パラメータ

```bash
# 変数に値をセット
ROLE_NAME="cli-workshop-web-server-role"
INSTANCE_PROFILE_NAME="cli-workshop-web-server-profile"
```

```bash
# 値を確認
cat << ETX
    ROLE_NAME=${ROLE_NAME}
    INSTANCE_PROFILE_NAME=${INSTANCE_PROFILE_NAME}

ETX
```

#### 1.2 事前条件の確認

IAM ロールが存在することを確認する。

```bash
aws iam get-role \
    --role-name ${ROLE_NAME} \
    --query "Role.RoleName" \
    --output text
```

出力例

```output
cli-workshop-web-server-role
```

### 2. 主処理

#### 2.1 Instance Profile の作成

```bash
aws iam create-instance-profile \
    --instance-profile-name ${INSTANCE_PROFILE_NAME}
```

結果の例

```output
{
    "InstanceProfile": {
        "Path": "/",
        "InstanceProfileName": "cli-workshop-web-server-profile",
        "InstanceProfileId": "AIPA0A1B2C3D4EEXAMPLE",
        "Arn": "arn:aws:iam::123456789012:instance-profile/cli-workshop-web-server-profile",
        "CreateDate": "2026-04-02T10:05:00+00:00",
        "Roles": []
    }
}
```

> **注目**: 作成直後の `Roles` は空。次のステップでロールを追加する。

#### 2.2 ロールを Instance Profile に追加

```bash
aws iam add-role-to-instance-profile \
    --instance-profile-name ${INSTANCE_PROFILE_NAME} \
    --role-name ${ROLE_NAME}
```

このコマンドは成功しても出力がない（サイレント）。

> **注意**: Instance Profile の作成直後にロールを追加しても、EC2 起動に使えるようになるまで数秒〜十数秒かかる場合がある。次の Step 06（EC2 作成）で問題が起きた場合は少し待ってからリトライする。

### 3. 後処理

#### 3.1 完了条件の結果確認

Instance Profile にロールが追加されていることを確認する。

```bash
aws iam get-instance-profile \
    --instance-profile-name ${INSTANCE_PROFILE_NAME}
```

結果の例

```output
{
    "InstanceProfile": {
        "Path": "/",
        "InstanceProfileName": "cli-workshop-web-server-profile",
        "InstanceProfileId": "AIPA0A1B2C3D4EEXAMPLE",
        "Arn": "arn:aws:iam::123456789012:instance-profile/cli-workshop-web-server-profile",
        "CreateDate": "2026-04-02T10:05:00+00:00",
        "Roles": [
            {
                "Path": "/",
                "RoleName": "cli-workshop-web-server-role",
                "RoleId": "AROA0A1B2C3D4EEXAMPLE",
                "Arn": "arn:aws:iam::123456789012:role/cli-workshop-web-server-role",
                "CreateDate": "2026-04-02T10:00:00+00:00",
                "AssumeRolePolicyDocument": {
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
            }
        ]
    }
}
```

`Roles` にロール名が表示されていれば期待通り。

#### 3.99 中間リソースの削除

今回は特になし。

#### Navigation

Next: [EC2 インスタンスを作成する](./06-step06-ec2.md)

# EOD
