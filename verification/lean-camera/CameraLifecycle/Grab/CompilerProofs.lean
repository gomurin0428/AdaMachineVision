import Lean
import Lean.Elab.Tactic.Omega
import CameraLifecycle.Grab.Proofs
import CameraLifecycle.Grab.CompilerGenerated

namespace CameraLifecycle.Grab

def compilerMathematicalRow (env : ScalarEnvironment) : Int := mathematicalRow env

def compilerInt64MaxNat : Nat := 9223372036854775807

theorem compiler_int64_bounds_of_nat (max value : Nat) (hvalue : value ≤ max) :
    Int.negSucc max ≤ Int.ofNat value ∧ Int.ofNat value ≤ Int.ofNat max := by
  constructor
  · change Int.NonNeg (Int.ofNat value - Int.negSucc max)
    have heq : Int.ofNat value - Int.negSucc max = Int.ofNat (value + (max + 1)) := rfl
    rw [heq]
    exact Int.NonNeg.mk _
  · exact int_ofNat_le_ofNat value max hvalue

theorem compiler_int64_bounds_of_neg_succ (max value : Nat) (hvalue : value ≤ max) :
    Int.negSucc max ≤ Int.negSucc value ∧ Int.negSucc value ≤ Int.ofNat max := by
  constructor
  · change Int.NonNeg (Int.subNatNat (max + 1) (value + 1))
    have hzero : (value + 1) - (max + 1) = 0 :=
      nat_sub_zero_of_le (Nat.succ_le_succ hvalue)
    unfold Int.subNatNat
    rw [hzero]
    change Int.NonNeg (Int.ofNat ((max + 1) - (value + 1)))
    have heq : (max + 1) - (value + 1) = max - value := Nat.succ_sub_succ max value
    rw [heq]
    exact Int.NonNeg.mk _
  · change Int.NonNeg (Int.ofNat max - Int.negSucc value)
    have heq : Int.ofNat max - Int.negSucc value = Int.ofNat (max + (value + 1)) := rfl
    rw [heq]
    exact Int.NonNeg.mk _

theorem compiler_int64_bounds_of_sub_nat_nat (max left right : Nat)
    (hleft : left ≤ max) (hright : right ≤ max) :
    Int.negSucc max ≤ Int.subNatNat left right ∧
      Int.subNatNat left right ≤ Int.ofNat max := by
  by_cases hrightLeft : right ≤ left
  · have hzero : right - left = 0 := nat_sub_zero_of_le hrightLeft
    unfold Int.subNatNat
    rw [hzero]
    change Int.negSucc max ≤ Int.ofNat (left - right) ∧
      Int.ofNat (left - right) ≤ Int.ofNat max
    exact compiler_int64_bounds_of_nat max (left - right)
      (Nat.le_trans (Nat.sub_le left right) hleft)
  · have hleftRight : left < right := Nat.lt_of_not_ge hrightLeft
    have hsub : right - left ≠ 0 := by
      intro hzero
      have hle := Nat.le_of_sub_eq_zero hzero
      exact Nat.not_le_of_gt hleftRight hle
    cases hdiff : right - left with
    | zero => exact False.elim (hsub hdiff)
    | succ k =>
        have hk : k ≤ max := by
          calc
            k ≤ Nat.succ k := Nat.le_succ _
            _ = right - left := hdiff.symm
            _ ≤ right := Nat.sub_le right left
            _ ≤ max := hright
        unfold Int.subNatNat
        rw [hdiff]
        change Int.negSucc max ≤ Int.negSucc k ∧
          Int.negSucc k ≤ Int.ofNat max
        exact compiler_int64_bounds_of_neg_succ max k hk

theorem compiler_neg_succ_width_bound (max width : Nat)
    (h : Int.negSucc max ≤ Int.negSucc width) : width ≤ max := by
  change Int.NonNeg (Int.subNatNat (max + 1) (width + 1)) at h
  cases hsub : (width + 1) - (max + 1) with
  | zero =>
      have hle : width + 1 ≤ max + 1 := Nat.le_of_sub_eq_zero hsub
      exact Nat.le_of_succ_le_succ hle
  | succ k =>
      unfold Int.subNatNat at h
      rw [hsub] at h
      cases h

theorem compiler_positive_row_expr (y width x : Nat) :
    Int.ofNat y * Int.ofNat width + Int.ofNat x =
      Int.ofNat (y * width + x) := by
  calc
    Int.ofNat y * Int.ofNat width + Int.ofNat x =
        Int.ofNat (y * width) + Int.ofNat x :=
      congrArg (fun value : Int => value + Int.ofNat x) (Int.ofNat_mul y width).symm
    _ = Int.ofNat (y * width + x) := (Int.ofNat_add (y * width) x).symm

theorem compiler_negative_product_expr (y width : Nat) :
    Int.ofNat y * Int.negSucc width = Int.subNatNat 0 (y * (width + 1)) := by
  change Int.negOfNat (y * (width + 1)) = Int.subNatNat 0 (y * (width + 1))
  cases h : y * (width + 1) with
  | zero => rfl
  | succ k => rfl

theorem compiler_sub_nat_nat_zero (value : Nat) :
    Int.subNatNat value 0 = Int.ofNat value := by
  unfold Int.subNatNat
  rw [Nat.zero_sub, Nat.sub_zero]

theorem compiler_int_ofNat_zero_add (value : Nat) :
    Int.ofNat 0 + Int.ofNat value = Int.ofNat value := by
  calc
    Int.ofNat 0 + Int.ofNat value = Int.ofNat (0 + value) :=
      (Int.ofNat_add 0 value).symm
    _ = Int.ofNat value := congrArg Int.ofNat (Nat.zero_add value)

theorem compiler_negative_row_expr (y width x : Nat) :
    (Int.ofNat y * Int.negSucc width) + Int.ofNat x =
      Int.subNatNat x (y * (width + 1)) := by
  change Int.negOfNat (y * (width + 1)) + Int.ofNat x =
    Int.subNatNat x (y * (width + 1))
  cases h : y * (width + 1) with
  | zero =>
      calc
        Int.negOfNat 0 + Int.ofNat x = Int.ofNat 0 + Int.ofNat x := rfl
        _ = Int.ofNat x := compiler_int_ofNat_zero_add x
        _ = Int.subNatNat x 0 := (compiler_sub_nat_nat_zero x).symm
  | succ k => rfl

theorem compiler_bounds_of_equal (lower upper value other : Int)
    (heq : value = other) (hfit : lower ≤ value ∧ value ≤ upper) :
    lower ≤ other ∧ other ≤ upper := by
  have hprop : (lower ≤ value ∧ value ≤ upper) =
      (lower ≤ other ∧ other ≤ upper) :=
    congrArg (fun current : Int => lower ≤ current ∧ current ≤ upper) heq
  exact hprop.mp hfit

theorem compiler_row_ranges (env : ScalarEnvironment)
    (hx : env.x ≤ compilerNaturalMax) (hy : env.y ≤ compilerNaturalMax)
    (hw : compilerWidthMin ≤ env.width ∧ env.width ≤ compilerWidthMax) :
    compilerBounds.int64Min ≤ compilerMathematicalRow env ∧
      compilerMathematicalRow env ≤ compilerBounds.int64Max ∧
      compilerBounds.int64Min ≤ (Int.ofNat env.y) * env.width ∧
      (Int.ofNat env.y) * env.width ≤ compilerBounds.int64Max := by
  have hnat64 : compilerNaturalMax ≤ compilerInt64MaxNat := by decide
  cases hwidthValue : env.width with
  | ofNat width =>
      have hwidth := hw.2
      rw [hwidthValue] at hwidth
      change Int.ofNat width ≤ Int.ofNat compilerNaturalMax at hwidth
      have hwidthNat := int_ofNat_le_toNat width compilerNaturalMax hwidth
      have hproductNat : env.y * width ≤ compilerNaturalMax * compilerNaturalMax := by
        calc
          env.y * width ≤ compilerNaturalMax * width :=
            Nat.mul_le_mul_right width hy
          _ ≤ compilerNaturalMax * compilerNaturalMax :=
            Nat.mul_le_mul_left compilerNaturalMax hwidthNat
      have hrowNat : env.y * width + env.x ≤
          compilerNaturalMax * compilerNaturalMax + compilerNaturalMax := by
        calc
          env.y * width + env.x ≤
              compilerNaturalMax * compilerNaturalMax + env.x :=
            Nat.add_le_add_right hproductNat env.x
          _ ≤ compilerNaturalMax * compilerNaturalMax + compilerNaturalMax :=
            Nat.add_le_add_left hx _
      have hproductBound : env.y * width ≤ compilerInt64MaxNat :=
        Nat.le_trans hproductNat (by decide)
      have hrowBound : env.y * width + env.x ≤ compilerInt64MaxNat :=
        Nat.le_trans hrowNat (by decide)
      have hproductFits := compiler_int64_bounds_of_nat compilerInt64MaxNat
        (env.y * width) hproductBound
      have hrowFits := compiler_int64_bounds_of_nat compilerInt64MaxNat
        (env.y * width + env.x) hrowBound
      unfold compilerMathematicalRow mathematicalRow
      rw [hwidthValue]
      change compilerBounds.int64Min ≤
          Int.ofNat env.y * Int.ofNat width + Int.ofNat env.x ∧
        Int.ofNat env.y * Int.ofNat width + Int.ofNat env.x ≤ compilerBounds.int64Max ∧
        compilerBounds.int64Min ≤ Int.ofNat env.y * Int.ofNat width ∧
        Int.ofNat env.y * Int.ofNat width ≤ compilerBounds.int64Max
      have hrowExpr := compiler_positive_row_expr env.y width env.x
      have hproductExpr : Int.ofNat env.y * Int.ofNat width =
          Int.ofNat (env.y * width) := (Int.ofNat_mul env.y width).symm
      have hrowFitsExpr := compiler_bounds_of_equal compilerBounds.int64Min
        compilerBounds.int64Max (Int.ofNat (env.y * width + env.x))
        (Int.ofNat env.y * Int.ofNat width + Int.ofNat env.x) hrowExpr.symm hrowFits
      have hproductFitsExpr := compiler_bounds_of_equal compilerBounds.int64Min
        compilerBounds.int64Max (Int.ofNat (env.y * width))
        (Int.ofNat env.y * Int.ofNat width) hproductExpr.symm hproductFits
      exact ⟨hrowFitsExpr.1, hrowFitsExpr.2,
        hproductFitsExpr.1, hproductFitsExpr.2⟩
  | negSucc width =>
      have hwidth := hw.1
      rw [hwidthValue] at hwidth
      change Int.negSucc compilerNaturalMax ≤ Int.negSucc width at hwidth
      have hwidthNat := compiler_neg_succ_width_bound compilerNaturalMax width hwidth
      have hwidthSucc : width + 1 ≤ compilerNaturalMax + 1 :=
        Nat.succ_le_succ hwidthNat
      let negativeProductMagnitude := env.y * (width + 1)
      have hnegativeProductNat : negativeProductMagnitude ≤
          compilerNaturalMax * (compilerNaturalMax + 1) := by
        change env.y * (width + 1) ≤ compilerNaturalMax * (compilerNaturalMax + 1)
        calc
          env.y * (width + 1) ≤ compilerNaturalMax * (width + 1) :=
            Nat.mul_le_mul_right (width + 1) hy
          _ ≤ compilerNaturalMax * (compilerNaturalMax + 1) :=
            Nat.mul_le_mul_left compilerNaturalMax hwidthSucc
      have hnegativeProductBound : negativeProductMagnitude ≤ compilerInt64MaxNat :=
        Nat.le_trans hnegativeProductNat (by decide)
      have hxBound : env.x ≤ compilerInt64MaxNat := Nat.le_trans hx hnat64
      have hproductFits := compiler_int64_bounds_of_sub_nat_nat compilerInt64MaxNat
        0 negativeProductMagnitude (Nat.zero_le _) hnegativeProductBound
      have hrowFits := compiler_int64_bounds_of_sub_nat_nat compilerInt64MaxNat
        env.x negativeProductMagnitude hxBound hnegativeProductBound
      unfold compilerMathematicalRow mathematicalRow
      rw [hwidthValue]
      change compilerBounds.int64Min ≤
          Int.ofNat env.y * Int.negSucc width + Int.ofNat env.x ∧
        Int.ofNat env.y * Int.negSucc width + Int.ofNat env.x ≤ compilerBounds.int64Max ∧
        compilerBounds.int64Min ≤ Int.ofNat env.y * Int.negSucc width ∧
        Int.ofNat env.y * Int.negSucc width ≤ compilerBounds.int64Max
      have hrowExpr := compiler_negative_row_expr env.y width env.x
      have hproductExpr := compiler_negative_product_expr env.y width
      have hrowFitsExpr := compiler_bounds_of_equal compilerBounds.int64Min
        compilerBounds.int64Max (Int.subNatNat env.x negativeProductMagnitude)
        (Int.ofNat env.y * Int.negSucc width + Int.ofNat env.x) hrowExpr.symm hrowFits
      have hproductFitsExpr := compiler_bounds_of_equal compilerBounds.int64Min
        compilerBounds.int64Max (Int.subNatNat 0 negativeProductMagnitude)
        (Int.ofNat env.y * Int.negSucc width) hproductExpr.symm hproductFits
      exact ⟨hrowFitsExpr.1, hrowFitsExpr.2,
        hproductFitsExpr.1, hproductFitsExpr.2⟩

theorem checkedValue_ok (bounds : ScalarBounds) (ty : ScalarType)
    (value : Int) (failure : ScalarFailure)
    (hfit : (bounds.forType ty).1 ≤ value ∧ value ≤ (bounds.forType ty).2) :
    checkedValue bounds ty value failure = .ok value := by
  unfold checkedValue
  change (if (bounds.forType ty).1 ≤ value ∧ value ≤ (bounds.forType ty).2 then
    Except.ok value else Except.error failure) = Except.ok value
  rw [if_pos hfit]

theorem evalScalar_cast_ok (bounds : ScalarBounds) (env : ScalarEnvironment)
    (ty : ScalarType) (expr : ScalarExpr) (value : Int)
    (heval : evalScalar bounds env expr = .ok value)
    (hfit : (bounds.forType ty).1 ≤ value ∧ value ≤ (bounds.forType ty).2) :
    evalScalar bounds env (.cast ty expr) = .ok value := by
  change (do
    let value ← evalScalar bounds env expr
    checkedValue bounds ty value .range) = .ok value
  rw [heval]
  change checkedValue bounds ty value .range = .ok value
  exact checkedValue_ok bounds ty value .range hfit

theorem evalScalar_add_ok (bounds : ScalarBounds) (env : ScalarEnvironment)
    (ty : ScalarType) (left right : ScalarExpr) (leftValue rightValue : Int)
    (hleft : evalScalar bounds env left = .ok leftValue)
    (hright : evalScalar bounds env right = .ok rightValue)
    (hfit : (bounds.forType ty).1 ≤ leftValue + rightValue ∧
      leftValue + rightValue ≤ (bounds.forType ty).2) :
    evalScalar bounds env (.add ty left right) = .ok (leftValue + rightValue) := by
  change (do
    let leftValue ← evalScalar bounds env left
    let rightValue ← evalScalar bounds env right
    checkedValue bounds ty (leftValue + rightValue) .overflow) = .ok (leftValue + rightValue)
  rw [hleft, hright]
  change checkedValue bounds ty (leftValue + rightValue) .overflow = .ok (leftValue + rightValue)
  exact checkedValue_ok bounds ty (leftValue + rightValue) .overflow hfit

theorem evalScalar_mul_ok (bounds : ScalarBounds) (env : ScalarEnvironment)
    (ty : ScalarType) (left right : ScalarExpr) (leftValue rightValue : Int)
    (hleft : evalScalar bounds env left = .ok leftValue)
    (hright : evalScalar bounds env right = .ok rightValue)
    (hfit : (bounds.forType ty).1 ≤ leftValue * rightValue ∧
      leftValue * rightValue ≤ (bounds.forType ty).2) :
    evalScalar bounds env (.mul ty left right) = .ok (leftValue * rightValue) := by
  change (do
    let leftValue ← evalScalar bounds env left
    let rightValue ← evalScalar bounds env right
    checkedValue bounds ty (leftValue * rightValue) .overflow) = .ok (leftValue * rightValue)
  rw [hleft, hright]
  change checkedValue bounds ty (leftValue * rightValue) .overflow = .ok (leftValue * rightValue)
  exact checkedValue_ok bounds ty (leftValue * rightValue) .overflow hfit

theorem compiler_int64_contains_natural (value : Nat)
    (hvalue : value ≤ compilerNaturalMax) :
    compilerBounds.int64Min ≤ Int.ofNat value ∧
      Int.ofNat value ≤ compilerBounds.int64Max := by
  have hvalue64 : value ≤ compilerInt64MaxNat := Nat.le_trans hvalue (by decide)
  change Int.negSucc compilerInt64MaxNat ≤ Int.ofNat value ∧
    Int.ofNat value ≤ Int.ofNat compilerInt64MaxNat
  exact compiler_int64_bounds_of_nat compilerInt64MaxNat value hvalue64

theorem compiler_int64_contains_width (width : Int)
    (hwidth : compilerWidthMin ≤ width ∧ width ≤ compilerWidthMax) :
    compilerBounds.int64Min ≤ width ∧ width ≤ compilerBounds.int64Max := by
  cases width with
  | ofNat value =>
      have hupper := hwidth.2
      change Int.ofNat value ≤ Int.ofNat compilerNaturalMax at hupper
      have hvalue := int_ofNat_le_toNat value compilerNaturalMax hupper
      have hvalue64 : value ≤ compilerInt64MaxNat := Nat.le_trans hvalue (by decide)
      change Int.negSucc compilerInt64MaxNat ≤ Int.ofNat value ∧
        Int.ofNat value ≤ Int.ofNat compilerInt64MaxNat
      exact compiler_int64_bounds_of_nat compilerInt64MaxNat value hvalue64
  | negSucc value =>
      have hlower := hwidth.1
      change Int.negSucc compilerNaturalMax ≤ Int.negSucc value at hlower
      have hvalue := compiler_neg_succ_width_bound compilerNaturalMax value hlower
      have hvalue64 : value ≤ compilerInt64MaxNat := Nat.le_trans hvalue (by decide)
      change Int.negSucc compilerInt64MaxNat ≤ Int.negSucc value ∧
        Int.negSucc value ≤ Int.ofNat compilerInt64MaxNat
      exact compiler_int64_bounds_of_neg_succ compilerInt64MaxNat value hvalue64

theorem compiler_widened_row_eval (env : ScalarEnvironment)
    (hx : env.x ≤ compilerNaturalMax) (hy : env.y ≤ compilerNaturalMax)
    (hw : compilerWidthMin ≤ env.width ∧ env.width ≤ compilerWidthMax) :
    evalScalar compilerBounds env
      (.add .int64
        (.mul .int64 (.cast .int64 .y) (.cast .int64 .width))
        (.cast .int64 .x)) =
      .ok (Int.ofNat env.y * env.width + Int.ofNat env.x) := by
  have hx64 := compiler_int64_contains_natural env.x hx
  have hy64 := compiler_int64_contains_natural env.y hy
  have hw64 := compiler_int64_contains_width env.width hw
  have ranges := compiler_row_ranges env hx hy hw
  have hxfit : (compilerBounds.forType .int64).1 ≤ Int.ofNat env.x ∧
      Int.ofNat env.x ≤ (compilerBounds.forType .int64).2 := by
    change compilerBounds.int64Min ≤ Int.ofNat env.x ∧
      Int.ofNat env.x ≤ compilerBounds.int64Max
    exact hx64
  have hyfit : (compilerBounds.forType .int64).1 ≤ Int.ofNat env.y ∧
      Int.ofNat env.y ≤ (compilerBounds.forType .int64).2 := by
    change compilerBounds.int64Min ≤ Int.ofNat env.y ∧
      Int.ofNat env.y ≤ compilerBounds.int64Max
    exact hy64
  have hwfit : (compilerBounds.forType .int64).1 ≤ env.width ∧
      env.width ≤ (compilerBounds.forType .int64).2 := by
    change compilerBounds.int64Min ≤ env.width ∧ env.width ≤ compilerBounds.int64Max
    exact hw64
  have hproductFit : (compilerBounds.forType .int64).1 ≤
      Int.ofNat env.y * env.width ∧
      Int.ofNat env.y * env.width ≤ (compilerBounds.forType .int64).2 := by
    change compilerBounds.int64Min ≤ Int.ofNat env.y * env.width ∧
      Int.ofNat env.y * env.width ≤ compilerBounds.int64Max
    exact ranges.2.2
  have hrowFit : (compilerBounds.forType .int64).1 ≤
      Int.ofNat env.y * env.width + Int.ofNat env.x ∧
      Int.ofNat env.y * env.width + Int.ofNat env.x ≤ (compilerBounds.forType .int64).2 := by
    have hrowBounds : compilerBounds.int64Min ≤ compilerMathematicalRow env ∧
        compilerMathematicalRow env ≤ compilerBounds.int64Max :=
      ⟨ranges.1, ranges.2.1⟩
    change compilerBounds.int64Min ≤ Int.ofNat env.y * env.width + Int.ofNat env.x ∧
      Int.ofNat env.y * env.width + Int.ofNat env.x ≤ compilerBounds.int64Max
    exact hrowBounds
  have hyCast := evalScalar_cast_ok compilerBounds env .int64 .y
    (Int.ofNat env.y) rfl hyfit
  have hwCast := evalScalar_cast_ok compilerBounds env .int64 .width env.width rfl hwfit
  have hxCast := evalScalar_cast_ok compilerBounds env .int64 .x
    (Int.ofNat env.x) rfl hxfit
  have hproduct := evalScalar_mul_ok compilerBounds env .int64
    (.cast .int64 .y) (.cast .int64 .width) (Int.ofNat env.y) env.width
    hyCast hwCast hproductFit
  exact evalScalar_add_ok compilerBounds env .int64
    (.mul .int64 (.cast .int64 .y) (.cast .int64 .width)) (.cast .int64 .x)
    (Int.ofNat env.y * env.width) (Int.ofNat env.x) hproduct hxCast hrowFit

theorem compiler_evalPredicate_inRange_ok (bounds : ScalarBounds)
    (env : ScalarEnvironment) (valueExpr lowerExpr upperExpr : ScalarExpr)
    (value lower upper : Int)
    (hvalue : evalScalar bounds env valueExpr = .ok value)
    (hlower : evalScalar bounds env lowerExpr = .ok lower)
    (hupper : evalScalar bounds env upperExpr = .ok upper) :
    evalPredicate bounds env (.inRange valueExpr lowerExpr upperExpr) =
      .ok (decide (lower ≤ value) && decide (value ≤ upper)) := by
  unfold evalPredicate
  change (do
    let value ← evalScalar bounds env valueExpr
    let lower ← evalScalar bounds env lowerExpr
    let upper ← evalScalar bounds env upperExpr
    Except.ok (decide (lower ≤ value) && decide (value ≤ upper))) =
      .ok (decide (lower ≤ value) && decide (value ≤ upper))
  rw [hvalue, hlower, hupper]
  rfl

theorem compiler_evalPredicate_not_ok (bounds : ScalarBounds)
    (env : ScalarEnvironment) (predicate : ScalarPredicate) (value : Bool)
    (hvalue : evalPredicate bounds env predicate = .ok value) :
    evalPredicate bounds env (.not predicate) = .ok (!value) := by
  change (do
    let result ← evalPredicate bounds env predicate
    Except.ok (!result)) = .ok (!value)
  rw [hvalue]
  rfl

theorem compiler_evalPredicate_equal_ok (bounds : ScalarBounds)
    (env : ScalarEnvironment) (left right : ScalarExpr) (leftValue rightValue : Int)
    (hleft : evalScalar bounds env left = .ok leftValue)
    (hright : evalScalar bounds env right = .ok rightValue) :
    evalPredicate bounds env (.equal left right) = .ok (leftValue == rightValue) := by
  unfold evalPredicate
  change (do
    let leftValue ← evalScalar bounds env left
    let rightValue ← evalScalar bounds env right
    Except.ok (leftValue == rightValue)) = .ok (leftValue == rightValue)
  rw [hleft, hright]
  rfl

theorem compiler_decide_true {predicate : Prop} [Decidable predicate]
    (hpredicate : predicate) : decide predicate = true := by
  cases hdecide : decide predicate with
  | true => rfl
  | false => exact False.elim ((of_decide_eq_false hdecide) hpredicate)

theorem compiler_decide_false {predicate : Prop} [Decidable predicate]
    (hpredicate : ¬ predicate) : decide predicate = false := by
  cases hdecide : decide predicate with
  | false => rfl
  | true => exact False.elim (hpredicate (of_decide_eq_true hdecide))

theorem compiler_int_ofNat_le_decide_true (value bound : Nat)
    (hvalue : value ≤ bound) :
    decide ((Int.ofNat value : Int) ≤ Int.ofNat bound) = true := by
  cases hdecide : decide ((Int.ofNat value : Int) ≤ Int.ofNat bound) with
  | true => rfl
  | false =>
      have hnot : ¬ value ≤ bound := by
        intro hle
        exact (of_decide_eq_false hdecide) (int_ofNat_le_ofNat value bound hle)
      exact False.elim (hnot hvalue)

theorem compiler_int_ofNat_le_decide_false (value bound : Nat)
    (hvalue : ¬ value ≤ bound) :
    decide ((Int.ofNat value : Int) ≤ Int.ofNat bound) = false := by
  cases hdecide : decide ((Int.ofNat value : Int) ≤ Int.ofNat bound) with
  | false => rfl
  | true =>
      exact False.elim (hvalue (int_ofNat_le_toNat value bound
        (of_decide_eq_true hdecide)))

theorem compiler_ofNat_lt (value bound : Nat) (hvalue : value < bound) :
    (Int.ofNat value : Int) < Int.ofNat bound := by
  change Int.ofNat value + 1 ≤ Int.ofNat bound
  have hsucc : Int.ofNat value + 1 = Int.ofNat (value + 1) := by
    change Int.ofNat value + Int.ofNat 1 = Int.ofNat (value + 1)
    exact (Int.ofNat_add value 1).symm
  rw [hsucc]
  exact int_ofNat_le_ofNat (value + 1) bound (Nat.succ_le_of_lt hvalue)

theorem compiler_int_ofNat_lt_decide_true (value bound : Nat)
    (hvalue : value < bound) :
    decide ((Int.ofNat value : Int) < Int.ofNat bound) = true := by
  exact compiler_decide_true (compiler_ofNat_lt value bound hvalue)

theorem compiler_int_ofNat_lt_decide_false (value bound : Nat)
    (hvalue : ¬ value < bound) :
    decide ((Int.ofNat value : Int) < Int.ofNat bound) = false := by
  cases hdecide : decide ((Int.ofNat value : Int) < Int.ofNat bound) with
  | false => rfl
  | true =>
      exact False.elim (hvalue (int_ofNat_lt_toNat value bound
        (of_decide_eq_true hdecide)))

theorem compiler_ofNat_succ_lt (value : Nat) :
    (Int.ofNat value : Int) < Int.ofNat (value + 1) := by
  exact compiler_ofNat_lt value (value + 1) (Nat.lt_succ_self value)

theorem compiler_neg_succ_add_one (value : Nat) :
    Int.negSucc value + 1 = Int.negOfNat value := by
  cases value with
  | zero => rfl
  | succ value => rfl

theorem compiler_zero_sub_negOfNat (value : Nat) :
    (0 : Int) - Int.negOfNat value = Int.ofNat value := by
  cases value with
  | zero => rfl
  | succ value =>
      change Int.ofNat 0 + Int.ofNat (Nat.succ value) = Int.ofNat (Nat.succ value)
      exact compiler_int_ofNat_zero_add _

theorem compiler_neg_succ_lt_zero (value : Nat) : Int.negSucc value < (0 : Int) := by
  change Int.NonNeg ((0 : Int) - (Int.negSucc value + 1))
  rw [compiler_neg_succ_add_one]
  rw [compiler_zero_sub_negOfNat]
  exact Int.NonNeg.mk _

theorem compiler_ofNat_not_lt_negSucc (value bound : Nat) :
    ¬ (Int.ofNat value : Int) < Int.negSucc bound := by
  intro h
  change Int.NonNeg (Int.negSucc bound - (Int.ofNat value + 1)) at h
  change Int.NonNeg (Int.negSucc (bound + value + 1)) at h
  cases h

def compiler_nat_failure_predicate (row : ScalarExpr) : ScalarPredicate :=
  .not (.inRange row (.literal compilerBounds.naturalMin) (.literal compilerBounds.naturalMax))

def compiler_overflow_failure_predicate (row : ScalarExpr) : ScalarPredicate :=
  .equal (.cast .integer row) (.literal compilerBounds.integerMax)

def compiler_index_value_from_row (row : ScalarExpr) : ScalarExpr :=
  .cast .integer
    (.cast .positive (.add .integer (.cast .natural row) (.literal 1)))

def compiler_array_failure_predicate (row : ScalarExpr) : ScalarPredicate :=
  .not (.inRange (compiler_index_value_from_row row) .arrayFirst .arrayLast)

def compilerIndexFromIR (env : ScalarEnvironment) : IndexOutcome :=
  interpretCompilerIndex compilerBounds env compilerRowExpr1
    compilerNaturalFailurePredicate compilerOverflowFailurePredicate
    compilerArrayFailurePredicate compilerIndexValueExpr

theorem compiler_generated_finish_predicates_match :
    compiler_nat_failure_predicate compilerRowExpr1 = compilerNaturalFailurePredicate ∧
    compiler_overflow_failure_predicate compilerRowExpr1 = compilerOverflowFailurePredicate ∧
    compiler_array_failure_predicate compilerRowExpr1 = compilerArrayFailurePredicate ∧
    compiler_index_value_from_row compilerRowExpr1 = compilerIndexValueExpr := by
  exact ⟨rfl, rfl, rfl, rfl⟩

theorem compiler_nat_failure_eval (env : ScalarEnvironment) (rowExpr : ScalarExpr)
    (row : Int) (hrow : evalScalar compilerBounds env rowExpr = .ok row) :
    evalPredicate compilerBounds env (compiler_nat_failure_predicate rowExpr) =
      .ok (!(decide (compilerBounds.naturalMin ≤ row) &&
        decide (row ≤ compilerBounds.naturalMax))) := by
  have hrange := compiler_evalPredicate_inRange_ok compilerBounds env rowExpr
    (.literal compilerBounds.naturalMin) (.literal compilerBounds.naturalMax)
    row compilerBounds.naturalMin compilerBounds.naturalMax hrow rfl rfl
  exact compiler_evalPredicate_not_ok compilerBounds env _ _ hrange

theorem compiler_overflow_failure_eval (env : ScalarEnvironment) (rowExpr : ScalarExpr)
    (row : Int) (hrow : evalScalar compilerBounds env rowExpr = .ok row)
    (hfit : (compilerBounds.forType .integer).1 ≤ row ∧
      row ≤ (compilerBounds.forType .integer).2) :
    evalPredicate compilerBounds env (compiler_overflow_failure_predicate rowExpr) =
      .ok (row == compilerBounds.integerMax) := by
  have hcast := evalScalar_cast_ok compilerBounds env .integer rowExpr row hrow hfit
  exact compiler_evalPredicate_equal_ok compilerBounds env
    (.cast .integer rowExpr) (.literal compilerBounds.integerMax)
    row compilerBounds.integerMax hcast rfl

theorem compiler_index_value_eval (env : ScalarEnvironment) (rowExpr : ScalarExpr)
    (row : Int) (hrow : evalScalar compilerBounds env rowExpr = .ok row)
    (hnatural : (compilerBounds.forType .natural).1 ≤ row ∧
      row ≤ (compilerBounds.forType .natural).2)
    (hinteger : (compilerBounds.forType .integer).1 ≤ row + 1 ∧
      row + 1 ≤ (compilerBounds.forType .integer).2)
    (hpositive : (compilerBounds.forType .positive).1 ≤ row + 1 ∧
      row + 1 ≤ (compilerBounds.forType .positive).2) :
    evalScalar compilerBounds env (compiler_index_value_from_row rowExpr) =
      .ok (row + 1) := by
  have hnaturalCast := evalScalar_cast_ok compilerBounds env .natural rowExpr
    row hrow hnatural
  have hincrement := evalScalar_add_ok compilerBounds env .integer
    (.cast .natural rowExpr) (.literal 1) row 1 hnaturalCast rfl hinteger
  have hpositiveCast := evalScalar_cast_ok compilerBounds env .positive
    (.add .integer (.cast .natural rowExpr) (.literal 1))
    (row + 1) hincrement hpositive
  have hintegerCast := evalScalar_cast_ok compilerBounds env .integer
    (.cast .positive (.add .integer (.cast .natural rowExpr) (.literal 1)))
    (row + 1) hpositiveCast hinteger
  exact hintegerCast

theorem compiler_index_backend_cast_safe (env : ScalarEnvironment) (value : Nat)
    (hrow : evalScalar compilerBounds env compilerRowExpr1 = .ok (Int.ofNat value))
    (hbelow : value < compilerNaturalMax) :
    evalScalar compilerBounds env compilerIndexValueExpr = .ok (Int.ofNat (value + 1)) ∧
      compilerArrayIndexMin ≤ Int.ofNat (value + 1) ∧
      Int.ofNat (value + 1) ≤ compilerArrayIndexMax := by
  have hnaturalBound : value ≤ compilerNaturalMax := Nat.le_of_lt hbelow
  have hsucc : value + 1 ≤ compilerNaturalMax := Nat.succ_le_of_lt hbelow
  have hplus : (Int.ofNat value : Int) + 1 = Int.ofNat (value + 1) := by
    change Int.ofNat value + Int.ofNat 1 = Int.ofNat (value + 1)
    exact (Int.ofNat_add value 1).symm
  have hnatural : (compilerBounds.forType .natural).1 ≤ Int.ofNat value ∧
      Int.ofNat value ≤ (compilerBounds.forType .natural).2 := by
    change (Int.ofNat 0 : Int) ≤ Int.ofNat value ∧
      Int.ofNat value ≤ Int.ofNat compilerNaturalMax
    exact ⟨int_ofNat_le_ofNat 0 value (Nat.zero_le value),
      int_ofNat_le_ofNat value compilerNaturalMax hnaturalBound⟩
  have hinteger : (compilerBounds.forType .integer).1 ≤ Int.ofNat value + 1 ∧
      Int.ofNat value + 1 ≤ (compilerBounds.forType .integer).2 := by
    rw [hplus]
    change Int.negSucc compilerNaturalMax ≤ Int.ofNat (value + 1) ∧
      Int.ofNat (value + 1) ≤ Int.ofNat compilerNaturalMax
    exact compiler_int64_bounds_of_nat compilerNaturalMax (value + 1) hsucc
  have hpositive : (compilerBounds.forType .positive).1 ≤ Int.ofNat value + 1 ∧
      Int.ofNat value + 1 ≤ (compilerBounds.forType .positive).2 := by
    rw [hplus]
    change (Int.ofNat 1 : Int) ≤ Int.ofNat (value + 1) ∧
      Int.ofNat (value + 1) ≤ Int.ofNat compilerNaturalMax
    exact ⟨int_ofNat_le_ofNat 1 (value + 1)
        (Nat.succ_le_succ (Nat.zero_le value)),
      int_ofNat_le_ofNat (value + 1) compilerNaturalMax hsucc⟩
  have hindex := compiler_index_value_eval env compilerRowExpr1 (Int.ofNat value)
    hrow hnatural hinteger hpositive
  rw [hplus] at hindex
  rw [compiler_generated_finish_predicates_match.2.2.2] at hindex
  refine ⟨hindex, ?_, ?_⟩
  · change (Int.ofNat 0 : Int) ≤ Int.ofNat (value + 1)
    exact int_ofNat_le_ofNat 0 (value + 1) (Nat.zero_le _)
  · change Int.ofNat (value + 1) ≤ Int.ofNat 18446744073709551615
    exact int_ofNat_le_ofNat (value + 1) 18446744073709551615
      (Nat.le_trans hsucc (by decide))

theorem compiler_array_failure_eval (env : ScalarEnvironment) (rowExpr : ScalarExpr)
    (index : Int)
    (hindex : evalScalar compilerBounds env (compiler_index_value_from_row rowExpr) =
      .ok index) :
    evalPredicate compilerBounds env (compiler_array_failure_predicate rowExpr) =
      .ok (!(decide (env.first ≤ index) && decide (index ≤ env.last))) := by
  have hrange := compiler_evalPredicate_inRange_ok compilerBounds env
    (compiler_index_value_from_row rowExpr) .arrayFirst .arrayLast
    index env.first env.last hindex rfl rfl
  exact compiler_evalPredicate_not_ok compilerBounds env _ _ hrange

theorem compiler_nat_failure_negative (env : ScalarEnvironment) (rowExpr : ScalarExpr)
    (value : Nat)
    (hrow : evalScalar compilerBounds env rowExpr = .ok (Int.negSucc value)) :
    evalPredicate compilerBounds env (compiler_nat_failure_predicate rowExpr) =
      .ok true := by
  rw [compiler_nat_failure_eval env rowExpr (Int.negSucc value) hrow]
  change Except.ok (!(decide ((0 : Int) ≤ Int.negSucc value) &&
    decide (Int.negSucc value ≤ Int.ofNat compilerNaturalMax))) = .ok true
  rfl

theorem compiler_nat_failure_above_max (env : ScalarEnvironment) (rowExpr : ScalarExpr)
    (value : Nat) (hvalue : ¬ value ≤ compilerNaturalMax)
    (hrow : evalScalar compilerBounds env rowExpr = .ok (Int.ofNat value)) :
    evalPredicate compilerBounds env (compiler_nat_failure_predicate rowExpr) =
      .ok true := by
  rw [compiler_nat_failure_eval env rowExpr (Int.ofNat value) hrow]
  change Except.ok (!(decide ((0 : Int) ≤ Int.ofNat value) &&
    decide (Int.ofNat value ≤ Int.ofNat compilerNaturalMax))) = .ok true
  rw [compiler_int_ofNat_le_decide_false value compilerNaturalMax hvalue]
  rfl

theorem compiler_nat_failure_within_max (env : ScalarEnvironment) (rowExpr : ScalarExpr)
    (value : Nat) (hvalue : value ≤ compilerNaturalMax)
    (hrow : evalScalar compilerBounds env rowExpr = .ok (Int.ofNat value)) :
    evalPredicate compilerBounds env (compiler_nat_failure_predicate rowExpr) =
      .ok false := by
  rw [compiler_nat_failure_eval env rowExpr (Int.ofNat value) hrow]
  change Except.ok (!(decide ((0 : Int) ≤ Int.ofNat value) &&
    decide (Int.ofNat value ≤ Int.ofNat compilerNaturalMax))) = .ok false
  rw [compiler_int_ofNat_le_decide_true value compilerNaturalMax hvalue]
  rfl

theorem compiler_integer_cast_fits_natural (value : Nat)
    (hvalue : value ≤ compilerNaturalMax) :
    (compilerBounds.forType .integer).1 ≤ Int.ofNat value ∧
      Int.ofNat value ≤ (compilerBounds.forType .integer).2 := by
  change Int.negSucc compilerNaturalMax ≤ Int.ofNat value ∧
    Int.ofNat value ≤ Int.ofNat compilerNaturalMax
  exact compiler_int64_bounds_of_nat compilerNaturalMax value hvalue

theorem compiler_overflow_failure_at_max (env : ScalarEnvironment)
    (rowExpr : ScalarExpr)
    (hrow : evalScalar compilerBounds env rowExpr =
      .ok (Int.ofNat compilerNaturalMax)) :
    evalPredicate compilerBounds env (compiler_overflow_failure_predicate rowExpr) =
      .ok true := by
  have hover := compiler_overflow_failure_eval env rowExpr
    (Int.ofNat compilerNaturalMax) hrow
    (compiler_integer_cast_fits_natural compilerNaturalMax (Nat.le_refl _))
  rw [hover]
  change Except.ok (decide (Int.ofNat compilerNaturalMax =
    Int.ofNat compilerNaturalMax)) = .ok true
  rw [compiler_decide_true rfl]

theorem compiler_overflow_failure_below_max (env : ScalarEnvironment)
    (rowExpr : ScalarExpr) (value : Nat) (hvalue : value < compilerNaturalMax)
    (hrow : evalScalar compilerBounds env rowExpr = .ok (Int.ofNat value)) :
    evalPredicate compilerBounds env (compiler_overflow_failure_predicate rowExpr) =
      .ok false := by
  have hwithin : value ≤ compilerNaturalMax := Nat.le_of_lt hvalue
  have hover := compiler_overflow_failure_eval env rowExpr (Int.ofNat value) hrow
    (compiler_integer_cast_fits_natural value hwithin)
  rw [hover]
  change Except.ok (decide (Int.ofNat value =
    Int.ofNat compilerNaturalMax)) = .ok false
  have hnot : Int.ofNat value ≠ Int.ofNat compilerNaturalMax := by
    intro heq
    exact (Nat.ne_of_lt hvalue) (Int.ofNat.inj heq)
  rw [compiler_decide_false hnot]

theorem compiler_finish_negative (env : ScalarEnvironment) (rowExpr : ScalarExpr)
    (value : Nat)
    (hrow : evalScalar compilerBounds env rowExpr = .ok (Int.negSucc value)) :
    interpretCompilerIndex compilerBounds env rowExpr
      (compiler_nat_failure_predicate rowExpr)
      (compiler_overflow_failure_predicate rowExpr)
      (compiler_array_failure_predicate rowExpr)
      (compiler_index_value_from_row rowExpr) =
      finishIndex compilerBounds (Int.negSucc value) env.first env.last := by
  have hnatural := compiler_nat_failure_negative env rowExpr value hrow
  unfold interpretCompilerIndex
  rw [hrow, hnatural]
  change IndexOutcome.failure .naturalRange =
    (if Int.negSucc value < (0 : Int) ∨
        Int.ofNat compilerNaturalMax < Int.negSucc value then
      .failure .naturalRange else _)
  rw [if_pos (Or.inl (compiler_neg_succ_lt_zero value))]

theorem compiler_finish_above_max (env : ScalarEnvironment) (rowExpr : ScalarExpr)
    (value : Nat) (hvalue : ¬ value ≤ compilerNaturalMax)
    (hrow : evalScalar compilerBounds env rowExpr = .ok (Int.ofNat value)) :
    interpretCompilerIndex compilerBounds env rowExpr
      (compiler_nat_failure_predicate rowExpr)
      (compiler_overflow_failure_predicate rowExpr)
      (compiler_array_failure_predicate rowExpr)
      (compiler_index_value_from_row rowExpr) =
      finishIndex compilerBounds (Int.ofNat value) env.first env.last := by
  have hnatural := compiler_nat_failure_above_max env rowExpr value hvalue hrow
  have hgreater : (Int.ofNat compilerNaturalMax : Int) < Int.ofNat value :=
    compiler_ofNat_lt compilerNaturalMax value (Nat.lt_of_not_ge hvalue)
  unfold interpretCompilerIndex
  rw [hrow, hnatural]
  change IndexOutcome.failure .naturalRange =
    (if Int.ofNat value < (0 : Int) ∨
        Int.ofNat compilerNaturalMax < Int.ofNat value then
      .failure .naturalRange else _)
  rw [if_pos (Or.inr hgreater)]

theorem compiler_finish_at_max (env : ScalarEnvironment) (rowExpr : ScalarExpr)
    (hrow : evalScalar compilerBounds env rowExpr =
      .ok (Int.ofNat compilerNaturalMax)) :
    interpretCompilerIndex compilerBounds env rowExpr
      (compiler_nat_failure_predicate rowExpr)
      (compiler_overflow_failure_predicate rowExpr)
      (compiler_array_failure_predicate rowExpr)
      (compiler_index_value_from_row rowExpr) =
      finishIndex compilerBounds (Int.ofNat compilerNaturalMax) env.first env.last := by
  have hnatural := compiler_nat_failure_within_max env rowExpr compilerNaturalMax
    (Nat.le_refl _) hrow
  have hoverflow := compiler_overflow_failure_at_max env rowExpr hrow
  have hnotNatural : ¬ ((Int.ofNat compilerNaturalMax : Int) < 0 ∨
      Int.ofNat compilerNaturalMax < Int.ofNat compilerNaturalMax) := by
    intro h
    cases h with
    | inl hlt =>
        exact Nat.not_lt_zero _
          (int_ofNat_lt_toNat compilerNaturalMax 0 hlt)
    | inr hlt =>
        exact Nat.lt_irrefl _
          (int_ofNat_lt_toNat compilerNaturalMax compilerNaturalMax hlt)
  have hplus : (Int.ofNat compilerNaturalMax : Int) + 1 =
      Int.ofNat (compilerNaturalMax + 1) := by
    change Int.ofNat compilerNaturalMax + Int.ofNat 1 =
      Int.ofNat (compilerNaturalMax + 1)
    exact (Int.ofNat_add compilerNaturalMax 1).symm
  have hOverflow : (Int.ofNat compilerNaturalMax : Int) <
      Int.ofNat compilerNaturalMax + 1 := by
    rw [hplus]
    exact compiler_ofNat_succ_lt compilerNaturalMax
  unfold interpretCompilerIndex
  rw [hrow, hnatural, hoverflow]
  change IndexOutcome.failure .incrementOverflow =
    finishIndex compilerBounds (Int.ofNat compilerNaturalMax) env.first env.last
  unfold finishIndex
  dsimp only [ScalarBounds.forType, compilerBounds]
  have hnotNaturalActual : ¬ ((Int.ofNat compilerNaturalMax : Int) < 0 ∨
      (2147483647 : Int) < Int.ofNat compilerNaturalMax) := by
    change ¬ ((Int.ofNat compilerNaturalMax : Int) < 0 ∨
      Int.ofNat compilerNaturalMax < Int.ofNat compilerNaturalMax)
    exact hnotNatural
  have hOverflowActual : (2147483647 : Int) < Int.ofNat compilerNaturalMax + 1 := by
    change (Int.ofNat compilerNaturalMax : Int) < Int.ofNat compilerNaturalMax + 1
    exact hOverflow
  rw [if_neg hnotNaturalActual, if_pos (Or.inr hOverflowActual)]

theorem compiler_finish_model_below_max (env : ScalarEnvironment) (value : Nat)
    (hvalue : value < compilerNaturalMax) :
    finishIndex compilerBounds (Int.ofNat value) env.first env.last =
      if ¬(env.first ≤ Int.ofNat (value + 1) ∧
        Int.ofNat (value + 1) ≤ env.last) then .failure .arrayIndex
      else .value (Int.ofNat (value + 1)) := by
  have hnatural : value ≤ compilerNaturalMax := Nat.le_of_lt hvalue
  have hsucc : value + 1 ≤ compilerNaturalMax := Nat.succ_le_of_lt hvalue
  have hplus : (Int.ofNat value : Int) + 1 = Int.ofNat (value + 1) := by
    change Int.ofNat value + Int.ofNat 1 = Int.ofNat (value + 1)
    exact (Int.ofNat_add value 1).symm
  have hnotNatural : ¬ ((Int.ofNat value : Int) < 0 ∨
      Int.ofNat compilerNaturalMax < Int.ofNat value) := by
    intro h
    cases h with
    | inl hlt => exact Nat.not_lt_zero _ (int_ofNat_lt_toNat value 0 hlt)
    | inr hlt =>
        exact (Nat.not_lt_of_ge hnatural)
          (int_ofNat_lt_toNat compilerNaturalMax value hlt)
  have hnotOverflow : ¬ ((Int.ofNat value : Int) + 1 <
      Int.negSucc compilerNaturalMax ∨
      Int.ofNat compilerNaturalMax < Int.ofNat value + 1) := by
    intro h
    cases h with
    | inl hlt =>
        rw [hplus] at hlt
        exact compiler_ofNat_not_lt_negSucc (value + 1) compilerNaturalMax hlt
    | inr hlt =>
        rw [hplus] at hlt
        exact (Nat.not_lt_of_ge hsucc)
          (int_ofNat_lt_toNat compilerNaturalMax (value + 1) hlt)
  have hnotPositive : ¬ ((Int.ofNat value : Int) + 1 < 1 ∨
      Int.ofNat compilerNaturalMax < Int.ofNat value + 1) := by
    intro h
    cases h with
    | inl hlt =>
        rw [hplus] at hlt
        exact (Nat.not_lt_of_ge (Nat.succ_le_succ (Nat.zero_le value)))
          (int_ofNat_lt_toNat (value + 1) 1 hlt)
    | inr hlt =>
        rw [hplus] at hlt
        exact (Nat.not_lt_of_ge hsucc)
          (int_ofNat_lt_toNat compilerNaturalMax (value + 1) hlt)
  unfold finishIndex
  dsimp only [ScalarBounds.forType, compilerBounds]
  have hnotNaturalActual : ¬ ((Int.ofNat value : Int) < 0 ∨
      (2147483647 : Int) < Int.ofNat value) := by
    change ¬ ((Int.ofNat value : Int) < 0 ∨
      Int.ofNat compilerNaturalMax < Int.ofNat value)
    exact hnotNatural
  have hnotOverflowActual : ¬ ((Int.ofNat value : Int) + 1 < -2147483648 ∨
      (2147483647 : Int) < Int.ofNat value + 1) := by
    change ¬ ((Int.ofNat value : Int) + 1 < Int.negSucc compilerNaturalMax ∨
      Int.ofNat compilerNaturalMax < Int.ofNat value + 1)
    exact hnotOverflow
  have hnotPositiveActual : ¬ ((Int.ofNat value : Int) + 1 < 1 ∨
      (2147483647 : Int) < Int.ofNat value + 1) := by
    change ¬ ((Int.ofNat value : Int) + 1 < 1 ∨
      Int.ofNat compilerNaturalMax < Int.ofNat value + 1)
    exact hnotPositive
  rw [if_neg hnotNaturalActual, if_neg hnotOverflowActual,
    if_neg hnotPositiveActual, hplus]

theorem compiler_finish_below_max (env : ScalarEnvironment) (rowExpr : ScalarExpr)
    (value : Nat) (hvalue : value < compilerNaturalMax)
    (hrow : evalScalar compilerBounds env rowExpr = .ok (Int.ofNat value)) :
    interpretCompilerIndex compilerBounds env rowExpr
      (compiler_nat_failure_predicate rowExpr)
      (compiler_overflow_failure_predicate rowExpr)
      (compiler_array_failure_predicate rowExpr)
      (compiler_index_value_from_row rowExpr) =
      finishIndex compilerBounds (Int.ofNat value) env.first env.last := by
  have hnatural : value ≤ compilerNaturalMax := Nat.le_of_lt hvalue
  have hsucc : value + 1 ≤ compilerNaturalMax := Nat.succ_le_of_lt hvalue
  have hplus : (Int.ofNat value : Int) + 1 = Int.ofNat (value + 1) := by
    change Int.ofNat value + Int.ofNat 1 = Int.ofNat (value + 1)
    exact (Int.ofNat_add value 1).symm
  have hnaturalFit : (compilerBounds.forType .natural).1 ≤ Int.ofNat value ∧
      Int.ofNat value ≤ (compilerBounds.forType .natural).2 := by
    change (Int.ofNat 0 : Int) ≤ Int.ofNat value ∧
      Int.ofNat value ≤ Int.ofNat compilerNaturalMax
    exact ⟨int_ofNat_le_ofNat 0 value (Nat.zero_le value),
      int_ofNat_le_ofNat value compilerNaturalMax hnatural⟩
  have hintegerFit : (compilerBounds.forType .integer).1 ≤ Int.ofNat value + 1 ∧
      Int.ofNat value + 1 ≤ (compilerBounds.forType .integer).2 := by
    rw [hplus]
    exact compiler_integer_cast_fits_natural (value + 1) hsucc
  have hpositiveFit : (compilerBounds.forType .positive).1 ≤ Int.ofNat value + 1 ∧
      Int.ofNat value + 1 ≤ (compilerBounds.forType .positive).2 := by
    rw [hplus]
    change (Int.ofNat 1 : Int) ≤ Int.ofNat (value + 1) ∧
      Int.ofNat (value + 1) ≤ Int.ofNat compilerNaturalMax
    exact ⟨int_ofNat_le_ofNat 1 (value + 1)
        (Nat.succ_le_succ (Nat.zero_le value)),
      int_ofNat_le_ofNat (value + 1) compilerNaturalMax hsucc⟩
  have hindex := compiler_index_value_eval env rowExpr (Int.ofNat value) hrow
    hnaturalFit hintegerFit hpositiveFit
  have hindexValue : evalScalar compilerBounds env
      (compiler_index_value_from_row rowExpr) = .ok (Int.ofNat (value + 1)) := by
    rw [hplus] at hindex
    exact hindex
  have hnaturalEval := compiler_nat_failure_within_max env rowExpr value hnatural hrow
  have hoverflowEval := compiler_overflow_failure_below_max env rowExpr value hvalue hrow
  have harrayEval := compiler_array_failure_eval env rowExpr
    (Int.ofNat (value + 1)) hindexValue
  rw [compiler_finish_model_below_max env value hvalue]
  unfold interpretCompilerIndex
  rw [hrow, hnaturalEval, hoverflowEval, harrayEval]
  by_cases hrange : env.first ≤ Int.ofNat (value + 1) ∧
      Int.ofNat (value + 1) ≤ env.last
  · have hfirst := compiler_decide_true hrange.1
    have hlast := compiler_decide_true hrange.2
    have hbool : (!(decide (env.first ≤ Int.ofNat (value + 1)) &&
        decide (Int.ofNat (value + 1) ≤ env.last))) = false := by
      rw [hfirst, hlast]
      rfl
    rw [hbool, hindexValue, if_neg (by intro h; exact h hrange)]
  · have hbool : (!(decide (env.first ≤ Int.ofNat (value + 1)) &&
        decide (Int.ofNat (value + 1) ≤ env.last))) = true := by
      cases hfirst : decide (env.first ≤ Int.ofNat (value + 1)) with
      | false => rfl
      | true =>
          cases hlast : decide (Int.ofNat (value + 1) ≤ env.last) with
          | false => rfl
          | true =>
              exact False.elim (hrange ⟨of_decide_eq_true hfirst,
                of_decide_eq_true hlast⟩)
    rw [hbool, if_pos hrange]

theorem compiler_finish_predicates_equiv (env : ScalarEnvironment)
    (rowExpr : ScalarExpr) (row : Int)
    (hrow : evalScalar compilerBounds env rowExpr = .ok row) :
    interpretCompilerIndex compilerBounds env rowExpr
      (compiler_nat_failure_predicate rowExpr)
      (compiler_overflow_failure_predicate rowExpr)
      (compiler_array_failure_predicate rowExpr)
      (compiler_index_value_from_row rowExpr) =
      finishIndex compilerBounds row env.first env.last := by
  cases row with
  | negSucc value => exact compiler_finish_negative env rowExpr value hrow
  | ofNat value =>
      by_cases hnatural : value ≤ compilerNaturalMax
      · by_cases hmax : value = compilerNaturalMax
        · subst value
          exact compiler_finish_at_max env rowExpr hrow
        · exact compiler_finish_below_max env rowExpr value
            (Nat.lt_of_le_of_ne hnatural hmax) hrow
      · exact compiler_finish_above_max env rowExpr value hnatural hrow

theorem compiler_row0_matches_mathematics (env : ScalarEnvironment)
    (hx : env.x ≤ compilerNaturalMax) (hy : env.y ≤ compilerNaturalMax)
    (hw : compilerWidthMin ≤ env.width ∧ env.width ≤ compilerWidthMax) :
    evalScalar compilerBounds env compilerRowExpr0 = .ok (compilerMathematicalRow env) := by
  change evalScalar compilerBounds env
    (.add .int64
      (.mul .int64 (.cast .int64 .y) (.cast .int64 .width))
      (.cast .int64 .x)) =
    .ok (Int.ofNat env.y * env.width + Int.ofNat env.x)
  exact compiler_widened_row_eval env hx hy hw

theorem compiler_row1_matches_mathematics (env : ScalarEnvironment)
    (hx : env.x ≤ compilerNaturalMax) (hy : env.y ≤ compilerNaturalMax)
    (hw : compilerWidthMin ≤ env.width ∧ env.width ≤ compilerWidthMax) :
    evalScalar compilerBounds env compilerRowExpr1 = .ok (compilerMathematicalRow env) := by
  change evalScalar compilerBounds env
    (.add .int64
      (.mul .int64 (.cast .int64 .y) (.cast .int64 .width))
      (.cast .int64 .x)) =
    .ok (Int.ofNat env.y * env.width + Int.ofNat env.x)
  exact compiler_widened_row_eval env hx hy hw

theorem compiler_ir_index_matches_mathematics (env : ScalarEnvironment)
    (hx : env.x ≤ compilerNaturalMax) (hy : env.y ≤ compilerNaturalMax)
    (hw : compilerWidthMin ≤ env.width ∧ env.width ≤ compilerWidthMax) :
    compilerIndexFromIR env =
      mathematicalIndex compilerBounds env env.first env.last := by
  have hrow := compiler_row1_matches_mathematics env hx hy hw
  change interpretCompilerIndex compilerBounds env compilerRowExpr1
    (compiler_nat_failure_predicate compilerRowExpr1)
    (compiler_overflow_failure_predicate compilerRowExpr1)
    (compiler_array_failure_predicate compilerRowExpr1)
    (compiler_index_value_from_row compilerRowExpr1) =
    finishIndex compilerBounds (compilerMathematicalRow env) env.first env.last
  exact compiler_finish_predicates_equiv env compilerRowExpr1
    (compilerMathematicalRow env) hrow

def compilerIndexBoundaryEnv (x y : Nat) (width first last : Int) :
    ScalarEnvironment :=
  { x := x, y := y, width := width, height := 0,
    first := first, last := last }

theorem compiler_index_negative_row_is_range :
    compilerIndexFromIR (compilerIndexBoundaryEnv 0 1 (-1) 1 1) =
      .failure .naturalRange := by
  rw [compiler_ir_index_matches_mathematics
    (compilerIndexBoundaryEnv 0 1 (-1) 1 1)
    (by decide) (by decide) (by decide)]
  decide

theorem compiler_index_zero_row_reads_lower_bound :
    compilerIndexFromIR (compilerIndexBoundaryEnv 0 0 0 1 1) = .value 1 := by
  rw [compiler_ir_index_matches_mathematics
    (compilerIndexBoundaryEnv 0 0 0 1 1)
    (by decide) (by decide) (by decide)]
  decide

theorem compiler_index_natural_last_overflows_increment :
    compilerIndexFromIR (compilerIndexBoundaryEnv compilerNaturalMax 0 0
      1 (Int.ofNat compilerNaturalMax)) = .failure .incrementOverflow := by
  rw [compiler_ir_index_matches_mathematics
    (compilerIndexBoundaryEnv compilerNaturalMax 0 0
      1 (Int.ofNat compilerNaturalMax))
    (by decide) (by decide) (by decide)]
  decide

theorem compiler_index_too_large_row_is_range :
    compilerIndexFromIR (compilerIndexBoundaryEnv 1 1
      (Int.ofNat compilerNaturalMax) 1 (Int.ofNat compilerNaturalMax)) =
      .failure .naturalRange := by
  rw [compiler_ir_index_matches_mathematics
    (compilerIndexBoundaryEnv 1 1
      (Int.ofNat compilerNaturalMax) 1 (Int.ofNat compilerNaturalMax))
    (by decide) (by decide) (by decide)]
  decide

theorem compiler_index_upper_bound_succeeds :
    compilerIndexFromIR (compilerIndexBoundaryEnv 1 0 0 1 2) = .value 2 := by
  rw [compiler_ir_index_matches_mathematics
    (compilerIndexBoundaryEnv 1 0 0 1 2)
    (by decide) (by decide) (by decide)]
  decide

theorem compiler_index_outside_upper_bound_fails :
    compilerIndexFromIR (compilerIndexBoundaryEnv 1 0 0 1 1) =
      .failure .arrayIndex := by
  rw [compiler_ir_index_matches_mathematics
    (compilerIndexBoundaryEnv 1 0 0 1 1)
    (by decide) (by decide) (by decide)]
  decide

theorem compiler_index_null_range_fails :
    compilerIndexFromIR (compilerIndexBoundaryEnv 0 0 0 2 1) =
      .failure .arrayIndex := by
  rw [compiler_ir_index_matches_mathematics
    (compilerIndexBoundaryEnv 0 0 0 2 1)
    (by decide) (by decide) (by decide)]
  decide

theorem compiler_index_natural_max_minus_one_succeeds :
    compilerIndexFromIR (compilerIndexBoundaryEnv (compilerNaturalMax - 1) 0 0
      1 (Int.ofNat compilerNaturalMax)) =
      .value (Int.ofNat compilerNaturalMax) := by
  rw [compiler_ir_index_matches_mathematics
    (compilerIndexBoundaryEnv (compilerNaturalMax - 1) 0 0
      1 (Int.ofNat compilerNaturalMax))
    (Nat.sub_le _ _) (by decide) (by decide)]
  decide

theorem compiler_widened_row_max_coordinates_width_edges :
    evalScalar compilerBounds
      (compilerIndexBoundaryEnv compilerNaturalMax compilerNaturalMax compilerWidthMin 1 1)
      compilerRowExpr1 = .ok (compilerMathematicalRow
        (compilerIndexBoundaryEnv compilerNaturalMax compilerNaturalMax compilerWidthMin 1 1)) ∧
    evalScalar compilerBounds
      (compilerIndexBoundaryEnv compilerNaturalMax compilerNaturalMax 0 1 1)
      compilerRowExpr1 = .ok (compilerMathematicalRow
        (compilerIndexBoundaryEnv compilerNaturalMax compilerNaturalMax 0 1 1)) ∧
    evalScalar compilerBounds
      (compilerIndexBoundaryEnv compilerNaturalMax compilerNaturalMax compilerWidthMax 1 1)
      compilerRowExpr1 = .ok (compilerMathematicalRow
        (compilerIndexBoundaryEnv compilerNaturalMax compilerNaturalMax compilerWidthMax 1 1)) := by
  exact ⟨
    compiler_row1_matches_mathematics _ (by decide) (by decide) (by decide),
    compiler_row1_matches_mathematics _ (by decide) (by decide) (by decide),
    compiler_row1_matches_mathematics _ (by decide) (by decide) (by decide)⟩

theorem compiler_widened_row_zero_coordinates_width_edges :
    evalScalar compilerBounds
      (compilerIndexBoundaryEnv 0 0 compilerWidthMin 1 1)
      compilerRowExpr1 = .ok (compilerMathematicalRow
        (compilerIndexBoundaryEnv 0 0 compilerWidthMin 1 1)) ∧
    evalScalar compilerBounds
      (compilerIndexBoundaryEnv 0 0 0 1 1)
      compilerRowExpr1 = .ok (compilerMathematicalRow
        (compilerIndexBoundaryEnv 0 0 0 1 1)) ∧
    evalScalar compilerBounds
      (compilerIndexBoundaryEnv 0 0 compilerWidthMax 1 1)
      compilerRowExpr1 = .ok (compilerMathematicalRow
        (compilerIndexBoundaryEnv 0 0 compilerWidthMax 1 1)) := by
  exact ⟨
    compiler_row1_matches_mathematics _ (by decide) (by decide) (by decide),
    compiler_row1_matches_mathematics _ (by decide) (by decide) (by decide),
    compiler_row1_matches_mathematics _ (by decide) (by decide) (by decide)⟩

theorem compiler_positive_conversion_has_no_independent_failure
    (env : ScalarEnvironment) (rowExpr : ScalarExpr)
    (value : Nat) (hvalue : value < compilerNaturalMax)
    (hrow : evalScalar compilerBounds env rowExpr = .ok (Int.ofNat value)) :
    evalScalar compilerBounds env (compiler_index_value_from_row rowExpr) =
      .ok (Int.ofNat (value + 1)) := by
  have hnatural : value ≤ compilerNaturalMax := Nat.le_of_lt hvalue
  have hsucc : value + 1 ≤ compilerNaturalMax := Nat.succ_le_of_lt hvalue
  have hplus : (Int.ofNat value : Int) + 1 = Int.ofNat (value + 1) := by
    change Int.ofNat value + Int.ofNat 1 = Int.ofNat (value + 1)
    exact (Int.ofNat_add value 1).symm
  have hnaturalFit : (compilerBounds.forType .natural).1 ≤ Int.ofNat value ∧
      Int.ofNat value ≤ (compilerBounds.forType .natural).2 := by
    change (Int.ofNat 0 : Int) ≤ Int.ofNat value ∧
      Int.ofNat value ≤ Int.ofNat compilerNaturalMax
    exact ⟨int_ofNat_le_ofNat 0 value (Nat.zero_le value),
      int_ofNat_le_ofNat value compilerNaturalMax hnatural⟩
  have hintegerFit : (compilerBounds.forType .integer).1 ≤ Int.ofNat value + 1 ∧
      Int.ofNat value + 1 ≤ (compilerBounds.forType .integer).2 := by
    rw [hplus]
    exact compiler_integer_cast_fits_natural (value + 1) hsucc
  have hpositiveFit : (compilerBounds.forType .positive).1 ≤ Int.ofNat value + 1 ∧
      Int.ofNat value + 1 ≤ (compilerBounds.forType .positive).2 := by
    rw [hplus]
    change (Int.ofNat 1 : Int) ≤ Int.ofNat (value + 1) ∧
      Int.ofNat (value + 1) ≤ Int.ofNat compilerNaturalMax
    exact ⟨int_ofNat_le_ofNat 1 (value + 1)
        (Nat.succ_le_succ (Nat.zero_le value)),
      int_ofNat_le_ofNat (value + 1) compilerNaturalMax hsucc⟩
  have hindex := compiler_index_value_eval env rowExpr (Int.ofNat value) hrow
    hnaturalFit hintegerFit hpositiveFit
  rw [hplus] at hindex
  exact hindex

def compilerPixelEnvironment (frame : Observation) (bytes : ByteArrayView)
    (x y : Nat) : ScalarEnvironment :=
  { x := x, y := y, width := frame.width, height := frame.height,
    first := bytes.first, last := bytes.last }

theorem compiler_model_early_guard_returns_zero (frame : Observation) (x y : Nat)
    (hguard :
      (decide (frame.width ≤ 0) || decide (frame.height ≤ 0) ||
        frame.byteCount == 0 || frame.bytes.isNone) = true) :
    Model.pixelAt frame x y = byteZero := by
  unfold Model.pixelAt
  rw [if_pos hguard]
  rfl

theorem compiler_model_invalid_coordinates_return_zero (frame : Observation)
    (x y : Nat)
    (hfirstGuard :
      (decide (frame.width ≤ 0) || decide (frame.height ≤ 0) ||
        frame.byteCount == 0 || frame.bytes.isNone) = false)
    (hcoordinate : decide (x ≥ Int.toNat frame.width) = true ∨
      decide (y ≥ Int.toNat frame.height) = true) :
    Model.pixelAt frame x y = byteZero := by
  have hfirstNot : ¬
      (decide (frame.width ≤ 0) || decide (frame.height ≤ 0) ||
        frame.byteCount == 0 || frame.bytes.isNone) = true := by
    rw [hfirstGuard]
    intro h
    cases h
  have hsecondGuard :
      (byteFirst frame != 1 || byteLength frame != frame.byteCount ||
        decide (x ≥ Int.toNat frame.width) || decide (y ≥ Int.toNat frame.height)) = true := by
    rcases hcoordinate with hx | hy
    · rw [hx]
      cases hfirst : (byteFirst frame != 1) <;>
        cases hlength : (byteLength frame != frame.byteCount) <;>
        cases hy : decide (y ≥ Int.toNat frame.height) <;> rfl
    · rw [hy]
      cases hfirst : (byteFirst frame != 1) <;>
        cases hlength : (byteLength frame != frame.byteCount) <;>
        cases hx : decide (x ≥ Int.toNat frame.width) <;> rfl
  unfold Model.pixelAt
  rw [if_neg hfirstNot, if_pos hsecondGuard]
  rfl

theorem compiler_model_row_outside_byte_count_returns_zero (frame : Observation)
    (x y : Nat)
    (hfirstGuard :
      (decide (frame.width ≤ 0) || decide (frame.height ≤ 0) ||
        frame.byteCount == 0 || frame.bytes.isNone) = false)
    (hsecondGuard :
      (byteFirst frame != 1 || byteLength frame != frame.byteCount ||
        decide (x ≥ Int.toNat frame.width) || decide (y ≥ Int.toNat frame.height)) = false)
    (hrowGuard :
      decide (Int.ofNat y * frame.width + Int.ofNat x ≥ Int.ofNat frame.byteCount) = true) :
    Model.pixelAt frame x y = byteZero := by
  have hfirstNot : ¬
      (decide (frame.width ≤ 0) || decide (frame.height ≤ 0) ||
        frame.byteCount == 0 || frame.bytes.isNone) = true := by
    rw [hfirstGuard]
    intro h
    cases h
  have hsecondNot : ¬
      (byteFirst frame != 1 || byteLength frame != frame.byteCount ||
        decide (x ≥ Int.toNat frame.width) || decide (y ≥ Int.toNat frame.height)) = true := by
    rw [hsecondGuard]
    intro h
    cases h
  unfold Model.pixelAt
  rw [if_neg hfirstNot, if_neg hsecondNot, if_pos hrowGuard]
  rfl

theorem compiler_pixel_read_branch_avoids_index_failures (frame : Observation)
    (bytes : ByteArrayView) (x y : Nat)
    (hdomain : observationDomain frame)
    (hwidth : 0 < frame.width) (hheight : 0 < frame.height)
    (hcount : 0 < frame.byteCount)
    (hbytes : frame.bytes = some bytes)
    (hfirst : bytes.first = 1)
    (hlength : byteLength frame = frame.byteCount)
    (hx : x < Int.toNat frame.width) (hy : y < Int.toNat frame.height)
    (hrow : Int.ofNat y * frame.width + Int.ofNat x < Int.ofNat frame.byteCount) :
    compilerIndexFromIR (compilerPixelEnvironment frame bytes x y) =
        .value (Int.ofNat
          (Int.toNat (Int.ofNat y * frame.width + Int.ofNat x) + 1)) ∧
      Model.pixelAt frame x y =
        bytes.content (Int.toNat (Int.ofNat y * frame.width + Int.ofNat x) + 1) := by
  unfold observationDomain at hdomain
  rcases hdomain with ⟨hcountBound, _, _, _, hwidthDomain, hheightDomain, _, hbytesDomain⟩
  unfold int32Domain at hwidthDomain hheightDomain
  rcases hwidthDomain with ⟨hwidthLower, hwidthUpper⟩
  rcases hheightDomain with ⟨hheightLower, hheightUpper⟩
  have hcountMax : frame.byteCount ≤ compilerNaturalMax := by
    change frame.byteCount ≤ compilerNaturalMax
    exact hcountBound
  have hwidthBool : decide (frame.width ≤ 0) = false := by
    cases hwidthValue : frame.width with
    | ofNat n =>
        rw [hwidthValue] at hwidth
        cases n with
        | zero =>
            change Int.NonNeg (Int.negSucc 0) at hwidth
            cases hwidth
        | succ n => rfl
    | negSucc n =>
        rw [hwidthValue] at hwidth
        change Int.NonNeg (Int.negSucc (n + 1)) at hwidth
        cases hwidth
  have hheightBool : decide (frame.height ≤ 0) = false := by
    cases hheightValue : frame.height with
    | ofNat n =>
        rw [hheightValue] at hheight
        cases n with
        | zero =>
            change Int.NonNeg (Int.negSucc 0) at hheight
            cases hheight
        | succ n => rfl
    | negSucc n =>
        rw [hheightValue] at hheight
        change Int.NonNeg (Int.negSucc (n + 1)) at hheight
        cases hheight
  obtain ⟨widthOffset, hwidthRep⟩ := positive_int_to_nat frame.width hwidthBool
  obtain ⟨heightOffset, hheightRep⟩ := positive_int_to_nat frame.height hheightBool
  have hwidthToNat : Int.toNat frame.width = Nat.succ widthOffset := by
    rw [hwidthRep]
    rfl
  have hheightToNat : Int.toNat frame.height = Nat.succ heightOffset := by
    rw [hheightRep]
    rfl
  have hwidthNatUpper : Nat.succ widthOffset ≤ compilerNaturalMax := by
    rw [hwidthRep] at hwidthUpper
    change (Int.ofNat (Nat.succ widthOffset) : Int) ≤ Int.ofNat compilerNaturalMax
      at hwidthUpper
    exact int_ofNat_le_toNat _ _ hwidthUpper
  have hheightNatUpper : Nat.succ heightOffset ≤ compilerNaturalMax := by
    rw [hheightRep] at hheightUpper
    change (Int.ofNat (Nat.succ heightOffset) : Int) ≤ Int.ofNat compilerNaturalMax
      at hheightUpper
    exact int_ofNat_le_toNat _ _ hheightUpper
  have hxBound : x ≤ compilerNaturalMax := by
    rw [hwidthToNat] at hx
    exact Nat.le_trans (Nat.le_of_lt hx) hwidthNatUpper
  have hyBound : y ≤ compilerNaturalMax := by
    rw [hheightToNat] at hy
    exact Nat.le_trans (Nat.le_of_lt hy) hheightNatUpper
  have hwBound : compilerWidthMin ≤ frame.width ∧ frame.width ≤ compilerWidthMax := by
    constructor
    · change int32Min ≤ frame.width
      exact hwidthLower
    · change frame.width ≤ int32Max
      exact hwidthUpper
  let env := compilerPixelEnvironment frame bytes x y
  let row := Int.ofNat y * frame.width + Int.ofNat x
  let rowNat := y * Nat.succ widthOffset + x
  have hrowEq : row = Int.ofNat rowNat := by
    dsimp [row, rowNat]
    rw [hwidthRep]
    exact compiler_positive_row_expr y (Nat.succ widthOffset) x
  have hrowNatLtCount : rowNat < frame.byteCount := by
    have hrowInt : Int.ofNat rowNat < Int.ofNat frame.byteCount := by
      rw [← hrowEq]
      change row < Int.ofNat frame.byteCount
      exact hrow
    exact int_ofNat_lt_toNat rowNat frame.byteCount hrowInt
  have hrowNatLtMax : rowNat < compilerNaturalMax :=
    Nat.lt_of_lt_of_le hrowNatLtCount hcountMax
  have hlengthRaw :
      (if bytes.last < 1 then 0 else Int.toNat (bytes.last - 1 + 1)) =
        frame.byteCount := by
    unfold byteLength at hlength
    rw [hbytes] at hlength
    change (if bytes.last < bytes.first then 0 else
      Int.toNat (bytes.last - bytes.first + 1)) = frame.byteCount at hlength
    rw [hfirst] at hlength
    exact hlength
  have hlast : bytes.last = Int.ofNat frame.byteCount :=
    byte_last_from_length bytes.last frame.byteCount hlengthRaw hcount
  have hrowPlus : row + 1 = Int.ofNat (rowNat + 1) := by
    rw [hrowEq]
    change Int.ofNat rowNat + Int.ofNat 1 = Int.ofNat (rowNat + 1)
    exact (Int.ofNat_add rowNat 1).symm
  have harrayRange : env.first ≤ row + 1 ∧ row + 1 ≤ env.last := by
    dsimp [env, compilerPixelEnvironment]
    rw [hfirst, hlast, hrowPlus]
    exact ⟨int_ofNat_le_ofNat 1 (rowNat + 1)
        (Nat.succ_le_succ (Nat.zero_le rowNat)),
      int_ofNat_le_ofNat (rowNat + 1) frame.byteCount
        (Nat.succ_le_of_lt hrowNatLtCount)⟩
  have hfinish : finishIndex compilerBounds row env.first env.last = .value (row + 1) := by
    have harrayNoFailure : ¬ ¬ (env.first ≤ row + 1 ∧ row + 1 ≤ env.last) := by
      intro h
      exact h harrayRange
    calc
      finishIndex compilerBounds row env.first env.last =
          finishIndex compilerBounds (Int.ofNat rowNat) env.first env.last := by
        rw [hrowEq]
      _ = if ¬ (env.first ≤ Int.ofNat (rowNat + 1) ∧
          Int.ofNat (rowNat + 1) ≤ env.last) then .failure .arrayIndex
          else .value (Int.ofNat (rowNat + 1)) :=
        compiler_finish_model_below_max env rowNat hrowNatLtMax
      _ = .value (row + 1) := by
        have harrayNoFailureNat := harrayNoFailure
        rw [hrowPlus] at harrayNoFailureNat
        rw [if_neg harrayNoFailureNat]
        exact congrArg IndexOutcome.value hrowPlus.symm
  have hcompilerValue : compilerIndexFromIR env = .value (row + 1) := by
    rw [compiler_ir_index_matches_mathematics env hxBound hyBound hwBound]
    change finishIndex compilerBounds row env.first env.last = .value (row + 1)
    exact hfinish
  have hindexFormula : row + 1 = Int.ofNat (Int.toNat row + 1) := by
    rw [hrowEq]
    change Int.ofNat rowNat + Int.ofNat 1 = Int.ofNat (rowNat + 1)
    exact (Int.ofNat_add rowNat 1).symm
  have hcompilerFormula : compilerIndexFromIR env =
      .value (Int.ofNat (Int.toNat row + 1)) := by
    rw [hindexFormula] at hcompilerValue
    exact hcompilerValue
  have hcountNonzero : (frame.byteCount == 0) = false := by
    change decide (frame.byteCount = 0) = false
    exact compiler_decide_false (Nat.ne_of_gt hcount)
  have hfirstGuard :
      (decide (frame.width ≤ 0) || decide (frame.height ≤ 0) ||
        frame.byteCount == 0 || frame.bytes.isNone) = false := by
    rw [hwidthBool, hheightBool, hcountNonzero, hbytes]
    rfl
  have hbyteFirst : (byteFirst frame != 1) = false := by
    unfold byteFirst
    rw [hbytes]
    change (bytes.first != 1) = false
    rw [hfirst]
    rfl
  have hlengthGuard : (byteLength frame != frame.byteCount) = false :=
    nat_bne_eq_false_of_eq _ _ hlength
  have hxGuard : decide (x ≥ Int.toNat frame.width) = false := by
    cases hdec : decide (x ≥ Int.toNat frame.width) with
    | false => rfl
    | true =>
        have hle := of_decide_eq_true hdec
        exact False.elim (Nat.not_le_of_gt hx hle)
  have hyGuard : decide (y ≥ Int.toNat frame.height) = false := by
    cases hdec : decide (y ≥ Int.toNat frame.height) with
    | false => rfl
    | true =>
        have hle := of_decide_eq_true hdec
        exact False.elim (Nat.not_le_of_gt hy hle)
  have hsecondGuard :
      (byteFirst frame != 1 || byteLength frame != frame.byteCount ||
        decide (x ≥ Int.toNat frame.width) || decide (y ≥ Int.toNat frame.height)) = false := by
    rw [hbyteFirst, hlengthGuard, hxGuard, hyGuard]
    rfl
  have hrowGuard : decide (row ≥ Int.ofNat frame.byteCount) = false := by
    rw [hrowEq]
    exact int_ofNat_lt_decide_ge_false rowNat frame.byteCount hrowNatLtCount
  have hindexLower : 1 ≤ rowNat + 1 := Nat.succ_le_succ (Nat.zero_le rowNat)
  have hindexUpper : rowNat + 1 ≤ frame.byteCount := Nat.succ_le_of_lt hrowNatLtCount
  have hcontains :
      bytes.first ≤ Int.ofNat (Int.toNat row + 1) ∧
        Int.ofNat (Int.toNat row + 1) ≤ bytes.last := by
    rw [hrowEq, hfirst, hlast]
    change (1 : Int) ≤ Int.ofNat (rowNat + 1) ∧
      Int.ofNat (rowNat + 1) ≤ Int.ofNat frame.byteCount
    exact ⟨int_ofNat_le_ofNat 1 (rowNat + 1) hindexLower,
      int_ofNat_le_ofNat (rowNat + 1) frame.byteCount hindexUpper⟩
  have hpixel := pixel_at_reads_byte_content frame bytes x y hbytes
    hfirstGuard hsecondGuard hrowGuard hcontains
  change compilerIndexFromIR env =
      .value (Int.ofNat (Int.toNat row + 1)) ∧
    Model.pixelAt frame x y = bytes.content (Int.toNat row + 1)
  exact ⟨hcompilerFormula, hpixel⟩

theorem compiler_row_copies_agree : compilerRowExpr0 = compilerRowExpr1 := rfl

end CameraLifecycle.Grab
