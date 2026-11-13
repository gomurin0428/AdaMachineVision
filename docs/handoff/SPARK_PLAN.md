# SPARK による証明の計画

状態: **9 の 1(基盤)が済み**(2026-11-08、ブランチ `feature/spark-foundation`)。カーネルのルート `AMV.Kernels`、状態値を例外に変える `AMV.Checks`、試験台の `AMV.Kernels.Misc`(`AMV.Misc` は薄い層になった)、`include/amv.h`、C のテスト、`make prove`、薄さの検査(`tools/shell_check`)があります。拘束力のある規則は `docs/DESIGN.md` の 9 節、証明の状態は `docs/PROOF.md` です。9 の 2 以降(コアのカーネル化)は、依存の順に進めています。済んだもの:`AMV.Transforms`(2026-11-08、ブランチ `feature/kernel-transforms`)、`AMV.Coordinate_Spaces`(2026-11-08、ブランチ `feature/kernel-coordinate-spaces`)、`AMV.Images`(2026-11-08、ブランチ `feature/kernel-images`。最初の所有権付きハンドルと、最初の信頼する部分)、`AMV.Image_File`(2026-11-08、ブランチ `feature/kernel-image-file`。PNM と BMP の復号・符号化をバイト列の上で行い、ファイルの読み書きだけが Ada の API に残った)、`AMV.Shapes`(2026-11-08、ブランチ `feature/kernel-shapes`。固定長の図形は C の構造体のまま値で渡し、多角形の頂点だけを所有権付きハンドルに置いた。座標と角度は 1.0E150、長さは 4.0E150 が上限)、`AMV.Regions`(2026-11-08、ブランチ `feature/kernel-regions`。画素の集合を所有権付きハンドルに置き、画素数が含まれる画素の数に等しいこと、外接矩形が最小であること、候補の各画素が図形の `Contains_Point` どおりであることを Gold で証明した。候補の範囲が漏れなく画素を覆うことは浮動小数点の議論で、証明していない)。`AMV.Image_Math` と `AMV.Geometry`(2026-11-08、ブランチ `feature/kernel-image-math-geometry`。画素値を ±1.0E100、座標を ±1.0E150 に制限し、和やフィットの反復が溢れないことを証明)。コアのカーネル化はこれで終わりです(`AMV.Tools` も薄い層になり、`tools/shell_check_legacy.txt` は空になった)。次はツール群で、`docs/handoff/TOOLS_PLAN.md` の「Tools as SPARK kernels」節に従います。

- **ツールチェーンを上げた(2026-11-08)。** GNAT 16.1、gprbuild 26、gnatprove 16.1(Alt-Ergo 2.6.1、cvc5 1.3.2、Z3 4.15.4)です。この文書の 6 節の予備実験は 14 系で行ったものです。
- **画素の共有は A 案に決定**(3.6、2026-11-08 にユーザーが決定)。

> **Windows での注意:** `gnatprove` は **PowerShell かコマンドプロンプトから**実行してください。
> Git Bash から実行すると、ソルバの呼び出しがすべて失敗し、正しいコードでも「might fail」になります。
> このとき `gnatprove.out` では Provers 列が空になり、「max steps used for successful proof: 0」と出ます。「High failure」は `obj/gnatprove/<ユニット>.spark` と `why3session.xml` に記録されます。
> 同じ課題を z3 で直接解くと証明できるので、Git Bash の環境が原因です(6 節)。

## 1. 目標

- **Silver(実行時エラーがないことの証明)**
  - ロジックをすべて SPARK のカーネルに置きます。画素と座標の演算、入力の検証、座標空間の解決などです。
  - 次がないことを `gnatprove` で証明します。
    - 整数・浮動小数点のオーバーフロー
    - 範囲外の添字
    - ゼロ除算
    - `Sqrt` や `Arctan` の定義域外の引数
    - 未初期化変数の読み出し
    - メモリリーク(所有権付きアクセス型)
- **Gold(機能的な性質の証明)**
  - 離散的な処理は、機能的な性質まで証明します。例:
    - 二値化した各画素がしきい値と正しく対応している
    - ヒストグラムの合計が画素数に等しい
    - ラスタライズの画素数がフラグの True の数に等しい
    - コーデックが入力の範囲外を読まない
  - 浮動小数点の処理は、値の範囲・有限性・単調性程度にとどめます。最小二乗の最適性のような性質は狙いません。
- **テストは残します。** 数値の精度(正しいエッジ位置を返すか)、Ada の公開 API の振る舞い、例外への変換は証明の対象外だからです。

## 2. 全体の構成

Ada の公開 API は VisionPro に倣った作りで、SPARK で扱えない次の機能を使っています。

- 参照カウントで画素を共有する制御型
- `Ada.Containers.Indefinite_*`(ランタイムで `SPARK_Mode => Off`)
- 関数からの例外送出

`Unbounded_String` とクラスワイドのディスパッチは SPARK 14 でも使えます。ただし C の ABI で公開できないので、カーネルの入口では使いません。

そこで、次の構成にします。

```
 C の利用者 ─────────────┐
                          ▼
 Ada の公開 API ──▶ カーネルの入口(SPARK、C の ABI で公開)= C の公開 API
 (VisionPro 風・例外・      │
  制御型。包むだけ)         ▼
                    カーネルの内部(SPARK、Ada の型を自由に使う)
```

| 層 | パッケージ | SPARK_Mode | 中身 |
|---|---|---|---|
| カーネルの入口 | `AMV.Kernels.*` の公開部分 | On | **準 VisionPro の API で、そのまま C の公開 API になる**(3 節)。C 互換の型だけを使い、入力をすべて検証し、状態値を返す |
| カーネルの内部 | `AMV.Kernels.*` の内部(private 部、本体、private 子パッケージ) | On | アルゴリズム本体。非制約配列・判別子付きレコード・範囲付きの型など、証明しやすい Ada の型を自由に使う |
| Ada の公開 API(シェル) | 既存の公開パッケージ(`AMV.Images` など) | Off(既定のまま) | **カーネルの入口を包むだけの薄い層**(5 節) |

- ルートの `AMV` には `with SPARK_Mode` を付けます。宣言は `Real`・`Version`(文字列定数)・例外だけで、SPARK_Mode を付けても gnatprove の検査を通ることを確認済みです。
- C の公開 API を別に作り直す必要はありません。カーネルの入口がそのまま C の公開 API です。
  - 入口には `Export`、`Convention => C`、`External_Name` を付けます。
  - 必要なのは、C のヘッダファイル(`amv.h`)を足すことだけです。

## 3. カーネルの入口(= C の公開 API)の形

カーネルの入口は、VisionPro と同じ概念・名前・操作を持つ API にします。SPARK で証明でき、かつ C の ABI で通る表現にするため、次のように置き換えます。

### 3.1 VisionPro 風の概念の置き換え

| Ada の公開 API(VisionPro 風) | カーネルの入口(SPARK + C ABI) |
|---|---|
| 大きさが変わるオブジェクト(画像の画素、結果の一覧、学習済みパターン、キャリブレーション、多角形の頂点) | **不透明なハンドル**。SPARK の所有権規則に従うアクセス型で、C からは `ks_image_8_grey*` のような構造体ポインタに見える。`ks_..._create` と `ks_..._destroy` を用意し、中身は取得・設定用の入口で操作する |
| 小さな値オブジェクト(変換行列、図形のパラメータ、パラメータ群) | `Convention => C` のレコード(C の構造体) |
| クラスワイドの図形(`Ks_Shape'Class` など) | 種類の符号と、種類ごとの部分レコードを並べた C 互換レコード(判別子付き可変レコードは C 互換にならない)。内部では判別子付き可変レコードに変換して使う |
| 例外 | すべての入口が `Status : out Ks_Status`(3.3)を返す |
| `Unbounded_String`(座標空間名など) | 長さ付きの固定長文字配列(C の `char[N]` と長さ) |
| `Ks_Tool.Run` | ツールのハンドルに対する `ks_<tool>_run`。結果はツールのハンドルの中に残り、取得用の入口で読む。`Run_Status` への記録と例外の捕捉は、Ada の公開 API の `Run` が行う |

### 3.2 入口の規則

1. **型は C 互換のものだけ。**
   - 使えるもの:
     - `Long_Float`(C の `double`)
     - `Interfaces.Unsigned_8` と `Unsigned_16`
     - 大きさを指定した整数(`type Int32 is range -2**31 .. 2**31 - 1 with Size => 32`)
     - `Convention => C` のレコード
     - 所有権付きアクセス型のハンドル
   - **Ada の `Boolean` は使わない。** 0 と 1 の整数で表します。
   - **列挙値は 32bit 整数の符号で受け取る。** 入口で範囲を検査してから、内部の Ada の列挙型に変換します。C からは範囲外の値が来うるうえ、SPARK は値が常に妥当だと仮定するため、`'Valid` には頼れません。
2. **入口には `Pre` を書かず、入力はすべて入口の中で検証する。**
   - 検証する対象: null のハンドル、範囲外の値、寸法の不整合、同じハンドルが入力と出力に渡されていないか、など。
   - `Pre` を書かない理由は、表明ポリシー(4 の 5)により、C 側の誤用が `Assertion_Error` として C に飛んでしまうためです。
   - 内部のサブプログラムでは、`Pre` を自由に使います。内部の `Pre` が成り立つことは証明されます。
3. **C のメモリとの受け渡しは、信頼する部分に閉じ込める。**
   - 対象は、C の利用者が持つ画素配列(ポインタと長さ)をハンドルにコピーする入口と、ハンドルからコピーして出す入口です。
   - これらは、ポインタを Ada の配列に見せる数行のコード(`with Import, Address => ...`)が必要で、証明できません。
   - その部分だけ `SPARK_Mode => Off` の本体に分け、`docs/PROOF.md` に列挙します。数はごく少数に抑えます。
4. **例外を外に出さない。**
   - gnatprove が証明するのは、浮動小数点の入力が妥当(NaN・±Inf でない)という仮定の下で例外が起きないことです。`-gnatVa` のままだと、NaN・±Inf の入力で妥当性検査の `Constraint_Error` が起きます。これは 4 の 4 の対策で防ぎます。
   - それ以外に残るのは、メモリ確保の失敗とスタック溢れ(どちらも `Storage_Error`)です。
   - 確保は、信頼する小さな補助ルーチンに寄せます。このルーチンは、失敗時に null を返して状態値に変えます。スタック溢れは、大きな配列をスタックに置かないことで避けます。
5. **名前は VisionPro に倣う。**
   - Ada 側は `AMV.Kernels.<パッケージ>.<操作>` です。
   - C 側の名前は `ks_<型>_<操作>` にします(例:`ks_transform_2d_linear_invert`、`ks_image_8_grey_create`、`ks_blob_tool_run`、`ks_blob_results_count`)。

### 3.3 状態値

- `AMV.Kernels` に、例外と 1 対 1 に対応する状態値を置きます(案)。

  ```ada
  --  失敗の種類(C 側では 32bit 整数の定数)
  None                          : constant := 0;
  Image_No_Pixels               : constant := 1;
  Image_Bad_Selected_Space_Name : constant := 2;
  Operator_Not_Trained          : constant := 3;
  Transform_Singular            : constant := 4;
  Image_File                    : constant := 5;
  Bad_Parameter                 : constant := 6;
  Out_Of_Memory                 : constant := 7;

  Max_Message_Length : constant := 200;
  type Message_Text is array (1 .. Max_Message_Length) of Character
    with Convention => C;

  type Ks_Status is record
     Failure : Int32 := None;
     Length  : Int32 := 0;
     Message : Message_Text := [others => ' '];
  end record with Convention => C;
  ```

- メッセージは VisionPro 風にプロパティ名を含めます(例:"RunParams.ContrastThreshold must be >= 0")。このメッセージもカーネルが作ります。
- Ada の公開 API には、状態値を例外に変える共通の `Check` を 1 つだけ置きます。失敗の種類から例外 ID への定数表を引き、`Ada.Exceptions.Raise_Exception` で送出します。

### 3.4 例

```ada
--  カーネルの入口(SPARK):src/amv-kernels-transforms.ads
type Ks_Transform_2D_Linear is record
   A, B, C, D, Translation_X, Translation_Y : Long_Float := 0.0;
end record with Convention => C;

procedure Invert
  (Transform : Ks_Transform_2D_Linear;
   Result    : out Ks_Transform_2D_Linear;
   Status    : out Ks_Status)
with Export, Convention => C,
     External_Name => "ks_transform_2d_linear_invert";
```

```c
/* C の利用者から見ると(amv.h) */
typedef struct { double a, b, c, d, translation_x, translation_y; }
  ks_transform_2d_linear;
void ks_transform_2d_linear_invert(const ks_transform_2d_linear *transform,
                                   ks_transform_2d_linear *result,
                                   ks_status *status);
```

```ada
--  Ada の公開 API:src/amv-transforms.adb
function Invert
  (Transform : Ks_Transform_2D_Linear) return Ks_Transform_2D_Linear
is
   Result : Ks_Transform_2D_Linear;
   Status : AMV.Kernels.Ks_Status;
begin
   AMV.Kernels.Transforms.Invert (Transform.Data, Result.Data, Status);
   Check (Status);   --  失敗なら対応する Ks_ 例外を送出する
   return Result;
end Invert;
```

- **ツールも同じ形です。** 例えば Blob は次のように使います。
  1. Ada の公開 API の `Execute` が、`ks_blob_tool_run` に次を渡す。
     - ツールのハンドル(パラメータと結果を持つ)
     - 入力画像の画素ハンドル
     - 座標空間の状態
     - 領域のレコード
  2. カーネルは、領域の画素空間への写像、計算、結果の "." 空間への写像まで行い、結果をツールのハンドルに格納する。
  3. Ada の公開 API は `Check (Status)` を呼び、結果の件数と各項目を取得用の入口で読み出す。

### 3.5 既存のパッケージに当てはめると

- **座標空間ツリー。** `Indefinite_Ordered_Maps` をやめ、上限付き配列の木(固定長の名前・親・`Parent_From_Child`)を C 互換レコードとしてカーネルに置きます。
  - 名前の検証と正規化、変換の合成順、`Get_Transform` の解決は、すべてカーネルが行います。
  - VisionPro のツリーは小さいので、上限は 64 程度で足ります。足りなければ状態値で失敗を返します。
  - (2026-11-08 に実施)上限はルートを含めて 64 空間、完全名は 256 文字です。項目は完全名の辞書順に並べ、親は子より前に来ます。Ada の公開 API は、カーネルのレコードをヒープの箱に入れて制御型で持ちます(`docs/handoff/CORE_NOTES.md`)。
- **画像。**
  - 画素は画像ハンドル(寸法と 1 次元の行優先配列)に持ちます。
  - 座標空間の状態(ツリー、選択中の空間名、`Pixel_From_Root`)は、別のレコードとして入口に渡します。
  - 分けて渡す理由は 3.6 にあります。
  - (2026-11-08 に実施)ハンドルは、幅・高さと、画素の 2 次元配列 `Pixels (Y, X)` への所有権付きポインタを持つレコードです。メモリ上の並びは 1 次元の行優先と同じで、2 次元にしたのは `Y * Width + X` の非線形な添字計算を証明から除くためです。null のハンドルは画素のない画像です。カラー画像は 8bit のハンドル 3 つで、入口は `ks_image_24_planar_color_*` です。座標空間の状態は、ツリーのレコード・`Ks_Space_Name`・変換を別々の引数として `ks_image_*` に渡します。確保・C のメモリとの行のコピー・ストリームのビット列から `Long_Float` への変換が信頼する部分です(`docs/PROOF.md`)。1 画素ずつ呼ばれる `Get_Pixel` / `Set_Pixel` は、状態値を作らない証明済みの変種(`Try_*`)を使います(`docs/DESIGN.md` 9.3、実測は `CORE_NOTES.md`)。
- **図形。**
  - 10 種の図形を、種類の符号付きの C 互換レコード `Ks_Shape` で表します。
  - 多角形の頂点だけは件数が変わるので、ハンドルにします。
  - 包含判定・外接矩形・面積・写像は、内部で判別子付き可変レコードに変換してから計算します。
- **領域。** ラスタライズ全体をカーネルで行います。Ada の公開 API が画素ごとに `Contains_Point` をディスパッチして呼ぶ現在の作りは、やめます。
- **画像ファイル。** Ada の公開 API(または C の利用者)はファイルとバイト配列の入出力だけを行います。ヘッダの解析と、画素の復号・符号化はカーネルが行います。

### 3.6 未決の設計事項:画素の共有

VisionPro と、現在の Ada の公開 API では、1 つの画素バッファを複数の画像が共有できます(代入や `Share_Pixels`)。SPARK の所有権規則では、この共有(エイリアス)を表現できません。選択肢は次の 2 つです。

- **A(推奨。まずこれで始める):カーネルは共有しない。**
  - 画素ハンドルと座標空間の状態を、別々に入口へ渡します。
  - 共有は Ada の公開 API だけが行います。参照カウント付きの箱に画素ハンドルを入れ、座標空間の状態は画像ごとの値として持ちます。
  - C の利用者は、共有したければ自分でハンドルを使い回します。その場合、同時に書き換えないことは利用者の責任です。
  - 同じハンドルが同じ呼び出しの入力と出力に渡された場合は、入口で検出して状態値を返します。
- **B:参照カウント付きの画素バッファ管理を、信頼する小さな部分として作る。**
  - 本体は `SPARK_Mode => Off` にし、仕様に SPARK の契約を付けます。カーネルは、そこから画素配列を借ります。
  - C の API はより VisionPro に近くなります。その代わり、信頼する部分が増えます。

## 4. カーネルの実装規則(入口と内部に共通)

1. **依存してよいもの:**
   - `AMV`、他のカーネル、`Interfaces`
   - `Ada.Numerics.Long_Elementary_Functions`(GNAT のランタイムには SPARK 用の契約が付いています。6 節)

   sparklib(`SPARK.Big_Integers` やフォーマルコンテナ)は使いません。「外部ライブラリなし」の方針に反し、ビルド時にもソースが必要になるためです。補題は、カーネル内のゴースト手続きとして自前で書きます。
   なお、GNAT 14.2 のランタイムには、ゴースト専用の `Ada.Numerics.Big_Numbers.Big_Integers_Ghost`(`a-nbnbig.ads`)があります。sparklib なしで、補題の中の大きな整数に使えます。

2. **使わないもの:**
   - 制御型、タスク、例外の送出と捕捉
   - タグ付き型とクラスワイドの型(代わりに判別子付き可変レコードを使う)
   - 共有(エイリアス)するアクセス型

   アクセス型は、SPARK の所有権規則(移動と借用、`Unchecked_Deallocation` による解放)に従う場合だけ使います。

3. **すべてのサブプログラムに契約を書く。**
   - `Pre` は量化子を含まない O(1) の式に限ります(理由は 5 で説明します)。入口には `Pre` を書きません(3.2 の 2)。
   - `Post` には、少なくとも出力の長さ・値の範囲・起こりうる失敗の種類を書きます。

4. **浮動小数点の入力は、入口で上限を検査する。**
   - 入口の引数は `Long_Float` のまま受け取ります。入口の中で `X in -Max .. Max` を検査し、外れたら `Bad_Parameter` を返します。
   - 内部のサブプログラムでは、`subtype Coordinate is Real range -Max_Coordinate .. Max_Coordinate` のような有界サブタイプを使ってかまいません。
   - 上限は各カーネルで決め、根拠をコメントに書きます(何と何を掛け、何個足すとどの大きさになるか)。
   - **NaN と ±Inf の扱いには注意が必要。** この範囲検査で弾けるのは、浮動小数点の妥当性検査(`-gnatVf`)が無効なときだけです。
     - `amv.gpr` と `amv_tests.gpr` は `-gnatVa` なので、そのままでは NaN・±Inf が比較の前に `Constraint_Error`("invalid data")になり、C から呼ばれた場合は例外が C 側へ抜けます。
     - 対策は 2 つです。ライブラリ全体を `-gnatVa -gnatVF` でビルドするか、カーネルのユニットの先頭に `pragma Validity_Checks ("F");` を置きます。どちらでも、範囲検査で弾けることを確かめました。
     - `X'Valid` を併用する方法は使いません。gnatprove が「attribute Valid is assumed to return True」と警告するためです。
   - 上限を入れると、1.0E200 程度の係数を使う既存のテストの期待が変わります。
     - 成功を期待するもの:
       - `tests/test_transforms.adb` の "huge Scaling_X"、"huge scale map angle"
       - 同じファイルの "invert, extreme scales" の節
       - `tests/test_coordinate_spaces.adb` の "Change_Transform with diag (1.0E200)" と "extreme scalings along a path" の節
       - `tests/test_shapes.adb` の "map: similarities of extreme scale" の節のうち、倍率 1.0E155 の場合
     - `Constraint_Error` を期待するもの:`tests/test_transforms.adb` の "determinant overflow" の節と、`tests/test_coordinate_spaces.adb` の "extreme scalings along a path" の節の後半(1.0E400 まで合成する場合)
     - 2026-11-08 のコア修正で、`Invert` は行ごとに 2 のべき乗で縮めてから逆行列を求めるようになりました。そのため、要素が極端に大きい・小さい行列も、逆行列が表現できる限り反転できます(以前は "determinant overflows" などで特異として扱っていました)。
     - 上限の決め方に合わせて、これらのテストと仕様コメント(`amv-transforms.ads` の `Invert` など)を直します。背景は `docs/handoff/CORE_NOTES.md` の「共通」の項にあります。

5. **表明ポリシー:** 各カーネルの仕様と本体の先頭に、次を書きます。

   ```ada
   pragma Assertion_Policy
     (Pre => Check, Post => Ignore, Ghost => Ignore,
      Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
      Assert_And_Cut => Ignore, Contract_Cases => Ignore,
      Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
      Type_Invariant => Ignore, Default_Initial_Condition => Ignore);
   ```

   この組み合わせは予備実験(6 節)で確かめました。
   - **`-gnata` でビルドしても、ユニット内の pragma が優先される。** ただし Ignore になるのは、pragma に列挙した種類だけです。
     - 列挙しなかった種類は、テストビルドでは実行されます。さらにゴーストを参照していると、テストビルドだけがコンパイルエラー("incompatible ghost policies")になります。そのため上の pragma では、`Assert_And_Cut` 以下も列挙しています。
     - `Assert_And_Cut`・`Contract_Cases`・`Subprogram_Variant`・`Dynamic_Predicate` は、列挙すると実行されなくなることを確認済みです。`Type_Invariant` と `Default_Initial_Condition` は、念のため列挙しています(未実験)。
     - これにより、テストビルドでも `Post`・ゴースト・ループ不変条件は実行されません。量化子付きのループ不変条件を実行すると O(n²)、再帰的なゴースト関数を実行するとスタック溢れになりますが、そのどちらも避けられます。
   - **内部の `Pre` は本番ビルドでも検査される。** 証明が通っていれば違反は起きませんが、念のための防御として残します。
   - **gnatprove はこのポリシーに関係なく、`Post`・ループ不変条件・`pragma Assert` を全部証明の対象にする。** 正しいものは証明され、誤ったものは指摘されます。
   - **注意:** `Pre` からゴーストの実体を参照すると `Ghost => Ignore` と矛盾し、コンパイルエラーになります。`Pre` は、ゴーストでない安い式にします。

6. **禁止事項(カーネル内):**
   - `pragma Assume`
   - `pragma Annotate (GNATprove, False_Positive | Intentional, ...)` による握りつぶし
   - `Skip_Proof` / `Skip_Flow_And_Proof`
   - 3.2 の 3 と 4 の信頼する部分以外での `SPARK_Mode => Off`

   どうしても必要な場合は `docs/PROOF.md` に理由と一緒に列挙し、レビューを通します。証明できない性質は、仮定で済ませずに `Post` を弱め、そのことを文書化します。

## 5. Ada の公開 API(シェル)は薄く保つ

Ada の公開 API は、カーネルの入口を包むだけの層にします。判断や計算はすべてカーネルに置き、証明の外に残るロジックを最小にします。

**Ada の公開 API の本体でしてよいこと(これ以外は書かない):**

1. **値の受け渡し。**
   - private 部に持つカーネルのレコードやハンドルを、そのまま入口に渡す。
   - 列挙型と符号を `'Pos` / `'Val` で変換する。
   - 結果を取得用の入口で読んで格納する。
2. **ハンドルの寿命と共有の管理。**
   - 制御型の `Finalize` で `ks_..._destroy` を呼ぶ。
   - 画素ハンドルの参照カウントを管理する(3.6 の A)。
3. **入口の呼び出し。** 1 つの公開操作につき、原則 1 回。
4. **状態値の変換。** `Check (Status)` で、対応する `Ks_` 例外を送出する。
5. **`Run` での処理。** 例外を捕まえて `Run_Status` に記録し、処理時間を計る。
6. **ファイル I/O。** ファイルとバイト配列の間の読み書きだけ。

**Ada の公開 API の本体に書いてはいけないこと:**

- `Real` や画素値の算術、およびそれを比べて値を判断すること。入力値の検証も含みます。検証はカーネルが行い、状態値で返します。
- 画素や座標を回すループ。
- `Ada.Numerics` の使用。
- 結果を左右する条件分岐。
- 座標空間名の解析。

**守らせ方:**

- **機械的なチェック(未作成。基盤を作る段階で用意する)。**
  - Ada の公開 API の本体(`src/amv-*.adb` のうちカーネル以外)から、次を検出するスクリプトを作ります。
    - `loop`
    - `Ada.Numerics`
    - 浮動小数点リテラル
    - 算術演算子
  - 同じ行に正当化のコメント(`--  SHELL: 理由`)がないものがあれば失敗にし、`make check` に組み込みます。
- **レビュー。** 差分が「受け渡し・入口の呼び出し・状態値の変換だけか」を必ず確認します。
- **大きさの目安。** 公開 API のサブプログラムは、多くが 10 行前後になるはずです。

## 6. 予備実験の結果

GNAT 14.2(`gnat_native=14.2.1`)と、Alire で入れた `gnatprove=14.1.1` を使いました(`alr install --info` で確認できます)。同梱のソルバは z3 4.13.0、cvc5 1.1.2、Alt-Ergo 2.4.0、Why3 1.6 です。実験用のコードはリポジトリに入れていません。

- **Git Bash からは証明できない。**
  - Git Bash から `gnatprove` を実行すると、全ソルバが「High failure」になります(`obj/gnatprove/<ユニット>.spark` と `why3session.xml` に記録されます)。`X not in 1 .. 10` で return した後の `pragma Assert (X >= 1)` すら証明されません。
  - 生成された証明課題(.smt2)を z3 で直接解くと unsat(証明成功)になります。
  - 同じプロジェクトを PowerShell から実行すると証明されます。PATH を変える必要はありません。
- **ランタイムの数学関数の契約。** `Ada.Numerics.Generic_Elementary_Functions`(`a-ngelfu.ads`)は `SPARK_Mode => On` で、主な契約は次のとおりです。

  | 関数 | Pre | Post |
  |---|---|---|
  | `Sqrt` | `X >= 0.0` | 結果 `>= 0.0` |
  | `Sin` / `Cos` | なし | 結果 ∈ [-1, 1] |
  | `Arcsin` / `Arccos` | `abs X <= 1.0` | 特定の点の値だけ(`X = 0.0` なら `Arcsin` は 0、`X = 1.0` なら `Arccos` は 0)。結果の範囲はない |
  | `Arctan (Y, X)` | `X /= 0.0 or Y /= 0.0` | **結果の範囲がない** |

  `Arctan`・`Arcsin`・`Arccos` には結果の範囲を述べる事後条件がありません。`Sqrt` にも上限がありません(`>= 0.0` だけ)。
  角度の範囲(例えば (-Pi, Pi])を証明したいときや、`Sqrt` の結果に掛け算・足し算をするときは、カーネル側で明示的に切り詰めるか、上限を補題で示してください。
  実験では、`DX`, `DY` ∈ [-1e6, 1e6] から求めた `Sqrt (DX*DX + DY*DY)` を 2 倍するだけで、オーバーフローの検査が証明できませんでした。
- **4 の 5 の表明ポリシー(PowerShell から実行)。**
  - 正しいループ不変条件と事後条件は証明される。
  - 誤ったループ不変条件・`Assert`・事後条件は指摘される。
  - `-gnata` でビルドしても、`Post` と再帰的なゴースト関数は実行時に呼ばれない(200 万要素でもスタック溢れなし)。
  - `Pre` 違反は実行時に検出される。
- **C ABI での公開。**
  - `Convention => C` のレコードを引数に持つ SPARK の手続きに `Export` を付けると、C の main から直接呼べた。
  - その手続きの検査の大半は証明できた(残りは実験コード自体の不備)。
  - 種類ごとの部分レコードを並べた図形レコードは、C の構造体と同じ配置になった。
- **所有権付きアクセス型によるハンドル。**
  - 画像ハンドルの作成・塗りつぶし・画素取得・破棄を SPARK で書き、C から `ks_image*` として使えた。
  - null のハンドルや範囲外の座標は、状態値で返った。
  - 証明では 48 件中 46 件が通り、メモリリークの指摘もなかった。残り 2 件は実験コードの添字計算の不備。

### 6.1 macOS と 16 系での追加の確認(2026-11-08)

- macOS では、Git Bash のようなソルバの失敗は起きない。正しいコードは証明され、誤りは指摘される(14.1 と 16.1 の両方)。
- **`pragma Validity_Checks ("F")` をカーネルの仕様と本体に置けば、Ada 側を `-gnatVa` でビルドしても、NaN・±Inf は入口の範囲検査まで届く**(`-O1 -gnata` と `-O2 -gnatn` の両方で確認)。pragma がないと、呼び出し側で `Constraint_Error`("invalid data")になる。Ada の公開 API 側には pragma は要らない。(2026-11-11 追記: 要らないように見えたのは、GNAT 16.1 が仕様ファイルの先頭の `pragma Validity_Checks` を、その仕様を with した単位にも適用するため。カーネルの仕様の pragma が Ada の層の検査も切っていた。今は Ada の層の各ファイルにも pragma を置く。`DESIGN.md` の 9.3)
- **非静的な `'Exponent` と `'Scaling` は、gnatprove 14.1 でも 16.1 でも未対応**("not yet supported" のエラー)。2026-11-08 のコア修正では、`Invert`、`AMV.Misc.Hypot`、幾何のフィットが、2 のべき乗で正確に縮めるためにこの 2 つを使っている。カーネルでは、静的な 2 のべき乗の定数で割る・掛ける形に書き換える(`AMV.Kernels.Misc.Hypot` が例)。
- **`'Remainder` の値の範囲は、16.1 なら証明できる**(14.1 ではできなかった)。`Norm_Angle` の (-Pi, Pi] を、守りの分岐なしで証明するには `--level=4` が要る(このユニットだけ上げている)。
- **GNAT の `-gnatceg`(Ada の仕様から C のヘッダを生成するスイッチ)は、FSF 版では何も生成しない。** そのため `include/amv.h` は手書きにし、配置は Ada 側の表現句(`Ks_Status`)と C 側の `_Static_assert` で固定している。
- **浮動小数点の積や商の上限は、そのままではソルバが時間内に示せないことが多い。** 上限を事後条件に持つ小さな関数(`AMV.Kernels.Numerics` の `Mul` など)を、本体の見えない関数として使うと、呼び出し側の証明が線形になり、すぐに通る(Transforms で 11 か所が解決)。`'Remainder` も、事後条件のない関数に包むと証明が速く安定する。
- **量化子付きの不変条件は、配列の要素について書く(座標空間のカーネルで確認)。** `for all I in ... => Valid_Space (Tree, I)` のように、木全体を引数に取る関数を量化子の中で呼ぶと、次の 2 つの理由で使えなかった(どのソルバも 60 秒で証明できない)。
  - gnatprove は、式関数の呼び出しがゴールになると、本体の連言に展開してから証明する。そのため、量化子のトリガになる項 `Valid_Space (Tree, I)` がゴールから消え、特定の添字で不変条件を取り出せない。
  - 配列の 1 要素を書き換えた後の木は別の項なので、書き換え前の木についての量化子とは照合しない。

  `Tree.Spaces (I).Parent in 0 .. I - 1 and then Valid_Link (Tree.Spaces (I), Tree.Spaces (I - 1), ...)` のように要素について書くと、どちらも解決した(トリガが要素の読み出しになり、更新の公理で等しくなった項とも照合する)。
- **量化子の本体で、事前条件を持つ関数を直接呼ばない。** 呼ぶと、その量化子はまったく使えなかった。事前条件の内容を連言に含めた全域の関数にする(`Less`)。
- **ループ不変条件では、入れ子の添字(`R.Spaces (R.Spaces (I).Parent)`)を避ける。** 更新をまたいだ保存が証明できなかった。ループは平らな事実(名前、付け替えた親の添字)だけを保ち、入れ子の性質は、書き換えのない木を引数に取るゴーストの補題(証明用のループを持つ)で導く。
- **内部のサブプログラムが妥当な木を前提とするときは、`Dynamic_Predicate` 付きの部分型を引数の型にする。** 表明ポリシー(4 の 5)により実行時には検査されず、gnatprove は呼び出しごとに述語を証明し、本体では仮定する。「内部の `Pre` は量化子を含まない安い式に限る」(4 の 3)を守ったまま、量化子付きの前提を渡せる。
- **GNAT 16.1 のコンパイラ内部エラー:** `pragma Compile_Time_Error` の条件に、オブジェクトの成分の `'Position` を書くと ICE になる。配置は表現句で固定する。

## 7. 証明の実行方法

- `amv.gpr` に Prove パッケージを足しました(9 の 1 で実施)。

  ```
  package Prove is
     for Proof_Switches ("Ada") use ("--level=2");
  end Prove;
  ```

  重いユニットだけ `for Proof_Switches ("amv-kernels-xxx.adb") use ("--level=4");` のように個別に上げます。
- `prove` の実行コマンドは次のとおりです。

  ```
  gnatprove -P amv.gpr -j0 --checks-as-errors=on --warnings=error --report=fail
  ```

  - Windows では PowerShell かコマンドプロンプトから実行します。`Makefile` から呼ぶ場合も、Git Bash 経由にならないよう注意してください。
  - カーネルのユニットに警告が出ないことも合格条件にします。gnatprove の既定は `--warnings=continue` で、警告が出ても終了コードは 0 になります。そのため上のコマンドでは `--warnings=error` を付けています。
- 複数人(複数エージェント)で同時に作業する場合:
  - 証明結果の置き場所が衝突しないよう、`--subdirs=<名前>` と `-u <ファイル>` で自分のユニットだけを証明します。
  - CPU を食い合わないよう `-j2` から `-j4` 程度に抑えます。

## 8. 既存コードの移し方(提案)

| Ada の公開 API(既存) | カーネル(新規) | 証明の目標 |
|---|---|---|
| `AMV.Misc` | `AMV.Kernels.Misc` | `Norm_Angle` ∈ (-Pi, Pi]、`Norm_Angle_Pi` ∈ (-Pi/2, Pi/2] などの範囲(Gold) |
| `AMV.Transforms` | `AMV.Kernels.Transforms` | 合成・状態付き逆変換・点とベクトルの写像・分解と再合成。オーバーフローなし(Silver)と、有界性 |
| `AMV.Coordinate_Spaces` | `AMV.Kernels.Coordinate_Spaces` | 上限付き配列の木。名前の検証、追加と削除、`Get_Transform` の解決。添字の安全と木の不変条件(親が存在し、循環がない)(Gold) |
| `AMV.Images` | `AMV.Kernels.Images` | 画素ハンドルの作成と破棄、塗りつぶし・窓のコピー・行の取得と設定・プレーン抽出。変更される要素が指定範囲だけであること(Gold)。C のメモリとの受け渡しは信頼する部分(3.2 の 3) |
| `AMV.Image_File` | `AMV.Kernels.Image_File` | バイト列からのヘッダ解析と画素の復号・符号化。範囲外を読まない、寸法の整合、悪意あるヘッダでも巨大な確保をしない(Silver と一部 Gold) |
| `AMV.Shapes` | `AMV.Kernels.Shapes` | 包含判定・外接矩形・面積・写像(Silver) |
| `AMV.Regions` | `AMV.Kernels.Regions` | 図形からのラスタライズ全体、境界の縮小、`Count` が True の数に等しいこと(Gold) |
| `AMV.Image_Math` | `AMV.Kernels.Image_Math` | ガウシアン・ボックス・Sobel・縮小・統計・バイリニア・リサンプル。値の上限を決めたうえで Silver |
| `AMV.Geometry` | `AMV.Kernels.Geometry` | 距離・交点・直線と円のフィット。退化は状態値で返す(Silver) |
| `AMV.Tools` | `AMV.Kernels.Tools` | `Ks_Tool_Result_Constants` などの共有の符号だけ。`Run` は Ada の公開 API に残す |

補足:

- **ツール群(未実装)は、最初からこの形で書く。** カーネルの `AMV.Kernels.Blob` などに、ツールのハンドル・パラメータのレコード・`ks_blob_tool_run`・結果の取得用の入口を書きます。Ada の公開 API の `AMV.Blob` などは、それを包むだけにします。ツールのカーネルでは、例えば次の処理を Gold まで狙えます。
  - 二値化、ヒストグラム、ルックアップテーブル(LUT)
  - モルフォロジー
  - 連結成分のラベリング(union-find)とモーメント
  - キャリパの射影プロファイルと 1 次元エッジ検出
  - 正規化相互相関(NCC)
- **`AMV.Image_File` の読み方。** カーネル化の前の復号器は `Get_Pixel` / `Set_Pixel` で 1 画素ずつ処理していました。`AMV.Kernels.Image_File` は、ファイル全体のバイト配列をまとめて復号し、画像のハンドルの画素行列に直接書きます(済み、2026-11-08)。

## 9. 進める順番(提案)

1. **基盤を作る。**(2026-11-08 に実施。計画との違いは次のとおり)
   - 確保用の信頼する補助ルーチンは、最初にハンドルを使うカーネル(9 の 2 の画像ファイル)で作る。使い道のないまま設計しないため。
   - 薄さの検査は Ada のプログラム(`tools/shell_check`)にした。GNAT さえあれば、どの環境でも動く。
   - `amv.h` は手書き(6.1 の `-gnatceg` を参照)。置き場所は `include/`。
   - C のテストは `tests/c/` と `amv_c_tests.gpr` に置いた(`make test` に含む)。C の例は、まだ置いていない。
   - `AMV` に `SPARK_Mode` を付ける。
   - `AMV.Kernels` のルートを作る。ここに `Ks_Status`、C 互換の基本型(`Int32` など)、上限の定数(`Max_Pixels` など)、確保用の信頼する補助ルーチンを置く。
   - Ada の公開 API 側に、共通の `Check` を作る。
   - 3.6 の画素共有の方式を決める(推奨は A)。
   - `amv.gpr` に Prove パッケージを、`Makefile` に `prove` を足す。
   - 5 節のチェック用スクリプトを作り、`make check` に組み込む。
   - `amv.h` の置き場所と保守の方法(手書きか生成スクリプト)を決める。ABI の版を返す入口(`ks_abi_version`)を用意する。
   - `docs/DESIGN.md` に「9. SPARK と C API」の節を足し、3〜5 節の規則を書き写す。
   - あわせて、`docs/DESIGN.md` の 7 節にある「no C code」と「every heap object is owned by a controlled type」を改める。C API・C の例・カーネルの所有権付きハンドルを認める形にする。
   - C の例を置くなら、`amv_examples.gpr` の `Languages` に "C" を足す。
2. **画像ファイルのコーデック。** 外部入力を扱うので、証明による安全性の効果が最も大きい部分です。
3. **Images と Regions(と、その前提になる Shapes)。** Gold を取りやすい部分です。
4. **Misc、Transforms、Coordinate_Spaces。**
5. **Image_Math と Geometry。** 浮動小数点なので難度が高い部分です。
6. **ツール群。** 最初からカーネルの入口(= C の公開 API)として書きます。
7. **C から使う例と、C 側のテスト。** `examples/` に置きます。ビルドの例は 6 節の実験と同じく、gprbuild の混在言語プロジェクトで C の main をリンクし、`adainit` / `adafinal` を呼びます。

ツール群をまだ書いていないので、**基盤(1)はツール実装より先に作る**ことを勧めます。

## 10. この構成のデメリットと対策

カーネルの入口をそのまま C の公開 API にする場合、次のデメリットがあります。どれも上の規則で対処できる範囲です。

| デメリット | 対策 |
|---|---|
| 入口の型が C 互換に限られる(判別子付きレコード・非制約配列・範囲付きの型・`Boolean`・列挙型を直接使えない) | 内部は Ada の型を自由に使い、変換は入口で行う(3.2 の 1)。Ada の公開 API は、列挙型と符号の変換を機械的に行う |
| 画素の共有を SPARK で表現できない | 3.6 の A(カーネルは共有せず、共有は Ada の公開 API が行う) |
| C のメモリとの受け渡し(ポインタと長さ)は証明できない | ごく少数の信頼する部分に閉じ込めて、`docs/PROOF.md` に列挙する(3.2 の 3) |
| メモリ確保の失敗だけは SPARK で扱えない | 確保を信頼する補助ルーチンに寄せ、`Out_Of_Memory` を返す(3.2 の 4) |
| 入口に `Pre` を置けない | 入口ですべて検証する(3.2 の 2)。内部の `Pre` は証明される |
| カーネルを変えると C の ABI が変わる | 公開する構造体は、末尾にしか項目を足さない。`ks_abi_version` を用意し、互換性を壊す変更では版を上げる |

利点は、公開する API が 1 種類で済むことです。C の公開 API がそのまま証明の対象になり、Ada の公開 API は機械的に薄く書けます。

## 11. 落とし穴

- **画素数の計算。** `Width * Height` は 32bit 整数をあふれることがあります。64bit に広げて比べるか、契約を `Height <= Max_Pixels / Width` の形で書きます。整数の掛け算(非線形)の証明はソルバが苦手なので、必要なら `pragma Assert` で中間の事実を置きます。
- **`Long_Float` の積和。** 入力の上限を決めないと、オーバーフローしないことを証明できません。何回足すか(画素数)も上限に効きます。
- **事前条件と事後条件は実行時の検査と同じではない。** 本番ビルド(`amv.gpr`)は `-gnata` なしです。4 の 5 の表明ポリシーで `Pre` だけを常に検査し、それ以外は証明に任せます。
- **大きな可変レコード。** 画素をレコードに埋め込んでローカル変数として宣言すると、スタックを溢れさせます。画素はハンドルの先のヒープに置きます。
- **浮動小数点の証明は重い。** 時間がかかるときは次を試してください。
  - `pragma Assert` で中間の不等式を置く
  - 補題をゴースト手続きに切り出す
  - `--level` を上げる
- **`-gnatVa`(テストと本番の両方)。** 浮動小数点のオーバーフローは代入した時点で `Constraint_Error` になります。カーネルではオーバーフローしないことを証明するので、この挙動には依存しなくなります。
