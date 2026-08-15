---
title: "Entra ID でマルチテナントアプリを構築する際に躓いた4つの基本概念"
emoji: "🔐"
type: "tech"
topics: ["EntraID", "AzureAD", "OAuth", "マルチテナント"]
published: true
---

## はじめに

他テナントの Microsoft 365 リソースと連携する機能を実装する機会がありました。以前は相手テナント側でアプリを作成してもらい、クライアントシークレットを受け取る方式の設計を経験していました。しかし、この方式では相手側の前準備コストが大きくなります。さらに、漏洩すれば相手テナントのリソースへ直接アクセスされるシークレットを、こちらで保管し、有効期限ごとに更新する運用も必要でした。

今回は自組織でアプリ登録するマルチテナント構成を採用しました。相手テナントの準備コストを削減でき、シークレット管理も不要になるためです。ただ、この構成で認可の仕組みを理解するのはなかなかしんどく、腹落ちするまで時間がかかりました。この記事では、私が躓いた4つの基本概念を整理します。

## アプリケーションとエンタープライズアプリケーション

最初に躓いたのが「アプリケーション」と「エンタープライズアプリケーション」の違いです。どちらも「アプリケーション」って名前がついているうえに、Azure Portal でアプリ登録をすると自動的にエンタープライズアプリケーションも作成されます。この振る舞いを先に知っていたこともあり、両者の区別がつかずに混乱しました。

[Microsoft のドキュメント](https://learn.microsoft.com/ja-jp/entra/identity-platform/app-objects-and-service-principals?tabs=browser#service-principal-object)を読んで、ようやく関係性が整理できました。

- アプリケーション（アプリ登録）はアプリの定義情報。いわば「設計図」にあたる
- エンタープライズアプリケーション（サービスプリンシパル）は各テナントにおけるアプリの実体。設計図から作られた「インスタンス」のようなイメージ

自テナントでアプリ登録をすると、同時にサービスプリンシパルが自動作成されます。そしてマルチテナント構成では、相手テナントのユーザーが初めてアプリに同意（consent）したタイミングで、相手テナント側にもサービスプリンシパルが自動作成されます。

![アプリケーションとエンタープライズアプリケーションの関係図](/images/entra-id-app-service-principal.drawio.png)

### 検証: エンタープライズアプリを削除するとどうなるか

ドキュメントを読んで両者の関係が理解できたので、1つ仮説が浮かびました。「自テナントのサービスプリンシパルを削除しても、再度同意フローを実行すれば自動的に再作成されるのではないか」と。

実際に検証してみたところ、予想どおりサービスプリンシパルは再作成されました。アプリケーションはあくまで自テナントに存在しており、相手テナント側のサービスプリンシパルは同意をきっかけに作成される、という理解で合っていました。

## サポートされるアカウントの種類

アプリ登録の際に「サポートされるアカウントの種類」を選択します。選択肢は以下のとおりです。

| signInAudience の値 | 対象 |
|---|---|
| AzureADMyOrg | 自テナントのアカウントのみ（シングルテナント） |
| AzureADMultipleOrgs | 任意の Entra ID テナントのアカウント（マルチテナント） |
| AzureADandPersonalMicrosoftAccount | Entra ID テナント + 個人の Microsoft アカウント |

前のセクションでアプリケーションとサービスプリンシパルの関係を理解していたので、複数テナントにサービスプリンシパルを作成できる `AzureADMultipleOrgs` を選択しました。個人の Microsoft アカウントからのサインインは要件として不要だったため、`AzureADandPersonalMicrosoftAccount` は除外しています。

参考: [シングルテナント アプリとマルチテナント アプリ](https://learn.microsoft.com/ja-jp/entra/identity-platform/single-and-multi-tenant-apps#who-can-sign-in-to-your-app)
参考: [サポートされるアカウントの種類の変更](https://learn.microsoft.com/ja-jp/entra/identity-platform/howto-modify-supported-accounts#change-the-application-registration-to-support-different-accounts)

## アクセス許可の選定

アプリに必要なスコープを付与する方法として、委任（Delegated）とアプリケーション（App-only）の2種類があります。

両者の違いは、Microsoft のドキュメントにある図が分かりやすいです。

https://learn.microsoft.com/ja-jp/entra/identity-platform/permissions-consent-overview#access-scenarios

### 委任によるアクセス許可

ユーザーの代理としてアプリが動作します。実際にアクセスできるリソースの範囲は、アプリに付与されたスコープとサインインユーザーの権限の両方を満たす範囲に限定されます。つまり、ユーザーがアクセスできないリソースにはアプリもアクセスできません。

### アプリケーションの許可

ユーザーを介さずアプリ自体の権限で動作します。この場合、付与されたスコープがそのままアクセスできるリソースの範囲に直結します。たとえば `Sites.Read.All` をアプリケーション許可で付与すると、テナント内のすべての SharePoint サイトを読み取れてしまいます。

### Selected スコープという選択肢

アプリケーション許可でもリソースを絞り込む方法はあります。`Sites.Selected` を使えば、特定のサイトだけにアクセスを限定できます。しかし、この方法だと相手テナントの管理者が Graph API で個別にアクセス許可を設定しなければなりません。

```
POST /sites/{siteid}/lists/{listid}/permissions
```

相手テナントにこの操作を要求するのはだいぶ面倒で、マルチテナントアプリの導入ハードルを下げたいという目的に反します。

### 私のケースでの判断

今回はユーザーの操作を起点とする連携しかなく、ユーザー不在のバックグラウンドで動かす要件がありませんでした。そこで、委任によるアクセス許可を選択しています。委任であれば、アクセス範囲はサインインユーザーの権限で自然に制限されます。相手テナントの管理者にとっても、アプリに過剰な権限を与えるリスクが低く、導入を判断しやすくなります。

参考: [Graph API アクセス許可リファレンス](https://learn.microsoft.com/ja-jp/graph/permissions-reference)
参考: [Selected スコープの仕組み](https://learn.microsoft.com/ja-jp/graph/permissions-selected-overview?tabs=http#how-selected-scopes-work-with-sharepoint-and-onedrive-permissions)

## Admin Consent

委任によるアクセス許可を選択しても、スコープによっては一般ユーザーの同意だけでは利用できません。管理者による事前の同意（Admin Consent）を要求するスコープが存在します。

判断を誤りかけたのが、リファレンスの記載と実際の挙動が食い違った点です。Graph API のアクセス許可リファレンスでは、[Sites.Read.All](https://learn.microsoft.com/ja-jp/graph/permissions-reference#sitesreadall) と [Sites.ReadWrite.All](https://learn.microsoft.com/ja-jp/graph/permissions-reference#sitesreadwriteall) のどちらも、委任のカテゴリでは管理者の同意は不要と記載されています。ところが実際に同意フローを通すと、いずれも Admin Consent を要求されました。

相手テナント側の上位の設定、たとえばユーザーによる同意を制限するポリシーが影響している可能性はありますが、そこまでは調査できていません。原因はどうあれ、リファレンスの記載だけを見て「管理者の手を借りずに導入できる」と設計すると、あとから前提が崩れます。実際に同意フローを通して確認するのが確実です。

### Admin Consent URL の構築

Admin Consent が必要な場合、相手テナントの管理者に事前認可してもらう必要があります。以下の形式で Admin Consent URL を構築し、管理者にアクセスしてもらいます。

```
https://login.microsoftonline.com/organizations/adminconsent?client_id={client-id}
```

管理者がこの URL にアクセスして同意すると、同意した時点でアプリに設定されているアクセス許可について、テナント全体で利用が許可されます。その範囲内であれば、一般ユーザーは個別に同意する必要がありません。逆に、あとからスコープを追加した場合は、あらためて管理者の同意が必要になります。

参考: [マルチテナントアプリの Admin Consent](https://learn.microsoft.com/ja-jp/entra/identity-platform/howto-convert-app-to-be-multi-tenant#admin-consent)
参考: [テナント全体の管理者の同意 URL の構築](https://learn.microsoft.com/ja-jp/entra/identity/enterprise-apps/grant-admin-consent?pivots=portal#construct-the-url-for-granting-tenant-wide-admin-consent)

## まとめ

Entra ID のマルチテナントアプリを構築する際に理解が必要だった4つの概念を振り返ります。

1. アプリケーションが設計図で、エンタープライズアプリケーション（サービスプリンシパル）がそのインスタンスにあたる。相手テナントには同意を通じてサービスプリンシパルが自動作成される
2. サポートされるアカウントの種類は、マルチテナント構成なら `AzureADMultipleOrgs` を選択する
3. 委任許可とアプリケーション許可は、相手テナントの管理者の視点でリスクと導入コストを考慮して選定する
4. Admin Consent はスコープによって管理者の事前同意が必要になる。委任のアクセス許可でも要求されることがあり、リファレンスの記載と一致しない場合がある

委任のアクセス許可で Admin Consent が要求された原因については、まだ突き止められていません。同じような状況に遭遇した方がいたら、ぜひ知見を共有してほしいです。
