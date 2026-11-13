# コアパッケージの実装メモと既知の課題

コアの各パッケージを実装した担当(並列エージェント)の報告を、要点だけ残したものです。

- 仕様(`.ads`)のコメントに書かれた振る舞いが正です。このメモは、その背景と、まだ残っている課題を記録します。
- テストの数は 2026-11-08 のコア修正(`fix/core-review`)の時点のものです。合計 7,485 チェック、失敗 0 です(最初の実装の時点では 6,170)。
- 2026-11-08 に、6 つの観点でコアをレビューし、確定した 22 件を回帰テスト付きで直しました。以下の記述は修正後の振る舞いです。

## 共通

- **極端な大きさの浮動小数点値。** テストも本番も `-gnatVa` でビルドするので、浮動小数点のオーバーフローは代入の時点で `Constraint_Error` になり、Inf が格納されることはありません。
  - `Invert` は、逆行列が `Real'Last` を超える場合を事前に検査し、`Ks_Transform_Singular_Exception` にします(`Constraint_Error` を捕まえる作りはやめました)。
  - `AMV.Transforms` は 2026-11-08 にカーネル化し、値の上限(1.0E150)を設けました。`Map_Point`、`Map_Vector`、`Compose`、`Determinant`(現在の `Matrix_Determinant`)が `Constraint_Error` を出すことはなくなり、上限を超える引数や結果は `Ks_Bad_Parameter_Exception` になります。
  - `Coordinate_Spaces.Get_Transform` も、経路の合成が上限を超えると `Ks_Bad_Parameter_Exception` になります(仕様に明記)。
  - NaN や ±Inf の引数は、カーネル化していないパッケージでは `-gnatVa` の妥当性検査で `Constraint_Error`("invalid data")になります。カーネル化したパッケージ(`AMV.Misc`、`AMV.Transforms`、`AMV.Shapes` など)では、カーネルの入口の範囲検査で `Ks_Bad_Parameter_Exception` になります。
- **長さの計算は `AMV.Misc.Hypot` にまとめた。** 2**(-500) から 2**500 の範囲では素直な式と同じ結果で、それ以外は 2 のべき乗で縮めてから計算するので、表現できる結果なら途中であふれません。`AMV.Transforms` と `AMV.Shapes` にあった同じ関数の写しは、これに置き換えました。
- **ヒープを持つ型のストリーム属性。** 画像 3 種、`Real_Image`、`Pixel_Region` は、既定のストリーム属性だとポインタそのものを書き読みしていました(読み込むと解放済みメモリの使用や二重解放になる)。いまはどれも値を書き、読むときは寸法を検証してから確保します。不正なデータは `Ks_Image_File_Exception` です。今後ヒープを持つ型を足すときの規則を `docs/DESIGN.md` の 7 節に足しました。

  SPARK 化の際には、入力の上限を決め、上限外を `Ks_Bad_Parameter_Exception` にそろえる予定です(`SPARK_PLAN.md` の 4 の 4)。
- **`AMV_Test_Support.Check_Raises` はどの例外でも合格にする。** 特定の例外だけを合格にする `AMV_Test_Support.Check_Raises_Exactly` がすでにあり、ほとんどのテストはこちらを使っています。新しいテストで例外の種類まで確かめるときは、`Check_Raises_Exactly` を使ってください。
- **2 つのテストが GNAT の挙動に依存している。** `tests/test_tools.adb` の次の 2 か所で、GNAT 14.2 では成り立ちます。
  - 添字の `Constraint_Error` のメッセージに "index" が含まれる。
  - 独自例外の名前が ".CUSTOM_ERROR" で終わる。
- **`test_image_file` の書き出し先。** カレントディレクトリ基準で `tests/output/` に書き出すので、リポジトリのルートから実行してください。このディレクトリは gitignore 済みです。
  - 担当者のリークチェックで、`tests/output/leak.pnm` と `leak_multi.pnm`(数 MB)が残っている場合があります。消してかまいません。
- **2026-11-08、例外の名前を VisionPro にそろえた。** `Ks_Not_Trained_Exception` は `Ks_Operator_Not_Trained_Exception`(VisionPro の `CogOperatorNotTrainedException`)に改名しました。失敗の符号も `Failure_Not_Trained` から `Failure_Operator_Not_Trained`、C の `KS_FAILURE_NOT_TRAINED` から `KS_FAILURE_OPERATOR_NOT_TRAINED` に改名しています(値は 3 のまま)。別名は残していません。`Ks_Bad_Parameter_Exception` は名前を変えず、.NET の `System.ArgumentException` に当たるものとして扱います(VisionPro には `CogBadParameterException` のような独自の例外がない)。対応は `docs/API_MAPPING.md` の「Exceptions」にあります。

## AMV.Transforms / AMV.Coordinate_Spaces

テスト: `test_transforms` 693 チェック、`test_coordinate_spaces` 2,027 チェック(カーネル化の後は 2,477 チェック。上限とストリームのテストを含む)。

- **`Map_Angle_Zero_Tolerance` を追加した(1.0E-14)。** 写像した方向ベクトルの 2 成分が、どちらも「この値 × 行列要素の最大絶対値」以下なら特異とみなして例外を送出します。
  - 丸めのため、厳密に 0 かどうかの判定では成り立たないケースがありました。例えば `[1 1; 1 1]` を -Pi/4 で写像すると、0 ではなく 1e-16 程度になります。
- **`Scaling_X = 0` のとき `Aspect` は 0.0 を返す(例外にしない)。**
- **負のスケール・アスペクトも受け付ける。** 負の値の軸が反転します(負の `Scaling` は両軸)。読み戻すと値は絶対値になり、反転した軸の回転(`Rotation_X` または `Rotation_Y`)が Pi ずれます。例えば負の `Aspect` では、`Rotation` は変わらず `Skew` が Pi ずれます。
- **`Is_Similarity` は反射を含まない(行列式 > 0 が必要)。** 一方、`AMV.Shapes` は反射を含めて相似とみなしています(下記)。
- **2026-11-08 以降、`AMV.Transforms` は SPARK のカーネル `AMV.Kernels.Transforms` を呼ぶ薄い層になった。** 次の項目のうち `Invert` の実装の説明は、カーネル化の前のものです。カーネルでは、要素・平行移動・座標・縦横比・角度の絶対値を 1.0E150 以下(スケールは 2.0E150 以下)に制限します。範囲外の引数と、範囲外になる結果(写像した点、合成、縦横比など)は `Ks_Bad_Parameter_Exception` です。逆行列が範囲外になる場合は `Ks_Transform_Singular_Exception` です。逆行列が範囲内に収まる行列は、行列式が約 2.5e-301 以上あるので、素直な式で精度を保てます(行ごとの縮小は不要になった)。NaN・±Inf も `Ks_Bad_Parameter_Exception` です。
- **`Invert` は行ごとに 2 のべき乗で縮めてから計算する。** 各行を、その行の最大の要素のすぐ上の 2 のべき乗で割ってから行列式を求めます。2 のべき乗の掛け算は誤差を生まないので、普通の大きさの行列では以前と 1 ビットも違わない結果になります。要素が極端に小さい行列(以前は 1e-162 程度以下で特異と判定)、極端に大きい行列、行どうしの大きさが極端に違う行列(diag(1e10, 1e-300) など)も、逆行列が表現できる限り正しく反転します。特異と判定するのは、行がほぼ平行(縮めた行列式が 2**(-1022) 未満)な場合と、逆行列が `Real'Last` を超える場合です。
- **`Norm_Angle` と `Norm_Angle_Pi` は `Real'Remainder` で縮める。** 以前は 1.1e17 程度より大きい角度で範囲外の値を返していました。いまはすべての有限の引数で (-Pi, Pi] / (-Pi/2, Pi/2] に入ります。範囲内の値はそのまま返し、0 は +0.0 にそろえます。2**55 を超える角度の縮約値には、幾何的な意味はありません(仕様に明記)。
- **`Deg_To_Rad` と `Rad_To_Deg` は定数を 1 つにまとめた。** 途中の積でのオーバーフローがなくなりました。
- **`Get_Transform` は木の深さに関係なく一定のスタックで動く。** 以前は再帰で各段に名前を写していたため、深さ 3,000〜4,000 段でスタックがあふれていました。合成の順序(結合のしかた)は再帰のときと同じなので、結果も以前と 1 ビットも違いません。
- **空間名の添字の範囲は任意。** `Integer'Last` で終わる文字列を渡しても、`Constraint_Error` ではなく正しく動きます(不正な名前は `Ks_Image_Bad_Selected_Space_Name_Exception`)。
- **スケールが 0 のときの `Set_Rotation` と `Set_Skew`。** 「1 つのプロパティを設定しても他は変わらない」という約束は、両方のスケールが 0 でない場合に限ります。0 の列があるときの振る舞いは仕様に書いてあります(コードの変更はなし)。
- **同じ空間名を 2 回指定した `Get_Transform` は厳密な恒等変換を返す。** 仕様に書いてあります。
- **2026-11-08 以降、`AMV.Coordinate_Spaces` は SPARK のカーネル `AMV.Kernels.Coordinate_Spaces`(C の `ks_coordinate_space_tree_*`)を呼ぶ薄い層になった。** 上の「深さに関係なく一定のスタック」と「添字の範囲は任意」の 2 項目のうち、前者の説明はカーネル化の前のものです(後者はそのまま成り立ちます)。
  - ツリーは、ポインタを持たない固定長の C 互換レコード(19,976 バイト)です。項目は完全名の辞書順(`String` の `"<"` と同じ順)に並び、親は必ず子より前にあります。この不変条件(`Valid_Tree`)を、ツリーを変えるすべての入口が保つことを証明しました。失敗した呼び出しはツリーを変えません(これも証明済み)。
  - Ada の公開 API は、このレコードをヒープの箱に入れ、制御型で持ちます。箱がない間は "@" だけのツリーで、最初の変更で確保し、代入で深くコピーし、`Clear` で解放します。画像が 20 KB を抱えずに済み、値の意味(代入でコピー)も変わりません。
- **上限。** 1 つのツリーに置ける空間は、ルートを含めて 64 個です。空間の完全名は 256 文字までです。
  - 上限を超える `Add_Space` は `Ks_Bad_Parameter_Exception` になり、ツリーは変わりません。すでにある空間の変換の置き換えは、ツリーがいっぱいでもできます。
  - 256 文字を超える名前の引数は、どの空間も指しません(`Space_Exists` は False、ほかの操作は `Ks_Image_Bad_Selected_Space_Name_Exception`)。
  - 256 文字を超える成分は、先頭 256 文字だけで妥当性を判断します。それより後ろに '\' があっても、`Ks_Image_Bad_Selected_Space_Name_Exception` ではなく、長すぎるとして `Ks_Bad_Parameter_Exception` になります。
  - 以前の深い木のテスト(5,000 段の鎖と、30 文字 × 1,000 段の鎖)は、上限でのテストに置き換えました。63 段の鎖でツリーがいっぱいになり、65 個目は拒否されます。50 文字 × 5 段で 256 文字の名前は使え、1 文字でも増えると拒否されます。
- **`Add_Space` の検査の順序。** 親が存在するか、成分が妥当か(ここまでは `Ks_Image_Bad_Selected_Space_Name_Exception`)、変換が有限で 1.0E150 以内か(`Ks_Bad_Parameter_Exception`)、逆変換がその範囲に収まるか(`Ks_Transform_Singular_Exception`)、完全名が 256 文字以内か、新しい空間を置く余地があるか(どちらも `Ks_Bad_Parameter_Exception`)、の順です。上限外の変換のメッセージは「Add_Space: the Parent_From_New transform must be finite and within +/-1.0E150」です(カーネル化の時点では「the Child_From_Parent transform ...」、その前は `Invert` のメッセージ)。名前の誤りのメッセージは以前と同じです。重複の扱いを足した後の順序は、下の 2026-11-08 の項目にあります。
- **`Space_Name` の添字の誤り。** 新しい失敗の符号 `Failure_Index_Out_Of_Range`(9、C では `KS_FAILURE_INDEX_OUT_OF_RANGE`)を足しました。`AMV.Checks` がこれを `Constraint_Error` に変えるので、Ada の振る舞いは変わりません。
- **ストリーム属性を足した。** ツリーがヒープを持つようになったので、`docs/DESIGN.md` の 7 節に従い、自前の `'Read` / `'Write` を持ちます。形式は `amv-coordinate_spaces.ads` の冒頭にあります(書式の符号、ルートを含む空間の数、ルート以外の各空間の名前(固定長 260 バイト)と変換)。読むときはストリームを信用せず、カーネルで 1 空間ずつ組み立て直します。不正なデータと途中で終わるストリームは `Ks_Image_File_Exception` で、読み込み先は変わりません。画像のストリームは、これまでどおり画像側の形式でツリーを書きます(この属性は使いません)。
- **等しさ。** `"="` は、同じ名前・親・変換(成分ごとの `"="`)の空間を持つかで比べます。箱を確保したかどうかは関係しません。以前の `Ordered_Maps` の `"="` と同じ意味です。
- **入口ごとの検査の費用。** C からは任意のレコードが渡りうるので、どの入口も最初に `Valid_Tree` を確かめます。費用は「空間の数 × 名前の長さ」に比例します(典型的な小さいツリーでは数百回の比較、最悪の 64 空間 × 256 文字でも数万回)。
- **2026-11-08、座標空間ツリーの API を VisionPro の `CogCoordinateSpaceTree` にそろえた。** 対応表は `docs/API_MAPPING.md` にあります。
  - **変換の向きを逆にした。** 各空間は、自分の座標を親の座標へ写す `Parent_From_Child` を持ちます(VisionPro の `AddSpace` の引数 parentFromNew と同じ向き)。以前の `Child_From_Parent`(親から子へ)とは逆です。カーネルは与えられた変換を逆行列にせず、そのまま保存するので、`Parent_From_Child_Transform` で 1 ビットも違わずに読み戻せます。C の構造体のフィールドも `ks_coordinate_space.parent_from_child` に改名しました(配置は同じ)。
  - **新しい操作。** `Add_Space (Tree, Parent_Space_Name, New_Space_Name, Parent_From_New, Duplicate_Handling := Replace_Duplicate)`、`Change_Transform (Tree, Child_Space_Name, New_Parent_From_Child)`、`Delete_Subtree`、`Parent_Name`、`Child_Names`、`All_Child_Names`、`Verify_Name`、`Root_Name`(いつも "@")。列挙型 `Ks_Add_Space_Constants`(`Duplicate_Is_Error`, `Replace_Duplicate`, `Ignore_Duplicate`)と `Ks_Space_Tree_Pathname_Constants`(`None`, `Full`, `Partial`)は、VisionPro と同じ位置(0, 1, 2)で、C には `KS_ADD_SPACE_*` と `KS_SPACE_TREE_PATHNAME_*` の `int32_t` の符号として渡ります。入口は符号を最初に確かめ、範囲外は `Ks_Bad_Parameter_Exception` です。
  - **消した名前(別名は残していない)。** `Remove_Space`(→ `Delete_Subtree`)、`Set_Child_From_Parent_Transform`(→ `Change_Transform`)、`Child_From_Parent_Transform`(→ `Parent_From_Child_Transform`、向きも逆)、`Parent_Space_Name`(→ `Parent_Name`)。
  - **既定値。** `Duplicate_Handling` の既定値 `Replace_Duplicate` は AMV の選択です(VisionPro の既定値は文書にない)。これまでの「すでにある空間は変換だけを置き換える」振る舞いを保ち、fixture ツールが実行のたびに空間を足し直す使い方に合います。`Parent_Name` などの `Pathname_Format` の既定値は `Full` です。VisionPro の copyTransform 引数は、変換が値なので対応するものがありません。
  - **`Partial` の規則。** 操作の `Space_Name` 引数の空間より下にある空間は、その空間からの相対パスで返します("@\A" の下の "@\A\B\C" は "B\C")。それ以外の空間(その空間自身、親)は完全名で返します。したがって `Parent_Name` と `Verify_Name` の `Partial` は `Full` と同じで、`All_Child_Names` の `Children_Only => False` で入る空間自身も完全名です。`None` は最後の成分(ルートは "@")です。並びは完全名の辞書順で、空間自身は先頭に来ます。
  - **名前は完全名だけ。** `Verify_Name` も含め、すべての名前の引数は "@" から始まる完全名です。VisionPro の、最後の成分だけの名前や相対パスの解決(`FindNames`、`LookUpName`、`ResolvePartialName`)は、まだ実装していません。`Verify_Name` は名前については例外を出さず、見つからない名前・不正な名前には False と "" を返します。
  - **`Ks_String_Collection` は入れ子のパッケージ `AMV.Coordinate_Spaces.String_Collections` にある。** `AMV.Coordinate_Spaces` には同名の subtype と `Count`・`Item` の別名を置きました。同じパッケージ仕様に 2 つのタグ付き型を置くと、`Child_Names` が両方の型でディスパッチする操作になってしまい、Ada では許されないためです。`Count` と 0 始まりの `Item` に加え、AMV 独自の `Append` を持ちます(ツリーは結果をこれで組み立てる)。
  - **`Get_Transform` の結合のしかた。** `Root_From_To.Invert.Compose (Root_From_From)` で、`To` が "@" のときは `Root_From_From` そのもの(逆行列を作らない)です。`Root_From_X` は、X からルートへ上りながら `P_Top * (... * (P_Parent * (P_X * Identity)))` と左から掛けます。したがって `Get_Transform ("@", "@\A")` は与えた変換と(符号付きゼロを除いて)同じです。逆行列が上限内に収まらないのは `To` 側だけになり、そのとき `Ks_Transform_Singular_Exception`、合成が上限を超えるときは `Ks_Bad_Parameter_Exception` です。上の「深さに関係なく一定のスタック」の項目にある結合のしかたは、これで変わりました(同じ名前を 2 回指定したときは、これまでどおり厳密な恒等変換)。
  - **重複の扱いを含めた `Add_Space` の検査の順序。** `Duplicate_Handling` の符号、親が存在するか、成分が妥当か、変換が有限で上限内か・逆変換が上限内に収まるか、完全名が 256 文字以内か、すでにある空間か(`Duplicate_Is_Error` なら `Ks_Bad_Parameter_Exception`、`Replace_Duplicate` なら変換だけを置き換え、`Ignore_Duplicate` なら何もしない)、新しい空間を置く余地があるか、の順です。`Ignore_Duplicate` でも引数は検査します。重複のメッセージは「Add_Space: the space "@\A" already exists」、ルートについての誤りは「Change_Transform: the root space "@" has no parent」と「Delete_Subtree: the root space "@" cannot be deleted」です。
  - **例外の対応。** VisionPro の `ArgumentException` と `CogSpaceTreeDuplicateChildNameException` は `Ks_Bad_Parameter_Exception`、`CogSpaceTreeNameNotInTreeException` と `CogSpaceTreeInvalidNameSyntaxException` は `Ks_Image_Bad_Selected_Space_Name_Exception`、逆にできない変換は `Ks_Transform_Singular_Exception`、コレクションの範囲外の添字は `Constraint_Error` です。
  - **ABI の版とストリームの符号は上げていない。** `add_space` の意味が変わり、入口の名前も変わったので、本来は `ks_abi_version` を上げる変更です。ただし、座標空間のカーネルを含め、まだ何も公開していない(origin/main には最初の骨組みしかない)ので、版は 1 のままにしました。ツリーと画像のストリームの符号も同じ理由で変えていません。ストリームに書く変換の向きが変わったので、この変更の前に書いたストリームは、読めても変換が逆になります。
- **2026-11-08、`AMV.Transforms` の名前を VisionPro の `CogTransform2DLinear` にそろえた。** 対応表は `docs/API_MAPPING.md` にあります。別名は残していません。
  - **改名。** `Get_Matrix` / `Set_Matrix` は `Get_Matrix_Elements_Translation` / `Set_Matrix_Elements_Translation`(引数とその順序は同じ。VisionPro の elem00, elem01, elem10, elem11 が A, B, C, D)、`Determinant` は `Matrix_Determinant`、`Is_Identity` は `Identity (Transform, Tolerance := 1.0E-12)` です。`Identity` は引数のないコンストラクタ `Identity` の多重定義なので、`T.Identity` と `Identity (T, Tol)` は判定、`Identity` だけならコンストラクタになります。カーネルの入口と C の関数も同じ名前にしました(`ks_transform_2d_linear_matrix_determinant`、`ks_transform_2d_linear_identity`)。
  - **追加。** `Get_Matrix_Element (Transform, Row, Column)` / `Set_Matrix_Element (Transform, Row, Column, Value)`、`Map_Area (Transform, Area)`、`Singular (Transform, Tolerance)`、`Matrix_Identity (Transform, Tolerance := 1.0E-12)`。計算と検査はすべてカーネル `AMV.Kernels.Transforms` の入口(`ks_transform_2d_linear_get_matrix_element`、`_set_matrix_element`、`_map_area`、`_singular`、`_matrix_identity`)にあり、証明済みです。Ada の層は値を渡すだけです。
  - **行と列。** `Row` と `Column` は Ada では `Integer`、C では `int32_t` で、0 か 1 以外はカーネルで `Ks_Bad_Parameter_Exception`(VisionPro の `ArgumentException`)になります。検査の順序は変換、`Row`、`Column`、(`Set_Matrix_Element` では)`Value` です。メッセージは「Row must be 0 or 1」「Column must be 0 or 1」です。カーネルの入口なので、上限(1.0E150)を超える要素を持つ変換も拒否します(`Create` や `Set_Matrix_Elements_Translation` は値をそのまま保存するだけなので、こちらは拒否しません)。`Get_Matrix_Element` がその位置の要素をそのまま返すこと、`Set_Matrix_Element` がその要素だけを変えることは、事後条件として証明しました。
  - **`Map_Area`。** 行列式の絶対値 × `Area` です。平行移動は関係しません。負の `Area` は符号を保ちます(符号付き面積を想定)。`Area` と結果は 1.0E150 以内でなければならず、超えると `Ks_Bad_Parameter_Exception` です。行列式は最大 2.0E300 になるので、`abs Area <= 1` なら行列式を縮める積として、それ以外は行列式が 1.0E150 以内のときだけ掛けます(それ以外は結果が必ず上限を超える)。行列式は `Matrix_Determinant` と同じく書いたとおりに計算するので、2.2E-308 を下回る積では精度を失います。
  - **`Singular` の許容値は絶対値。** 行列式の絶対値が `Tolerance` 以下なら真です。行列式は要素の 2 乗の大きさなので、既定値は付けていません(`Identity` と `Matrix_Identity` の既定値は従来の 1.0E-12)。0 にアンダーフローする行列式は、どの許容値でも特異です。
  - **`Identity` の意味。** VisionPro の `Identity (tolerance)` の正確な意味は文書にないので、AMV は従来の `Is_Identity` と同じく、平行移動を含む 6 つの値すべてを比べます。平行移動を無視するのは `Matrix_Identity` です。
  - **AMV 独自のもの。** `Is_Similarity`、`Is_Axis_Aligned`、`Map_Angle`、`"*"` は残しました。VisionPro では `ScalingX`、`ScalingY`、`RotationX`、`RotationY` は読み取り専用なので、`Set_Scaling_X` などの設定手続きは AMV の追加です(仕様に明記)。
  - **ABI の版は上げていない。** C の関数名が 2 つ変わり(`determinant`、`is_identity`)、失敗の符号の名前も変わりましたが、上の座標空間の項目と同じ理由で 1 のままです。古い名前で書かれた C のプログラムは、リンクの時点で失敗します(黙って違う動きをすることはない)。

## AMV.Images / AMV.Image_File

テスト: `test_images` 543 チェック、`test_image_file` 508 チェック。

- **画素数の上限。** `Create` と `Allocate` は、`Width * Height` が `Natural'Last` を超えると `Ks_Bad_Parameter_Exception` を送出します。
- **選択中の空間が消された場合。** `Coordinate_Space_Tree` の参照を通して選択中の空間が削除されると、選択は "@" になり、同じ名前の空間を後で足しても "@" のままです(以前は、見えない状態しだいで元の選択が復活していました)。例外は、参照を名前の付け替えやオブジェクトとして保持し、その参照が生きているあいだに削除と再追加をした場合だけです(仕様に明記)。
- **`Image_File` の対応形式は PNM(P2/P3/P5/P6)と BMP。**
  - 16bit 画像は .pgm/.pnm にだけ書けます。.ppm と .bmp に書くと `Ks_Image_File_Exception` になります。
  - `Read_Image_8_Grey` が縮尺し直すのは 16bit の値だけです。maxval が 255 未満の 8bit PNM は、引き伸ばさずにそのまま返します。
- **(2026-11-08 まで)復号器と符号化器は `Get_Pixel` / `Set_Pixel` で 1 画素ずつ処理していた。** いまはカーネルがバイト配列をまとめて処理します(下の `AMV.Image_File` の項目)。
  以前の記録: この作業機で 2000×2000 の画像を実測すると、8bit とカラーで 1 サンプル 2〜7 ns、16bit PNM の読み込みで 20〜30 ns でした。SPARK 化の際に、バイト配列を処理するカーネルへ書き換える候補です。
- 悪意あるヘッダ(巨大な寸法、切り詰められたファイル)への耐性は、2026-11-08 のレビューで改めて確かめました。BMP の「寸法が大きく中身が小さい」テストは、パレットの検査で先に弾かれて画素データの検査まで届いていなかったので、24 ビットの例に直し、メッセージも確かめるようにしました。
- **メモリに載らない大きさのファイル。** 読み込み用のバッファを確保できないと、`Ks_Image_File_Exception`("the file is too large to read into memory")になり、ファイルは必ず閉じます。以前は `Storage_Error` が漏れ、ファイルも開いたままでした。
- **追記。** 空でないファイルの最後のバイトが Netpbm の空白でないときは、PNM 画像の前に LF を 1 つ書きます(改行で終わらない plain PNM に追記すると、読めないファイルになっていたため)。BMP への追記は、ディスク上のファイルが空でなければ拒否します(ファイルオブジェクトのコピーから書いた場合も含む)。
- **2026-11-08、`Copy` の `No_Pixels` を足した。** `Ks_Image_Copy_Mode_Constants` は VisionPro の `CogImageCopyModeConstants` と同じ `Copy_Pixels`、`Share_Pixels`、`No_Pixels` になりました。`Copy (Image, No_Pixels)` は、画素を持たない(`Width = Height = 0` の)画像に、座標空間ツリー・選択中の空間・`Pixel_From_Root_Transform` だけを写したものを返します。元の画像とは何も共有しません。あとで `Allocate` すれば、その状態のまま画素を持てます。選択中の空間が消えている場合は、ほかの写し方と同じく "@" になります。(当時は `AMV.Images` がまだ旧来の本体だったので、実装はそこにありました。いまはカーネルにあります。下の項目を参照。)
- **2026-11-08、`Ks_Image_File_Mode_Constants` を VisionPro の `CogImageFileModeConstants` にそろえた。** 値は `Closed`、`Read`、`Write`、`Update` の順です。
  - **`Append` は `Update` に改名した。** 振る舞いは同じです(既存のファイルの後ろに画像を足し、ファイルがなければ作る)。VisionPro の `Update` は既存のファイルを読み書きできるように開きますが、AMV の `Update` は書き足すだけで、`Item` は `Read` のときしか使えません。また、ファイルがなければ作ります。どちらも仕様に書きました。手続きの `Append` はそのままです(VisionPro でもメソッド)。
  - **`Closed` を足し、`Mode` を `Open_Mode` に改名した。** VisionPro の `OpenMode` と同じく、閉じているファイルでは `Closed` を返します(以前の `Mode` は `Read` を返していた)。`Open` に `Closed` を渡すと、何も変えずに `Ks_Bad_Parameter_Exception` になります(ほかの失敗は `Ks_Image_File_Exception` で、ファイルは閉じた状態になる)。内部の `Opened` フラグはなくし、`Open_Mode` の値だけで状態を持つようにしました。`Is_Open` は `Open_Mode /= Closed` と同じで、AMV 独自のものとして残しました。

- **2026-11-08、`AMV.Images` は SPARK のカーネル `AMV.Kernels.Images` を呼ぶ薄い層になった(ブランチ `feature/kernel-images`)。** C の関数は `ks_image_8_grey_*`、`ks_image_16_grey_*`、`ks_image_24_planar_color_*`、`ks_image_*`(座標空間の状態)です。Ada の公開 API の名前は変わっていません。
  - **画素ハンドル。** 画素は所有権付きのハンドルにあります。ハンドルは、幅・高さと、画素の 2 次元配列 `Pixels (Y, X)`(添字は 0 から)への所有権付きポインタを持つレコードで、C からは不透明なポインタです。2 次元配列にしたのは、メモリ上の並び(行ごと、行優先)は 1 次元の場合と同じまま、`Y * Width + X` という非線形の添字計算を証明から除くためです。カーネルは画素を共有しません(`SPARK_PLAN.md` 3.6 の A 案)。代入による共有は Ada の公開 API が、ハンドルを参照カウント付きの箱(原子的なカウンタは従来どおり)に入れて行います。カラー画像は 8bit のハンドル 3 つで、`Get_Plane` はその箱を共有します。
  - **null のハンドルは画素のない画像。** 幅・高さは 0、複製は null、破棄は何もしない、画素を使う操作は `Image_No_Pixels`(Ada では `Ks_Image_No_Pixels_Exception`)です。範囲外の座標と、行の長さが幅と違う場合は `Index_Out_Of_Range`(Ada では従来どおり `Constraint_Error`)です。
  - **信頼する部分は 3 つ(`docs/PROOF.md`)。** 確保の補助ルーチン `Allocate`(`Storage_Error` を null に変え、入口が `Out_Of_Memory` を返す。Ada では `Storage_Error`)、C のメモリとの行のコピー(`ks_image_*_get_row` / `set_row` の本体)、ストリームの 64 ビットから `Long_Float` への変換(`To_Long_Float`。浮動小数点型への unchecked conversion は SPARK で禁止されているため)です。
  - **1 画素ずつの呼び出しの速さ。** 入口を経由すると、212 バイトの状態値を毎回作るので、1 画素 11 ns 前後(以前は 1〜3 ns)になりました。そこで `Get_Pixel` / `Set_Pixel` は、状態値を作らない Ada 専用の証明済みの変種(`Try_Get_Pixel` など。入口と同じ条件で成功し、同じ効果を持つことを証明済み)を呼び、失敗したときだけ入口を呼んで状態値を得ます(`docs/DESIGN.md` 9.3 に例外として追記)。2000×2000 の画像での実測(ライブラリと同じ -O2、証明を並行して走らせた負荷あり、1 画素あたり):8bit の `Set_Pixel` 1.1 → 1.9 ns、`Get_Pixel` 1.6 → 2.3 ns、カラーの `Set_Pixel` 2.6 → 4.3 ns、`Get_Pixel` 3.2 → 5.3 ns、PGM の書き込みと読み込み 4.5 → 6.3 ns。テスト全体の時間は 0.75 秒前後で変わりません。
  - **同じハンドルを 2 回渡す誤り。** SPARK ではアクセス値どうしを比べられない(`=` も `'Address` も SPARK の外)ので、入口では検出できません。複数のハンドルを取る入口は画素の値しか変えないので、同じハンドルでも不正なアクセスにはならず、引数の順に書いた結果になります(`amv.h` に明記)。`Set_Plane` に同じ画像を渡すのは、以前と同じく何もしないのと同じです。
  - **振る舞いの変化(Ada の公開 API)。** 例外の種類は変わっていません。
    - メッセージ:名前の誤りは操作名で始まります("Get_Transform: no space named ..."、"Resolve_Space_Name: ...")。大きすぎる `Create` / `Allocate` は "Create: the image size W x H is too large" です。上限外の `Pixel_From_Root_Transform` は "Pixel_From_Root_Transform: the transform must be finite and within +/-1.0E150"(以前は `Invert` のメッセージ)です。
    - `Resolve_Space_Name` の結果の添字は 1 から始まります(以前は引数そのもの)。
    - `Get_Row` が失敗したとき、`Row` は 0 で埋まります(以前は変わらなかった。out 引数なので仕様上は不定)。
    - ストリームの `'Read` は、空間の数(ルート以外で 63 まで)と名前の長さ(256 文字まで)を、読む前に検査します(以前は木に加える時点で失敗していた。どちらも `Ks_Image_File_Exception`)。ストリームの形式は変わっていません。
  - **`AMV.Coordinate_Spaces.Kernel_Trees` を足した。** ツリーのカーネルのレコードを読み書きするための子パッケージで、`AMV.Images` が画像のツリーを `ks_image_*` に渡すために使います。また、`AMV.Kernels.Coordinate_Spaces.Add_Read_Space` に、メッセージの先頭の操作名を取る版を足しました(画像のストリームの読み込みが使う)。
  - **テスト。** `test_kernels` に画像カーネルの節を足しました(101 チェック増えて 718)。C のテストは 49 チェック増えて 123 です。既存のテストは変えずに通ります。

- **2026-11-08、`AMV.Image_File` は SPARK のカーネル `AMV.Kernels.Image_File` を呼ぶ薄い層になった(ブランチ `feature/kernel-image-file`)。** Ada の公開 API の名前と振る舞いは変わっていません(既存の `test_image_file` はそのまま通る)。C の関数は `ks_image_file_*` です(`docs/API_MAPPING.md`)。
  - **分担。** カーネルはメモリ上のバイト列だけを扱います。PNM と BMP の復号(ファイル全体を一度に。画素はハンドルの行列に直接書く)、書き込み形式の選択(拡張子から)、符号化の選択と大きさ、追記の規則(BMP は 1 枚だけ、plain PNM の後ろには LF)、符号化、`CogImageFile` の状態の規則(`Open` は `Closed` を拒む、`Item` は Read、`Append` は Write か Update)と、ツールの添字の規則です。Ada の API は、ファイルを丸ごとバイト配列に読み込んでカーネルに渡し、カーネルが作ったバイト列をファイルに書くだけです。`tools/shell_check_legacy.txt` から外しました。`--  SHELL:` はストリームの属性の 2 つのループ(画像ごと)だけです。
  - **復号は 2 回読む。** PNM は、1 回目で全画像を検査して数え、ちょうどその数のスロットを確保してから 2 回目で画素を復号します(所有権付きの配列を伸ばす証明を避けるため)。BMP は 1 枚なので、ヘッダの検査のあとで直接復号します。ヘッダが告げる画素データの大きさは、確保の前に実際のバイト数と比べます。証明では、どの画像もバイトあたり 8 画素(1 ビットの BMP)を超えないことまで示しています。
  - **メッセージ。** カーネルの状態値は 200 文字なので、ファイル名を含みません。`AMV.Checks` に `Check (Status, Context)` を足し、Ada の API がファイル名と ": " を前に付けます。メッセージの本文は以前と同じです(拡張子が 100 文字を超える場合だけ、メッセージの拡張子を 100 文字で切ります)。
  - **メモリ。** 書き込みは、符号化した画像全体をメモリに作ってから書きます(仕様に、そのとき足りなければ `Storage_Error` と追記)。Update で開くときは、画像を数えて形式を確かめるだけで、画素は確保しません(以前は全画像を復号していた)。
  - **ファイルオブジェクトの中身。** Read で開いたファイルの復号結果は、カーネルのハンドルを参照カウント付きの箱に入れて持ちます(復号結果は変わらないので、コピーどうしで共有しても見分けられない)。ヒープを持つ型になったので、`docs/DESIGN.md` 7 節に従って自前の `'Read` / `'Write` を持ちます(画像の数・種類、画像ごとの型・maxval・画像そのもの。読むときはカーネルが数と符号を検査し、maxval を超える画素を拒む)。以前の既定の属性とは形式が違います。
  - **`AMV.Images.Kernel_Images` を足した。** カーネルの画像ハンドルを `Ks_Image_*` に引き取らせる `Adopt` と、画像のハンドルを読み取り用に渡す `Kernel_Handle` / `Kernel_Plane` です(`AMV.Coordinate_Spaces.Kernel_Trees` と同じ位置づけ)。
  - **振る舞いの細かな変化。** BMP の追記で、ディスク上のファイルを調べる(存在・大きさ・最後のバイト)のが「このオブジェクトはもう 1 枚書いた」の検査より先になりました。違いが出るのは、そのファイルを調べる I/O が失敗する場合だけです。読み込みの「想定外の Constraint_Error を `malformed image file (...)` に変える」安全網はなくなりました(証明で起こらないことを示した)。
  - **テスト。** `test_kernels` に画像ファイルのカーネルの節(41 チェック増えて 759)、`test_image_file` にファイルオブジェクトのストリームの節(5 チェック増えて 508)、C のテストに 41 チェック(164)を足しました。

## AMV.Shapes

テスト: `test_shapes` 1,283 チェック。

- **境界の許容誤差。** `Contains_Point` の境界は 1.0E-9 × L + 64 × `Real'Model_Epsilon` × (P + L) の幅を持たせて判定します。L は図形の大きさ、P は位置の大きさです(表は仕様にあります)。
  - 以前は 1.0E-9 × (1 + S) で、座標が大きいほど幅が広がり、1e9 付近の半径 12 の円が 1 単位も太っていました。いまは座標の丸め誤差の数十倍(1e9 付近で約 1.4e-5)にとどまります。
  - 許容幅でどこまで外側の点が含まれうるかを、新しいプリミティブ `Boundary_Slack` が返します(AMV 独自。`AMV.Regions` が使う)。抽象なので、AMV の外で `Ks_Region` を拡張する場合は実装が必要です。
- **円・円弧・円環の `Map` の半径の倍率。** 相似変換の倍率を `sqrt (abs Matrix_Determinant)` ではなく、1 列目の長さ(`Hypot (A, C)`)で求めます。倍率 1e155 で `Constraint_Error`、1e-170 で半径 0 になっていた問題がなくなりました。
- **`Area` の意味。** 自己交差する多角形の `Area` は、`Contains_Point` が含む集合(偶奇規則)の面積ではなく、符号付きの正味の面積です。`Ks_Region.Area` と `Ks_Polygon.Area` の仕様の記述を、矛盾しないように直しました。
- **「相似」の意味が 2 つのパッケージで違う。**
  - `AMV.Shapes` の円・円弧・円環の `Map` は、反射を含む相似変換で形を保ちます。
  - `AMV.Transforms.Is_Similarity` は反射を除きます。
  - そのため Shapes の内部では、鏡映を合成した変換でも判定しています。`Is_Similarity` に反射を許すオプションを付ければ、重複を消せます。
- **`Ks_Line.Map` と `Ks_Point_Marker.Map` の例外。** 方向が 0 に写像されると、点そのものは写像できても `Ks_Transform_Singular_Exception` を送出します(仕様どおり)。
- **`Ks_Polygon` の添字範囲。** `Set_Vertex` と `Remove_Vertex` は、範囲外の添字で `Constraint_Error` を送出します。
- **2026-11-08、楕円の手続きの名前を VisionPro にそろえた。** `Set_Center_Radius_X_Y_Rotation` は `Set_Center_XY_Radius_XY_Rotation`(VisionPro の `SetCenterXYRadiusXYRotation`)に改名し、対になる `Get_Center_XY_Radius_XY_Rotation` を足しました。"XY" は 1 語として扱います(`docs/DESIGN.md` の 3 節に追記)。`Ks_Line` の `Set_X_Y_Rotation` と `Set_From_Start_X_Y_End_X_Y` も、カーネル化の際に `Set_XY_Rotation` と `Set_From_Start_XY_End_XY` に改名しました(下記)。
- **2026-11-08、`Enclosing_Rectangle` を足した。** `Enclosing_Rectangle (Region) return Ks_Rectangle` は、`Get_Bounding_Box` の箱を矩形にしたものです(X = Min_X、Y = Min_Y、幅と高さは差)。選択中の空間の名前も写します。`Ks_Rectangle` に使うと、X と Y は元と同じで、幅と高さは (X + Width) - X の丸めの分だけ違うことがあります。`Ks_Region'Class` を取る関数で、`Region.Enclosing_Rectangle` とも書けます。`Ks_Rectangle` は `Ks_Region` から派生しているので、`Ks_Region` のプリミティブとしては宣言できないためです。VisionPro ではすべての図形にありますが、AMV で外接矩形を持つのは領域だけなので、線・線分・点・円弧にはまだありません。VisionPro の copyFlags 引数は、AMV の図形に描画用の性質がないので、対応するものがありません。`Get_Bounding_Box` は AMV のプリミティブとして残しました。

- **2026-11-08、`AMV.Shapes` は SPARK のカーネル `AMV.Kernels.Shapes` を呼ぶ薄い層になった**(ブランチ `feature/kernel-shapes`)。
  - 固定長の図形(矩形・平行四辺形・円・楕円・円環の扇形・直線・線分・点・円弧)は、カーネルの C 互換レコード(`include/amv.h` の `ks_rectangle` など)を Ada の型の中にそのまま持ちます。選択中の空間の名前だけは Ada の側に残しました。
  - 多角形の頂点は所有権付きのハンドル(`ks_polygon *`)です。null は頂点のない多角形で、`ks_polygon_add_vertex` が必要なら作ります。頂点の配列は満杯になると倍に広げます。`Ks_Polygon` は制御型の成分を持ち、代入で複製し(カーネルの duplicate)、終了処理で破棄します。`"="` は頂点を比べます(以前の `Vectors` と同じ意味)。ストリーム属性は値を書き読みし、頂点の数(2**20 まで)と座標をカーネルが検査します。
  - 上限: 座標と角度は 1.0E150、長さ(幅・高さ・辺・半径・線分の長さ・直線の原点からの距離)は 4.0E150、`Radial_Scale` は 1.0E150 で、`Radius * Radial_Scale` も 4.0E150 まで。範囲外や NaN・±Inf の引数、範囲外になる結果(中心・角・外接矩形・端点・写像した図形)は `Ks_Bad_Parameter_Exception` です。多角形は 2**20 頂点まで(面積の和があふれない)。
  - 振る舞いの細かな変化(どれも境界の許容幅より十分小さい丸めの差で、既存のテストはそのまま通る): 多角形の偶奇判定の交点は (Y - A.Y) / (B.Y - A.Y) の比を先に作ってから掛ける形にした(以前は積を先に作って割っていたので、辺がほぼ水平だとあふれ得た)。線分までの距離も、射影の比を割る前に [0, 1] に収まる場合を分けた。円環の扇形の角度の 2 Pi での剰余は、範囲内ならそのまま、範囲外は IEEE の剰余で求める(1.0E150 のような角度でも [0, 2 Pi] に入る)。楕円の写像は、内部の写像ベクトルが 1.0E150 を超えても途中で失敗しなくなった(結果が上限を超える場合だけ失敗)。
  - 名前を VisionPro にそろえた: `Set_X_Y_Width_Height` -> `Set_XY_Width_Height`、`Set_X_Y_Rotation` -> `Set_XY_Rotation`、`Set_From_Start_X_Y_End_X_Y` -> `Set_From_Start_XY_End_XY`。足したもの: `Get_XY_Width_Height`、`Get_Center_Width_Height`、`Perimeter`(矩形と多角形)、平行四辺形・円・円環の扇形・線分・円弧の `Get_...` の対、`Ks_Polygon.Get_Vertex`、`Ks_Line` の `Get_XY_Rotation`、`Set_Distance_Rotation` / `Get_Distance_Rotation`(距離の符号は AMV の定義。VisionPro の符号は未確認)、`Set_From_Line_Segment`。別名は残していません。
  - テスト: `test_kernels` に図形のカーネルの節(Ada の API を通した NaN・±Inf、上限、矩形の被覆の性質、多角形のハンドル、2**20 頂点の上限、`Ks_Polygon` の値の意味とストリーム)、C のテストに図形の節を足しました。`test_shapes` と `test_regions` は改名だけを直しました。

## AMV.Regions

テスト: `test_regions` 1,152 チェック。

- **`Full` フラグを追加した(private)。** ラスタライズの結果が外接矩形の画素をすべて含むときは、フラグ配列を持たずに表現します。画像全体や軸に平行な矩形などが該当し、位置が画素の境界にそろっている必要はありません。
- **候補範囲の余白。** ラスタライズでは、外接矩形の 4 隅を画素空間へ写像し、余白を取って候補にします。余白は、丸めのための 0.5 画素に、`Boundary_Slack` を画素空間へ写像した幅を足したものです。そのため、結果はどの入力でも定義(画素中心が `Contains_Point` を満たす画素の集合)と一致します。以前は余白が 0.5 画素に固定で、座標が大きい領域では定義と食い違っていました。
- **2026-11-08、`AMV.Regions` は SPARK のカーネル `AMV.Kernels.Regions` を呼ぶ薄い層になった(ブランチ `feature/kernel-regions`)。** Ada の公開 API の名前と振る舞いは変わっていません(既存の `test_regions` はそのまま通る)。C の関数は `ks_pixel_region_*` です(`docs/API_MAPPING.md`)。
  - **表現。** `Pixel_Region` はカーネルの所有権付きハンドル(`ks_pixel_region *`。null は空の領域)を 1 つ持つ制御型です。代入でカーネルの duplicate、終了処理で destroy を呼びます(複製の確保に失敗すると `Storage_Error`、代入先は空)。ハンドルは外接矩形(X_Min、Y_Min、Width、Height)、画素数と、画素の座標そのものを添字にした 2 次元のフラグ行列 `Flags (Y, X)` を持ちます。外接矩形の画素をすべて含む領域(上の `Full`)は、フラグを持ちません(`Flags = null`)。2 次元にしたのは、`Contains`・走査・縮小のコピー・複製から添字の計算(非線形)をなくすためです。
  - **ラスタライズ。** 領域の型ごとの入口(`ks_pixel_region_rasterize_rectangle` など)が、画像の大きさ、`Image.Get_Transform ("#", ...)` の変換、図形の構造体(多角形はハンドル)を受け取ります。Ada の `Rasterize` は、画像と型の検査(`Check_Rasterize`。画素がないことを空間の名前より先に報告するため)、`Get_Transform`、型に合う入口の呼び出しだけをします。カーネルは候補の範囲(仕様どおりの 4 隅と余白)の画素を図形カーネルの `Contains_Point`(状態値を作らない Ada 専用の関数。入口と同じ結果になることを証明済み)で調べ、候補の大きさのフラグに書き、最小の外接矩形に縮めた行列だけを残します(候補の行列は返る前に解放。縮める必要がなければそのまま使う)。
  - **証明(Gold)。** 返すハンドルはどれも、画素数が `Contains` の受け付ける画素の数に等しく(再帰的なゴーストの数え上げ)、外接矩形が最小です。`Contains` は矩形の中では保存されたフラグそのもので、候補の各画素では、結果の `Contains` が定義(逆変換で写した画素中心が 1.0E150 以内で、図形の `Contains_Point` が受け付ける)と一致します。候補の範囲が定義を満たす画素をすべて含むことは浮動小数点の議論で、証明していません(図形カーネルが証明しているのは矩形の被覆の性質だけ)。
  - **ストリーム。** 形式は変わっていません。読み込みでは、カーネルがヘッダの各値を以前と同じ順に検査し、画素の要素は読めた分だけ伸びるバッファに入れ(65,536 から倍々、宣言された数まで)、最後にフラグ行列へ移して数と最小の矩形を検査します。ストリームの途中終了は、画像と同じく `'Read` の `End_Error` で検出します(以前は部分的な読み込みを繰り返す自前のループだった)。
  - **振る舞いの細かな変化。**
    - AMV.Shapes の 6 つの領域型(とその派生型。派生型はその型として扱う)以外の `Ks_Region` の派生型は、`Rasterize` で `Ks_Bad_Parameter_Exception` になります(空間の名前より先に検査)。以前はその型の `Contains_Point` を呼んでいました。
    - 1.0E150 を超える点に写る画素中心は含めません(以前は `Map_Point` が `Ks_Bad_Parameter_Exception` を出し得た)。外接矩形の 4 隅を画素空間へ写すときも、上限の検査をしなくなりました(以前は 1.0E150 を超える隅で例外)。
    - メッセージ: 画素のない画像は "Whole_Image: the image has no pixels" / "Rasterize: the image has no pixels"(以前は "AMV.Regions: Image is not allocated (it has no pixels)")、ストリームの誤りは "Pixel_Region'Read: ..."(以前は先頭に "AMV.Regions.")。
  - **速さ。** 2000×2000 の画像で(ライブラリと同じ -O2、ほかの証明を並行して走らせた負荷あり、5 回の最良値): 円 78 → 41 ms、楕円 117 → 62 ms、軸に平行な矩形 76 → 42 ms、平行四辺形 262 → 166 ms、5 頂点の多角形 286 → 279 ms、円環の扇形 113 → 76 ms。`Contains` を全画素で呼ぶループは 9.1 → 6.6 ms。1 画素ごとに状態値を作らなくなった分です。平行四辺形と楕円は、`Contains_Point` が呼び出しごとに三角関数を計算しているので、図形ごとに前計算すればまだ速くなります。
  - **テスト。** `test_kernels` に領域のカーネルの節(26 チェック増えて 851。不正なハンドル、1 画素の矩形がフラグを持たないこと、巨大なヘッダでもバッファが読めた分しか伸びないこと、要素の書き出し、AMV.Shapes の外の派生型)、C のテストに 25 チェック(273)を足しました。

## AMV.Image_Math / AMV_Test_Images(テスト用の合成画像)

テスト: `test_image_math` 361 チェック、`test_test_images` 229 チェック。

- **`Max_Sigma`(1.0E6)を追加した。** これを超える `Sigma` は `Ks_Bad_Parameter_Exception` になります。
- **空画像の扱い。** フィルタは同じ大きさの空画像を返します。空の `Real_Image` をサンプリングすると `Ks_Bad_Parameter_Exception` になります。
- **画像の幅に比例する配列をスタックに置かない。** `From_Grey_8`、`To_Grey_8`、`Resample` が画像 1 行分の配列をスタックに置いていたため、幅 300 万画素の画像で、2 MB のスタックがあふれていました。いまはどの操作も、画像の大きさに比例するものをスタックに置きません(256 KB のスタックのタスクで確かめるテストあり)。
- **`Box_Smooth` の移動和は補償付き(Neumaier)。** 以前は、とても大きな値が窓を通り過ぎると、その後の平均がずっと狂っていました(1e17 の画素の後で、1 の画素の平均が 1/3 になる)。
- **`Real_Image` の代入で確保に失敗した場合。** 代入先は空(0 × 0)になり、代入元と何も共有しません。以前は代入元のバッファを指したまま残り、二重解放になっていました。
- **合成画像の精度。** `AMV_Test_Images` は 1 画素を S×S 個のサンプル点(既定 S = 8)で塗ります。
  - **傾きが既約分数 p/q のエッジは、全体がまとめて量子化され、最大 1/(2S·√(p²+q²)) 画素ずれる。** 軸に平行なエッジ(p = 0)では 1/(2S)(既定 1/16)です。1/S の倍数の位置にある軸平行のエッジは正確に描けます。
  - **小さな円(半径 5〜10 画素未満)では、重心の誤差が約 0.02〜0.025 画素、面積の誤差が最大約 0.7% になる。** それより大きい曲線では約 0.01 画素です。
  - 8 ビットへの丸めで、部分被覆の画素ごとに最大 0.5/255 の誤差が加わります。
  - サブピクセル精度を検証するテストでは、図形をわずかに回す(傾きが小さな整数比にならない角度)、エッジを 1/8 の倍数に置く、`Samples` を増やす、のいずれかを行ってください。
- **重心のバイアス。** 片側だけに部分被覆の画素がある図形では、画素中心で計算した重心に小さな偏りが出ます(21 画素幅で約 0.006 画素)。
- **カーネル化(`AMV.Kernels.Image_Math`、ブランチ `feature/kernel-image-math-geometry`)。** 処理はすべてカーネル(C API は `ks_real_image_*`)に移り、`AMV.Image_Math` は薄い層になりました。
  - `Real_Image` は、カーネルの所有権付きハンドル(`Long_Float` の行列、添字は (Y, X))を 1 つ持つ制御型です。代入は `Adjust` でカーネルの `Duplicate` を呼んで深いコピーを作ります。コピーに失敗したときに代入先が空(0 × 0)になる動作はそのままです。null のハンドルが既定の空画像(0 × 0)で、幅か高さが 0 の画像は寸法を持つハンドルです。
  - **画素値の上限は ±1.0E100。** `Box_Smooth` の窓の和(最大 (2·2³¹+1)² 個)、`Statistics` の 2 乗和(2³¹ 個 × (2·1.0E100)²、約 8.6E209)が `Long_Float` に収まるように決めました。`Create`・`Set`・`Fill` はこれを超える値や NaN・無限大を `Ks_Bad_Parameter_Exception` で拒みます。フィルタなどが計算した値は上限で切り詰めます。平均やソーベル微分は元の値の範囲に収まるので、切り詰めが働くのは上限ちょうどの値が丸めで上限を越えたときだけです。
  - **座標と `Sigma`。** 有限でなければ `Ks_Bad_Parameter_Exception` です(以前は NaN を境界に寄せていました)。座標は有限ならいくらでもよく、画像の範囲に寄せてから計算します。
  - **`Statistics` の平均は [Minimum, Maximum] に収める。** 0.1 が 3 つの平均が 0.1 をわずかに超える、といった丸めを直します(標準偏差の計算は変わりません)。
  - **ストリームの読み込み。** 値はチャンク(1024 個)ごとに読み、カーネルの 1 次元のバッファに溜めます(最初は最大 65536 個、満杯になったら倍)。全部そろってから画像を作るので、終わりに一度コピーします。上限を超える値は `Ks_Image_File_Exception` です。
  - `Get` / `Set` は、`AMV.Images` と同じく、状態値を作らない `Try_` 版を呼びます。

## AMV.Geometry / AMV.Tools

テスト: `test_geometry` 548 チェック(カーネル化で、1E160 と 1E300 の倍率の繰り返しを 1E140 にまとめ、上限を超える座標の拒否を足した)、`test_tools` 141 チェック。

- **`Fit_Circle` が退化と判定する条件。**
  - 線に直交する方向の散らばりが、線に沿う方向の散らばりの 1e-8 倍以下なら、共線とみなします。
  - 中心が散らばりの 1e9 倍を超えて離れていくなら、あきらめます。
- **ロバスト版のフィットは一点除外法。** 外す点は、それを除いたときに残りの点のフィットの RMS が最も下がる点です(以前は「全点のフィットで残差が最大の点」で、大きな外れ値 1 つに引っ張られて正しい点を外していました)。直線では和の更新で O(N)、円では候補ごとに再フィットします。同点(丸め誤差の範囲で同じ)のときは添字の小さい点を外します。
  - 限界: 同じ位置に固まった外れ値が複数あると、互いを隠し合い、正しい点を外すことがあります(貪欲法の性質。仕様に明記)。
- **`Fit_Circle` はニュートン法を併用する。** ヘッセ行列が正定値でコストが下がる場合はニュートン法の一歩、そうでなければ減衰付きガウス・ニュートン法の一歩を取ります。残差が大きい短い円弧で、以前は 100 回の上限で最小点から遠いところで止まっていました。
- **`Fit_Line` の等方性の判定は丸め誤差を考慮する。** 正多角形の頂点のように散らばりが等方的なときは、`Rotation` = 0 を返します(以前は丸めで決まる任意の角度でした)。
- **大きさによらないフィット。** 重心からのずれを 2 のべき乗で縮めてから 2 乗以上の量を作るので、座標が 1e-170 でも 1e160 でも同じように動きます(以前は 0 になったり `Constraint_Error` になったりしていました)。`Intersect` だけは長さどうしを掛けるので、1e-150〜1e150 程度の範囲に限られます。
- **カーネル化(`AMV.Kernels.Geometry`、ブランチ `feature/kernel-image-math-geometry`)。** 処理はすべてカーネル(C API は `ks_geometry_*`)に移り、`AMV.Geometry` は薄い層になりました。
  - `Point_2D`・`Line_2D`・`Circle_2D` はカーネルの C 構造体の部分型、`Point_Array`・`Boolean_Array` はカーネルの配列型からの派生型です(点の配列をコピーせずにカーネルへ渡すため)。成分と既定値は以前と同じで、`=` は `AMV.Geometry` から見えます。
  - **座標と半径の上限は ±1.0E150、回転は有限。** 超える値や NaN・無限大は `Ks_Bad_Parameter_Exception` です。返す座標・長さ・半径も上限内に収め、超える場合(引数が約 3.5E149 を超えるとき、またはほぼ平行な直線が遠くで交わるとき)は `Ks_Bad_Parameter_Exception`("Distance: the result would exceed +/-1.0E150")です。以前は 1E160 や 1E300 の座標も受け付けていました(テストの大きい側の倍率は 1E140 に変更)。
  - **2 のべき乗による縮小は静的な 2 のべき乗で行う。** `'Exponent` と `'Scaling` の代わりに、比較で指数を求め、正確に作った 2 のべき乗を 1 回掛けます(丸めは `'Scaling` と同じ)。2**(-500) 未満では 2 回の正確な掛け算に分けます。
  - 円のフィットで、試行中心に極端に近い点(Res / Dist が 2**60 を超える)は曲率の項に寄与しません(以前は割り算が溢れる可能性がありました)。行列式による割り算は、商が逃げ出しの判定値の 2 倍以下のときだけ作り、それを超える場合は以前と同じく「中心が逃げた」と扱います。
  - `Angle_Between` は、差が溢れるほど大きい回転でも、各回転を先に正規化して (-Pi, Pi] を返します(`AMV.Misc.Angle_Difference` と同じ)。
  - ロバスト版の失敗時、`Used` はすべて False になります。
- **`Run` の挙動。**
  - 例外のメッセージが空なら、例外名をメッセージにします。
  - 最初の `Reset_Results` が例外を出したら、`Execute` は呼ばずに失敗として記録します。
  - 後始末の `Reset_Results` が出した例外は無視し、元の失敗を残します。
  - 失敗した場合も処理時間を記録します。
- **`Message` と `Set_Result`。** `Execute` が `Set_Result` で `Accept_Result` に添えた注記は、`Message` に残ります。`Run` が結果を消すのは `Execute` が例外を出したときだけなので、`Set_Result` で `Error` を報告するツールは、自分で結果を消す必要があります(どちらも仕様に明記。コードの変更はなし)。
- **予約語との衝突による改名は `CogToolResultConstants.Accept` → `Accept_Result` だけ。** `docs/API_MAPPING.md` に記載済みです。
