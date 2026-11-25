# AMV Flow: ツールをノードでつなぐノーコード環境（設計案）

状態: 草案（2026-11-25、ブランチ `design/node-editor`）。GUI は JavaFX で
作ると決めた（6 章）。決めていない点は最後の「未決事項」にまとめた。

## 1. 目的と範囲

AMV のツールを画面上でノードとして並べ、端子を線でつないで検査を組み、
コードを書かずに実行・保存できるようにする。エディタは PC ネイティブの
アプリとして Windows・Linux・macOS で動かす。保存したフローは GUI なしでも
（コマンドラインや Ada のコードから）実行できる。

参考にしたのは Cognex の次の製品の「仕組み」である。

| Cognex | 仕組みの要点 | この設計での扱い |
|---|---|---|
| VisionPro QuickBuild / ToolBlock | 型付きの入出力端子をドラッグでつなぐ。Job = 画像取得 + ツールの集まり | フローとリンク（3 章）。画像入力ノード |
| VisionPro の Fixture と座標系ツリー | 位置決めの結果を画像に座標系として足し、後ろのツールが追従する | AMV に既にある（3.2） |
| Cognex Designer | フローチャート、並列実行、タグ、レシピ、HMI | 実行順序（4.2）。レシピと作業者画面は後の段階 |
| In-Sight EasyBuilder | 手順に沿って組むウィザード（接続→画像→位置決め→検査→通信） | 第 4 段階のウィザード |
| In-Sight Spreadsheet | セルの式でツールをつなぐ | 第 4 段階の式ノード |
| 保存画像での再生（Filmstrip） | 保存した画像で調整してから本番に回す | 画像フォルダ再生（4.5） |

まねるのは考え方だけで、他製品の名称・画面・文書・コードは使わない
（`docs/DESIGN.md` 1 章の方針をこの層にも当てはめる）。用語は一般的な
「ノード」「端子」「リンク」を使う。

最初は扱わないもの: 3D、ディープラーニング、PLC との通信、複数カメラの
同期、ループと条件分岐、作業者向け画面の作成機能。

## 2. 全体の構成

```
  Flow Editor (JavaFX, Java 25)          amv_flow (CLI, Ada)
        │  Foreign Function & Memory API        │
        ▼                                       ▼
  amv_flow 共有ライブラリ (.dll / .so / .dylib) ─ C API amvf_*（7 章）
        │
        ▼
  AMV.Flow (エンジン, Ada) ──▶ AMV のツール (src/)
        │                 ──▶ AMV.GigE_Vision (optional/aravis)
        ▼
  フローファイル (.amvflow, JSON) + 学習データ
```

* エンジン（`AMV.Flow`）は Ada で書き、C API を出す共有ライブラリにする。
  エディタは JavaFX で書き、同じプロセスの中から Java の Foreign Function &
  Memory API（以下 FFM）でその C API を呼ぶ。CLI は同じエンジンを直接
  使う。
* 置き場所は `optional/flow/`（エンジン、C API、CLI、テスト）と
  `optional/flow_editor/`（Java のプロジェクト）。`optional/aravis` と
  同じく、コアのライブラリとは別のプロジェクトにする。
* コアの `src/` は原則として変えない。`src/` は SPARK カーネルと薄い Ada
  API という規約（`docs/DESIGN.md` 9.3）で、グラフの処理や JSON の解析の
  ような計算を Ada API の層に置けないためである。ツール側に足りないもの
  （たとえば図形の一覧を返す関数）が出たら、その都度別の変更として
  `src/` に入れる。
* エンジンが依存するのは Ada のランタイムと AMV だけにする。JSON の読み書き
  も自前で持つ（読む JSON は信頼しない入力として扱う。5 章）。
* エンジンは最初は SPARK の証明の対象にしない。リンクの検査や実行順序の
  計算は、あとでカーネルにして証明できる候補である。

## 3. データモデル

* **フロー**: ノードとリンクの集まりに、フロー自身の入力端子と出力端子を
  加えたもの（ToolBlock に当たる）。
* **ノード**: AMV のツール 1 個（中に `AMV.Tools.Ks_Tool'Class` を 1 つ
  持つ）か、特別なノード（画像入力、判定、ログ出力、サブフロー）。
* **端子**: 名前、向き（入力か出力か）、値の型、必須かどうか。
* **リンク**: 出力端子から入力端子への線。1 つの出力から何本でも出せる
  が、1 つの入力に入るのは 1 本まで。
* **パラメータ**: 線でつながない設定値（`Run_Params` の成分や検査領域）。
  プロパティ欄に出し、ファイルに保存する。入力端子に線がつながっていない
  ときは、その端子にもパラメータとして値を持たせられる（固定値）。

### 3.1 値の型

`AMV.Tool_Block` の端子の型（`Ks_Tool_Block_Terminal_Type`）を土台に
する。

| 型 | 中身 | 例 |
|---|---|---|
| Real, Integer, Boolean, String | スカラー | 面積、個数、合否 |
| Image_8_Grey, Image_16_Grey | 画像（画素は共有、座標系ツリーつき） | カメラの画像、Fixture 後の画像 |
| Transform | `Ks_Transform_2D_Linear` | Shape Match が見つけた姿勢 |
| Shape | `Ks_Shape'Class`。端子が受け付ける種類を決める | 検査領域、見つけた円や線 |
| （将来）List | 結果の並び | ブロブごとに処理するとき |

Shape の種類は AMV の図形の型そのもの: 領域（Rectangle、
Rectangle_Affine、Circle、Ellipse、Polygon、Circular_Annulus_Section）と、
Line_Segment、Line、Point_Marker、Circular_Arc。たとえば Caliper の領域は
Rectangle_Affine だけ、Blob の領域はどの領域でもよい。

リンクは型が同じ端子どうしにだけ引ける（Shape は受け側が許す種類の
もの）。暗黙の変換は Integer から Real だけにする。

### 3.2 座標系（Fixture）

AMV の画像は座標系ツリーを持ち、図形はどの空間で定義されたかを持つ
（`docs/DESIGN.md` 5 章）。

* Fixture ノード（`AMV.Calib_Fix.Ks_Fixture_Tool`）は、入力画像に
  `@\<名前>` の空間を足した画像を出力する。
* 後ろのノードの領域を Fixture の空間で定義しておけば、Fixture 後の画像を
  つなぐだけで、部品の位置と回転に検査位置が追従する。
* エンジンは画像を端子から端子へそのまま渡すだけでよい。ここが Cognex の
  方式と同じで、AMV では既に動いている（`examples/align_and_measure.adb`）。
* エディタで領域を描くときは、選んだノードの入力画像の選択空間で描く。

### 3.3 ノード種別の記述

Ada には実行時に型の中身を調べる仕組み（リフレクション）がないので、
ツールの種類ごとに小さなアダプタを書き、端子とパラメータの一覧を返させる。
エディタのプロパティ欄、ファイルの読み書き、リンクの型検査はこの一覧から
作る。エディタには C API を通して JSON で渡す（7.3）。

```ada
--  名前と形は仮。
package AMV.Flow.Nodes is

   type Port_Descriptor is record
      Name        : Unbounded_String;
      Direction   : Port_Direction;     --  Input / Output
      Value_Type  : Ks_Flow_Value_Type;
      Shape_Kinds : Shape_Kind_Set;     --  Shape のとき受け付ける種類
      Required    : Boolean;
   end record;

   type Param_Descriptor is record
      Name, Unit, Help : Unbounded_String;
      Kind             : Param_Kind;    --  Real / Integer / Boolean / Choice / Region ...
      Default, Low, High : Real;        --  数値のとき
      Choices          : String_List;   --  Choice のとき
   end record;

   type Ks_Flow_Node is abstract tagged limited private;

   function Kind_Id (Node : Ks_Flow_Node) return String is abstract;
   --  "Blob"、"FindCircle" など。ファイルに保存する変わらない名前。

   function Ports  (Node : Ks_Flow_Node) return Port_Descriptor_Array is abstract;
   function Params (Node : Ks_Flow_Node) return Param_Descriptor_Array is abstract;

   procedure Set_Param (Node : in out Ks_Flow_Node; Name : String;
                        Value : Ks_Flow_Value) is abstract;  --  範囲を検査する
   function  Get_Param (Node : Ks_Flow_Node; Name : String)
                        return Ks_Flow_Value is abstract;

   procedure Set_Input (Node : in out Ks_Flow_Node; Port : String;
                        Value : Ks_Flow_Value) is abstract;
   procedure Run (Node : in out Ks_Flow_Node) is abstract;
   --  中のツールの Run を呼ぶ。例外は外に出さない。
   function  Get_Output (Node : Ks_Flow_Node; Port : String)
                         return Ks_Flow_Value is abstract;

   function  Status (Node : Ks_Flow_Node) return AMV.Tools.Ks_Run_Status;
   procedure Graphics (Node : Ks_Flow_Node; Into : in out Shape_List);
   --  表示用の図形: 検査領域、見つけたエッジ・円・ブロブの輪郭など。

end AMV.Flow.Nodes;
```

* 種別の登録表（`Kind_Id` から生成関数への表）を 1 つ持ち、ツール
  パレットとファイルの読み込みはそこから作る。
* アダプタは手書きで始める。数が増えたら、ツールの spec から生成する
  スクリプトを考える。

最初に用意するノード（第 1〜2 段階）:

| 分類 | ノード | 中身 |
|---|---|---|
| 入力 | Image File | 画像 1 枚、またはフォルダの画像を順に |
| 入力 | Camera | GigE カメラ（`AMV.GigE_Vision`、第 3 段階） |
| 位置決め | Shape Match, NCC Search | 姿勢（Transform）を出す |
| 位置決め | Fixture | 画像に部品の座標系を足す |
| 計測 | Caliper, Find Line, Find Circle, Blob | 見つけた図形と数値を出す |
| 計測 | Distance, Angle | `AMV.Dimensioning` の各ツール |
| 前処理 | Histogram, IP One Image | 平均・分散、フィルタ |
| 前処理 | Polar Unwrap, Morphology | 円環を帯状に展開、濃淡モルフォロジー（トップハットで細い傷を浮かせる） |
| 判定 | Range Check, And / Or | 下限 ≤ 値 ≤ 上限 で合否 |
| 出力 | CSV Log, Result Image | 1 回の実行ごとに 1 行、図形を描いた画像 |
| 応用 | Circularity | `examples/live_circularity` の真円度測定を移したもの（中心と半径も出す） |

コード読み取り、校正、作図・フィット系などほかの AMV ツールは順に足す。

## 4. 実行エンジン

### 4.1 検証

編集中と実行の前に次を調べ、エラーを該当するノードに出す。

* 型の合わないリンク、1 つの入力への 2 本目のリンク
* 閉路（フローは有向非巡回グラフに限る）
* つながっていない必須入力、学習していないパターン

### 4.2 実行順序

* リンクの依存関係に従ったトポロジカル順に実行する。依存のないノードの
  順はノード ID の昇順（作った順）で決め、毎回同じにする。
* 画面上の位置には依存させない。Cognex Designer は左から右へ実行するが、
  ノードを動かしただけで結果が変わるのを避けたい。
* 1 回の実行は画像 1 枚（トリガ 1 回）に当たる。

### 4.3 失敗の伝わり方

* 各ノードは `Ks_Tool.Run` と同じく例外を外に出さず、`Run_Status`
  （Accept / Warning / Reject / Error）を持つ。
* 上流が Error のとき、その出力を使うノードは実行せず「未実行（上流の
  失敗）」とする。関係のない枝は実行を続ける。設定で「最初の Error で
  止める」も選べる（`AMV.Tool_Group` の Abort_Run_On_Tool_Failure と同じ）。
* フロー全体の結果は、実行したノードの中で最も悪い結果とする
  （`AMV.Tool_Group` と同じ規則: Error > Reject > Warning > Accept）。
  判定ノードの不合格は Reject になる。

### 4.4 サブフローと Ada からの利用

* フローを 1 つのノードとして別のフローに入れられる（ToolBlock に当たる）。
  サブフローの入出力端子がそのノードの端子になる。
* 保存したフローを Ada のコードからふつうのツールとして実行できるように
  する: `Ks_Flow_Tool is new AMV.Tools.Ks_Tool`（ファイルを読み込み、入力
  端子に値を入れて `Run`、出力端子から結果を読む）。

### 4.5 実行のしかた

* 1 回実行、連続実行（カメラ）、画像フォルダの再生（保存画像で調整する）。
* ノードごとの処理時間・結果・図形を、実行のたびにまとめて残し（以下
  スナップショット）、エディタが表示に使う。
* フロー 1 つは 1 本のスレッドから使う（7.5）。画像の取得とフローの実行を
  別のスレッドに分けるのは第 3 段階。

## 5. フローファイルの形式

* JSON（UTF-8）、拡張子 `.amvflow`。人が読めて、差分を取れる。
* 学習データ（Shape Match と NCC のパターン、校正）は、AMV に既にある
  ストリーム形式（互換性の規則つき、`docs/DESIGN.md` 9.1）でそのまま書き、
  フローファイルと同じ名前のフォルダに置く:
  `part.amvflow` と `part.amvflow.d/1.pattern`。JSON に埋め込むより
  ファイルが大きくならず、差分も見やすい。
* 先頭に `"format": 1` を書く。知らない種別・端子・パラメータは読み込み時に
  エラーにする（黙って捨てない）。
* 読み込みは信頼しない入力として扱い、すべての値を検査する（大きさ、
  NaN、範囲、閉路）。`docs/DESIGN.md` 7 章のストリームの規則と同じ考え方。
* パラメータは名前で保存する（並び順や既定値が変わっても読める）。角度は
  ラジアンで保存し（`docs/DESIGN.md` 5 章）、エディタの表示は度でもよい。

例（`examples/align_and_measure.adb` と同じ処理。パラメータ名は仮）:

```json
{
  "format": 1,
  "name": "align_and_measure",
  "inputs":  [ { "name": "Image", "type": "Image_8_Grey" } ],
  "outputs": [ { "name": "Pass",  "type": "Boolean" },
               { "name": "Width", "type": "Real" } ],
  "nodes": [
    { "id": 1, "kind": "ShapeMatch", "name": "Locate",
      "params": { "AcceptThreshold": 0.6 },
      "pattern": "align_and_measure.amvflow.d/1.pattern",
      "ui": { "x": 80, "y": 120 } },
    { "id": 2, "kind": "Fixture", "name": "Part frame",
      "params": { "FixturedSpaceName": "Part" },
      "ui": { "x": 300, "y": 120 } },
    { "id": 3, "kind": "Caliper", "name": "Width",
      "params": { "EdgeMode": "Pair", "ContrastThreshold": 20.0,
                  "Region": { "shape": "RectangleAffine", "space": "@\\Part",
                              "centerX": 0.0, "centerY": 0.0,
                              "sideX": 120.0, "sideY": 20.0,
                              "rotation": 0.0, "skew": 0.0 } },
      "ui": { "x": 520, "y": 120 } },
    { "id": 4, "kind": "RangeCheck", "name": "Width OK",
      "params": { "Low": 99.5, "High": 100.5 },
      "ui": { "x": 740, "y": 120 } }
  ],
  "links": [
    { "from": "input.Image", "to": "1.Image" },
    { "from": "input.Image", "to": "2.Image" },
    { "from": "1.Pose",      "to": "2.Transform" },
    { "from": "2.Image",     "to": "3.Image" },
    { "from": "3.Width",     "to": "4.Value" },
    { "from": "4.Pass",      "to": "output.Pass" },
    { "from": "3.Width",     "to": "output.Width" }
  ]
}
```

## 6. エディタ（JavaFX）

### 6.1 画面

```
+----------+--------------------------------+----------------+
| ツール   | フロー（ノードと線）            | プロパティ      |
| パレット |                                | （選んだノード）|
|          +--------------------------------+                |
|          | 画像（選んだノードの入力画像と  | 結果           |
|          | 図形。領域はドラッグで編集）    | （全ノード）    |
+----------+--------------------------------+----------------+
| 実行: [1 回] [連続] [フォルダ < >]   結果・処理時間          |
+-------------------------------------------------------------+
```

* ノードには名前、状態の色（Accept 緑、Reject 橙、Error 赤、未実行 灰）、
  処理時間を出す。
* 端子は型ごとに色を変える。ドラッグで線を引き、型の合わない端子には
  引けない。
* 画像の欄には、選んだノードの入力画像に、そのノードの図形（検査領域、
  見つけたエッジ・円・ブロブ）を重ねる。領域はハンドルをドラッグして
  直す。ノーコードで組めるかどうかはここで決まる。
* プロパティ欄はノード種別の記述（3.3）から自動で作る（数値と範囲、
  選択肢、チェックボックス）。
* パラメータを変えたら、直前の画像ですぐに実行し直して結果を見せる。

### 6.2 JavaFX での作り

* **Java と JavaFX**: Java 25（LTS）と OpenJFX。FFM は Java 22 で正式に
  なったので、22 より前の版は使えない。ビルドは Gradle（OpenJFX の
  Gradle プラグインを使う。未決事項 1）。
* **モジュール**（名前は仮）:
  * `amv-flow-native`: C API の呼び出し（7 章）と、それを包む Java の
    クラス（`Flow`、`NodeKind`、`Snapshot` など）。失敗は
    `AmvFlowException` にする。JavaFX には依存しない。
  * `amv-flow-editor`: JavaFX のアプリ本体。
* **フローの編集**: 正しいフローの形を持つのはエンジンだけにする。エディタ
  はノードの追加・削除、リンク、パラメータの変更を C API で頼み、エンジン
  が返す検証結果をそのまま表示する。検証の規則を Java と Ada の二か所に
  書かないためである。
* **元に戻す / やり直し**: 編集のたびにエンジンからフローの JSON を受け
  取って Java 側に積み、元に戻すときはその JSON をエンジンに読ませる。
  学習データはエンジンの中の保管庫に ID で持ち、JSON はその ID を指すので、
  元に戻しても学習し直さなくてよい。
* **ノード編集の画面**: JavaFX の `Pane` の上に、ノードを部品として、
  リンクを `CubicCurve` として置く。拡大・移動は全体にかける変換で行う。
* **画像の表示**: エンジンが画像を 8 bit の BGRA（不透明、A = 255）で
  Java が確保したネイティブメモリに書き、そのメモリの `ByteBuffer` を
  JavaFX の `PixelBuffer<ByteBuffer>`（`PixelFormat.getByteBgraPreInstance()`）
  を通して `WritableImage` にコピーなしで渡す。グレー画像から BGRA への
  変換はエンジンが行う。
* **図形の重ね描き**: エンジンはノードの図形を、画像の画素座標の単純な
  図形（線分、折れ線、円、楕円、円弧、回転した矩形、点）の一覧として
  返す（7.3）。エディタはそれを画像の上の `Canvas` に、表示の拡大率に
  合わせて描く（線の太さは画面の画素で一定）。
* **領域のドラッグ**: ドラッグ中は Java 側だけで描き直し、離したときに
  パラメータとしてエンジンに送って実行し直す（実行は最大でも数回/秒に
  間引く）。
* **スレッド**: JavaFX の画面スレッドからエンジンを呼ばない。エンジン用の
  スレッドを 1 本作り（`Executors.newSingleThreadExecutor`）、すべての
  呼び出しをそこに送る。結果は `Platform.runLater` で画面に戻し、前の結果が
  まだ描かれていなければ古い方を捨てる（ライブ表示で遅れが溜まらない
  ように）。

### 6.3 選ばなかった案

| 案 | 選ばなかった理由 |
|---|---|
| Win32 + Ada（今のライブアプリの作り） | Windows 専用。ノード編集やプロパティ欄を全部自作になる |
| ブラウザの画面 + Ada の HTTP サーバ | PC ネイティブのアプリにしたい |
| GtkAda | Windows と macOS での配布が重い |
| Qt（C++） | C++ の層が増え、ビルドとライセンスの扱いが重い |
| Avalonia（.NET） | 候補にはなるが、JavaFX を選んだ |

## 7. エンジンの C API（`amvf_*`）

JavaFX のエディタからエンジンを呼ぶための C API。名前と形は仮。将来は
Python や C# などからも同じ API で使える。

### 7.1 方針

AMV のカーネルの C API（`include/amv.h`、`docs/DESIGN.md` 9.1）と同じ
流儀にする。

* ヘッダは `optional/flow/include/amv_flow.h`。関数名は `amvf_` で始める。
* 型は C の型だけ: `double`、`int32_t`、`int64_t`、`uint8_t`、
  UTF-8 の文字列（NUL 終端の `const char *`）、不透明なハンドル
  （`amvf_flow *`）。Boolean は 0 か 1 の `int32_t`。
* すべての関数は最後の引数の `amvf_status *` に結果を書く。形は AMV の
  `ks_status` と同じ（失敗コード、メッセージの長さ、メッセージ）。
  失敗コードはこの API 独自のものにし、AMV の失敗はその中の 1 つとして
  メッセージごと伝える。
* 例外を外に出さない（Ada の例外はすべて境界で失敗コードにする）。
* 可変長のデータ（JSON、画像）は呼ぶ側の領域に書く: 容量 0 で呼ぶと必要な
  大きさを返し、十分な容量で呼び直すと書く。エンジンが確保したメモリを
  呼ぶ側に解放させない。
* `amvf_abi_version()` を持ち、互換性のない変更のたびに上げる。エディタは
  読み込み時に照合し、合わなければ起動時にそう表示する。

### 7.2 関数（案）

```c
/* 名前と形は仮。 */
int32_t amvf_abi_version(void);

/* ノード種別の一覧（端子とパラメータの記述, 3.3）を JSON で */
void amvf_kinds_json(char *buf, int64_t cap, int64_t *needed, amvf_status *st);

/* フローの作成・破棄・保存・読み込み */
amvf_flow *amvf_flow_create(amvf_status *st);
void amvf_flow_destroy(amvf_flow *flow);
void amvf_flow_load(amvf_flow *flow, const char *path, amvf_status *st);
void amvf_flow_save(amvf_flow *flow, const char *path, amvf_status *st);
void amvf_flow_to_json(amvf_flow *flow, char *buf, int64_t cap,
                       int64_t *needed, amvf_status *st);
void amvf_flow_from_json(amvf_flow *flow, const char *json, amvf_status *st);

/* 編集（エンジンが検証し、問題の一覧を JSON で返す） */
int64_t amvf_flow_add_node(amvf_flow *flow, const char *kind,
                           double x, double y, amvf_status *st);
void amvf_flow_remove_node(amvf_flow *flow, int64_t node, amvf_status *st);
void amvf_flow_link(amvf_flow *flow, int64_t from_node, const char *from_port,
                    int64_t to_node, const char *to_port, amvf_status *st);
void amvf_flow_unlink(amvf_flow *flow, int64_t to_node, const char *to_port,
                      amvf_status *st);
void amvf_flow_set_param_json(amvf_flow *flow, int64_t node, const char *name,
                              const char *value_json, amvf_status *st);
void amvf_flow_problems_json(amvf_flow *flow, char *buf, int64_t cap,
                             int64_t *needed, amvf_status *st);

/* 入力と実行 */
void amvf_flow_set_input_image_8(amvf_flow *flow, const char *port,
                                 int32_t width, int32_t height, int32_t stride,
                                 const uint8_t *pixels, amvf_status *st);
void amvf_flow_run(amvf_flow *flow, amvf_status *st);

/* 結果（スナップショット）: ノードごとの状態・時間・数値の出力を JSON で */
void amvf_flow_results_json(amvf_flow *flow, char *buf, int64_t cap,
                            int64_t *needed, amvf_status *st);
/* 表示用の図形（画素座標の単純な図形の一覧, 6.2）を JSON で */
void amvf_node_graphics_json(amvf_flow *flow, int64_t node, char *buf,
                             int64_t cap, int64_t *needed, amvf_status *st);
/* ノードの入力画像を BGRA で（大きさを返し、dst に書く） */
void amvf_node_image_bgra(amvf_flow *flow, int64_t node, const char *port,
                          uint8_t *dst, int64_t cap, int32_t *width,
                          int32_t *height, amvf_status *st);
```

### 7.3 JSON と型付きの関数の使い分け

* **メタデータは JSON**: ノード種別の記述、検証の問題、結果の数値、表示用の
  図形。量が少なく形が変わりやすいので、C の構造体を増やさずに済む。
  中身の形は文書にし、テストで確かめる。
* **重いデータは型付きの関数**: 画像の受け渡しはバイト列で直接行う。
* 実行のたびに呼ぶ関数（実行、結果、図形、画像）は 1 回の呼び出しで
  済むようにし、端子ごとに何度も往復しない。

### 7.4 Java からの呼び出し

* Java 側の呼び出しコードは FFM で手書きする（関数は 30 個ほど）。
  関数が増えたら、ヘッダから jextract で生成する方式に切り替えを考える。
  ヘッダのすべての関数に Java の呼び出しがあることをテストで確かめる。
* ライブラリは `SymbolLookup.libraryLookup` で、アプリと一緒に置いた
  パスから読む。FFM を使うので、起動オプションに
  `--enable-native-access` を付ける（jpackage の Java オプションに入れる）。
* Java の `Arena` で呼び出しごとの一時領域を確保し、フローのハンドルは
  `AutoCloseable` のクラスで包んで確実に `amvf_flow_destroy` を呼ぶ。

### 7.5 スレッド

* フローのハンドル 1 つは、同時に 1 本のスレッドからだけ使う（エンジンは
  ハンドルごとの排他を持たない）。エディタはエンジン用のスレッド 1 本から
  呼ぶ（6.2）。
* Java のスレッドは Ada から見ると外のスレッドである。エンジンは境界の
  関数の中で Ada のタスク機能を使わないようにし、使う場合は GNAT の外部
  スレッドの登録を確かめる。

### 7.6 Ada 側の作り

* 共有ライブラリは gprbuild の自立型ライブラリ（`Library_Standalone` を
  `"encapsulated"`）にして、GNAT のランタイムを中に含める。Java から
  読み込むだけで初期化（elaboration）が済むようにする。
* カメラ（Aravis）を使う部分は、カメラなしでも組めるようにビルドを分ける。

## 8. ビルドと配布

* **Ada のエンジン**: OS ごとに GNAT でビルドする（Windows x86_64、
  Linux x86_64、macOS）。Alire の GNAT を使う。
* **Java**: Gradle で Java のモジュールとエディタをビルドし、JUnit で
  テストする。
* **配布**: jpackage で OS ごとのインストーラーを作る（Java の実行環境と
  共有ライブラリを同梱する）。jpackage はその OS の上でしか作れないので、
  CI で Windows・Linux・macOS の 3 つのランナーを使う。
* **カメラ**: Aravis は Windows（今と同じ MSYS2 でのビルド）、Linux（各
  ディストリビューションのパッケージ）、macOS（Homebrew）で用意する。
  Windows では依存する DLL をライブラリと同じフォルダに置き、読み込み順を
  確かめる。macOS は未確認。
* **ライセンス**: OpenJFX は GPLv2 + Classpath Exception、Aravis は
  LGPL-2.1 以降（動的リンク）、AMV は MIT / Apache-2.0。配布物には
  それぞれの表示を入れる。macOS 向けの署名と公証は配布の段階で考える。

## 9. 段階的な作り方

**第 1 段階: エンジンと CLI（GUI なし）**

* `AMV.Flow`: 値、端子、ノード、リンク、検証、実行、JSON の読み書き
* ノード: Image File、Shape Match、Fixture、Caliper、Find Circle、Blob、
  Distance、Range Check、CSV Log、Circularity
* `amv_flow run part.amvflow images/*.bmp` で、結果を CSV と結果画像に出す
* `Ks_Flow_Tool` で、保存したフローを Ada から実行する
* 完了の目安: `examples/align_and_measure.adb` をフローファイル 1 つで
  再現し、同じ寸法が出る

**第 2 段階: C API と JavaFX のエディタ**

* `amv_flow.h` と共有ライブラリ、C からのテスト
* `amv-flow-native`（FFM の呼び出しと Java のクラス）と JUnit のテスト
* エディタ: ノードの配置と接続、プロパティ欄、画像と図形の表示、領域の
  ドラッグ、1 回実行、フォルダ再生、保存と読み込み、元に戻す
* 完了の目安: カップの真円度検査（今のライブアプリと同じこと）を GUI だけで
  組み、保存して実行できる。Windows と Linux で動く

**第 3 段階: カメラと配布**

* Camera ノード、連続実行、取得用のスレッド、合否の集計、レシピ（
  パラメータの組の切り替え）
* 3 つの OS のインストーラーを CI で作る

**第 4 段階: 使いやすさ**

* EasyBuilder のようなウィザード（「画像 → 位置決め → 検査 → 出力」の
  手順に答えるとフローができる）、作業者向けの簡単な画面、ブロブごとの
  ループ、式ノード

## 10. テスト

* `docs/DESIGN.md` 8 章に合わせる: 合成画像（`AMV_Test_Images`）で幾何の
  結果を真値と比べる。パラメータの検査と `Run_Status` も調べる。
* フローファイルの往復（保存して読むと同じフローになる）。
* 壊れたファイル: 壊れた JSON、巨大な値、NaN、知らない種別、閉路、型の
  合わないリンク。どれもエラーとして報告し、例外で落ちない。
* C API: C からのテスト（`tests/c` と同じ形）で、すべての関数の成功と
  失敗、容量の足りない領域、NULL のハンドルを確かめる。
* Java: JUnit で、`amv-flow-native` が C API を正しく呼び、失敗を例外に
  することを確かめる。エディタの操作はエンジンを通るので、大部分は
  エンジンと C API のテストで押さえる。

## 11. 未決事項

1. Java のビルドツール: Gradle を勧める（Maven でもよい）
2. 対象の OS と CPU: Windows x86_64、Linux x86_64、macOS（Apple Silicon
   だけか Intel もか）
3. 置き場所: `optional/flow`（Ada）と `optional/flow_editor`（Java）で
   よいか、別のリポジトリにするか
4. ファイルの形式: JSON と学習データの別ファイルでよいか（1 つの zip に
   まとめるか）
5. ノード種別の記述: 手書きのアダプタで始めてよいか
6. 最初の目標: 寸法検査（align_and_measure）とカップの真円度検査の 2 つで
   よいか
7. この文書は日本語で書いた。英語版が要るか
