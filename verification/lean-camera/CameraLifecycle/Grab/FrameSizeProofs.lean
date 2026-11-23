import CameraLifecycle.Grab.FrameSizeGenerated
import CameraLifecycle.Grab.CompilerProofs
import CameraLifecycle.Grab.Model

namespace CameraLifecycle.Grab

open CameraLifecycle.Model

def frameSizeSuffix (frame : Observation) : FrameStatus :=
  if decide (frame.width ≤ 0) || decide (frame.height ≤ 0) then
    .invalidDimensions
  else if decide (frame.width * frame.height > 2147483647) then
    .tooLarge
  else if frame.sourceSize != Int.toNat (frame.width * frame.height) ||
      Int.ofNat frame.byteCount != frame.width * frame.height ||
      frame.bytes.isNone || byteFirst frame != 1 ||
      Int.ofNat (byteLength frame) != frame.width * frame.height then
    .invalidLength
  else
    .success

def frameSizePrefixPassed (state : CameraState) (timeout : Nat) (frame : Observation) : Prop :=
  state = .streaming ∧
  0 < timeout ∧ timeout ≤ naturalMax ∧
  frame.acquisitionStatus = .success ∧
  frame.bufferStatus = 0 ∧ frame.payloadType = 1 ∧ frame.pixelFormat = 17301505

theorem compiler_frame_size_bounds_resolved :
    compilerFrameSizeBounds.naturalMin = 0 ∧
    compilerFrameSizeBounds.naturalMax = naturalMax ∧
    compilerFrameSizeBounds.positiveMin = 1 ∧
    compilerFrameSizeBounds.positiveMax = naturalMax ∧
    compilerFrameSizeBounds.integerMin = int32Min ∧
    compilerFrameSizeBounds.integerMax = int32Max ∧
    compilerFrameSizeBounds.int32Min = int32Min ∧
    compilerFrameSizeBounds.int32Max = int32Max ∧
    compilerFrameSizeBounds.int64Min = -9223372036854775808 ∧
    compilerFrameSizeBounds.int64Max = 9223372036854775807 ∧
    compilerFrameSizeBounds.unsigned64Max = 18446744073709551615 ∧
    compilerFrameSizeBounds.sizeMin = 0 ∧
    compilerFrameSizeBounds.sizeMax = 4294967295 := by
  decide

theorem compiler_frame_size_enum_mapping :
    compilerFrameSizeStatusCodes.invalidDimensions = 5 ∧
    compilerFrameSizeStatusCodes.tooLarge = 6 ∧
    compilerFrameSizeStatusCodes.invalidLength = 7 ∧
    compilerFrameSizeStatusCodes.success = 0 := by
  decide

theorem compiler_frame_size_program_order :
    compilerFrameSizeProgram.control =
      .ifThenElse compilerFrameSizeProgram.dimensions (.returnStatus .invalidDimensions)
        (.ifThenElse compilerFrameSizeProgram.limit (.returnStatus .tooLarge)
          (.ifThenElse compilerFrameSizeProgram.invalidLength (.returnStatus .invalidLength)
            (.returnStatus .success))) := by
  rfl

theorem checkedFrameSizeValue_ok (bounds : FrameSizeBounds) (ty : FrameSizeScalarType)
    (failure : FrameSizeFailure) (value : Int)
    (hfit : (scalarBounds bounds ty).1 ≤ value ∧ value ≤ (scalarBounds bounds ty).2) :
    checkedFrameSizeValue bounds ty failure value = .ok value := by
  unfold checkedFrameSizeValue
  cases hBounds : scalarBounds bounds ty with
  | mk lower upper =>
      have hlow : decide (lower ≤ value) = true :=
        compiler_decide_true (by simpa [hBounds] using hfit.1)
      have hhigh : decide (value ≤ upper) = true :=
        compiler_decide_true (by simpa [hBounds] using hfit.2)
      change (if decide (lower ≤ value) && decide (value ≤ upper) then
        Except.ok value else Except.error failure) = Except.ok value
      rw [hlow, hhigh]
      rfl

theorem int32_product_fits_int64 (width height : Int)
    (hw : int32Domain width) (hh : int32Domain height) :
    -9223372036854775808 ≤ width * height ∧ width * height ≤ 9223372036854775807 := by
  have hwBounds : compilerWidthMin ≤ width ∧ width ≤ compilerWidthMax := by
    change compilerWidthMin ≤ width ∧ width ≤ compilerWidthMax
    exact hw
  have hhBounds : compilerWidthMin ≤ height ∧ height ≤ compilerWidthMax := by
    change compilerWidthMin ≤ height ∧ height ≤ compilerWidthMax
    exact hh
  cases width with
  | ofNat w =>
      have hwNat : w ≤ compilerNaturalMax := by
        apply int_ofNat_le_toNat w compilerNaturalMax
        change Int.ofNat w ≤ Int.ofNat compilerNaturalMax
        exact hwBounds.2
      cases height with
      | ofNat h =>
          have hhNat : h ≤ compilerNaturalMax := by
            apply int_ofNat_le_toNat h compilerNaturalMax
            change Int.ofNat h ≤ Int.ofNat compilerNaturalMax
            exact hhBounds.2
          have hproduct : w * h ≤ compilerInt64MaxNat := by
            calc
              w * h ≤ compilerNaturalMax * compilerNaturalMax := Nat.mul_le_mul hwNat hhNat
              _ ≤ compilerInt64MaxNat := by decide
          have hfit := compiler_int64_bounds_of_nat compilerInt64MaxNat (w * h) hproduct
          constructor
          · calc
              -9223372036854775808 ≤ Int.ofNat (w * h) := hfit.1
              _ = Int.ofNat w * Int.ofNat h := Int.ofNat_mul w h
          · calc
              Int.ofNat w * Int.ofNat h = Int.ofNat (w * h) := (Int.ofNat_mul w h).symm
              _ ≤ 9223372036854775807 := hfit.2
      | negSucc h =>
          have hhNat : h ≤ compilerNaturalMax := by
            apply compiler_neg_succ_width_bound compilerNaturalMax h
            change Int.negSucc compilerNaturalMax ≤ Int.negSucc h
            exact hhBounds.1
          have hsucc : h + 1 ≤ compilerNaturalMax + 1 := Nat.add_le_add_right hhNat 1
          have hproduct : w * (h + 1) ≤ compilerInt64MaxNat := by
            calc
              w * (h + 1) ≤ compilerNaturalMax * (compilerNaturalMax + 1) :=
                Nat.mul_le_mul hwNat hsucc
              _ ≤ compilerInt64MaxNat := by decide
          have hfit := compiler_int64_bounds_of_sub_nat_nat compilerInt64MaxNat 0
            (w * (h + 1)) (Nat.zero_le _) hproduct
          rw [compiler_negative_product_expr]
          exact hfit
  | negSucc w =>
      have hwNat : w ≤ compilerNaturalMax := by
        apply compiler_neg_succ_width_bound compilerNaturalMax w
        change Int.negSucc compilerNaturalMax ≤ Int.negSucc w
        exact hwBounds.1
      cases height with
      | ofNat h =>
          have hhNat : h ≤ compilerNaturalMax := by
            apply int_ofNat_le_toNat h compilerNaturalMax
            change Int.ofNat h ≤ Int.ofNat compilerNaturalMax
            exact hhBounds.2
          have hsucc : w + 1 ≤ compilerNaturalMax + 1 := Nat.add_le_add_right hwNat 1
          have hproduct : (w + 1) * h ≤ compilerInt64MaxNat := by
            calc
              (w + 1) * h ≤ (compilerNaturalMax + 1) * compilerNaturalMax :=
                Nat.mul_le_mul hsucc hhNat
              _ ≤ compilerInt64MaxNat := by decide
          have hfit := compiler_int64_bounds_of_sub_nat_nat compilerInt64MaxNat 0
            ((w + 1) * h) (Nat.zero_le _) hproduct
          have hnegative : Int.negSucc w * Int.ofNat h = Int.subNatNat 0 ((w + 1) * h) := by
            calc
              Int.negSucc w * Int.ofNat h = -Int.ofNat ((w + 1) * h) :=
                Int.negSucc_mul_ofNat w h
              _ = Int.subNatNat 0 ((w + 1) * h) := by
                cases (w + 1) * h <;> rfl
          rw [hnegative]
          exact hfit
      | negSucc h =>
          have hhNat : h ≤ compilerNaturalMax := by
            apply compiler_neg_succ_width_bound compilerNaturalMax h
            change Int.negSucc compilerNaturalMax ≤ Int.negSucc h
            exact hhBounds.1
          have hwSucc : w + 1 ≤ compilerNaturalMax + 1 := Nat.add_le_add_right hwNat 1
          have hhSucc : h + 1 ≤ compilerNaturalMax + 1 := Nat.add_le_add_right hhNat 1
          have hproduct : (w + 1) * (h + 1) ≤ compilerInt64MaxNat := by
            calc
              (w + 1) * (h + 1) ≤ (compilerNaturalMax + 1) * (compilerNaturalMax + 1) :=
                Nat.mul_le_mul hwSucc hhSucc
              _ ≤ compilerInt64MaxNat := by decide
          have hfit := compiler_int64_bounds_of_nat compilerInt64MaxNat
            ((w + 1) * (h + 1)) hproduct
          rw [Int.negSucc_mul_negSucc]
          exact hfit

theorem compiler_frame_product_all_int32 (frame : Observation)
    (hw : int32Domain frame.width) (hh : int32Domain frame.height) :
    evalFrameSizeExpr compilerFrameSizeBounds frame compilerFrameSizeProgram.product =
      .ok (frame.width * frame.height) := by
  have hwBounds : compilerWidthMin ≤ frame.width ∧ frame.width ≤ compilerWidthMax := by
    simpa [compilerWidthMin, compilerWidthMax, int32Domain, int32Min, int32Max] using hw
  have hhBounds : compilerWidthMin ≤ frame.height ∧ frame.height ≤ compilerWidthMax := by
    simpa [compilerWidthMin, compilerWidthMax, int32Domain, int32Min, int32Max] using hh
  have hw64 := compiler_int64_contains_width frame.width hwBounds
  have hh64 := compiler_int64_contains_width frame.height hhBounds
  have hwidthFit : (scalarBounds compilerFrameSizeBounds .int64).1 ≤ frame.width ∧
      frame.width ≤ (scalarBounds compilerFrameSizeBounds .int64).2 := by
    change (-9223372036854775808 : Int) ≤ frame.width ∧
      frame.width ≤ (9223372036854775807 : Int)
    exact hw64
  have hheightFit : (scalarBounds compilerFrameSizeBounds .int64).1 ≤ frame.height ∧
      frame.height ≤ (scalarBounds compilerFrameSizeBounds .int64).2 := by
    change (-9223372036854775808 : Int) ≤ frame.height ∧
      frame.height ≤ (9223372036854775807 : Int)
    exact hh64
  have hwidthEval : evalFrameSizeExpr compilerFrameSizeBounds frame
      (.cast .int64 .width) = .ok frame.width := by
    change checkedFrameSizeValue compilerFrameSizeBounds .int64 .rangeCheck frame.width =
      .ok frame.width
    exact checkedFrameSizeValue_ok compilerFrameSizeBounds .int64 .rangeCheck frame.width hwidthFit
  have hheightEval : evalFrameSizeExpr compilerFrameSizeBounds frame
      (.cast .int64 .height) = .ok frame.height := by
    change checkedFrameSizeValue compilerFrameSizeBounds .int64 .rangeCheck frame.height =
      .ok frame.height
    exact checkedFrameSizeValue_ok compilerFrameSizeBounds .int64 .rangeCheck frame.height hheightFit
  have hproductBounds := int32_product_fits_int64 frame.width frame.height hw hh
  have hproductFit : (scalarBounds compilerFrameSizeBounds .int64).1 ≤
      frame.width * frame.height ∧ frame.width * frame.height ≤
        (scalarBounds compilerFrameSizeBounds .int64).2 := by
    change (-9223372036854775808 : Int) ≤ frame.width * frame.height ∧
      frame.width * frame.height ≤ (9223372036854775807 : Int)
    exact hproductBounds
  change (do
    let left ← evalFrameSizeExpr compilerFrameSizeBounds frame (.cast .int64 .width)
    let right ← evalFrameSizeExpr compilerFrameSizeBounds frame (.cast .int64 .height)
    checkedFrameSizeValue compilerFrameSizeBounds .int64 .overflowCheck (left * right)) =
      .ok (frame.width * frame.height)
  rw [hwidthEval, hheightEval]
  exact checkedFrameSizeValue_ok compilerFrameSizeBounds .int64 .overflowCheck
    (frame.width * frame.height) hproductFit

theorem unsigned64_cast_failure_exact (value : Int)
    (hInt64 : -9223372036854775808 ≤ value ∧ value ≤ 9223372036854775807) :
    checkedFrameSizeValue compilerFrameSizeBounds .unsigned64 .rangeCheck value =
      if value < 0 then .error .rangeCheck else .ok value := by
  cases value with
  | ofNat n =>
      have hnInt64 : n ≤ compilerInt64MaxNat := by
        apply int_ofNat_le_toNat n compilerInt64MaxNat
        change Int.ofNat n ≤ Int.ofNat compilerInt64MaxNat
        exact hInt64.2
      have hnUnsigned64 : n ≤ 18446744073709551615 :=
        Nat.le_trans hnInt64 (by decide)
      have hnonnegative : (0 : Int) ≤ Int.ofNat n := by
        change Int.NonNeg (Int.ofNat n)
        exact Int.NonNeg.mk n
      have hfit : (scalarBounds compilerFrameSizeBounds .unsigned64).1 ≤ Int.ofNat n ∧
          Int.ofNat n ≤ (scalarBounds compilerFrameSizeBounds .unsigned64).2 := by
        change (0 : Int) ≤ Int.ofNat n ∧ Int.ofNat n ≤ (18446744073709551615 : Int)
        exact ⟨hnonnegative, int_ofNat_le_ofNat n 18446744073709551615 hnUnsigned64⟩
      have hchecked := checkedFrameSizeValue_ok compilerFrameSizeBounds .unsigned64
        .rangeCheck (Int.ofNat n) hfit
      have hnonneg : ¬ Int.ofNat n < 0 := by
        intro hnegative
        change Int.NonNeg ((0 : Int) - (Int.ofNat n + 1)) at hnegative
        cases n with
        | zero =>
            change Int.NonNeg (Int.negSucc 0) at hnegative
            cases hnegative
        | succ n =>
            change Int.NonNeg (Int.negSucc (n + 1)) at hnegative
            cases hnegative
      simpa only [if_neg hnonneg] using hchecked
  | negSucc n =>
      have hnegative : Int.negSucc n < 0 := compiler_neg_succ_lt_zero n
      have hlow : decide ((0 : Int) ≤ Int.negSucc n) = false := by
        cases hdecide : decide ((0 : Int) ≤ Int.negSucc n) with
        | false => rfl
        | true =>
            have hle := of_decide_eq_true hdecide
            change Int.NonNeg (Int.negSucc n) at hle
            cases hle
      change checkedFrameSizeValue compilerFrameSizeBounds .unsigned64 .rangeCheck (Int.negSucc n) =
        if Int.negSucc n < 0 then .error .rangeCheck else .ok (Int.negSucc n)
      unfold checkedFrameSizeValue
      change (if decide ((0 : Int) ≤ Int.negSucc n) &&
          decide (Int.negSucc n ≤ 18446744073709551615) then
          Except.ok (Int.negSucc n) else Except.error FrameSizeFailure.rangeCheck) =
        if Int.negSucc n < 0 then Except.error FrameSizeFailure.rangeCheck
        else Except.ok (Int.negSucc n)
      rw [hlow, if_pos hnegative]
      rfl

theorem compiler_byte_count_to_int64_safe (frame : Observation)
    (hDomain : observationDomain frame) :
    evalFrameSizeExpr compilerFrameSizeBounds frame (.cast .int64 .byteCount) =
      .ok (Int.ofNat frame.byteCount) := by
  have hcount : frame.byteCount ≤ compilerNaturalMax := by
    simpa [compilerNaturalMax, naturalMax] using hDomain.1
  have hcast := compiler_int64_contains_natural frame.byteCount hcount
  have hnaturalFit : compilerFrameSizeBounds.naturalMin ≤ Int.ofNat frame.byteCount ∧
      Int.ofNat frame.byteCount ≤ compilerFrameSizeBounds.naturalMax := by
    change (Int.ofNat 0 : Int) ≤ Int.ofNat frame.byteCount ∧
      Int.ofNat frame.byteCount ≤ Int.ofNat compilerNaturalMax
    exact ⟨int_ofNat_le_ofNat 0 frame.byteCount (Nat.zero_le _),
      int_ofNat_le_ofNat frame.byteCount compilerNaturalMax hcount⟩
  have hint64Fit : (scalarBounds compilerFrameSizeBounds .int64).1 ≤
      Int.ofNat frame.byteCount ∧ Int.ofNat frame.byteCount ≤
        (scalarBounds compilerFrameSizeBounds .int64).2 := by
    change compilerBounds.int64Min ≤ Int.ofNat frame.byteCount ∧
      Int.ofNat frame.byteCount ≤ compilerBounds.int64Max
    exact hcast
  unfold evalFrameSizeExpr
  have hnaturalLow : decide (compilerFrameSizeBounds.naturalMin ≤
      Int.ofNat frame.byteCount) = true := compiler_decide_true hnaturalFit.1
  have hnaturalHigh : decide (Int.ofNat frame.byteCount ≤
      compilerFrameSizeBounds.naturalMax) = true := compiler_decide_true hnaturalFit.2
  change (if decide (compilerFrameSizeBounds.naturalMin ≤ Int.ofNat frame.byteCount) &&
      decide (Int.ofNat frame.byteCount ≤ compilerFrameSizeBounds.naturalMax) then
      checkedFrameSizeValue compilerFrameSizeBounds .int64 .rangeCheck
        (Int.ofNat frame.byteCount)
    else .error .invalidData) = .ok (Int.ofNat frame.byteCount)
  rw [hnaturalLow, hnaturalHigh]
  exact checkedFrameSizeValue_ok compilerFrameSizeBounds .int64 .rangeCheck
    (Int.ofNat frame.byteCount) hint64Fit

theorem compiler_frame_product_unsigned64_cast (frame : Observation)
    (hw : int32Domain frame.width) (hh : int32Domain frame.height) :
    evalFrameSizeExpr compilerFrameSizeBounds frame
      (.cast .unsigned64 compilerFrameSizeProgram.product) =
        if frame.width * frame.height < 0 then .error .rangeCheck
        else .ok (frame.width * frame.height) := by
  have hProduct := compiler_frame_product_all_int32 frame hw hh
  have hProductBounds := int32_product_fits_int64 frame.width frame.height hw hh
  change (do
      let value ← evalFrameSizeExpr compilerFrameSizeBounds frame
        compilerFrameSizeProgram.product
      checkedFrameSizeValue compilerFrameSizeBounds .unsigned64 .rangeCheck value) = _
  rw [hProduct]
  exact unsigned64_cast_failure_exact (frame.width * frame.height) hProductBounds

theorem compiler_source_size_unsigned64_identity (frame : Observation)
    (hSource : frame.sourceSize < 2^64) :
    evalFrameSizeExpr compilerFrameSizeBounds frame
      (.cast .unsigned64 .sourceSize) = .ok (Int.ofNat frame.sourceSize) := by
  have hmax : frame.sourceSize ≤ 18446744073709551615 := by
    change frame.sourceSize < 18446744073709551616 at hSource
    exact Nat.le_of_lt_succ hSource
  have hfit : (scalarBounds compilerFrameSizeBounds .unsigned64).1 ≤
      Int.ofNat frame.sourceSize ∧ Int.ofNat frame.sourceSize ≤
        (scalarBounds compilerFrameSizeBounds .unsigned64).2 := by
    change (0 : Int) ≤ Int.ofNat frame.sourceSize ∧
      Int.ofNat frame.sourceSize ≤ (18446744073709551615 : Int)
    exact ⟨by
      change Int.NonNeg (Int.ofNat frame.sourceSize)
      exact Int.NonNeg.mk _,
      int_ofNat_le_ofNat frame.sourceSize 18446744073709551615 hmax⟩
  change checkedFrameSizeValue compilerFrameSizeBounds .unsigned64 .rangeCheck
      (Int.ofNat frame.sourceSize) = .ok (Int.ofNat frame.sourceSize)
  exact checkedFrameSizeValue_ok compilerFrameSizeBounds .unsigned64 .rangeCheck
    (Int.ofNat frame.sourceSize) hfit

theorem compiler_int32_max_squared_fits_int64 :
    -9223372036854775808 ≤ (2147483647 : Int) * 2147483647 ∧
      (2147483647 : Int) * 2147483647 ≤ 9223372036854775807 := by
  exact int32_product_fits_int64 2147483647 2147483647
    (by
      change int32Min ≤ (2147483647 : Int) ∧ (2147483647 : Int) ≤ int32Max
      exact ⟨by decide, by decide⟩)
    (by
      change int32Min ≤ (2147483647 : Int) ∧ (2147483647 : Int) ≤ int32Max
      exact ⟨by decide, by decide⟩)

theorem compiler_int32_minimum_squared_fits_int64 :
    -9223372036854775808 ≤ (-2147483648 : Int) * (-2147483648) ∧
      (-2147483648 : Int) * (-2147483648) ≤ 9223372036854775807 := by
  exact int32_product_fits_int64 (-2147483648) (-2147483648)
    (by
      change int32Min ≤ (-2147483648 : Int) ∧ (-2147483648 : Int) ≤ int32Max
      exact ⟨by decide, by decide⟩)
    (by
      change int32Min ≤ (-2147483648 : Int) ∧ (-2147483648 : Int) ≤ int32Max
      exact ⟨by decide, by decide⟩)

theorem compiler_frame_size_size_cast_ok (bounds : FrameSizeBounds) (frame : Observation)
    (expression : FrameSizeExpr) (value : Int)
    (hEval : evalFrameSizeExpr bounds frame expression = .ok value)
    (hFit : (scalarBounds bounds .size).1 ≤ value ∧ value ≤ (scalarBounds bounds .size).2) :
    evalFrameSizeExpr bounds frame (.cast .size expression) = .ok value := by
  change (do
      let castValue ← evalFrameSizeExpr bounds frame expression
      checkedFrameSizeValue bounds .size .rangeCheck castValue) = .ok value
  rw [hEval]
  exact checkedFrameSizeValue_ok bounds .size .rangeCheck value hFit

theorem compiler_frame_size_subtract_ok (bounds : FrameSizeBounds) (frame : Observation)
    (target : FrameSizeScalarType) (left right : FrameSizeExpr) (leftValue rightValue : Int)
    (hLeft : evalFrameSizeExpr bounds frame left = .ok leftValue)
    (hRight : evalFrameSizeExpr bounds frame right = .ok rightValue)
    (hFit : (scalarBounds bounds target).1 ≤ leftValue - rightValue ∧
      leftValue - rightValue ≤ (scalarBounds bounds target).2) :
    evalFrameSizeExpr bounds frame (.subtract target left right) = .ok (leftValue - rightValue) := by
  change (do
      let leftResult ← evalFrameSizeExpr bounds frame left
      let rightResult ← evalFrameSizeExpr bounds frame right
      checkedFrameSizeValue bounds target .overflowCheck (leftResult - rightResult)) =
        .ok (leftValue - rightValue)
  rw [hLeft, hRight]
  exact checkedFrameSizeValue_ok bounds target .overflowCheck (leftValue - rightValue) hFit

theorem compiler_frame_size_add_ok (bounds : FrameSizeBounds) (frame : Observation)
    (target : FrameSizeScalarType) (left right : FrameSizeExpr) (leftValue rightValue : Int)
    (hLeft : evalFrameSizeExpr bounds frame left = .ok leftValue)
    (hRight : evalFrameSizeExpr bounds frame right = .ok rightValue)
    (hFit : (scalarBounds bounds target).1 ≤ leftValue + rightValue ∧
      leftValue + rightValue ≤ (scalarBounds bounds target).2) :
    evalFrameSizeExpr bounds frame (.add target left right) = .ok (leftValue + rightValue) := by
  change (do
      let leftResult ← evalFrameSizeExpr bounds frame left
      let rightResult ← evalFrameSizeExpr bounds frame right
      checkedFrameSizeValue bounds target .overflowCheck (leftResult + rightResult)) =
        .ok (leftValue + rightValue)
  rw [hLeft, hRight]
  exact checkedFrameSizeValue_ok bounds target .overflowCheck (leftValue + rightValue) hFit

theorem compiler_frame_array_length_present (frame : Observation) (first last : Int)
    (content : Nat → UInt8) (hDomain : observationDomain frame)
    (hBytes : frame.bytes = some ⟨first, last, content⟩) :
    evalFrameSizeExpr compilerFrameSizeBounds frame compilerFrameSizeProgram.arrayLength =
      .ok (Int.ofNat (byteLength frame)) := by
  rcases hDomain with ⟨_, _, _, _, _, _, _, hViewDomain⟩
  rw [hBytes] at hViewDomain
  change int32Domain first ∧ int32Domain last ∧ (last < first ∨ 0 < first) at hViewDomain
  rcases hViewDomain with ⟨hFirstDomain, hLastDomain, hShape⟩
  have hFirstBounds : -2147483648 ≤ first ∧ first ≤ 2147483647 := by
    change int32Min ≤ first ∧ first ≤ int32Max at hFirstDomain
    exact hFirstDomain
  have hLastBounds : -2147483648 ≤ last ∧ last ≤ 2147483647 := by
    change int32Min ≤ last ∧ last ≤ int32Max at hLastDomain
    exact hLastDomain
  change evalFrameSizeExpr compilerFrameSizeBounds frame
    (.ifThenElse (.greaterEqual .byteLast .byteFirst)
      (.cast .int64 (.cast .integer
        (.add .size (.subtract .size (.cast .size .byteLast) (.cast .size .byteFirst))
          (.literal 1)))) (.literal 0)) = .ok (Int.ofNat (byteLength frame))
  by_cases hReversed : last < first
  · have hFirstEval : evalFrameSizeExpr compilerFrameSizeBounds frame .byteFirst = .ok first := by
      unfold evalFrameSizeExpr
      rw [hBytes]
    have hLastEval : evalFrameSizeExpr compilerFrameSizeBounds frame .byteLast = .ok last := by
      unfold evalFrameSizeExpr
      rw [hBytes]
    have hPredicate : evalFrameSizePredicate compilerFrameSizeBounds frame
        (.greaterEqual .byteLast .byteFirst) = .ok false := by
      have hFalse : ¬ first ≤ last := by
        intro hFirstLeLast
        cases first with
        | ofNat firstNat =>
            cases last with
            | ofNat lastNat =>
                have hLastLtFirst : lastNat < firstNat :=
                  int_ofNat_lt_toNat lastNat firstNat hReversed
                have hFirstLeLastNat : firstNat ≤ lastNat :=
                  int_ofNat_le_toNat firstNat lastNat hFirstLeLast
                exact Nat.not_le_of_gt hLastLtFirst hFirstLeLastNat
            | negSucc lastNeg =>
                change Int.NonNeg (Int.negSucc lastNeg - Int.ofNat firstNat) at hFirstLeLast
                cases firstNat with
                | zero =>
                    change Int.NonNeg (Int.negSucc lastNeg) at hFirstLeLast
                    cases hFirstLeLast
                | succ firstNat =>
                    change Int.NonNeg (Int.negSucc (Nat.succ (lastNeg + firstNat))) at hFirstLeLast
                    cases hFirstLeLast
        | negSucc firstNeg =>
            cases last with
            | ofNat lastNat =>
                change Int.NonNeg (Int.negSucc firstNeg - (Int.ofNat lastNat + 1)) at hReversed
                cases hReversed
            | negSucc lastNeg =>
                cases lastNeg with
                | zero =>
                    change Int.NonNeg (Int.negSucc firstNeg - (Int.negSucc 0 + 1)) at hReversed
                    change Int.NonNeg (Int.negSucc firstNeg) at hReversed
                    cases hReversed
                | succ lastNat =>
                    change Int.NonNeg
                      (Int.negSucc firstNeg - (Int.negSucc (Nat.succ lastNat) + 1)) at hReversed
                    change Int.NonNeg
                      (Int.subNatNat (Nat.succ lastNat) (Nat.succ firstNeg)) at hReversed
                    have hReverseNat : firstNeg ≤ lastNat := by
                      cases hsub : firstNeg - lastNat with
                      | zero => exact Nat.le_of_sub_eq_zero hsub
                      | succ k =>
                          unfold Int.subNatNat at hReversed
                          rw [Nat.succ_sub_succ, hsub] at hReversed
                          cases hReversed
                    have hLeNat : Nat.succ lastNat ≤ firstNeg := by
                      change Int.NonNeg
                        (Int.negSucc (Nat.succ lastNat) - Int.negSucc firstNeg) at hFirstLeLast
                      change Int.NonNeg
                        (Int.subNatNat (Nat.succ firstNeg) (Nat.succ (Nat.succ lastNat)))
                        at hFirstLeLast
                      cases hsub : Nat.succ lastNat - firstNeg with
                      | zero => exact Nat.le_of_sub_eq_zero hsub
                      | succ k =>
                          unfold Int.subNatNat at hFirstLeLast
                          rw [Nat.succ_sub_succ, hsub] at hFirstLeLast
                          cases hFirstLeLast
                    exact Nat.not_le_of_gt (Nat.lt_succ_of_le hReverseNat) hLeNat
      have hGeFalse : decide (first ≤ last) = false := compiler_decide_false hFalse
      unfold evalFrameSizePredicate
      change (do
          let left ← evalFrameSizeExpr compilerFrameSizeBounds frame .byteLast
          let right ← evalFrameSizeExpr compilerFrameSizeBounds frame .byteFirst
          Except.ok (decide (left ≥ right))) = .ok false
      rw [hLastEval, hFirstEval]
      change Except.ok (decide (first ≤ last)) = .ok false
      rw [hGeFalse]
    have hModelLength : Int.ofNat (byteLength frame) = 0 := by
      unfold byteLength
      rw [hBytes]
      change Int.ofNat (if last < first then 0 else (last - first + 1).toNat) = 0
      rw [if_pos hReversed]
      rfl
    change (do
        let condition ← evalFrameSizePredicate compilerFrameSizeBounds frame
          (.greaterEqual .byteLast .byteFirst)
        if condition then
          evalFrameSizeExpr compilerFrameSizeBounds frame
            (.cast .int64 (.cast .integer (.add .size
              (.subtract .size (.cast .size .byteLast) (.cast .size .byteFirst)) (.literal 1))))
        else evalFrameSizeExpr compilerFrameSizeBounds frame (.literal 0)) = _
    rw [hPredicate, hModelLength]
    rfl
  · have hFirstPositive : 0 < first := by
      rcases hShape with hViewReversed | hPositive
      · exact False.elim (hReversed hViewReversed)
      · exact hPositive
    have hFirstPositiveBool : decide (first ≤ 0) = false := by
      cases first with
      | ofNat n =>
          cases n with
          | zero => cases hFirstPositive
          | succ n => exact int_ofNat_lt_decide_ge_false 0 (Nat.succ n) (Nat.zero_lt_succ n)
      | negSucc n => cases hFirstPositive
    obtain ⟨firstOffset, hFirstAsNat⟩ := positive_int_to_nat first hFirstPositiveBool
    have hFirstEval : evalFrameSizeExpr compilerFrameSizeBounds frame .byteFirst = .ok first := by
      unfold evalFrameSizeExpr
      rw [hBytes]
    have hLastEval : evalFrameSizeExpr compilerFrameSizeBounds frame .byteLast = .ok last := by
      unfold evalFrameSizeExpr
      rw [hBytes]
    have hNotReversed : ¬ last < first := hReversed
    have hLastPositive : 0 < last := by
      cases last with
      | ofNat n =>
          cases n with
          | zero =>
              have hLtDecide := compiler_int_ofNat_lt_decide_true
                0 (Nat.succ firstOffset) (Nat.zero_lt_succ _)
              have hLt : (Int.ofNat 0 : Int) < Int.ofNat (Nat.succ firstOffset) :=
                of_decide_eq_true hLtDecide
              have hLtFrame : (Int.ofNat 0 : Int) < first := by
                rw [hFirstAsNat]
                exact hLt
              exact False.elim (hNotReversed hLtFrame)
          | succ n =>
              have hLtDecide := compiler_int_ofNat_lt_decide_true
                0 (Nat.succ n) (Nat.zero_lt_succ n)
              exact of_decide_eq_true hLtDecide
      | negSucc n =>
          have hLt : (Int.negSucc n : Int) < Int.ofNat (Nat.succ firstOffset) := by
            change Int.NonNeg (Int.ofNat (Nat.succ firstOffset) - (Int.negSucc n + 1))
            cases n with
            | zero =>
                change Int.NonNeg (Int.ofNat (Nat.succ firstOffset))
                exact Int.NonNeg.mk _
            | succ n =>
                change Int.NonNeg (Int.ofNat (Nat.succ firstOffset + Nat.succ n))
                exact Int.NonNeg.mk _
          have hLtFrame : (Int.negSucc n : Int) < first := by
            rw [hFirstAsNat]
            exact hLt
          exact False.elim (hNotReversed hLtFrame)
    have hLastPositiveBool : decide (last ≤ 0) = false := by
      cases last with
      | ofNat n =>
          cases n with
          | zero => cases hLastPositive
          | succ n => exact int_ofNat_lt_decide_ge_false 0 (Nat.succ n) (Nat.zero_lt_succ n)
      | negSucc n => cases hLastPositive
    obtain ⟨lastOffset, hLastAsNat⟩ := positive_int_to_nat last hLastPositiveBool
    have hFirstNatMax : Nat.succ firstOffset ≤ 2147483647 := by
      have hFirstIntMax : (Int.ofNat (Nat.succ firstOffset) : Int) ≤ Int.ofNat 2147483647 := by
        rw [← hFirstAsNat]
        exact hFirstBounds.2
      exact int_ofNat_le_toNat _ _ hFirstIntMax
    have hLastNatMax : Nat.succ lastOffset ≤ 2147483647 := by
      have hLastIntMax : (Int.ofNat (Nat.succ lastOffset) : Int) ≤ Int.ofNat 2147483647 := by
        rw [← hLastAsNat]
        exact hLastBounds.2
      exact int_ofNat_le_toNat _ _ hLastIntMax
    have hNatLE : Nat.succ firstOffset ≤ Nat.succ lastOffset := by
      apply Nat.le_of_not_lt
      intro hLastLtFirst
      have hLtDecide := compiler_int_ofNat_lt_decide_true
        (Nat.succ lastOffset) (Nat.succ firstOffset) hLastLtFirst
      have hLt : (Int.ofNat (Nat.succ lastOffset) : Int) < Int.ofNat (Nat.succ firstOffset) :=
        of_decide_eq_true hLtDecide
      have hLtFrame : last < first := by
        rw [hLastAsNat, hFirstAsNat]
        exact hLt
      exact hNotReversed hLtFrame
    have hGe : last ≥ first := by
      rw [hLastAsNat, hFirstAsNat]
      exact int_ofNat_le_ofNat (Nat.succ firstOffset) (Nat.succ lastOffset) hNatLE
    have hFirstSizeFit : (scalarBounds compilerFrameSizeBounds .size).1 ≤ first ∧
        first ≤ (scalarBounds compilerFrameSizeBounds .size).2 := by
      change 0 ≤ first ∧ first ≤ 4294967295
      rw [hFirstAsNat]
      constructor
      · exact Int.NonNeg.mk _
      · exact int_ofNat_le_ofNat (Nat.succ firstOffset) 4294967295
          (Nat.le_trans hFirstNatMax (by decide))
    have hLastSizeFit : (scalarBounds compilerFrameSizeBounds .size).1 ≤ last ∧
        last ≤ (scalarBounds compilerFrameSizeBounds .size).2 := by
      change 0 ≤ last ∧ last ≤ 4294967295
      rw [hLastAsNat]
      constructor
      · exact Int.NonNeg.mk _
      · exact int_ofNat_le_ofNat (Nat.succ lastOffset) 4294967295
          (Nat.le_trans hLastNatMax (by decide))
    have hFirstSizeEval := compiler_frame_size_size_cast_ok compilerFrameSizeBounds frame
      .byteFirst first hFirstEval hFirstSizeFit
    have hLastSizeEval := compiler_frame_size_size_cast_ok compilerFrameSizeBounds frame
      .byteLast last hLastEval hLastSizeFit
    have hDifferenceExpr : last - first =
        Int.ofNat (Nat.succ lastOffset - Nat.succ firstOffset) := by
      rw [hLastAsNat, hFirstAsNat]
      change Int.add (Int.ofNat (Nat.succ lastOffset))
        (Int.neg (Int.ofNat (Nat.succ firstOffset))) = _
      change Int.add (Int.ofNat (Nat.succ lastOffset)) (Int.negSucc firstOffset) = _
      change Int.subNatNat (Nat.succ lastOffset) (Nat.succ firstOffset) = _
      have hZero : Nat.succ firstOffset - Nat.succ lastOffset = 0 :=
        nat_sub_zero_of_le hNatLE
      unfold Int.subNatNat
      rw [hZero]
    have hDifferencePlusOneUpper :
        (Nat.succ lastOffset - Nat.succ firstOffset) + 1 ≤ Nat.succ lastOffset := by
      change Nat.succ (Nat.succ lastOffset - Nat.succ firstOffset) ≤ Nat.succ lastOffset
      rw [Nat.succ_sub_succ]
      exact Nat.succ_le_succ (Nat.sub_le _ _)
    have hLengthNatUpper :
        (Nat.succ lastOffset - Nat.succ firstOffset) + 1 ≤ 2147483647 :=
      Nat.le_trans hDifferencePlusOneUpper hLastNatMax
    have hLengthNatLower :
        1 ≤ (Nat.succ lastOffset - Nat.succ firstOffset) + 1 := by
      change Nat.succ 0 ≤ Nat.succ (Nat.succ lastOffset - Nat.succ firstOffset)
      exact Nat.succ_le_succ (Nat.zero_le _)
    have hDifferenceNatMax : Nat.succ lastOffset - Nat.succ firstOffset ≤ 2147483646 := by
      apply Nat.le_of_succ_le_succ
      change Nat.succ (Nat.succ lastOffset - Nat.succ firstOffset) ≤ Nat.succ 2147483646
      exact hLengthNatUpper
    have hDifference : 0 ≤ last - first ∧ last - first ≤ 2147483646 := by
      rw [hDifferenceExpr]
      constructor
      · exact Int.NonNeg.mk _
      · exact int_ofNat_le_ofNat _ _ hDifferenceNatMax
    have hDifferenceSizeFit : (scalarBounds compilerFrameSizeBounds .size).1 ≤ last - first ∧
        last - first ≤ (scalarBounds compilerFrameSizeBounds .size).2 := by
      change 0 ≤ last - first ∧ last - first ≤ 4294967295
      rw [hDifferenceExpr]
      constructor
      · exact Int.NonNeg.mk _
      · exact int_ofNat_le_ofNat _ _ (Nat.le_trans hDifferenceNatMax (by decide))
    have hDifferenceEval := compiler_frame_size_subtract_ok compilerFrameSizeBounds frame .size
      (.cast .size .byteLast) (.cast .size .byteFirst) last first
      hLastSizeEval hFirstSizeEval hDifferenceSizeFit
    have hLengthExpr : last - first + 1 =
        Int.ofNat ((Nat.succ lastOffset - Nat.succ firstOffset) + 1) := by
      rw [hDifferenceExpr]
      change Int.ofNat (Nat.succ lastOffset - Nat.succ firstOffset) + Int.ofNat 1 = _
      exact (Int.ofNat_add (Nat.succ lastOffset - Nat.succ firstOffset) 1).symm
    have hLength : 1 ≤ last - first + 1 ∧ last - first + 1 ≤ 2147483647 := by
      rw [hLengthExpr]
      exact ⟨int_ofNat_le_ofNat _ _ hLengthNatLower,
        int_ofNat_le_ofNat _ _ hLengthNatUpper⟩
    have hOneEval : evalFrameSizeExpr compilerFrameSizeBounds frame (.literal 1) = .ok 1 := rfl
    have hLengthSizeFit : (scalarBounds compilerFrameSizeBounds .size).1 ≤ last - first + 1 ∧
        last - first + 1 ≤ (scalarBounds compilerFrameSizeBounds .size).2 := by
      change 0 ≤ last - first + 1 ∧ last - first + 1 ≤ 4294967295
      rw [hLengthExpr]
      exact ⟨Int.NonNeg.mk _, int_ofNat_le_ofNat _ _
        (Nat.le_trans hLengthNatUpper (by decide))⟩
    have hLengthSizeEval := compiler_frame_size_add_ok compilerFrameSizeBounds frame .size
      (.subtract .size (.cast .size .byteLast) (.cast .size .byteFirst)) (.literal 1)
      (last - first) 1 hDifferenceEval hOneEval hLengthSizeFit
    have hLengthIntegerFit : (scalarBounds compilerFrameSizeBounds .integer).1 ≤
        last - first + 1 ∧ last - first + 1 ≤
          (scalarBounds compilerFrameSizeBounds .integer).2 := by
      change -2147483648 ≤ last - first + 1 ∧ last - first + 1 ≤ 2147483647
      rw [hLengthExpr]
      exact compiler_int64_bounds_of_nat 2147483647
        ((Nat.succ lastOffset - Nat.succ firstOffset) + 1) hLengthNatUpper
    have hLengthIntegerEval : evalFrameSizeExpr compilerFrameSizeBounds frame
        (.cast .integer (.add .size
        (.subtract .size (.cast .size .byteLast) (.cast .size .byteFirst)) (.literal 1))
        ) = .ok (last - first + 1) := by
      change (do
          let castValue ← evalFrameSizeExpr compilerFrameSizeBounds frame
            (.add .size (.subtract .size (.cast .size .byteLast) (.cast .size .byteFirst))
              (.literal 1))
          checkedFrameSizeValue compilerFrameSizeBounds .integer .rangeCheck castValue) = _
      rw [hLengthSizeEval]
      exact checkedFrameSizeValue_ok compilerFrameSizeBounds .integer .rangeCheck
        (last - first + 1) hLengthIntegerFit
    have hLengthInt64Fit : (scalarBounds compilerFrameSizeBounds .int64).1 ≤
        last - first + 1 ∧ last - first + 1 ≤
          (scalarBounds compilerFrameSizeBounds .int64).2 := by
      change -9223372036854775808 ≤ last - first + 1 ∧
        last - first + 1 ≤ 9223372036854775807
      rw [hLengthExpr]
      exact compiler_int64_bounds_of_nat 9223372036854775807
        ((Nat.succ lastOffset - Nat.succ firstOffset) + 1)
        (Nat.le_trans hLengthNatUpper (by decide))
    have hLengthInt64Eval : evalFrameSizeExpr compilerFrameSizeBounds frame
        (.cast .int64 (.cast .integer (.add .size
          (.subtract .size (.cast .size .byteLast) (.cast .size .byteFirst)) (.literal 1)))) =
        .ok (last - first + 1) := by
      change (do
          let castValue ← evalFrameSizeExpr compilerFrameSizeBounds frame
            (.cast .integer (.add .size
              (.subtract .size (.cast .size .byteLast) (.cast .size .byteFirst)) (.literal 1)))
          checkedFrameSizeValue compilerFrameSizeBounds .int64 .rangeCheck castValue) = _
      rw [hLengthIntegerEval]
      exact checkedFrameSizeValue_ok compilerFrameSizeBounds .int64 .rangeCheck
        (last - first + 1) hLengthInt64Fit
    have hModelLength : Int.ofNat (byteLength frame) = last - first + 1 := by
      unfold byteLength
      rw [hBytes]
      change Int.ofNat (if last < first then 0 else (last - first + 1).toNat) = last - first + 1
      rw [if_neg hReversed]
      rw [hLengthExpr]
      exact congrArg Int.ofNat (Int.toNat_ofNat _)
    have hFirstLELast : first ≤ last := hGe
    have hGeTrue : decide (first ≤ last) = true := compiler_decide_true hFirstLELast
    have hLengthPredicate : evalFrameSizePredicate compilerFrameSizeBounds frame
        (.greaterEqual .byteLast .byteFirst) = .ok true := by
      unfold evalFrameSizePredicate
      change (do
          let left ← evalFrameSizeExpr compilerFrameSizeBounds frame .byteLast
          let right ← evalFrameSizeExpr compilerFrameSizeBounds frame .byteFirst
          Except.ok (decide (left ≥ right))) = .ok true
      rw [hLastEval, hFirstEval]
      change Except.ok (decide (first ≤ last)) = .ok true
      rw [hGeTrue]
    change (do
        let condition ← evalFrameSizePredicate compilerFrameSizeBounds frame
          (.greaterEqual .byteLast .byteFirst)
        if condition then
          evalFrameSizeExpr compilerFrameSizeBounds frame
            (.cast .int64 (.cast .integer (.add .size
              (.subtract .size (.cast .size .byteLast) (.cast .size .byteFirst)) (.literal 1))))
        else evalFrameSizeExpr compilerFrameSizeBounds frame (.literal 0)) = _
    rw [hLengthPredicate]
    change evalFrameSizeExpr compilerFrameSizeBounds frame
      (.cast .int64 (.cast .integer (.add .size
        (.subtract .size (.cast .size .byteLast) (.cast .size .byteFirst)) (.literal 1)))) =
        .ok (Int.ofNat (byteLength frame))
    rw [hLengthInt64Eval, hModelLength]

theorem compiler_frame_array_length_null_access_fails (frame : Observation)
    (hBytes : frame.bytes = none) :
    evalFrameSizeExpr compilerFrameSizeBounds frame compilerFrameSizeProgram.arrayLength =
      .error .accessCheck := by
  change evalFrameSizeExpr compilerFrameSizeBounds frame
    (.ifThenElse (.greaterEqual .byteLast .byteFirst)
      (.cast .int64 (.cast .integer
        (.add .size (.subtract .size (.cast .size .byteLast) (.cast .size .byteFirst))
          (.literal 1)))) (.literal 0)) = .error .accessCheck
  have hLastError : evalFrameSizeExpr compilerFrameSizeBounds frame .byteLast = .error .accessCheck := by
    unfold evalFrameSizeExpr
    rw [hBytes]
  have hLengthPredicate : evalFrameSizePredicate compilerFrameSizeBounds frame
      (.greaterEqual .byteLast .byteFirst) = .error .accessCheck := by
    unfold evalFrameSizePredicate
    change (do
        let left ← evalFrameSizeExpr compilerFrameSizeBounds frame .byteLast
        let right ← evalFrameSizeExpr compilerFrameSizeBounds frame .byteFirst
        Except.ok (decide (left ≥ right))) = .error .accessCheck
    rw [hLastError]
    rfl
  change (do
      let condition ← evalFrameSizePredicate compilerFrameSizeBounds frame
        (.greaterEqual .byteLast .byteFirst)
      if condition then
        evalFrameSizeExpr compilerFrameSizeBounds frame
          (.cast .int64 (.cast .integer (.add .size
            (.subtract .size (.cast .size .byteLast) (.cast .size .byteFirst)) (.literal 1))))
      else evalFrameSizeExpr compilerFrameSizeBounds frame (.literal 0)) = .error .accessCheck
  rw [hLengthPredicate]
  rfl

def productBoundaryFrame (width height : Int) (sourceSize byteCount : Nat)
    (first last : Int) (present : Bool) : Observation := {
  acquisitionStatus := .success
  byteCount := byteCount
  bytes := if present then some ⟨first, last, fun _ => byteZero⟩ else none
  bufferStatus := 0
  payloadType := 1
  pixelFormat := 17301505
  width := width
  height := height
  sourceSize := sourceSize
}

theorem compiler_frame_size_dimensions_eval (frame : Observation) :
    evalFrameSizePredicate compilerFrameSizeBounds frame compilerFrameSizeProgram.dimensions =
      .ok (decide (frame.width ≤ 0) || decide (frame.height ≤ 0)) := by
  change evalFrameSizePredicate compilerFrameSizeBounds frame
    (.orElse (.lessEqual .width (.literal 0)) (.lessEqual .height (.literal 0))) = _
  have hWidth : evalFrameSizePredicate compilerFrameSizeBounds frame
      (.lessEqual .width (.literal 0)) = .ok (decide (frame.width ≤ 0)) := by
    unfold evalFrameSizePredicate
    rfl
  have hHeight : evalFrameSizePredicate compilerFrameSizeBounds frame
      (.lessEqual .height (.literal 0)) = .ok (decide (frame.height ≤ 0)) := by
    unfold evalFrameSizePredicate
    rfl
  unfold evalFrameSizePredicate
  change (do
      let left ← evalFrameSizePredicate compilerFrameSizeBounds frame
        (.lessEqual .width (.literal 0))
      if left then pure true else
        (evalFrameSizePredicate compilerFrameSizeBounds frame (.lessEqual .height (.literal 0)))) = _
  rw [hWidth]
  cases hBool : decide (frame.width ≤ 0) with
  | true => rfl
  | false => rw [hHeight]; rfl

theorem compiler_frame_size_limit_eval (frame : Observation)
    (hDomain : observationDomain frame) :
    evalFrameSizePredicate compilerFrameSizeBounds frame compilerFrameSizeProgram.limit =
      .ok (decide (frame.width * frame.height > 2147483647)) := by
  have hProduct := compiler_frame_product_all_int32 frame
    hDomain.2.2.2.2.1 hDomain.2.2.2.2.2.1
  change evalFrameSizePredicate compilerFrameSizeBounds frame
    (.greater (.multiply .int64 (.cast .int64 .width) (.cast .int64 .height))
      (.literal 2147483647)) = _
  unfold evalFrameSizePredicate
  change (do
      let left ← evalFrameSizeExpr compilerFrameSizeBounds frame
        (.multiply .int64 (.cast .int64 .width) (.cast .int64 .height))
      let right ← evalFrameSizeExpr compilerFrameSizeBounds frame (.literal 2147483647)
      pure (decide (left > right))) = _
  have hProductEval : evalFrameSizeExpr compilerFrameSizeBounds frame
      (.multiply .int64 (.cast .int64 .width) (.cast .int64 .height)) =
        .ok (frame.width * frame.height) := by
    change evalFrameSizeExpr compilerFrameSizeBounds frame compilerFrameSizeProgram.product = _
    exact hProduct
  rw [hProductEval]
  rfl

theorem frame_size_success_at_strict_maximum :
    frameSizeSuffix
      (productBoundaryFrame 2147483647 1 2147483647 2147483647 1 2147483647 true) =
        .success := by
  decide

theorem frame_size_strict_maximum_plus_one_is_too_large :
    frameSizeSuffix (productBoundaryFrame 1073741824 2 0 0 0 0 false) = .tooLarge := by
  decide

theorem frame_size_int32_minimum_is_invalid_dimensions :
    frameSizeSuffix (productBoundaryFrame (-2147483648) (-2147483648) 0 0 0 0 false) =
      .invalidDimensions := by
  decide

theorem frame_size_zero_dimension_is_invalid_dimensions :
    frameSizeSuffix (productBoundaryFrame 0 2147483647 0 0 0 0 false) =
      .invalidDimensions := by
  decide

theorem frame_size_unsigned64_max_source_size_is_invalid_length :
    frameSizeSuffix (productBoundaryFrame 1 1 18446744073709551615 1 1 1 true) =
      .invalidLength := by
  decide

theorem frame_size_short_byte_view_is_invalid_length :
    frameSizeSuffix (productBoundaryFrame 2 2 4 4 1 3 true) = .invalidLength := by
  decide

theorem frame_size_long_byte_view_is_invalid_length :
    frameSizeSuffix (productBoundaryFrame 2 2 4 4 1 5 true) = .invalidLength := by
  decide

theorem frame_size_zero_byte_view_is_invalid_length :
    frameSizeSuffix (productBoundaryFrame 1 1 0 0 1 0 true) = .invalidLength := by
  decide

theorem frame_size_absent_byte_view_is_invalid_length :
    frameSizeSuffix (productBoundaryFrame 1 1 1 1 0 0 false) = .invalidLength := by
  decide

theorem frame_size_non_one_first_bound_is_invalid_length :
    frameSizeSuffix (productBoundaryFrame 1 1 1 1 2 2 true) = .invalidLength := by
  decide

theorem frame_size_reversed_byte_bounds_are_invalid_length :
    frameSizeSuffix (productBoundaryFrame 1 1 0 0 2 1 true) = .invalidLength := by
  decide

theorem frame_size_inconsistent_source_count_is_invalid_length :
    frameSizeSuffix (productBoundaryFrame 2 2 3 3 1 4 true) = .invalidLength := by
  decide

theorem frame_size_inconsistent_byte_count_is_invalid_length :
    frameSizeSuffix (productBoundaryFrame 2 2 4 3 1 4 true) = .invalidLength := by
  decide

theorem frame_size_exact_size_success :
    frameSizeSuffix (productBoundaryFrame 2 2 4 4 1 4 true) = .success := by
  decide

theorem frame_size_bridge_to_grab_status_prefix (state : CameraState) (timeout : Nat)
    (frame : Observation) (hPrefix : frameSizePrefixPassed state timeout frame) :
    Model.grabStatus state timeout frame = frameSizeSuffix frame := by
  rcases hPrefix with ⟨hs, ht, htb, ha, hb, hp, hf⟩
  subst state
  have hNotCalled : (frame.acquisitionStatus == NativeResult.notCalled) = false := by
    rw [ha]
    decide
  have hBadParameter : (frame.acquisitionStatus == NativeResult.badParameter) = false := by
    rw [ha]
    decide
  have hTimeout : (frame.acquisitionStatus == NativeResult.timeout) = false := by
    rw [ha]
    decide
  have hMemory : (frame.acquisitionStatus == NativeResult.outOfMemory) = false := by
    rw [ha]
    decide
  have hUnsupported : (frame.acquisitionStatus == NativeResult.unsupported) = false := by
    rw [ha]
    decide
  have hError : (frame.acquisitionStatus == NativeResult.error) = false := by
    rw [ha]
    decide
  have hState : (CameraState.streaming != CameraState.streaming) = false := by decide
  have hTimeoutNZ : (timeout == 0) = false := by
    cases timeout with
    | zero => exact False.elim (Nat.lt_irrefl 0 ht)
    | succ _ => rfl
  have hBufferTimeout : (frame.bufferStatus == 2) = false := by
    rw [hb]
    cases hbeq : ((0 : Int) == 2) with
    | false => rfl
    | true =>
        have heq := int_beq_true_eq 0 2 hbeq
        cases heq
  have hBufferError : (frame.bufferStatus != 0) = false := by
    rw [hb]
    change (!(decide ((0 : Int) = 0))) = false
    have hdec : decide ((0 : Int) = 0) = true := rfl
    rw [hdec]
    rfl
  have hPayload : (frame.payloadType != 1) = false := by
    rw [hp]
    change (!(decide ((1 : Int) = 1))) = false
    have hdec : decide ((1 : Int) = 1) = true := rfl
    rw [hdec]
    rfl
  have hFormat : (frame.pixelFormat != 17301505) = false := by
    rw [hf]
    change (!(decide ((17301505 : Int) = 17301505))) = false
    have hdec : decide ((17301505 : Int) = 17301505) = true := rfl
    rw [hdec]
    rfl
  unfold Model.grabStatus frameSizeSuffix
  rw [hState, hTimeoutNZ, hNotCalled, hBadParameter, hTimeout, hMemory, hUnsupported,
    hError, hBufferTimeout, hBufferError, hPayload, hFormat]
  rfl

theorem compiler_frame_size_check_false_ok (bounds : FrameSizeBounds) (frame : Observation)
    (failure : FrameSizeFailure) (condition : FrameSizePredicate)
    (hCondition : evalFrameSizePredicate bounds frame condition = .ok false) :
    evalFrameSizeExpr bounds frame (.check failure condition) = .ok (0 : Int) := by
  unfold evalFrameSizeExpr
  change (do
      if ← evalFrameSizePredicate bounds frame condition then .error failure else .ok (0 : Int)) =
        .ok (0 : Int)
  rw [hCondition]
  rfl

theorem compiler_frame_size_sequence_predicate_ok (bounds : FrameSizeBounds)
    (frame : Observation) (first : FrameSizeExpr) (second : FrameSizePredicate)
    (value : Int) (result : Bool)
    (hFirst : evalFrameSizeExpr bounds frame first = .ok value)
    (hSecond : evalFrameSizePredicate bounds frame second = .ok result) :
    evalFrameSizePredicate bounds frame (.sequence first second) = .ok result := by
  unfold evalFrameSizePredicate
  change (do
      let _ ← evalFrameSizeExpr bounds frame first
      evalFrameSizePredicate bounds frame second) = .ok result
  rw [hFirst, hSecond]
  rfl

theorem compiler_frame_size_or_else_ok (bounds : FrameSizeBounds) (frame : Observation)
    (left right : FrameSizePredicate) (leftValue rightValue : Bool)
    (hLeft : evalFrameSizePredicate bounds frame left = .ok leftValue)
    (hRight : evalFrameSizePredicate bounds frame right = .ok rightValue) :
    evalFrameSizePredicate bounds frame (.orElse left right) =
      .ok (leftValue || rightValue) := by
  unfold evalFrameSizePredicate
  change (do
      let value ← evalFrameSizePredicate bounds frame left
      if value then pure true else evalFrameSizePredicate bounds frame right) = _
  rw [hLeft]
  cases leftValue with
  | true => rfl
  | false => rw [hRight]; rfl

theorem compiler_frame_size_or_else_true_left (bounds : FrameSizeBounds) (frame : Observation)
    (left right : FrameSizePredicate)
    (hLeft : evalFrameSizePredicate bounds frame left = .ok true) :
    evalFrameSizePredicate bounds frame (.orElse left right) = .ok true := by
  unfold evalFrameSizePredicate
  change (do
      let value ← evalFrameSizePredicate bounds frame left
      if value then pure true else evalFrameSizePredicate bounds frame right) = .ok true
  rw [hLeft]
  rfl

theorem compiler_frame_size_invalid_length_eval (frame : Observation)
    (hDomain : observationDomain frame)
    (hDimensionsFalse : (decide (frame.width ≤ 0) || decide (frame.height ≤ 0)) = false) :
    evalFrameSizePredicate compilerFrameSizeBounds frame compilerFrameSizeProgram.invalidLength =
      .ok (frame.sourceSize != Int.toNat (frame.width * frame.height) ||
        Int.ofNat frame.byteCount != frame.width * frame.height || frame.bytes.isNone ||
        byteFirst frame != 1 || Int.ofNat (byteLength frame) != frame.width * frame.height) := by
  have hBoolParts := bool_or_eq_false_components
    (decide (frame.width ≤ 0)) (decide (frame.height ≤ 0)) hDimensionsFalse
  have hWidthBool := hBoolParts.1
  have hHeightBool := hBoolParts.2
  obtain ⟨widthOffset, hWidthNat⟩ := positive_int_to_nat frame.width hWidthBool
  obtain ⟨heightOffset, hHeightNat⟩ := positive_int_to_nat frame.height hHeightBool
  let productExpr : FrameSizeExpr :=
    .multiply .int64 (.cast .int64 .width) (.cast .int64 .height)
  let sourceMismatch : Bool := frame.sourceSize != Int.toNat (frame.width * frame.height)
  let countMismatch : Bool := Int.ofNat frame.byteCount != frame.width * frame.height
  let firstMismatch : Bool := byteFirst frame != 1
  let lengthMismatch : Bool := Int.ofNat (byteLength frame) != frame.width * frame.height
  let rangeCondition : FrameSizePredicate := .less productExpr (.literal 0)
  let sourceCompare : FrameSizePredicate := .notEqual
    (.cast .unsigned64 .sourceSize) (.cast .unsigned64 productExpr)
  let countCondition : FrameSizePredicate := .less .byteCount (.literal 0)
  let countCheck : FrameSizeExpr := .check .invalidData countCondition
  let countCompare : FrameSizePredicate := .notEqual
    (.cast .int64 .byteCount) productExpr
  let sourceBranch : FrameSizePredicate :=
    .sequence (.check .rangeCheck rangeCondition) sourceCompare
  let countBranch : FrameSizePredicate :=
    .sequence (.sequence countCheck countCheck) countCompare
  let nullBranch : FrameSizePredicate := .bytesNull
  let firstBranch : FrameSizePredicate := .sequence
    (.check .accessCheck nullBranch) (.notEqual .byteFirst (.literal 1))
  let lengthBranch : FrameSizePredicate := .sequence
    (.check .accessCheck nullBranch)
    (.notEqual
      (.ifThenElse (.greaterEqual .byteLast .byteFirst)
        (.cast .int64 (.cast .integer (.add .size
          (.subtract .size (.cast .size .byteLast) (.cast .size .byteFirst)) (.literal 1))))
        (.literal 0)) productExpr)
  have hInvalidShape : compilerFrameSizeProgram.invalidLength =
      ((((sourceBranch.orElse countBranch).orElse nullBranch).orElse firstBranch).orElse lengthBranch) := by
    rfl
  have hProductEval : evalFrameSizeExpr compilerFrameSizeBounds frame productExpr =
      .ok (frame.width * frame.height) := by
    change evalFrameSizeExpr compilerFrameSizeBounds frame compilerFrameSizeProgram.product = _
    exact compiler_frame_product_all_int32 frame
      hDomain.2.2.2.2.1 hDomain.2.2.2.2.2.1
  have hProductNat : frame.width * frame.height =
      Int.ofNat ((Nat.succ widthOffset) * (Nat.succ heightOffset)) := by
    rw [hWidthNat, hHeightNat]
    exact Int.ofNat_mul _ _
  have hOfNatNotNegative (value : Nat) : ¬ Int.ofNat value < 0 := by
    intro hNegative
    change Int.NonNeg ((0 : Int) - (Int.ofNat value + 1)) at hNegative
    cases value with
    | zero => change Int.NonNeg (Int.negSucc 0) at hNegative; cases hNegative
    | succ value => change Int.NonNeg (Int.negSucc (value + 1)) at hNegative; cases hNegative
  have hProductLessFalse : decide (frame.width * frame.height < 0) = false := by
    rw [hProductNat]
    exact compiler_decide_false (hOfNatNotNegative _)
  have hRangePredicate : evalFrameSizePredicate compilerFrameSizeBounds frame rangeCondition =
      .ok false := by
    unfold evalFrameSizePredicate
    change (do
        let left ← evalFrameSizeExpr compilerFrameSizeBounds frame productExpr
        let right ← evalFrameSizeExpr compilerFrameSizeBounds frame (.literal 0)
        pure (decide (left < right))) = .ok false
    rw [hProductEval]
    change Except.ok (decide (frame.width * frame.height < 0)) = Except.ok false
    rw [hProductLessFalse]
  have hRangeCheck : evalFrameSizeExpr compilerFrameSizeBounds frame
      (.check .rangeCheck rangeCondition) = .ok 0 :=
    compiler_frame_size_check_false_ok _ _ _ _ hRangePredicate
  have hSourceCast := compiler_source_size_unsigned64_identity frame hDomain.2.2.2.2.2.2.1
  have hProductCast : evalFrameSizeExpr compilerFrameSizeBounds frame
      (.cast .unsigned64 productExpr) =
        .ok (Int.ofNat ((Nat.succ widthOffset) * (Nat.succ heightOffset))) := by
    have hCast := compiler_frame_product_unsigned64_cast frame
      hDomain.2.2.2.2.1 hDomain.2.2.2.2.2.1
    change evalFrameSizeExpr compilerFrameSizeBounds frame
      (.cast .unsigned64 productExpr) = _ at hCast
    rw [hProductNat, if_neg (hOfNatNotNegative _)] at hCast
    exact hCast
  have hSourceCompare : evalFrameSizePredicate compilerFrameSizeBounds frame sourceCompare =
      .ok sourceMismatch := by
    unfold evalFrameSizePredicate
    change (do
        let left ← evalFrameSizeExpr compilerFrameSizeBounds frame (.cast .unsigned64 .sourceSize)
        let right ← evalFrameSizeExpr compilerFrameSizeBounds frame (.cast .unsigned64 productExpr)
        pure (left != right)) = .ok
          (frame.sourceSize != Int.toNat (frame.width * frame.height))
    rw [hSourceCast, hProductCast, hProductNat]
    have hToNat : Int.toNat
        (Int.ofNat ((Nat.succ widthOffset) * (Nat.succ heightOffset))) =
          (Nat.succ widthOffset) * (Nat.succ heightOffset) := Int.toNat_ofNat _
    rw [hToNat]
    have hIntNe (left right : Nat) :
        (Int.ofNat left != Int.ofNat right) = (left != right) := by
      change bne (Int.ofNat left) (Int.ofNat right) = bne left right
      have intBneFalse (a b : Int) (h : a = b) : (a != b) = false := by
        subst b
        change (!(decide (a = a))) = false
        have hDecide : decide (a = a) = true := by
          cases hEq : decide (a = a) with
          | false => exact False.elim ((of_decide_eq_false hEq) rfl)
          | true => rfl
        rw [hDecide]
        rfl
      cases hNat : left != right with
      | false =>
          cases hInt : Int.ofNat left != Int.ofNat right with
          | false => rfl
          | true =>
              have hEqual := nat_bne_false_eq left right hNat
              rw [intBneFalse _ _ (congrArg Int.ofNat hEqual)] at hInt
              cases hInt
      | true =>
          cases hInt : Int.ofNat left != Int.ofNat right with
          | true => rfl
          | false =>
              have hEqual := Int.ofNat_inj.mp (int_bne_false_eq _ _ hInt)
              have hNatFalse := nat_bne_eq_false_of_eq left right hEqual
              rw [hNatFalse] at hNat
              cases hNat
    change Except.ok
      (Int.ofNat frame.sourceSize !=
        Int.ofNat ((Nat.succ widthOffset) * (Nat.succ heightOffset))) = Except.ok
      (frame.sourceSize != (Nat.succ widthOffset) * (Nat.succ heightOffset))
    rw [hIntNe]
  have hSourceBranch : evalFrameSizePredicate compilerFrameSizeBounds frame sourceBranch =
      .ok sourceMismatch :=
    compiler_frame_size_sequence_predicate_ok _ _ _ _ _ _ hRangeCheck hSourceCompare
  have hCountPredicate : evalFrameSizePredicate compilerFrameSizeBounds frame countCondition =
      .ok false := by
    unfold evalFrameSizePredicate
    change (do
        let left ← evalFrameSizeExpr compilerFrameSizeBounds frame .byteCount
        let right ← evalFrameSizeExpr compilerFrameSizeBounds frame (.literal 0)
        pure (decide (left < right))) = .ok false
    rw [show evalFrameSizeExpr compilerFrameSizeBounds frame .byteCount =
      .ok (Int.ofNat frame.byteCount) by rfl]
    change Except.ok (decide (Int.ofNat frame.byteCount < 0)) = Except.ok false
    rw [compiler_decide_false (hOfNatNotNegative frame.byteCount)]
  have hCountCheck : evalFrameSizeExpr compilerFrameSizeBounds frame countCheck = .ok 0 :=
    compiler_frame_size_check_false_ok _ _ _ _ hCountPredicate
  have hCountChecks : evalFrameSizeExpr compilerFrameSizeBounds frame
      (.sequence countCheck countCheck) = .ok 0 := by
    unfold evalFrameSizeExpr
    change (do
        let _ ← evalFrameSizeExpr compilerFrameSizeBounds frame countCheck
        evalFrameSizeExpr compilerFrameSizeBounds frame countCheck) = .ok 0
    rw [hCountCheck]
    rfl
  have hByteCountCast := compiler_byte_count_to_int64_safe frame hDomain
  have hCountCompare : evalFrameSizePredicate compilerFrameSizeBounds frame countCompare =
      .ok countMismatch := by
    unfold evalFrameSizePredicate
    change (do
        let left ← evalFrameSizeExpr compilerFrameSizeBounds frame (.cast .int64 .byteCount)
        let right ← evalFrameSizeExpr compilerFrameSizeBounds frame productExpr
        pure (left != right)) = .ok countMismatch
    rw [hByteCountCast, hProductEval]
    rfl
  have hCountBranch : evalFrameSizePredicate compilerFrameSizeBounds frame countBranch =
      .ok countMismatch :=
    compiler_frame_size_sequence_predicate_ok _ _ _ _ _ _ hCountChecks hCountCompare
  have hNull : evalFrameSizePredicate compilerFrameSizeBounds frame nullBranch =
      .ok frame.bytes.isNone := by
    rfl
  cases hBytes : frame.bytes with
  | none =>
      have hNullTrue : evalFrameSizePredicate compilerFrameSizeBounds frame nullBranch = .ok true := by
        unfold evalFrameSizePredicate
        rw [hBytes]
        rfl
      have hBase := compiler_frame_size_or_else_ok _ _ _ _ _ _ hSourceBranch hCountBranch
      have hBaseNull := compiler_frame_size_or_else_ok _ _ _ _ _ _ hBase hNullTrue
      have hBaseIsTrue : evalFrameSizePredicate compilerFrameSizeBounds frame
          ((sourceBranch.orElse countBranch).orElse nullBranch) = .ok true := by
        rw [hBaseNull]
        cases sourceMismatch <;> cases countMismatch <;> rfl
      have hThroughFirst : evalFrameSizePredicate compilerFrameSizeBounds frame
          (((sourceBranch.orElse countBranch).orElse nullBranch).orElse firstBranch) = .ok true := by
        exact compiler_frame_size_or_else_true_left _ _ _ _ hBaseIsTrue
      have hAll : evalFrameSizePredicate compilerFrameSizeBounds frame
          ((((sourceBranch.orElse countBranch).orElse nullBranch).orElse firstBranch).orElse lengthBranch) =
            .ok true := compiler_frame_size_or_else_true_left _ _ _ _ hThroughFirst
      change evalFrameSizePredicate compilerFrameSizeBounds frame compilerFrameSizeProgram.invalidLength = _
      rw [hInvalidShape]
      rw [hAll]
      change Except.ok true = Except.ok
        (sourceMismatch || countMismatch || true || firstMismatch || lengthMismatch)
      cases sourceMismatch <;> cases countMismatch <;> rfl
  | some bytes =>
      have hNullFalse : evalFrameSizePredicate compilerFrameSizeBounds frame nullBranch = .ok false := by
        unfold evalFrameSizePredicate
        rw [hBytes]
        rfl
      have hArray : evalFrameSizeExpr compilerFrameSizeBounds frame
          (.ifThenElse (.greaterEqual .byteLast .byteFirst)
            (.cast .int64 (.cast .integer (.add .size
              (.subtract .size (.cast .size .byteLast) (.cast .size .byteFirst)) (.literal 1))))
            (.literal 0)) = .ok (Int.ofNat (byteLength frame)) := by
        change evalFrameSizeExpr compilerFrameSizeBounds frame compilerFrameSizeProgram.arrayLength = _
        exact compiler_frame_array_length_present frame bytes.first bytes.last bytes.content hDomain hBytes
      have hArrayCompare : evalFrameSizePredicate compilerFrameSizeBounds frame
          (.notEqual (.ifThenElse (.greaterEqual .byteLast .byteFirst)
            (.cast .int64 (.cast .integer (.add .size
              (.subtract .size (.cast .size .byteLast) (.cast .size .byteFirst)) (.literal 1))))
            (.literal 0)) productExpr) = .ok lengthMismatch := by
        unfold evalFrameSizePredicate
        change (do
            let left ← evalFrameSizeExpr compilerFrameSizeBounds frame
              (.ifThenElse (.greaterEqual .byteLast .byteFirst)
                (.cast .int64 (.cast .integer (.add .size
                  (.subtract .size (.cast .size .byteLast) (.cast .size .byteFirst)) (.literal 1))))
                (.literal 0))
            let right ← evalFrameSizeExpr compilerFrameSizeBounds frame productExpr
            pure (left != right)) = .ok lengthMismatch
        rw [hArray, hProductEval]
        rfl
      have hArrayAccess : evalFrameSizeExpr compilerFrameSizeBounds frame
          (.check .accessCheck nullBranch) = .ok (0 : Int) :=
        compiler_frame_size_check_false_ok _ _ .accessCheck nullBranch hNullFalse
      have hLengthBranch := compiler_frame_size_sequence_predicate_ok _ _ _ _ _ _
        hArrayAccess hArrayCompare
      have hFirstValue : evalFrameSizeExpr compilerFrameSizeBounds frame .byteFirst =
          .ok bytes.first := by
        unfold evalFrameSizeExpr
        rw [hBytes]
      have hFirstCompare : evalFrameSizePredicate compilerFrameSizeBounds frame
          (.notEqual .byteFirst (.literal 1)) = .ok firstMismatch := by
        unfold evalFrameSizePredicate
        change (do
            let left ← evalFrameSizeExpr compilerFrameSizeBounds frame .byteFirst
            let right ← evalFrameSizeExpr compilerFrameSizeBounds frame (.literal 1)
            pure (left != right)) = .ok firstMismatch
        rw [hFirstValue]
        change Except.ok (bytes.first != 1) = Except.ok (byteFirst frame != 1)
        rw [show byteFirst frame = bytes.first by
          unfold byteFirst
          rw [hBytes]
          rfl]
      have hFirst := compiler_frame_size_sequence_predicate_ok _ _ _ _ _ _ hArrayAccess hFirstCompare
      have hBase := compiler_frame_size_or_else_ok _ _ _ _ _ _ hSourceBranch hCountBranch
      have hBaseNull := compiler_frame_size_or_else_ok _ _ _ _ _ _ hBase hNullFalse
      have hThroughFirst := compiler_frame_size_or_else_ok _ _ _ _ _ _ hBaseNull hFirst
      exact compiler_frame_size_or_else_ok _ _ _ _ _ _ hThroughFirst hLengthBranch

theorem compiler_frame_size_suffix_agrees (frame : Observation)
    (hDomain : observationDomain frame) :
    runFrameSizeProgram compilerFrameSizeProgram compilerFrameSizeBounds frame =
      .returned (frameSizeSuffix frame) := by
  have hDimensions := compiler_frame_size_dimensions_eval frame
  have hLimit := compiler_frame_size_limit_eval frame hDomain
  have controlIfTrue (condition : FrameSizePredicate) (yes no : FrameSizeControl)
      (status : FrameStatus)
      (hCondition : evalFrameSizePredicate compilerFrameSizeBounds frame condition = .ok true)
      (hYes : evalFrameSizeControl compilerFrameSizeBounds frame yes = .ok status) :
      evalFrameSizeControl compilerFrameSizeBounds frame (.ifThenElse condition yes no) =
        .ok status := by
    unfold evalFrameSizeControl
    rw [hCondition]
    exact hYes
  have controlIfFalse (condition : FrameSizePredicate) (yes no : FrameSizeControl)
      (status : FrameStatus)
      (hCondition : evalFrameSizePredicate compilerFrameSizeBounds frame condition = .ok false)
      (hNo : evalFrameSizeControl compilerFrameSizeBounds frame no = .ok status) :
      evalFrameSizeControl compilerFrameSizeBounds frame (.ifThenElse condition yes no) =
        .ok status := by
    unfold evalFrameSizeControl
    rw [hCondition]
    exact hNo
  cases hDimension : decide (frame.width ≤ 0) || decide (frame.height ≤ 0) with
  | true =>
      rw [hDimension] at hDimensions
      have hControl : evalFrameSizeControl compilerFrameSizeBounds frame
          compilerFrameSizeProgram.control = .ok .invalidDimensions := by
        rw [compiler_frame_size_program_order]
        exact controlIfTrue compilerFrameSizeProgram.dimensions _ _ .invalidDimensions hDimensions rfl
      unfold runFrameSizeProgram
      rw [hControl]
      unfold frameSizeSuffix
      rw [if_pos hDimension]
  | false =>
      rw [hDimension] at hDimensions
      cases hLimitBool : decide (frame.width * frame.height > 2147483647) with
      | true =>
          rw [hLimitBool] at hLimit
          have hInner : evalFrameSizeControl compilerFrameSizeBounds frame
              (.ifThenElse compilerFrameSizeProgram.limit (.returnStatus .tooLarge)
                (.ifThenElse compilerFrameSizeProgram.invalidLength (.returnStatus .invalidLength)
                  (.returnStatus .success))) = .ok .tooLarge :=
            controlIfTrue compilerFrameSizeProgram.limit _ _ .tooLarge hLimit rfl
          have hControl : evalFrameSizeControl compilerFrameSizeBounds frame
              compilerFrameSizeProgram.control = .ok .tooLarge := by
            rw [compiler_frame_size_program_order]
            exact controlIfFalse compilerFrameSizeProgram.dimensions _ _ .tooLarge hDimensions hInner
          have hDimensionNot :
              ¬ ((decide (frame.width ≤ 0) || decide (frame.height ≤ 0)) = true) := by
            rw [hDimension]
            intro h
            cases h
          unfold runFrameSizeProgram
          rw [hControl]
          unfold frameSizeSuffix
          rw [if_neg hDimensionNot, if_pos hLimitBool]
      | false =>
          rw [hLimitBool] at hLimit
          have hInvalid := compiler_frame_size_invalid_length_eval frame hDomain hDimension
          cases hInvalidBool : (frame.sourceSize != Int.toNat (frame.width * frame.height) ||
              Int.ofNat frame.byteCount != frame.width * frame.height || frame.bytes.isNone ||
              byteFirst frame != 1 || Int.ofNat (byteLength frame) != frame.width * frame.height) with
          | true =>
              rw [hInvalidBool] at hInvalid
              have hInner : evalFrameSizeControl compilerFrameSizeBounds frame
                  (.ifThenElse compilerFrameSizeProgram.invalidLength (.returnStatus .invalidLength)
                    (.returnStatus .success)) = .ok .invalidLength :=
                controlIfTrue compilerFrameSizeProgram.invalidLength _ _ .invalidLength hInvalid rfl
              have hMiddle : evalFrameSizeControl compilerFrameSizeBounds frame
                  (.ifThenElse compilerFrameSizeProgram.limit (.returnStatus .tooLarge)
                    (.ifThenElse compilerFrameSizeProgram.invalidLength (.returnStatus .invalidLength)
                      (.returnStatus .success))) = .ok .invalidLength :=
                controlIfFalse compilerFrameSizeProgram.limit _ _ .invalidLength hLimit hInner
              have hControl : evalFrameSizeControl compilerFrameSizeBounds frame
                  compilerFrameSizeProgram.control = .ok .invalidLength := by
                rw [compiler_frame_size_program_order]
                exact controlIfFalse compilerFrameSizeProgram.dimensions _ _ .invalidLength
                  hDimensions hMiddle
              have hDimensionNot :
                  ¬ ((decide (frame.width ≤ 0) || decide (frame.height ≤ 0)) = true) := by
                rw [hDimension]
                intro h
                cases h
              have hLimitNot : ¬ (decide (frame.width * frame.height > 2147483647) = true) := by
                rw [hLimitBool]
                intro h
                cases h
              unfold runFrameSizeProgram
              rw [hControl]
              unfold frameSizeSuffix
              rw [if_neg hDimensionNot, if_neg hLimitNot, if_pos hInvalidBool]
          | false =>
              rw [hInvalidBool] at hInvalid
              have hInner : evalFrameSizeControl compilerFrameSizeBounds frame
                  (.ifThenElse compilerFrameSizeProgram.invalidLength (.returnStatus .invalidLength)
                    (.returnStatus .success)) = .ok .success :=
                controlIfFalse compilerFrameSizeProgram.invalidLength _ _ .success hInvalid rfl
              have hMiddle : evalFrameSizeControl compilerFrameSizeBounds frame
                  (.ifThenElse compilerFrameSizeProgram.limit (.returnStatus .tooLarge)
                    (.ifThenElse compilerFrameSizeProgram.invalidLength (.returnStatus .invalidLength)
                      (.returnStatus .success))) = .ok .success :=
                controlIfFalse compilerFrameSizeProgram.limit _ _ .success hLimit hInner
              have hControl : evalFrameSizeControl compilerFrameSizeBounds frame
                  compilerFrameSizeProgram.control = .ok .success := by
                rw [compiler_frame_size_program_order]
                exact controlIfFalse compilerFrameSizeProgram.dimensions _ _ .success
                  hDimensions hMiddle
              have hDimensionNot :
                  ¬ ((decide (frame.width ≤ 0) || decide (frame.height ≤ 0)) = true) := by
                rw [hDimension]
                intro h
                cases h
              have hLimitNot : ¬ (decide (frame.width * frame.height > 2147483647) = true) := by
                rw [hLimitBool]
                intro h
                cases h
              have hInvalidNot :
                  ¬ ((frame.sourceSize != Int.toNat (frame.width * frame.height) ||
                    Int.ofNat frame.byteCount != frame.width * frame.height || frame.bytes.isNone ||
                    byteFirst frame != 1 || Int.ofNat (byteLength frame) != frame.width * frame.height) = true) := by
                rw [hInvalidBool]
                intro h
                cases h
              unfold runFrameSizeProgram
              rw [hControl]
              unfold frameSizeSuffix
              rw [if_neg hDimensionNot, if_neg hLimitNot, if_neg hInvalidNot]

theorem compiler_frame_size_suffix_failure_free (frame : Observation)
    (hDomain : observationDomain frame) :
    ∀ reason, runFrameSizeProgram compilerFrameSizeProgram compilerFrameSizeBounds frame ≠
      .failed reason := by
  intro reason hFailed
  rw [compiler_frame_size_suffix_agrees frame hDomain] at hFailed
  cases hFailed

theorem compiler_frame_size_bridge_to_grab_status_prefix (state : CameraState) (timeout : Nat)
    (frame : Observation) (hPrefix : frameSizePrefixPassed state timeout frame)
    (hDomain : observationDomain frame) :
    runFrameSizeProgram compilerFrameSizeProgram compilerFrameSizeBounds frame =
      .returned (Model.grabStatus state timeout frame) := by
  rw [frame_size_bridge_to_grab_status_prefix state timeout frame hPrefix]
  exact compiler_frame_size_suffix_agrees frame hDomain

theorem compiler_frame_size_success_at_strict_maximum :
    runFrameSizeProgram compilerFrameSizeProgram compilerFrameSizeBounds
      (productBoundaryFrame 2147483647 1 2147483647 2147483647 1 2147483647 true) =
        .returned .success := by
  rw [compiler_frame_size_suffix_agrees _
    (by dsimp [observationDomain, productBoundaryFrame, int32Domain]; decide),
    frame_size_success_at_strict_maximum]

theorem compiler_frame_size_strict_maximum_plus_one_is_too_large :
    runFrameSizeProgram compilerFrameSizeProgram compilerFrameSizeBounds
      (productBoundaryFrame 1073741824 2 0 0 0 0 false) = .returned .tooLarge := by
  rw [compiler_frame_size_suffix_agrees _
    (by dsimp [observationDomain, productBoundaryFrame, int32Domain]; decide),
    frame_size_strict_maximum_plus_one_is_too_large]

theorem compiler_frame_size_int32_minimum_is_invalid_dimensions :
    runFrameSizeProgram compilerFrameSizeProgram compilerFrameSizeBounds
      (productBoundaryFrame (-2147483648) (-2147483648) 0 0 0 0 false) =
        .returned .invalidDimensions := by
  rw [compiler_frame_size_suffix_agrees _
    (by dsimp [observationDomain, productBoundaryFrame, int32Domain]; decide),
    frame_size_int32_minimum_is_invalid_dimensions]

theorem compiler_frame_size_zero_dimension_is_invalid_dimensions :
    runFrameSizeProgram compilerFrameSizeProgram compilerFrameSizeBounds
      (productBoundaryFrame 0 2147483647 0 0 0 0 false) = .returned .invalidDimensions := by
  rw [compiler_frame_size_suffix_agrees _
    (by dsimp [observationDomain, productBoundaryFrame, int32Domain]; decide),
    frame_size_zero_dimension_is_invalid_dimensions]

theorem compiler_frame_size_unsigned64_max_source_size_is_invalid_length :
    runFrameSizeProgram compilerFrameSizeProgram compilerFrameSizeBounds
      (productBoundaryFrame 1 1 18446744073709551615 1 1 1 true) = .returned .invalidLength := by
  rw [compiler_frame_size_suffix_agrees _
    (by dsimp [observationDomain, productBoundaryFrame, int32Domain]; decide),
    frame_size_unsigned64_max_source_size_is_invalid_length]

theorem compiler_frame_size_short_byte_view_is_invalid_length :
    runFrameSizeProgram compilerFrameSizeProgram compilerFrameSizeBounds
      (productBoundaryFrame 2 2 4 4 1 3 true) = .returned .invalidLength := by
  rw [compiler_frame_size_suffix_agrees _
    (by dsimp [observationDomain, productBoundaryFrame, int32Domain]; decide),
    frame_size_short_byte_view_is_invalid_length]

theorem compiler_frame_size_long_byte_view_is_invalid_length :
    runFrameSizeProgram compilerFrameSizeProgram compilerFrameSizeBounds
      (productBoundaryFrame 2 2 4 4 1 5 true) = .returned .invalidLength := by
  rw [compiler_frame_size_suffix_agrees _
    (by dsimp [observationDomain, productBoundaryFrame, int32Domain]; decide),
    frame_size_long_byte_view_is_invalid_length]

theorem compiler_frame_size_zero_byte_view_is_invalid_length :
    runFrameSizeProgram compilerFrameSizeProgram compilerFrameSizeBounds
      (productBoundaryFrame 1 1 0 0 1 0 true) = .returned .invalidLength := by
  rw [compiler_frame_size_suffix_agrees _
    (by dsimp [observationDomain, productBoundaryFrame, int32Domain]; decide),
    frame_size_zero_byte_view_is_invalid_length]

theorem compiler_frame_size_absent_byte_view_is_invalid_length :
    runFrameSizeProgram compilerFrameSizeProgram compilerFrameSizeBounds
      (productBoundaryFrame 1 1 1 1 0 0 false) = .returned .invalidLength := by
  rw [compiler_frame_size_suffix_agrees _
    (by dsimp [observationDomain, productBoundaryFrame, int32Domain]; decide),
    frame_size_absent_byte_view_is_invalid_length]

theorem compiler_frame_size_non_one_first_bound_is_invalid_length :
    runFrameSizeProgram compilerFrameSizeProgram compilerFrameSizeBounds
      (productBoundaryFrame 1 1 1 1 2 2 true) = .returned .invalidLength := by
  rw [compiler_frame_size_suffix_agrees _
    (by dsimp [observationDomain, productBoundaryFrame, int32Domain]; decide),
    frame_size_non_one_first_bound_is_invalid_length]

theorem compiler_frame_size_reversed_byte_bounds_are_invalid_length :
    runFrameSizeProgram compilerFrameSizeProgram compilerFrameSizeBounds
      (productBoundaryFrame 1 1 0 0 2 1 true) = .returned .invalidLength := by
  rw [compiler_frame_size_suffix_agrees _
    (by dsimp [observationDomain, productBoundaryFrame, int32Domain]; decide),
    frame_size_reversed_byte_bounds_are_invalid_length]

theorem compiler_frame_size_inconsistent_source_count_is_invalid_length :
    runFrameSizeProgram compilerFrameSizeProgram compilerFrameSizeBounds
      (productBoundaryFrame 2 2 3 3 1 4 true) = .returned .invalidLength := by
  rw [compiler_frame_size_suffix_agrees _
    (by dsimp [observationDomain, productBoundaryFrame, int32Domain]; decide),
    frame_size_inconsistent_source_count_is_invalid_length]

theorem compiler_frame_size_inconsistent_byte_count_is_invalid_length :
    runFrameSizeProgram compilerFrameSizeProgram compilerFrameSizeBounds
      (productBoundaryFrame 2 2 4 3 1 4 true) = .returned .invalidLength := by
  rw [compiler_frame_size_suffix_agrees _
    (by dsimp [observationDomain, productBoundaryFrame, int32Domain]; decide),
    frame_size_inconsistent_byte_count_is_invalid_length]

theorem compiler_frame_size_exact_size_success :
    runFrameSizeProgram compilerFrameSizeProgram compilerFrameSizeBounds
      (productBoundaryFrame 2 2 4 4 1 4 true) = .returned .success := by
  rw [compiler_frame_size_suffix_agrees _
    (by dsimp [observationDomain, productBoundaryFrame, int32Domain]; decide),
    frame_size_exact_size_success]

end CameraLifecycle.Grab
