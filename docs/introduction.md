# イントロダクション

このワークショップでは、AWS CLI を使ってコマンドを 1 つずつ実行しながらインフラを構築します。
本編に入る前に、手順書で繰り返し使う **Bash の基礎機能**と **AWS CLI の共通オプション**を確認しておきましょう。

---

## 1. Bash の基礎

### 1.1 シェル変数

シェル変数は `変数名=値` で設定し、`${変数名}` で参照します。
このワークショップでは、AWS リソースの ID やパラメータをシェル変数に格納して、後続のコマンドで使います。

```bash
# 変数に値をセット（= の前後にスペースを入れない）
AWS_REGION="ap-northeast-1"
VPC_CIDR="10.0.0.0/16"

# 変数を参照
echo ${AWS_REGION}
```

```output
ap-northeast-1
```

**ポイント**:
- `=` の前後に **スペースを入れない**（入れるとエラーになる）
- 値にスペースや特殊文字を含む場合は `"` で囲む
- `$VPC_CIDR` と `${VPC_CIDR}` はどちらでも同じ。`${}` の方が変数名の境界が明確なので、このワークショップでは `${}` に統一する

---

### 1.2 コマンド置換

`$(コマンド)` と書くと、コマンドの実行結果を文字列として取得できます。
AWS CLI の出力からリソース ID を取得してシェル変数に格納する、という場面で毎回使います。

```bash
# 現在の日付を変数に格納
TODAY=$(date +%Y-%m-%d)
echo ${TODAY}
```

```output
2026-04-02
```

```bash
# AWS CLI の出力から VPC ID を取得して変数に格納
VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=cidr,Values=10.0.0.0/16" \
    --query "Vpcs[].VpcId" \
    --output text)
echo ${VPC_ID}
```

```output
vpc-0a60eb65b4EXAMPLE
```

**ポイント**:
- `$()` の中に書いたコマンドが実行され、その標準出力が変数に入る
- 長いコマンドは `\` で改行して読みやすくできる

---

### 1.3 ヒアドキュメント

`<< 終了マーカー` を使うと、複数行のテキストをそのまま出力・ファイルに書き込めます。
パラメータの確認や、JSON ファイルの作成に使います。

#### 変数展開あり（マーカーをそのまま書く）

```bash
AWS_REGION="ap-northeast-1"
VPC_CIDR="10.0.0.0/16"

cat << ETX
    AWS_REGION=${AWS_REGION}
    VPC_CIDR=${VPC_CIDR}
ETX
```

```output
    AWS_REGION=ap-northeast-1
    VPC_CIDR=10.0.0.0/16
```

パラメータ確認のパターンとして、手順書で毎回使います。

#### 変数展開なし（マーカーをシングルクォートで囲む）

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

IAM ロールの信頼ポリシーなど、JSON をファイルに書き出す際に使います。
`'EOF'` とシングルクォートで囲むと、`${...}` が変数展開されずにそのまま出力されます。

---

### 1.4 リダイレクトとパイプ

#### リダイレクト（`>`）

コマンドの出力をファイルに書き込みます。

```bash
# コマンドの出力をファイルに保存
echo "VPC_ID=${VPC_ID}" > parameters.env

# ファイルの末尾に追記（>> を使う）
echo "SUBNET_ID=${SUBNET_ID}" >> parameters.env
```

- `>` は上書き、`>>` は追記

#### パイプ（`|`）

コマンドの出力を次のコマンドの入力に渡します。

```bash
# JSON 出力を jq で整形して表示
aws ec2 describe-vpcs --output json | jq '.Vpcs[0].VpcId'
```

このワークショップでは、パイプよりも `--query` オプションで AWS CLI 側でフィルタリングする方法を主に使います（後述）。

---

### 1.5 `&&` によるコマンド連結

`&&` は「前のコマンドが成功したら次を実行」という意味です。
リソース ID を変数に格納した直後に、値が正しく取れたか確認するパターンで多用します。

```bash
# VPC ID を取得し、成功したら値を表示
VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=cidr,Values=10.0.0.0/16" \
    --query "Vpcs[].VpcId" \
    --output text) && echo ${VPC_ID}
```

```output
vpc-0a60eb65b4EXAMPLE
```

もし前のコマンドが失敗した場合、`&&` の後のコマンドは実行されないので、
エラーに気づきやすくなります。

---

## 2. AWS CLI の基礎

### 2.1 `--output` の使い分け

AWS CLI の出力形式は 3 種類あります。用途に応じて使い分けます。

| 形式 | 用途 | 指定方法 |
|------|------|---------|
| `json` | デフォルト。レスポンスの全体構造を確認したいとき | `--output json`（省略可） |
| `text` | シェル変数への格納。余計なクォートや括弧がない | `--output text` |
| `table` | 一覧を見やすく表示したいとき | `--output table` |

```bash
# json（デフォルト）— 構造を詳しく確認
aws ec2 describe-vpcs --query "Vpcs[].VpcId"
```

```output
[
    "vpc-0a60eb65b4EXAMPLE"
]
```

```bash
# text — 変数に格納するとき
aws ec2 describe-vpcs --query "Vpcs[].VpcId" --output text
```

```output
vpc-0a60eb65b4EXAMPLE
```

```bash
# table — 一覧を見やすく
aws ec2 describe-vpcs --query "Vpcs[].[VpcId,CidrBlock,State]" --output table
```

```output
-------------------------------------------------
|                 DescribeVpcs                   |
+---------------------------+--------------+-----+
|  vpc-0a60eb65b4EXAMPLE    |  10.0.0.0/16 | available |
+---------------------------+--------------+-----+
```

---

### 2.2 `--query`（JMESPath）

`--query` は AWS CLI のレスポンス JSON から必要な値だけを抽出するオプションです。
JMESPath という問い合わせ言語の構文を使います。

#### よく使うパターン

```bash
# 1 つの値を取得（作成直後のレスポンスから）
--query 'Vpc.VpcId'

# 配列から全要素を取得（describe 系のレスポンスから）
--query 'Vpcs[].VpcId'

# 複数の値を取得
--query 'Vpcs[].[VpcId, CidrBlock]'

# 条件でフィルタリング
--query "Vpcs[?CidrBlock=='10.0.0.0/16'].VpcId"
```

**ポイント**:
- `create` 系のレスポンスは単一オブジェクト（`Vpc.VpcId`）
- `describe` 系のレスポンスは配列（`Vpcs[].VpcId`）
- `--output text` と組み合わせてシェル変数に格納するのが基本パターン

---

### 2.3 `--filters`

`describe` 系コマンドで、条件に合うリソースだけを返すよう API 側でフィルタリングします。

```bash
# CIDR が一致する VPC を検索
aws ec2 describe-vpcs \
    --filters "Name=cidr,Values=10.0.0.0/16"

# Name タグが一致するサブネットを検索
aws ec2 describe-subnets \
    --filters "Name=tag:Name,Values=cli-workshop-public-1a"

# 複数条件（AND）
aws ec2 describe-subnets \
    --filters \
        "Name=vpc-id,Values=${VPC_ID}" \
        "Name=cidrBlock,Values=10.0.1.0/24"
```

**`--filters` と `--query` の使い分け**:
- `--filters`: API 側で絞り込む。リソースが多いときに効率的
- `--query`: レスポンス JSON をクライアント側で加工する。値の抽出に使う
- 両方を組み合わせるのが一般的: `--filters` で絞り込み → `--query` で ID を抽出

---

### 2.4 `--region`

操作対象のリージョンを指定します。

```bash
aws ec2 describe-vpcs --region ap-northeast-1
```

CloudShell では、開いたリージョンがデフォルトで設定されていますが、
手順書では明示的に `--region` を指定して、どのリージョンに作成するかを明確にします。

---

### 2.5 `--tag-specifications`

リソース作成時に Name タグを付与します。
マネジメントコンソールで「名前」として表示されるので、必ず付けます。

```bash
aws ec2 create-vpc \
    --cidr-block "10.0.0.0/16" \
    --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=cli-workshop-vpc}]' \
    --region ap-northeast-1
```

**ポイント**:
- `ResourceType` はリソースの種類（`vpc`, `subnet`, `security-group` 等）
- `Tags` は `Key=xxx,Value=yyy` の配列
- 全体をシングルクォートで囲むと、シェルの特殊文字解釈を避けられる

---

### 2.6 `--dry-run`（参考）

`--dry-run` を付けると、実際にはリソースを作成せずにパラメータの検証だけを行います。

```bash
aws ec2 create-vpc \
    --cidr-block "10.0.0.0/16" \
    --dry-run
```

```output
An error occurred (DryRunOperation) when calling the CreateVpc operation: Request would have succeeded, but DryRun flag is set.
```

`DryRunOperation` エラーが返れば、パラメータは正しく、実行すれば成功するという意味です。
本ワークショップでは使いませんが、本番運用で「実行前に確認したい」場面で役立ちます。

---

## まとめ

本編で繰り返し使うパターンを表にまとめます。

| パターン | 使う場面 | 例 |
|---------|---------|-----|
| 変数セット + 確認 | 手順の冒頭でパラメータ準備 | `VPC_CIDR="10.0.0.0/16"` → `cat << ETX` |
| コマンド置換 + && | リソース ID の取得・確認 | `VPC_ID=$(...) && echo ${VPC_ID}` |
| describe + filters + query | 事前条件・完了条件の確認 | `aws ec2 describe-vpcs --filters ... --query ... --output text` |
| create + tag-specifications | リソース作成 | `aws ec2 create-vpc --tag-specifications ...` |
| ヒアドキュメント → ファイル | JSON ポリシーの作成 | `cat << 'EOF' > policy.json` |

これらのパターンに慣れておけば、手順書のコマンドがスムーズに読めるようになります。
では、[ハンズオン概要](./hands-on/00-overview.md) に進みましょう。
