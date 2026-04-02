# SPEC.md — AWS CLI ワークショップ仕様

## コンセプト

AWS CLI を使って VPC + ALB + ASG の構成を **1 リソースずつ手で作る**ことで、
CloudFormation や CDK が裏でやっている **AWS API のナマの仕組み**を理解するワークショップ。

手順書からコマンドをコピー＆実行する形式で進め、
各コマンドの意味・リソース間の依存関係・ID の引き回しを体感する。

---

## ワークショップ基本情報

| 項目 | 内容 |
|---|---|
| 所要時間 | 制限なし（必要なだけ） |
| 形式 | ハンズオン（手順書からコマンドをコピーして CloudShell で実行） |
| 実行環境 | AWS CloudShell（`aws configure` 済み） |
| リージョン | `ap-northeast-1`（東京）固定 |
| 環境 | 1 環境のみ（prod/dev の切り替えなし） |
| エラーハンドリング | ハッピーパターンのみ |
| 進め方 | 手順書の指示に沿い、コマンドをコピー＆実行。出力例と照合して確認 |

---

## 完成形アーキテクチャ

CloudFormation ワークショップと同一の構成を構築する。

```
            Internet
               │
         ┌─────┴─────┐
         │    IGW     │
         └─────┬─────┘
               │
    ┌──────────┴──────────┐
    │        VPC          │
    │   (10.0.0.0/16)     │
    │  ┌───────┬────────┐ │
    │  │Pub-1a │ Pub-1c │ │  ← パブリックサブネット × 2 (Multi-AZ)
    │  │.1.0/24│.2.0/24 │ │
    │  │       │        │ │
    │  │  EC2  │  EC2   │ │  ← Auto Scaling Group で管理
    │  └───┬───┴───┬────┘ │
    │      └───┬───┘      │
    │      ┌───┴───┐      │
    │      │  ALB  │      │
    │      └───────┘      │
    └─────────────────────┘
```

- **DB 不使用**: EC2 でスタティックな Web サイトをホスト
- EC2 の UserData で httpd を起動し、シェルスクリプトでカレンダーページを生成
- **表示内容**: 当月カレンダー + EC2 メタデータ（Instance ID / Private IP）
- ALB でリロードすると別インスタンスに振り分けられ、ロードバランシングを実感できる
- **SSM Session Manager** でアクセス（キーペア不使用）

---

## 作成リソース一覧

### ネットワーク系

| # | リソース | 名前（Name タグ） | 主要パラメータ |
|---|---------|-------------------|---------------|
| 1 | VPC | `cli-workshop-vpc` | CIDR: `10.0.0.0/16`, DNS サポート有効 |
| 2 | Subnet (1a) | `cli-workshop-public-1a` | CIDR: `10.0.1.0/24`, AZ: `ap-northeast-1a`, パブリック IP 自動付与 |
| 3 | Subnet (1c) | `cli-workshop-public-1c` | CIDR: `10.0.2.0/24`, AZ: `ap-northeast-1c`, パブリック IP 自動付与 |
| 4 | Internet Gateway | `cli-workshop-igw` | VPC にアタッチ |
| 5 | Route Table | `cli-workshop-public-rt` | VPC に紐付け |
| 6 | Route | — | `0.0.0.0/0` → IGW |
| 7 | Subnet-RT 関連付け (×2) | — | Subnet 1a, 1c それぞれ |
| 8 | SG (ALB用) | `cli-workshop-alb-sg` | インバウンド: TCP 80 from `0.0.0.0/0` |
| 9 | SG (EC2用) | `cli-workshop-web-sg` | インバウンド: TCP 80 from ALB SG のみ |

### アプリケーション系

| # | リソース | 名前 | 主要パラメータ |
|---|---------|------|---------------|
| 10 | IAM Role | `cli-workshop-web-server-role` | 信頼: `ec2.amazonaws.com`, ポリシー: `AmazonSSMManagedInstanceCore` |
| 11 | Instance Profile | `cli-workshop-web-server-profile` | 上記ロールを紐付け |
| 12 | EC2 (動作確認用) | `cli-workshop-web-server` | AMI: Amazon Linux 2023, Type: `t2.micro`, UserData: カレンダーアプリ |
| 13 | ALB | `cli-workshop-alb` | Scheme: `internet-facing`, Type: `application` |
| 14 | Target Group | `cli-workshop-tg` | Protocol: HTTP, Port: 80, ヘルスチェック: `/` |
| 15 | Listener | — | Port: 80 → Target Group に forward |
| 16 | Launch Template | `cli-workshop-lt` | AMI, InstanceType, SG, IAM Profile, UserData |
| 17 | Auto Scaling Group | `cli-workshop-asg` | Min: 2, Max: 4, Desired: 2, 2 AZ |

---

## 手順書の構成

### ステップ分割

| Step | 手順書ファイル | 内容 | 学ぶこと |
|------|---------------|------|---------|
| 01 | `01-create-vpc.md` | VPC 作成 | `create-vpc`, `describe-vpcs`, `--query`, `--output text`, シェル変数 |
| 02 | `02-create-subnets.md` | Subnet × 2 作成 | `create-subnet`, AZ 指定, パブリック IP 自動付与 (`modify-subnet-attribute`) |
| 03 | `03-create-igw-routes.md` | IGW + RouteTable + Route | `create-internet-gateway`, `attach-internet-gateway`, `create-route-table`, `create-route`, `associate-route-table` |
| 04 | `04-create-security-groups.md` | SG × 2 作成 | `create-security-group`, `authorize-security-group-ingress`, SG 間参照 |
| 05 | `05-create-iam-role.md` | IAM Role + Instance Profile | `iam create-role`, `iam attach-role-policy`, `iam create-instance-profile`, `iam add-role-to-instance-profile` |
| 06 | `06-create-ec2.md` | EC2 単体作成・動作確認 | `run-instances`, `--user-data`, SSM 接続確認, EC2 単体での HTTP 確認 |
| 07 | `07-create-alb.md` | ALB + TG + Listener | `elbv2 create-load-balancer`, `create-target-group`, `create-listener`, `register-targets` |
| 08 | `08-create-asg.md` | Launch Template + ASG | `create-launch-template`, `autoscaling create-auto-scaling-group`, `attach-load-balancer-target-groups`, EC2→ASG への移行体験 |
| 09 | `09-cleanup.md` | 全リソース削除（逆順） | 依存関係を意識した削除順序の理解 |

### 各手順書のフォーマット

Yohei の標準手順書フォーマットに準拠する。

```markdown
# [XXYY] タイトル

## About
手順の概要説明。

## When: 作業の条件

### Before: 事前前提条件
1. ...

### After: 作業終了状況
1. ...

## How: 以下は作業手順

### 1. 前処理

#### 1.1 処理パラメータの準備
- RUNBOOK_TITLE, FILE_PARAMETER の設定
- 手順の実行パラメータをシェル変数にセット
- `cat << ETX` で変数値を確認

#### 1.2〜 事前条件の確認
- `describe` 系コマンドで事前条件を確認

### 2. 主処理

#### 2.1 リソースの操作 (CREATE)
- パラメータの最終確認（.env ファイルに書き出し）
- `create` 系コマンドの実行

### 3. 後処理

#### 3.1 完了条件の結果確認
- `describe` 系コマンドで完了条件を確認

#### 3.99 中間リソースの削除
- 不要な中間リソースがあれば削除

#### Navigation
- Next: 次の手順へのリンク
```

---

## 手順書の番号体系

CFn ワークショップのステップ番号に対応させた 4 桁コード:

| コード | 手順書 |
|--------|--------|
| `0100` | Step 01: VPC 作成 |
| `0201` | Step 02: Subnet 作成 (1a) |
| `0202` | Step 02: Subnet 作成 (1c) |
| `0203` | Step 02: Subnet パブリック IP 自動付与 |
| `0301` | Step 03: IGW 作成・アタッチ |
| `0302` | Step 03: RouteTable 作成・Route 追加 |
| `0303` | Step 03: Subnet-RouteTable 関連付け |
| `0401` | Step 04: ALB 用 SG 作成 |
| `0402` | Step 04: EC2 用 SG 作成 |
| `0501` | Step 05: IAM Role 作成 |
| `0502` | Step 05: Instance Profile 作成 |
| `0601` | Step 06: EC2 インスタンス作成 |
| `0602` | Step 06: 動作確認（SSM + HTTP） |
| `0701` | Step 07: ALB 作成 |
| `0702` | Step 07: Target Group 作成 |
| `0703` | Step 07: Listener 作成・ターゲット登録 |
| `0801` | Step 08: Launch Template 作成 |
| `0802` | Step 08: ASG 作成 |
| `0803` | Step 08: EC2→ASG 移行（単体 EC2 削除） |
| `0901` | Step 09: クリーンアップ |

---

## 学習要素の対応表

| Step | 学ぶ AWS CLI 操作 | 学ぶ概念 |
|------|------------------|---------|
| 01 | `ec2 create-vpc`, `describe-vpcs` | `--query` / `--output` によるフィルタリング、シェル変数への格納 |
| 02 | `ec2 create-subnet`, `modify-subnet-attribute` | AZ の指定、サブネット属性の変更 |
| 03 | `ec2 create-internet-gateway`, `attach-internet-gateway`, `create-route-table`, `create-route`, `associate-route-table` | リソース間の依存関係（IGW→Route の順序） |
| 04 | `ec2 create-security-group`, `authorize-security-group-ingress` | SG 間参照（`--source-group`）、インバウンドルール |
| 05 | `iam create-role`, `attach-role-policy`, `create-instance-profile`, `add-role-to-instance-profile` | 信頼ポリシー（JSON）、マネージドポリシーの ARN |
| 06 | `ec2 run-instances`, `ssm start-session` | UserData（Base64）、AMI ID の確認方法、SSM 接続 |
| 07 | `elbv2 create-load-balancer`, `create-target-group`, `create-listener`, `register-targets` | ALB の 3 層構造（ALB→Listener→TG） |
| 08 | `ec2 create-launch-template`, `autoscaling create-auto-scaling-group` | Launch Template と ASG の関係、ローリング更新 |
| 09 | 各 `delete` / `terminate` / `deregister` コマンド | 依存関係の逆順削除、削除待ち（`wait`） |

---

## CLI ワークショップ固有の学習ポイント

CloudFormation ワークショップでは学べない、CLI ならではの学び:

| ポイント | 説明 |
|---------|------|
| **リソース ID の引き回し** | `--query` + `--output text` で ID を取得し、シェル変数に格納して次のコマンドで使う |
| **依存関係の手動管理** | CFn は自動解決するが、CLI では自分で正しい順序を意識する必要がある |
| **API レスポンスの読み方** | JSON レスポンスの構造を理解し、必要な値を `--query` で抽出する |
| **逆順削除の必要性** | CFn はスタック削除で一括だが、CLI では依存関係の逆順で 1 つずつ削除する |
| **`describe` による状態確認** | 作成前・作成後に `describe` で状態を確認するオペレーションの基本動作 |
| **`wait` による完了待ち** | 非同期リソース（EC2, ALB 等）の作成完了を `wait` で待つ |
| **UserData の Base64 エンコード** | CLI では `--user-data fileb://` または `file://` でスクリプトを渡す |

---

## CFn ワークショップとの対応関係

| CFn ワークショップ | CLI ワークショップ | 備考 |
|---|---|---|
| Step 1: VPC | Step 01: VPC 作成 | 同一 |
| Step 2: Subnets + Parameters | Step 02: Subnets 作成 | Parameters は不要（直接値を指定） |
| Step 3: IGW + Routes | Step 03: IGW + Routes | CFn では 1 テンプレートだが CLI では複数コマンド |
| Step 4: SG + Outputs | Step 04: SG 作成 | Outputs/Export は不要（シェル変数で管理） |
| Step 5: EC2 + ImportValue + Mappings | Step 05: IAM + Step 06: EC2 | ImportValue/Mappings は不要、IAM を独立ステップに |
| Step 6: ALB | Step 07: ALB | 同一内容 |
| Step 7: ASG + Conditions | Step 08: ASG | Conditions は省略（1 環境のみ） |
| — | Step 09: クリーンアップ | CFn はスタック削除で完了、CLI は逆順で 1 つずつ |

---

## パラメータ定義

全手順で共通して使用するパラメータ:

```bash
# リージョン
AWS_REGION="ap-northeast-1"

# プロジェクト名（Name タグのプレフィックス）
PROJECT_NAME="cli-workshop"

# ネットワーク
VPC_CIDR="10.0.0.0/16"
SUBNET_1A_CIDR="10.0.1.0/24"
SUBNET_1C_CIDR="10.0.2.0/24"
SUBNET_1A_AZ="ap-northeast-1a"
SUBNET_1C_AZ="ap-northeast-1c"

# EC2
INSTANCE_TYPE="t2.micro"
# AMI_ID はワークショップ実施前に最新の Amazon Linux 2023 を確認して設定
```

---

## ディレクトリ構成

```
cli_workshop/
├── SPEC.md              # このファイル（仕様）
├── TODOS.md             # タスク管理
├── CLAUDE.md            # プロジェクト規約
├── ISSUES.md            # エラー・トラブル記録
├── KNOWLEDGE.md         # ナレッジ・TIPS 集
├── docs/
│   ├── introduction.md           # イントロダクション（Bash 基礎 + AWS CLI 基礎）
│   ├── cli-workshop-outline.md   # ワークショップ設計書
│   ├── instructor-guide.md       # 講師ガイド
│   └── hands-on/
│       ├── 00-overview.md           # 全体概要・ナビゲーション
│       ├── 01-step01-vpc.md         # Step 01 の全手順
│       ├── 02-step02-subnets.md     # Step 02 の全手順
│       ├── 03-step03-igw-routes.md  # Step 03 の全手順
│       ├── 04-step04-sg.md          # Step 04 の全手順
│       ├── 05-step05-iam.md         # Step 05 の全手順
│       ├── 06-step06-ec2.md         # Step 06 の全手順
│       ├── 07-step07-alb.md         # Step 07 の全手順
│       ├── 08-step08-asg.md         # Step 08 の全手順
│       └── 09-step09-cleanup.md     # Step 09: クリーンアップ
├── scripts/                         # 講師用・完成形スクリプト
│   ├── create-all.sh                # 全リソース一括作成
│   └── cleanup-all.sh               # 全リソース一括削除
└── app/
    └── generate-page.sh             # カレンダーアプリ（CFn 版と同一）
```

---

## 前提条件

- **参加者**: AWS の基礎知識あり（VPC, EC2, SG の概念は知っている前提）
- **実行環境**: AWS CloudShell（追加インストール不要）
- **認証**: CloudShell のため `aws configure` 不要（IAM ユーザーの権限で自動認証）
- **参照資料**: AWS CLI リファレンス（`aws ec2 create-vpc help` 等）
- **リージョン**: `ap-northeast-1`（東京）固定

---

## イントロダクション（introduction.md）の構成

ハンズオン本編で頻出する Bash と AWS CLI の基礎を、冒頭でまとめて解説する。

### セクション 1: Bash の基礎

CLI 手順書で繰り返し登場する Bash の機能を復習する。

| トピック | 手順書での使用場面 | 例 |
|---------|-------------------|-----|
| **シェル変数** | リソース ID の格納・参照 | `VPC_ID="vpc-xxx"`, `echo ${VPC_ID}` |
| **コマンド置換** | AWS CLI の戻り値をシェル変数に格納 | `VPC_ID=$(aws ec2 describe-vpcs ...)` |
| **ヒアドキュメント** | パラメータ確認、JSON ポリシーの記述 | `cat << ETX ... ETX`, `cat << 'EOF' > trust-policy.json ... EOF` |
| **リダイレクトとパイプ** | ファイルへの書き出し、コマンド連携 | `> file.json`, `\| jq .` |
| **`&&` によるコマンド連結** | 成功時のみ次を実行（値の格納直後に確認） | `VPC_ID=$(...) && echo ${VPC_ID}` |

### セクション 2: AWS CLI の基礎

ハンズオン全体を通じて使う AWS CLI の共通オプション・パターンを解説する。

| トピック | 説明 | 例 |
|---------|------|-----|
| **`--output` の使い分け** | `json`（デフォルト・詳細確認）, `text`（変数格納用）, `table`（視認用） | `--output text`, `--output table` |
| **`--query`（JMESPath）** | JSON レスポンスから必要な値を抽出する | `--query 'Vpc.VpcId'`, `--query 'Vpcs[].VpcId'` |
| **`--filters`** | `describe` 系でリソースを絞り込む | `--filters "Name=cidr,Values=10.0.0.0/16"` |
| **`--region`** | リージョン指定（CloudShell では環境変数で設定済みだが明示する） | `--region ap-northeast-1` |
| **`--tag-specifications`** | リソース作成時に Name タグを付与 | `--tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=xxx}]'` |
| **`--dry-run`** | 実行前のパラメータ検証（参考情報として紹介） | `--dry-run` |

---

## JSON バリデーションルール

手順書内でヒアドキュメント等を使って JSON ファイルを作成した場合、**作成直後に必ず `jsonlint` でバリデーションする**。

```bash
# JSON ファイル作成後、必ず実行する
jsonlint -q ファイル名.json
```

- ワークショップ冒頭（00-overview.md の環境準備）で `npm install -g jsonlint` を実施する
- `-q` オプション: 正常時はサイレント、エラー時のみメッセージ出力
- このルールに例外はない

---

## 手順書の記述方針

- 手順書からコピー＆ペーストで実行できるようにする
- 各コマンドに `output` ブロックで出力例を付ける
- リソース ID は `vpc-0xxxxxxxxEXAMPLE` のようなダミー値を使う
- シェル変数への格納は `$()` + `--query` + `--output text` のパターンを統一的に使う
- `describe` による事前確認・事後確認を必ず入れる（Before/After の検証）
- コマンドの意味は手順書内のコメントや説明文で補足する
