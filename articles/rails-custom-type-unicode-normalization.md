---
title: "Rails のカスタム Type Class で Unicode 正規化ゆれを封じる"
emoji: "🔤"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["rails", "ruby", "activerecord", "unicode"]
published: true
---

画面上は同じファイル名にしか見えないのに、DB からは別の文字列として扱われる。そのせいで一意制約がすり抜け、まったく別の場所で `ActiveRecord::RecordNotUnique` が出る。原因は Unicode の正規化形式（NFC / NFD）の違いでした。

対応として、`ActiveModel::Type::String` を継承したカスタム Type Class を作り、正規化を属性の型そのものに閉じ込めました。この記事では、なぜ `before_validation` とラッパーメソッドではなく型を選んだのかを書きます。

## 同じファイル名なのに、別レコードとして通ってしまった

アップロードされたファイルを管理するテーブルがありました。ファイル名を `key` カラムに持つ親テーブルと、その中身が 1:N でぶら下がる子テーブルという構成です。同じファイル名で再アップロードされた場合は、親を使い回して子レコードだけを洗い替えします。

説明用に単純化すると、スキーマはこんな形です。

```ruby
create_table :uploads do |t|
  t.string :key, null: false
  t.timestamps

  t.index :key, unique: true
end

create_table :upload_rows do |t|
  t.references :upload, null: false, foreign_key: true
  t.string :name, null: false
  t.timestamps

  t.index :name, unique: true
end
```

ある日、この処理が `ActiveRecord::RecordNotUnique` で落ちました。しかも落ちていたのは、親ではなく子テーブルの `name` カラムの一意制約です。

同じファイル名なら親が既存レコードとして見つかり、洗い替えのルートに入るはずです。ところが実際には親が「別のファイル」と判定されて新規作成に進み、その先で子レコードを作ろうとして、すでにある子レコードとぶつかっていました。

原因は Unicode の正規化形式の違いでした。macOS からアップロードされたファイル名が NFD だったのに対して、DB に入っていた既存のファイル名は NFC です。画面上は同じ文字列に見えても、バイト列としては別物として扱われます。

NFC と NFD の違いは次の記事に詳しく、今回はそのゆれをアプリケーション側で封じる話に絞ります。

https://zenn.dev/hacobell_dev/articles/68ccc92bffd6cc

親テーブルにもファイル名の一意制約は付いていました。ただし DB から見れば別の文字列なので、制約は素通りします。守ってくれるはずのものがすり抜けた結果、エラーが出た場所（子テーブルの一意制約）と原因の場所（親のキー比較）が離れてしまい、追いにくい落ち方になりました。

## 最初の案:「呼び忘れないように気をつける」

最初に検討した案は、モデルに正規化を仕込むものでした。保存前に `before_validation` で NFC へ揃え、検索は正規化を挟むクラスメソッド経由にする、という形です。

```ruby
before_validation :normalize_unicode_to_nfc

def normalize_unicode_to_nfc
  self.key = key.unicode_normalize(:nfc) if key.present?
end

def self.find_by_normalized_key(key:)
  find_by(key: key&.unicode_normalize(:nfc))
end
```

正しいメソッドを経由する限り、今回の不具合はこれで直ります。

引っかかったのは、この設計が「使う側が呼び忘れないこと」を前提にしている点でした。`find_by_normalized_key` の存在を知らない人が、素朴に `find_by(key: params[:key])` と書いた瞬間に、同じ問題がまた起きます。`where` でも `find_or_create_by` でも同じです。ラッパーを増やすたびに、覚えておくべきことも増えていきます。

つまり正しさの担保がレビューに寄ってしまいます。指摘し続けるのは面倒くさいし、いつか漏れます。

そもそも「この属性は常に NFC である」というのは、書き方の作法ではなく属性そのものの性質のはずです。であれば、呼び出し側の規律ではなく、もっと手前で保証したいと考えました。

## カスタム Type Class に閉じ込める

そこで思い出したのが、以前趣味で追っていた ActiveRecord の cast まわりの仕組みです。特に目的があったわけではなく、`attribute` が値をどう変換しているのかが気になって読んでいただけでした。これを使えば、正規化を属性の型そのものに埋め込めます。

できたのがこの `NfcString` です。

```ruby
class NfcString < ActiveModel::Type::String
  # DB へ書き込む値・クエリ条件に使う値を NFC へ正規化する。
  def serialize(value)
    normalize(super)
  end

  private

  # 代入・読み出し時のキャスト値を NFC へ正規化する。
  def cast_value(value)
    normalize(super)
  end

  # 文字列のみ正規化し、nil などはそのまま返す(空文字は空文字のまま保持)。
  def normalize(value)
    value.is_a?(::String) ? value.unicode_normalize(:nfc) : value
  end
end
```

やっていることは `super` の結果を NFC に通すだけです。`serialize` と `cast_value` の両方を上書きしています。

### なぜ両方必要なのか

この2つは担当する場面が違います。役割は [ActiveModel::Type::Value](https://api.rubyonrails.org/classes/ActiveModel/Type/Value.html) のドキュメントと、手元で動かして確かめた挙動から整理しました。

- `cast_value`：属性への代入時と、DB から読み出した値のキャスト時に呼ばれる
- `serialize`：DB へ書き込む値を作るときに呼ばれる。クエリ条件の値もここを通る（こちらは ActiveRecord 側の挙動）

片方だけでは穴が残ります。`cast_value` だけを上書きした場合、`where(key: params[:key])` のようなクエリ条件はキャストを経由しません。NFD のまま SQL に渡るので、検索がヒットしないという元の症状が残ったままになります。

逆に `serialize` だけの場合、DB とのやり取りは揃います。ただしメモリ上のオブジェクトが持つ値は NFD のままです。保存前に `record.key == params[:key]` のような比較をすると、そこでずれます。

この2つの穴は、片方だけを上書きした型を実際に作って確かめました。`cast_value` だけの型では `where(key: nfd).to_sql` の中身が NFD のままで、`find_by` は `nil` を返します。`serialize` だけの型では、代入直後の `upload.key` が NFD のまま残ります。

### モデルへの適用

あとは属性に型を指定するだけです。

```ruby
class Upload < ApplicationRecord
  attribute :key, NfcString.new
end
```

これで `create` でも `where` でも `find_by` でも、ActiveRecord の型を通る限り `key` は NFC に揃います。呼び出し側は何も意識しません。

複数のモデルで使うなら、型に名前を付けて登録する手もあります。

```ruby
# config/initializers/types.rb
Rails.application.config.to_prepare do
  ActiveRecord::Type.register(:nfc_string, NfcString)
end
```

```ruby
attribute :key, :nfc_string
```

:::message
`to_prepare` で囲んでいるのには理由があります。`app/types/nfc_string.rb` のような autoload 対象の場所にクラスを置いた場合、initializer に直接書くと初期化の時点ではまだ定数を参照できません。試しに素で書いてみたら、`NameError: uninitialized constant NfcString` で起動に失敗しました。
:::

今回は使う箇所が限られていたので、`NfcString.new` を直接渡す形にしました。

## 何が変わったか

型を入れたあと、NFD のファイル名で再現テストを書いて確認しました。NFD の文字列で検索しても既存レコードが引けること、そして保存された値が NFC になっていることを見ています。

```ruby
require "test_helper"

class NfcStringTest < ActiveSupport::TestCase
  NFC = "ガジェット一覧.csv".unicode_normalize(:nfc)
  NFD = "ガジェット一覧.csv".unicode_normalize(:nfd)

  test "NFD のキーでも既存レコードを引ける" do
    upload = Upload.create!(key: NFC)

    assert_equal upload, Upload.find_by(key: NFD)
  end

  test "NFD を代入しても保存される値は NFC" do
    upload = Upload.create!(key: NFD)

    assert_equal NFC, upload.reload.key
  end
end
```

呼び出し側のコードは何も変わっていません。それでも NFD の混ざった検索が通るようになりました。型の存在を知らずに素朴に `find_by` や `where` を書いても、同じ問題を踏みません。

### 型が届かない経路

:::message alert
型が揃えるのは入口だけです。`update_all` や生の SQL で書き込む箇所があれば、そこは素通りします。すでに DB に入ってしまった NFD のデータもこの型では直らないので、今回はデータマイグレーションで別途揃えました。
:::

## まとめ

正規化という数行の処理をどこに置くか、という判断でした。コールバックとラッパーメソッドに置けば、使う人が正しいメソッドを選び続ける必要があります。型に置けば、素朴に書いたコードがそのまま正しくなります。

`ActiveModel::Type::Value` を継承した型は、正規化のような「その属性が常に満たしていてほしい性質」を置く場所として使えます。全角と半角の統一や前後の空白除去など、同じ形が効く場面はほかにもありそうです。

同じ問題で時間を取られた方の参考になれば幸いです。
