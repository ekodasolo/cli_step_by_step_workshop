# CLAUDE.md — プロジェクト規約

## プロジェクト概要

AWS CLI で VPC + ALB + ASG の構成を手動構築するハンズオンコンテンツの開発プロジェクト。
CloudFormation ワークショップ（`../cfn_workshop/`）と同一構成を CLI で構築する姉妹編。
対象者は AWS の基礎知識を持つ社内メンバー。

---

## ユーザー（Yohei）について

- このプロジェクトの開発者を「Yohei」と呼ぶ
- Web アプリケーション開発は初心者のため、教育的な観点での解説やわかりやすい説明を心がける
- 技術的な判断をする際は、なぜそうするのかの背景も添える

---

## 仕様管理・ナレッジ管理

- **SPEC.md**: ワークショップで作成するものの仕様をまとめたファイル。設計・実装はこのファイルを参照して行う。仕様変更時は SPEC.md を更新する
- **TODOS.md**: タスクの内容を先にこのファイルにまとめてから、タスクを順番に消化する。タスクが一つ終わるごとにこのファイルを更新して進捗状況をまとめる
- **ISSUES.md**: 開発中に発生したエラーやトラブルの内容を記録する。発生状況・原因・対処法をセットで残す
- **KNOWLEDGE.md**: ISSUES.md での対応から得られたナレッジや TIPS をまとめる。今後の開発やハンズオン運営に活かせる知見を蓄積する

---

## ディレクトリ構成

```
cli_workshop/
├── SPEC.md              # ワークショップ仕様
├── TODOS.md             # タスク管理
├── CLAUDE.md            # このファイル（プロジェクト規約）
├── ISSUES.md            # エラー・トラブル記録
├── KNOWLEDGE.md         # ナレッジ・TIPS 集
├── docs/
│   ├── introduction.md           # イントロダクション（Bash 基礎 + AWS CLI 基礎）
│   ├── cli-workshop-outline.md   # ワークショップ設計書
│   ├── instructor-guide.md       # 講師ガイド
│   └── hands-on/
│       ├── 00-overview.md           # 全体概要・ナビゲーション
│       ├── 01-step01-vpc.md         # Step 01: VPC 作成
│       ├── 02-step02-subnets.md     # Step 02: Subnet 作成
│       ├── 03-step03-igw-routes.md  # Step 03: IGW + RouteTable
│       ├── 04-step04-sg.md          # Step 04: Security Group
│       ├── 05-step05-iam.md         # Step 05: IAM Role
│       ├── 06-step06-ec2.md         # Step 06: EC2
│       ├── 07-step07-alb.md         # Step 07: ALB
│       ├── 08-step08-asg.md         # Step 08: ASG
│       └── 09-step09-cleanup.md     # Step 09: クリーンアップ
├── scripts/                         # 講師用・完成形スクリプト
│   ├── create-all.sh                # 全リソース一括作成
│   └── cleanup-all.sh               # 全リソース一括削除
└── app/
    └── generate-page.sh             # カレンダーアプリ（CFn 版と同一）
```

---

## コード・ドキュメントの言語方針

| 対象 | 言語 | 例 |
|---|---|---|
| ドキュメント（.md 等） | 日本語 | 手順書、講師ガイド |
| コード内コメント | 日本語 | `# VPC を作成する` |
| 変数名 | 英語 | `VPC_ID`, `SUBNET_1A_CIDR` |
| AWS CLI コマンド | 英語 | `aws ec2 create-vpc` |
| 手順書内の説明文 | 日本語 | 「VPCが作成済みであれば、期待通り。」 |

基本方針: **システム的なものは英語、人間が説明を受けるためのものは日本語**

---

## バージョン管理

- Git で管理する
- リポジトリはこのプロジェクトディレクトリをルートとする

---

## JSON バリデーションルール

手順書でヒアドキュメント等を使って JSON ファイルを作成した場合、**必ず直後に `jsonlint` でバリデーションする**。

```bash
jsonlint -q ファイル名.json
```

- `-q` オプションで正常時はサイレント（出力なし）、エラー時のみメッセージが出る
- ワークショップ冒頭（00-overview.md）で `npm install -g jsonlint` を実施する前提
- このルールに例外はない。JSON を作ったら必ずチェックする

---

## 手順書のフォーマット

Yohei の標準手順書フォーマットに準拠する（詳細は SPEC.md 参照）:

- **About**: 手順の概要
- **When**: 事前条件（Before）と完了条件（After）
- **How**: 前処理 → 主処理 → 後処理
- パラメータは冒頭でシェル変数にセット → `cat << ETX` で確認
- 事前条件を `describe` で確認してから `create`
- 完了条件も `describe` で確認
- パラメータの事後確認用 `.env` ファイル出力
- 各コマンドに `output` の例を付ける
- **Navigation** で次の手順にリンク

---

## 姉妹プロジェクトとの関係

- **[CFn ワークショップ](https://github.com/ekodasolo/cfn_step_by_step_workshop)** と同一の最終構成を、異なるツール（AWS CLI）で構築する
- カレンダーアプリ（`app/generate-page.sh`）は CFn 版と同一のものを使用する
- アーキテクチャの詳細は CFn ワークショップの `docs/cfn-workshop-outline.md` を参照

---

## 作業の進め方

- 作業が完了したら、その内容を **TODOS.md に反映**（該当タスクを `[x]` に更新）してから、Yohei に報告する
- 作業ごとに **Git のコミットを作成**する

---

## Claude Code との協業原則

### ドキュメント駆動

- `SPEC.md`, `TODOS.md`, `CLAUDE.md` がプロジェクトの記憶装置になる
- セッションが切れてもこれらのファイルからコンテキストを復元できるので、常に最新に保つ
- 新しいセッションを開始したら、まずこれらを読んで現状を把握する

### 小さく作って確認する

- 1 タスク 1 コミットで進める
- 手順書は 1 ステップずつ作成し、実際に CloudShell で動作確認してからNext に進む

### エラーとナレッジの蓄積

- トラブルが起きたら `ISSUES.md` に記録し、得られた知見は `KNOWLEDGE.md` にまとめる
- 同じ問題を繰り返さないための仕組みとして機能する
