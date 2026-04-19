---
title: "Entra ID でマルチテナントアプリを構築する際に躓いた4つの基本概念"
emoji: "🔐"
type: "tech"
topics: ["EntraID", "AzureAD", "OAuth", "マルチテナント"]
published: false
---

## はじめに

他テナントの Microsoft 365 リソースと連携する機能を実装する機会がありました。以前は相手テナント側でアプリを作成してもらい、クライアントシークレットを受け取る方式の設計を経験していました。しかし、この方式では相手側の前準備コストが大きく、リスクのあるシークレット情報をこちらで管理する必要もありました。

今回は自組織でアプリ登録するマルチテナント構成を採用しました。相手テナントの準備コストを削減でき、シークレット管理も不要になるためです。ただ、この構成で認可の仕組みを理解するのがなかなかしんどかったです。この記事では、私が躓いた4つの基本概念を整理します。

### この記事の要点

- アプリケーション（設計図）とサービスプリンシパル（インスタンス）は別物。ここを押さえると後続の理解がめっちゃ楽になる
- マルチテナント構成では `AzureADMultipleOrgs` を選択する
- アクセス許可は「委任」と「アプリケーション」の2種類。相手テナントの管理者目線で選定するのが大事
- Admin Consent はドキュメントの記載と実際の挙動に差異があるケースもあるので注意

## アプリケーションとエンタープライズアプリケーション

最初に躓いたのが「アプリケーション」と「エンタープライズアプリケーション」の違いです。どちらも「アプリケーション」って名前がついているうえに、Azure Portal でアプリ登録をすると自動的にエンタープライズアプリケーションも作成されます。この振る舞いを先に知っていたこともあり、両者の区別がつかずに混乱しました。

[Microsoft のドキュメント](https://learn.microsoft.com/ja-jp/entra/identity-platform/app-objects-and-service-principals?tabs=browser#service-principal-object)を読んで、ようやく関係性が整理できました。

- アプリケーション（アプリ登録）はアプリの定義情報。いわば「設計図」にあたる
- エンタープライズアプリケーション（サービスプリンシパル）は各テナントにおけるアプリの実体。設計図から作られた「インスタンス」のようなイメージ

自テナントでアプリ登録をすると、同時にサービスプリンシパルが自動作成されます。そしてマルチテナント構成では、相手テナントのユーザーが初めてアプリに同意（consent）したタイミングで、相手テナント側にもサービスプリンシパルが自動作成されます。

![アプリケーションとエンタープライズアプリケーションの関係図](/images/entra-id-app-service-principal.drawio.png)

### 検証: エンタープライズアプリを削除するとどうなるか

ドキュメントを読んで両者の関係が理解できたので、1つ仮説が浮かびました。「自テナントのサービスプリンシパルを削除しても、再度同意フローを実行すれば自動的に再作成されるのではないか」と。

実際に検証してみたところ、予想どおりサービスプリンシパルは再作成されました。アプリケーションはあくまで自テナントに存在しており、相手テナント側のサービスプリンシパルは同意をきっかけに作成される、という理解で正しかったです。

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

## アクセス許可の選定 — 委任 vs アプリケーション許可

アプリに必要なスコープを付与する方法として、委任（Delegated）とアプリケーション（App-only）の2種類があります。

![委任とアプリケーション許可の概要](https://learn.microsoft.com/ja-jp/entra/identity-platform/media/permissions-consent-overview/access-scenarios.png)
*出典: [Microsoft Entra ID - アクセス許可と同意の概要](https://learn.microsoft.com/ja-jp/entra/identity-platform/permissions-consent-overview#access-scenarios)*

### 委任によるアクセス許可

ユーザーの代理としてアプリが動作します。実際にアクセスできるリソースの範囲は、アプリに付与されたスコープとサインインユーザーの権限の両方を満たす範囲に限定されます。つまり、ユーザーがアクセスできないリソースにはアプリもアクセスできません。

### アプリケーションの許可

ユーザーを介さずアプリ自体の権限で動作します。この場合、付与されたスコープがそのままアクセスできるリソースの範囲に直結します。たとえば `Sites.Read.All` をアプリケーション許可で付与すると、テナント内のすべての SharePoint サイトを読み取れてしまいます。相手テナントの管理者からすると、この広い権限を外部アプリへ与えるのは不安ですよね。

### Selected スコープという選択肢

アプリケーション許可でもリソースを絞り込む方法はあります。`Sites.Selected` を使えば、特定のサイトだけにアクセスを限定できます。しかし、この方法だと相手テナントの管理者が Graph API で個別にアクセス許可を設定しなければなりません。

```
POST /sites/{siteid}/lists/{listid}/permissions
```

相手テナントにこの操作を要求するのはだいぶ面倒くさいです。マルチテナントアプリの導入ハードルを下げたいという目的に反します。

### 私のケースでの判断

委任によるアクセス許可を選択しました。委任であれば、アクセス範囲はサインインユーザーの権限で自然に制限されます。相手テナントの管理者にとっても、アプリに過剰な権限を与えるリスクが低く、安心して導入してもらえやすいと判断したためです。

参考: [アクセス許可の概要](https://learn.microsoft.com/ja-jp/entra/identity-platform/permissions-consent-overview#access-scenarios)
参考: [Graph API アクセス許可リファレンス](https://learn.microsoft.com/ja-jp/graph/permissions-reference)
参考: [Selected スコープの仕組み](https://learn.microsoft.com/ja-jp/graph/permissions-selected-overview?tabs=http#how-selected-scopes-work-with-sharepoint-and-onedrive-permissions)

## Admin Consent

委任によるアクセス許可を選択しても、スコープによっては一般ユーザーの同意だけでは利用できません。管理者による事前の同意（Admin Consent）を要求するスコープが存在します。

私のケースでは、一部のスコープで Admin Consent を要求されました。ドキュメントの記載だけでは判断しきれないこともあるので、実際に動かして確認するのが確実です。

### Admin Consent URL の構築

Admin Consent が必要な場合、相手テナントの管理者に事前認可してもらう必要があります。以下の形式で Admin Consent URL を構築し、管理者にアクセスしてもらいます。

```
https://login.microsoftonline.com/organizations/adminconsent?client_id={client-id}
```

管理者がこの URL にアクセスして同意すると、テナント全体でアプリの利用が許可されます。これにより、一般ユーザーは個別に同意する必要がなくなります。

参考: [マルチテナントアプリの Admin Consent](https://learn.microsoft.com/ja-jp/entra/identity-platform/howto-convert-app-to-be-multi-tenant#admin-consent)
参考: [テナント全体の管理者の同意 URL の構築](https://learn.microsoft.com/ja-jp/entra/identity/enterprise-apps/grant-admin-consent?pivots=portal#construct-the-url-for-granting-tenant-wide-admin-consent)

## まとめ

Entra ID のマルチテナントアプリを構築する際に理解が必要だった4つの概念を振り返ります。

1. **アプリケーションとエンタープライズアプリケーション** — アプリケーションが設計図、サービスプリンシパルがインスタンス。相手テナントには同意を通じてサービスプリンシパルが自動作成される
2. **サポートされるアカウントの種類** — マルチテナント構成では `AzureADMultipleOrgs` を選択する
3. **委任 vs アプリケーション許可** — 相手テナントの管理者の視点でリスクと導入コストを考慮して選定する
4. **Admin Consent** — スコープによっては管理者の事前同意が必要。ドキュメントの記載と実際の挙動が異なる場合もある

これらの概念を順番に理解していくと、次の判断がシュッと決まるようになります。特にアプリケーションとサービスプリンシパルの関係を最初に押さえたことで、後続の設定項目の意味がすんなり入ってきました。

Admin Consent まわりのドキュメントと実挙動の差異については、まだ理解しきれていない部分があります。同じような状況に遭遇した方がいたら、ぜひ知見を共有してほしいです。
