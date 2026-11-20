# 引き継ぎメモ(2026-11-20)

作業を止めた時点の状態と、残っている作業です。計画そのものは
`docs/PLATINUM.md`、ミューテーションテストの生存の一覧は
`docs/MUTATION.md` にあります。

## 状態

- `main` = 1339c76。最近マージしたもの:
  - #8 Code Reader の QR コード
  - #10 `docs/PLATINUM.md`(Platinum の計画)
  - #11 ミュータントの実行中は、時間を上限と比べるチェックをしない(`AMV_Test_Support.Check_Timing`)
  - #12 Platinum フェーズ 3(テストがすべての契約を検査する)
  - #13 ミュータントの証明の前に、why3 のセッションを消す
- 開いている PR: #14 Platinum フェーズ 4 の最初の 3 つ(`IP_Two_Image`、`Pixel_Map`、`Image_Convert` を `AMV.Spec` で仕様化)。CI はすべて通っています。3 つの本体の生存は `docs/MUTATION.md` に書きました。残りは下の「#14 の残り」です。

## #14 の残り

本体全体のワークフロー Mutation の実行(run 44641866623、`workflow_dispatch` で `files` に 3 つの本体を指定)で「証明が時間内に終わらない」とされたミュータントのうち、次の 10 件は、サブプログラムに絞った証明をまだしていません。`docs/MUTATION.md` では「no narrower proof made yet」と書いています。

- `Image_Convert`(8 件)
  - `Convert_Colour` の事前条件: `Same_Planes (...)` または `Valid_Params (Params)` を消すもの、`and then` を `or else` にするもの。計 4 件
  - `Convert_16` と `Convert_Colour` の、出力の確保に失敗したときの分岐: `if not Succeeded (Status)` を `False` にするものと、`return` を消すもの。計 4 件
- `Pixel_Map`(2 件): `Execute` の同じ分岐の 2 件

`IP_Two_Image` の 7 件は済んでおり、どれも証明が失敗しました(検出)。この 10 件はマージの条件ではありません。結果が出たら `docs/MUTATION.md` の該当行を直してください。

## サブプログラムに絞った証明の手順

1. ワークフローの成果物の `mutation-report.json` から、ミュータントの `location`(開始と終了の行・桁)と `replacement` を取り、本体のその範囲を置き換える。ジョブが変異子の部分に分かれているときは、ID は部分ごとに振られている
2. `build/obj/gnatprove` の下の `why3session.xml*` と `why3shapes*` を消す(`find build/obj/gnatprove \( -name 'why3session.xml*' -o -name 'why3shapes*' \) -type f -delete`)。前の証明のセッションが、プローバーの失敗を使い回すことがあるため(#13)
3. `gnatprove -P amv.gpr -j3 --steps=200000 --timeout=0 --checks-as-errors=on --report=fail -u <本体>.adb --limit-subp=<本体>.adb:<サブプログラムの宣言の行>`。事前条件や事後条件のミュータントは、呼び出し側(ループ不変条件を持つものなど)にも絞って証明する
4. 失敗した場所が、ミュータントで変わったゴールか(事後条件そのもの、弱めた事前条件のもとでのチェック、呼び出し側のループ不変条件など)を確かめる
5. 本体を `git checkout` で元に戻す

1 件あたり数分から 15 分ほどかかります。

## 次にやること

1. **QR コードの本体のミューテーションのやり直し。** #13 より前の実行は、証明による検出に偽物を含んでいる可能性があります。#14 の 3 本体では、手元の実行で証明により検出とされた 76 件が、#13 のあとの実行では「テストも証明も通る」でした。`QR_Code`、`QR_Code.Finder`、`Views`、`Code_Reader` と `Data_Matrix.Finder` の変えた行を、ワークフロー Mutation でやり直し、`docs/MUTATION.md` の QR の節を直してください。`workflow_dispatch` で `files` を指定すると、本体全体を実行します
2. **Platinum フェーズ 4 の残り**(`docs/PLATINUM.md` の順)
   - `Copy_Region`: 変換と失敗の一部が浮動小数点で、フェーズ 10 に関わります
   - `IP_One_Image` の画素ごとの演算、反転、拡大: 画像全体を述べる仕様の形を決める必要があります
3. **テストの穴。** `Image_Convert` と `IP_Two_Image` では、範囲外のパラメーターの多くをどのテストも渡していません。失敗の状態は事後条件で証明されていますが、その分岐とメッセージはテストされていません

## 気をつけること

- ミュータントの証明はステップ数だけで打ち切ります(200000、`tools/mutant_prove.sh`)。上限の近いチェックは、関係のない変更で通ったり通らなかったりします。`Sobel_Edge.Execute` の事後条件は、main でもユニット全体の証明でこの上限を越えていました(#12 でアサーションを足しました)
- Alt-Ergo は、一部のゴールで「High failure」を返します
- ワークフロー Mutation は、PR に docs だけを push しても走ります(paths の条件は、PR 全体の差分で判断されるため)。本体が同じなら、取り消してかまいません
- CI の build-test が、ImageMagick のインストールで止まって 2 時間で打ち切られたことが 1 回あります。再実行で通りました
