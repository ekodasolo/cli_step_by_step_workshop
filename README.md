# AWS CLI ワークショップ

AWS CLI を使って VPC + ALB + ASG の構成を **1 リソースずつ手で作る**ハンズオンワークショップです。
CloudFormation や CDK が裏でやっている AWS API のナマの仕組みを、CLI を通じて理解します。

## 完成形アーキテクチャ

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

ALB の DNS 名にブラウザでアクセスすると、カレンダーページが表示されます。
リロードするたびに Instance ID が変わり、ロードバランシングを体感できます。

## 前提条件

- AWS の基礎知識（VPC, EC2, SG の概念を知っている）
- AWS マネジメントコンソールにログインできる
- 実行環境: **AWS CloudShell**（追加インストール不要）

## 所要時間の目安

全体で **約 2.5〜3 時間** です。

| チャプター | 内容 | 所要目安 | 累計 |
|-----------|------|---------|------|
| [イントロダクション](docs/introduction.md) | Bash 基礎 + AWS CLI 基礎の復習 | 15 分 | 0:15 |
| [Step 01 — VPC](docs/hands-on/01-step01-vpc.md) | VPC 作成、`--query` / `--output` / シェル変数の基本パターン | 10 分 | 0:25 |
| [Step 02 — Subnet](docs/hands-on/02-step02-subnets.md) | パブリックサブネット × 2、AZ 指定、パブリック IP 自動付与 | 15 分 | 0:40 |
| [Step 03 — IGW + Routes](docs/hands-on/03-step03-igw-routes.md) | IGW 作成・アタッチ、RouteTable、Route、サブネット関連付け | 20 分 | 1:00 |
| [Step 04 — Security Group](docs/hands-on/04-step04-sg.md) | ALB 用 SG、EC2 用 SG（SG 間参照） | 15 分 | 1:15 |
| *休憩* | | *10 分* | *1:25* |
| [Step 05 — IAM](docs/hands-on/05-step05-iam.md) | IAM Role（信頼ポリシー JSON）、Instance Profile | 15 分 | 1:40 |
| [Step 06 — EC2](docs/hands-on/06-step06-ec2.md) | EC2 作成、UserData、SSM 接続、HTTP 確認 | 20 分 | 2:00 |
| [Step 07 — ALB](docs/hands-on/07-step07-alb.md) | ALB + Target Group + Listener、ブラウザ確認 | 20 分 | 2:20 |
| [Step 08 — ASG](docs/hands-on/08-step08-asg.md) | Launch Template、ASG 作成、ロードバランシング確認 | 25 分 | 2:45 |
| [Step 09 — クリーンアップ](docs/hands-on/09-step09-cleanup.md) | 全リソースを逆順で削除 | 20 分 | 3:05 |

> Step 06〜07 では AWS リソースの作成待ち（`wait`）が含まれるため、実際の手を動かす時間はもう少し短くなります。

## ディレクトリ構成

```
cli_workshop/
├── README.md                          # このファイル
├── SPEC.md                            # ワークショップ仕様
├── docs/
│   ├── introduction.md                # イントロダクション（Bash + AWS CLI 基礎）
│   ├── cli-workshop-outline.md        # ワークショップ設計書
│   ├── instructor-guide.md            # 講師ガイド
│   └── hands-on/
│       ├── 00-overview.md             # ハンズオン概要
│       ├── 01-step01-vpc.md           # Step 01: VPC
│       ├── 02-step02-subnets.md       # Step 02: Subnet × 2
│       ├── 03-step03-igw-routes.md    # Step 03: IGW + RouteTable
│       ├── 04-step04-sg.md            # Step 04: Security Group × 2
│       ├── 05-step05-iam.md           # Step 05: IAM Role + Instance Profile
│       ├── 06-step06-ec2.md           # Step 06: EC2 + SSM 確認
│       ├── 07-step07-alb.md           # Step 07: ALB + TG + Listener
│       ├── 08-step08-asg.md           # Step 08: Launch Template + ASG
│       └── 09-step09-cleanup.md       # Step 09: クリーンアップ
├── scripts/
│   ├── workshop.env                   # 可変パラメータ（リージョン、CIDR 等）
│   ├── create-all.sh                  # 講師用: 全リソース一括作成
│   └── cleanup-all.sh                 # 講師用: 全リソース一括削除
└── app/
    └── generate-page.sh               # カレンダーアプリ（参考用）
```

## 講師向け: クイックスタート

環境の事前構築・動作確認は講師用スクリプトで行えます。

```bash
# パラメータ確認・変更
vi scripts/workshop.env

# 全リソース一括作成（約 5 分）
./scripts/create-all.sh

# 全リソース一括削除
./scripts/cleanup-all.sh
```

詳細は [講師ガイド](docs/instructor-guide.md) を参照してください。

## 姉妹ワークショップ

このワークショップは [CloudFormation ワークショップ](../cfn_workshop/) と同一の最終構成を、異なるツールで構築する姉妹編です。

| | CFn ワークショップ | CLI ワークショップ（本リポジトリ） |
|---|---|---|
| ツール | CloudFormation テンプレート（YAML） | AWS CLI コマンド |
| 依存関係の管理 | CFn が自動解決 | 自分で順序を制御 |
| パラメータの受け渡し | Parameters / Outputs / ImportValue | シェル変数 |
| 削除 | スタック削除 1 回 | 逆順で 1 つずつ |
| 環境切り替え | Conditions（prod/dev） | なし（1 環境のみ） |
