# AWS CLI ワークショップ 構想まとめ

## コンセプト

AWS CLI を使って VPC + ALB + ASG の構成を **1 リソースずつ手で作る**ことで、
CloudFormation や CDK が裏でやっている **AWS API のナマの仕組み**を理解するワークショップ。

手順書からコマンドをコピー＆実行する対話的な形式で進め、
各コマンドの意味・リソース間の依存関係・ID の引き回しを体感する。

---

## ワークショップ基本情報

| 項目 | 内容 |
|---|---|
| 所要時間 | 制限なし（必要なだけ） |
| 形式 | ハンズオン（手順書からコマンドをコピーして CloudShell で実行） |
| 実行環境 | AWS CloudShell |
| リージョン | `ap-northeast-1`（東京）固定 |
| 環境 | 1 環境のみ |
| エラーハンドリング | ハッピーパターンのみ |
| 姉妹ワークショップ | CloudFormation ワークショップ（同一構成を CFn で構築） |

---

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

- **DB 不使用**: EC2 でスタティックな Web サイトをホスト
- EC2 の UserData で httpd を起動し、シェルスクリプトでカレンダーページを生成
- **表示内容**: 当月カレンダー + EC2 メタデータ（Instance ID / Private IP）
  - ALB でリロードすると別インスタンスに振り分けられ、ロードバランシングを実感できる
- **SSM Session Manager** でアクセス（キーペア不使用）

---

## 段階的構築ステップ

### ネットワーク編

#### Step 01: VPC 作成

**作るもの**: VPC 1 つ

**学ぶこと**:
- `aws ec2 create-vpc` の基本構文
- `--query` + `--output text` でレスポンスから ID を抽出
- シェル変数への格納パターン（`VPC_ID=$(...) && echo ${VPC_ID}`）
- `describe-vpcs` による確認
- `--tag-specifications` で Name タグ付与

**主な CLI コマンド**:
- `aws ec2 create-vpc`
- `aws ec2 describe-vpcs`
- `aws ec2 modify-vpc-attribute`（DNS ホスト名有効化）

---

#### Step 02: Subnet 作成（× 2）

**作るもの**: パブリックサブネット × 2（Multi-AZ: 1a, 1c）

**学ぶこと**:
- `aws ec2 create-subnet` で AZ とサブネットを指定
- `modify-subnet-attribute` でパブリック IP 自動付与を有効化
- 同じ構造のリソースを 2 つ作る（パラメータだけ変える）

**主な CLI コマンド**:
- `aws ec2 create-subnet`
- `aws ec2 modify-subnet-attribute`
- `aws ec2 describe-subnets`

---

#### Step 03: IGW + RouteTable + Route

**作るもの**: Internet Gateway / VPC へのアタッチ / RouteTable / デフォルトルート / サブネット関連付け

**学ぶこと**:
- リソース間の依存関係を手動で管理する（IGW 作成 → アタッチ → Route 作成の順序）
- 1 つのリソースを作るために複数のコマンドが必要な場合がある
- 「アタッチ」「関連付け」という概念（リソース同士を紐付ける操作）

**主な CLI コマンド**:
- `aws ec2 create-internet-gateway`
- `aws ec2 attach-internet-gateway`
- `aws ec2 create-route-table`
- `aws ec2 create-route`
- `aws ec2 associate-route-table`

---

#### Step 04: Security Group 作成（× 2）

**作るもの**: ALB 用 SG（HTTP 80 を公開）/ EC2 用 SG（ALB SG からのみ HTTP 許可）

**学ぶこと**:
- `create-security-group` で SG を作成（VPC 内に作る）
- `authorize-security-group-ingress` でインバウンドルールを追加
- SG 間参照（`--source-group` で ALB SG を指定 → EC2 SG に許可）
- セキュリティの多層防御の考え方

**主な CLI コマンド**:
- `aws ec2 create-security-group`
- `aws ec2 authorize-security-group-ingress`
- `aws ec2 describe-security-groups`

---

### アプリケーション編

#### Step 05: IAM Role + Instance Profile

**作るもの**: SSM Session Manager 用の IAM ロール / インスタンスプロファイル

**学ぶこと**:
- 信頼ポリシー（JSON）をヒアドキュメントでファイルに書き出す
- `iam create-role` で信頼ポリシーを指定してロール作成
- マネージドポリシーの ARN を指定してアタッチ
- インスタンスプロファイルの作成とロールの追加（2 ステップ）
- EC2 がロールを引き受ける（AssumeRole）仕組みの理解

**主な CLI コマンド**:
- `aws iam create-role`
- `aws iam attach-role-policy`
- `aws iam create-instance-profile`
- `aws iam add-role-to-instance-profile`

---

#### Step 06: EC2 インスタンス作成

**作るもの**: EC2 インスタンス 1 台（カレンダーアプリ）

**学ぶこと**:
- `run-instances` の主要パラメータ（AMI, InstanceType, SubnetId, SecurityGroupIds 等）
- UserData の渡し方（`--user-data fileb://` でスクリプトファイルを指定）
- AMI ID の確認方法（SSM パラメータストアから最新の Amazon Linux 2023 を取得）
- SSM Session Manager で EC2 に接続して動作確認
- `curl localhost` で HTTP 応答を確認

**主な CLI コマンド**:
- `aws ssm get-parameters`（AMI ID 取得）
- `aws ec2 run-instances`
- `aws ec2 describe-instances`
- `aws ec2 wait instance-running`
- `aws ssm start-session`

---

#### Step 07: ALB + Target Group + Listener

**作るもの**: ALB / ターゲットグループ / リスナー / ターゲット登録

**学ぶこと**:
- ALB の 3 層構造（ALB → Listener → TargetGroup → Targets）
- 各リソースを個別に作成して紐付ける流れ
- ALB は作成に時間がかかる → `wait` で完了を待つ
- ヘルスチェックの仕組み（healthy になるまで待つ）
- ALB の DNS 名でブラウザからアクセス確認

**主な CLI コマンド**:
- `aws elbv2 create-load-balancer`
- `aws elbv2 create-target-group`
- `aws elbv2 create-listener`
- `aws elbv2 register-targets`
- `aws elbv2 wait load-balancer-available`
- `aws elbv2 describe-target-health`

---

#### Step 08: Launch Template + Auto Scaling Group

**作るもの**: Launch Template / Auto Scaling Group / 単体 EC2 の削除

**学ぶこと**:
- Launch Template: EC2 の設定をテンプレート化する
- Auto Scaling Group: 複数の EC2 をまとめて管理する
- ASG とターゲットグループの紐付け
- 単体 EC2 から ASG への移行（単体 EC2 をターゲットから外す → ASG で置き換え → 単体 EC2 を削除）
- ASG が自動で EC2 を起動・管理する様子を確認

**主な CLI コマンド**:
- `aws ec2 create-launch-template`
- `aws autoscaling create-auto-scaling-group`
- `aws elbv2 deregister-targets`（単体 EC2 をターゲットから外す）
- `aws ec2 terminate-instances`（単体 EC2 を削除）
- `aws autoscaling describe-auto-scaling-groups`

---

#### Step 09: クリーンアップ

**削除するもの**: 全リソースを依存関係の逆順で削除

**学ぶこと**:
- CLI でリソースを削除する場合、依存関係の逆順で行う必要がある
- CloudFormation ならスタック削除 1 回で完了するが、CLI では 1 つずつ
- 削除順序を間違えるとエラーになる（依存しているリソースがまだ存在する）
- `wait` による削除完了の待機

**削除順序**:
1. Auto Scaling Group（EC2 が自動終了される）
2. Launch Template
3. ALB Listener
4. ALB
5. Target Group
6. IAM（Instance Profile からロール除去 → Profile 削除 → ポリシーデタッチ → ロール削除）
7. Security Group（× 2）
8. Subnet-RouteTable 関連付け解除
9. Route 削除
10. RouteTable
11. IGW デタッチ → 削除
12. Subnet（× 2）
13. VPC

---

## 学習要素の対応表

| Step | 主な CLI コマンド | 学ぶ概念 |
|------|------------------|---------|
| 01 | `ec2 create-vpc`, `describe-vpcs` | `--query` / `--output` / シェル変数 |
| 02 | `ec2 create-subnet`, `modify-subnet-attribute` | AZ 指定、属性変更 |
| 03 | `ec2 create-internet-gateway`, `attach-*`, `create-route-table`, `create-route`, `associate-*` | リソース間の依存関係 |
| 04 | `ec2 create-security-group`, `authorize-security-group-ingress` | SG 間参照、インバウンドルール |
| 05 | `iam create-role`, `attach-role-policy`, `create-instance-profile` | 信頼ポリシー（JSON）、IAM の構造 |
| 06 | `ec2 run-instances`, `ssm start-session` | UserData、AMI 取得、SSM 接続 |
| 07 | `elbv2 create-load-balancer`, `create-target-group`, `create-listener` | ALB の 3 層構造、`wait` |
| 08 | `ec2 create-launch-template`, `autoscaling create-auto-scaling-group` | テンプレート化、ASG 管理 |
| 09 | 各 `delete` / `terminate` / `deregister` | 依存関係の逆順削除 |

---

## CFn ワークショップとの対応関係

| CFn ワークショップ | CLI ワークショップ | 備考 |
|---|---|---|
| Step 1: VPC | Step 01: VPC 作成 | 同一内容 |
| Step 2: Subnets + Parameters | Step 02: Subnets 作成 | Parameters は不要（シェル変数で直接指定） |
| Step 3: IGW + Routes + DependsOn | Step 03: IGW + Routes | 依存関係は手動で順序制御 |
| Step 4: SG + Outputs/Export | Step 04: SG 作成 | Outputs/Export は不要（シェル変数で管理） |
| Step 5: EC2 + ImportValue + Mappings | Step 05: IAM + Step 06: EC2 | IAM を独立ステップに分離 |
| Step 6: ALB | Step 07: ALB | 同一内容 |
| Step 7: ASG + Conditions | Step 08: ASG | Conditions は省略（1 環境のみ） |
| — | Step 09: クリーンアップ | CFn はスタック削除で完了。CLI は逆順で 1 つずつ |

---

## CLI ワークショップならではの学び

CloudFormation ワークショップでは体験できない、CLI ワークショップ固有の学習ポイント:

| ポイント | 説明 |
|---------|------|
| **リソース ID の引き回し** | `--query` + `--output text` で ID を取得し、シェル変数で次のコマンドに渡す |
| **依存関係の手動管理** | CFn は自動解決するが、CLI では正しい順序で作成・削除する必要がある |
| **API レスポンスの読み方** | JSON レスポンスの構造を理解し、`--query` で必要な値を抽出する |
| **逆順削除の必要性** | CFn はスタック削除で一括だが、CLI では依存関係の逆順で 1 つずつ削除する |
| **`describe` による状態確認** | 作成前・作成後に `describe` で状態を確認するオペレーションの基本動作 |
| **`wait` による完了待ち** | 非同期リソース（EC2, ALB 等）の完了を `wait` で待つ |

---

## 前提条件

- **参加者**: AWS の基礎知識あり（VPC, EC2, SG の概念は知っている前提）
- **実行環境**: AWS CloudShell
- **参照資料**: AWS CLI リファレンス、`aws <service> <command> help`
- **リージョン**: `ap-northeast-1`（東京）固定
