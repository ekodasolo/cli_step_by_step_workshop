# 講師ガイド — AWS CLI ワークショップ

## 概要

このドキュメントは、AWS CLI ワークショップを運営する講師向けのガイドです。

---

## 事前準備

### 1. 参加者の AWS 環境

- 各参加者に IAM ユーザー（または SSO アクセス）を用意する
- 必要な権限:
  - `AmazonEC2FullAccess`
  - `AmazonVPCFullAccess`
  - `ElasticLoadBalancingFullAccess`
  - `IAMFullAccess`
  - `AmazonSSMFullAccess`
  - `AutoScalingFullAccess`
- リージョンは `ap-northeast-1` に統一

### 2. 講師環境の動作確認

ワークショップ前に、講師用スクリプトで環境を作成・削除して動作確認しておく。

```bash
# 全リソース一括作成
./scripts/create-all.sh

# ブラウザで ALB URL にアクセスして動作確認

# 全リソース一括削除
./scripts/cleanup-all.sh
```

### 3. AMI ID の確認

手順書の AMI 取得は SSM パラメータストアから動的に行うため、通常は更新不要。
ただし、ワークショップ前に以下で最新の AMI ID を確認しておくとよい。

```bash
aws ssm get-parameters \
    --names /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
    --query "Parameters[].Value" \
    --region ap-northeast-1 \
    --output text
```

---

## 進行のポイント

### Step 01〜02: VPC + Subnet

- **最初のステップ**なので丁寧に進める
- `--query` + `--output text` + シェル変数のパターンをここでしっかり定着させる
- 参加者全員が VPC ID を変数に格納できていることを確認してから次へ

### Step 03: IGW + RouteTable

- **リソース間の依存関係**がテーマ
- IGW を作っただけではインターネット接続できない → アタッチ → ルート追加 → サブネット関連付け、という「紐付け」の連鎖を強調
- CFn では自動解決される依存関係を、CLI では自分で管理することを体感させる

### Step 04: Security Group

- **SG 間参照**（`--source-group`）が重要ポイント
- 「ALB を経由したアクセスだけを EC2 に許可する」というセキュリティ設計の意図を説明する
- ネットワーク編の完了を祝う（ここまでで基盤が完成）

### Step 05: IAM

- **JSON ファイルを手で作る**初めてのステップ
- 信頼ポリシーの意味（「誰がこのロールを引き受けられるか」）を図解で説明するとよい
- Instance Profile という「入れ物」が必要な理由: EC2 に直接ロールを付けられない AWS の仕様
- `jsonlint` によるバリデーションの重要性を強調する

### Step 06: EC2

- **動作確認の山場**
- UserData の実行には時間がかかる。`wait instance-running` 後もさらに 1〜2 分待つ必要がある
- SSM 接続ができない場合のトラブルシュート:
  - Instance Profile が正しくアタッチされているか
  - SSM エージェントが起動しているか（起動まで数分かかる）
  - VPC エンドポイントは不要（パブリックサブネット＋IGW があるため）

### Step 07: ALB

- ALB の **3 層構造**（ALB → Listener → TargetGroup）を図示して説明
- ALB の作成には 2〜3 分かかる。`wait` で待っている間に構成を解説するとよい
- ターゲットが `healthy` になるまでのヘルスチェックの仕組みも説明

### Step 08: ASG

- **ワークショップのクライマックス**
- Launch Template: EC2 の設定を「テンプレート化」する概念
- ASG 作成後、自動で EC2 が起動される様子を観察させる
- **ロードバランシングの確認**: ブラウザでリロードして Instance ID が変わることを全員で確認
- 単体 EC2 の削除は「ASG に移行したので不要になった」というストーリーで進める

### Step 09: クリーンアップ

- **CLI ならではの学び**を強調
- 「CFn ならスタック削除 1 回で終わるが、CLI では逆順で 1 つずつ」
- 依存関係を間違えるとどんなエラーが出るか、実演してもよい

---

## トラブルシュート

### よくある問題

| 症状 | 原因 | 対処 |
|------|------|------|
| 変数が空（`echo` で何も出ない） | コマンドのコピーミス、`--query` の間違い | コマンドを再実行。`--output json` にして生データを確認 |
| `An error occurred (DependencyViolation)` | 依存しているリソースがまだ存在する | 先に依存リソースを削除してからリトライ |
| SSM 接続できない | Instance Profile 未設定、SSM エージェント未起動 | `describe-instances` で IamInstanceProfile を確認。数分待つ |
| ALB URL で 502 エラー | EC2 の httpd が未起動、ヘルスチェック未完了 | Target Health を確認。`initial` なら待つ |
| `InvalidParameterValue` | パラメータの値が不正（ID の打ち間違い等） | 変数の値を `echo` で確認 |

### 講師用一括リカバリ

参加者の環境が壊れた場合、一度全削除してから再作成できる。

```bash
# 全削除（エラーを無視しつつ可能な限り削除）
./scripts/cleanup-all.sh

# 全作成
./scripts/create-all.sh
```

---

## CFn ワークショップとの併用

この CLI ワークショップは、CloudFormation ワークショップ（`../cfn_workshop/`）の姉妹編として設計されている。

**併用パターン**:
- **CLI → CFn の順**: 手動でリソースを作る大変さを体感した後に、CFn の自動化の恩恵を実感する
- **CFn → CLI の順**: CFn が裏でやっていることを CLI で紐解く
- **独立実施**: どちらか一方だけでも成立する

**比較ポイントとして使えるネタ**:
- CFn の `DependsOn` → CLI では自分で順序管理
- CFn の `Outputs/Export/ImportValue` → CLI ではシェル変数で ID を引き回す
- CFn のスタック削除 → CLI では逆順で 1 つずつ
- CFn の `Conditions` → CLI では不要（コマンドのパラメータを直接変える）
