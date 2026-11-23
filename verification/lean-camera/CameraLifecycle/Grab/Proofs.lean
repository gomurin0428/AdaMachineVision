import Lean
import CameraLifecycle.Grab.Generated
import CameraLifecycle.Grab.Model

namespace CameraLifecycle.Grab

open CameraLifecycle.Model
open CameraLifecycle.Grab

theorem positive_int_to_nat (value : Int)
    (hpositive : decide (value ≤ 0) = false) :
    ∃ n, value = Int.ofNat (Nat.succ n) := by
  cases value with
  | ofNat n =>
      cases n with
      | zero =>
          change decide ((Int.ofNat 0 : Int) ≤ 0) = false at hpositive
          have hzero : decide ((Int.ofNat 0 : Int) ≤ 0) = true := rfl
          rw [hzero] at hpositive
          cases hpositive
      | succ n => exact ⟨n, rfl⟩
  | negSucc n =>
      change decide ((Int.negSucc n : Int) ≤ 0) = false at hpositive
      have hnegative : decide ((Int.negSucc n : Int) ≤ 0) = true := rfl
      rw [hnegative] at hpositive
      cases hpositive

theorem int_ofNat_lt_toNat (x bound : Nat)
    (h : (Int.ofNat x) < (Int.ofNat bound)) : x < bound := by
  change Int.NonNeg (Int.ofNat bound - (Int.ofNat x + 1)) at h
  change Int.NonNeg (Int.ofNat bound - Int.ofNat (x + 1)) at h
  change Int.NonNeg (Int.add (Int.ofNat bound) (Int.neg (Int.ofNat (x + 1)))) at h
  change Int.NonNeg (Int.add (Int.ofNat bound) (Int.negSucc x)) at h
  change Int.NonNeg (Int.subNatNat bound (x + 1)) at h
  cases hsub : (x + 1) - bound with
  | zero =>
      have hbound : x + 1 ≤ bound := Nat.le_of_sub_eq_zero hsub
      exact Nat.lt_of_succ_le (by simpa only [Nat.succ_eq_add_one] using hbound)
  | succ k =>
      unfold Int.subNatNat at h
      rw [hsub] at h
      cases h

theorem int_ofNat_le_toNat (x bound : Nat)
    (h : (Int.ofNat x) ≤ (Int.ofNat bound)) : x ≤ bound := by
  change Int.NonNeg (Int.ofNat bound - Int.ofNat x) at h
  cases x with
  | zero => exact Nat.zero_le bound
  | succ x =>
      change Int.NonNeg (Int.add (Int.ofNat bound) (Int.negSucc x)) at h
      change Int.NonNeg (Int.subNatNat bound (Nat.succ x)) at h
      cases hsub : (Nat.succ x) - bound with
      | zero => exact Nat.le_of_sub_eq_zero hsub
      | succ k =>
          unfold Int.subNatNat at h
          rw [hsub] at h
          cases h

theorem nat_sub_zero_of_le {a b : Nat} (h : a ≤ b) : a - b = 0 := by
  induction b generalizing a with
  | zero =>
      cases a with
      | zero => rfl
      | succ a => cases h
  | succ b ih =>
      cases a with
      | zero => exact Nat.zero_sub _
      | succ a =>
          rw [Nat.succ_sub_succ]
          exact ih (Nat.le_of_succ_le_succ h)

theorem int_ofNat_le_ofNat (a b : Nat) (h : a ≤ b) :
    (Int.ofNat a : Int) ≤ Int.ofNat b := by
  change Int.NonNeg (Int.ofNat b - Int.ofNat a)
  cases a with
  | zero =>
      change Int.NonNeg (Int.ofNat b)
      exact Int.NonNeg.mk b
  | succ a =>
      change Int.NonNeg (Int.add (Int.ofNat b) (Int.neg (Int.ofNat (Nat.succ a))))
      unfold Int.add Int.neg Int.negOfNat
      change Int.NonNeg (Int.subNatNat b (Nat.succ a))
      unfold Int.subNatNat
      rw [nat_sub_zero_of_le h]
      change Int.NonNeg (Int.ofNat (b - Nat.succ a))
      exact Int.NonNeg.mk _

theorem int_ofNat_lt_decide_ge_false (x bound : Nat)
    (h : x < bound) :
    decide ((Int.ofNat bound : Int) ≤ Int.ofNat x) = false := by
  cases hdec : decide ((Int.ofNat bound : Int) ≤ Int.ofNat x) with
  | false => rfl
  | true =>
      have hle : (Int.ofNat bound : Int) ≤ Int.ofNat x := of_decide_eq_true hdec
      have hnat : bound ≤ x := int_ofNat_le_toNat bound x hle
      exact False.elim (Nat.not_le_of_gt h hnat)

theorem bool_eq_false_of_not_true (value : Bool)
    (h : ¬ value = true) : value = false := by
  cases value with
  | false => rfl
  | true => exact False.elim (h rfl)

theorem bool_and_eq_true_components (left right : Bool)
    (h : (left && right) = true) :
    left = true ∧ right = true := by
  cases left with
  | false => cases h
  | true =>
      cases right with
      | false => cases h
      | true => exact ⟨rfl, rfl⟩

theorem bool_or_eq_false_components (left right : Bool)
    (h : (left || right) = false) :
    left = false ∧ right = false := by
  cases left with
  | false =>
      cases right with
      | false => exact ⟨rfl, rfl⟩
      | true => cases h
  | true => cases h

theorem int_beq_true_eq (left right : Int)
    (h : (left == right) = true) : left = right := by
  change decide (left = right) = true at h
  exact of_decide_eq_true h

theorem nat_bne_false_eq (left right : Nat)
    (h : (left != right) = false) : left = right := by
  change (!(decide (left = right))) = false at h
  cases decEq left right with
  | isTrue heq => exact heq
  | isFalse hne =>
      have hdec : decide (left = right) = false := by
        cases hd : decide (left = right) with
        | false => rfl
        | true => exact False.elim (hne (of_decide_eq_true hd))
      rw [hdec] at h
      cases h

theorem nat_bne_eq_false_of_eq (left right : Nat)
    (h : left = right) : (left != right) = false := by
  subst right
  change (!(decide (left = left))) = false
  have hdec : decide (left = left) = true := by
    cases hd : decide (left = left) with
    | false => exact False.elim ((of_decide_eq_false hd) rfl)
    | true => rfl
  rw [hdec]
  rfl

theorem int_bne_false_eq (left right : Int)
    (h : (left != right) = false) : left = right := by
  change (!(decide (left = right))) = false at h
  cases decEq left right with
  | isTrue heq => exact heq
  | isFalse hne =>
      have hdec : decide (left = right) = false := by
        cases hd : decide (left = right) with
        | false => rfl
        | true => exact False.elim (hne (of_decide_eq_true hd))
      rw [hdec] at h
      cases h

theorem grab_status_success_guards (state : CameraState) (timeout : Nat)
    (frame : Observation)
    (hstatus : Model.grabStatus state timeout frame = .success) :
    (decide (frame.width ≤ 0) || decide (frame.height ≤ 0)) = false ∧
      (frame.sourceSize != Int.toNat (frame.width * frame.height) ||
        (Int.ofNat frame.byteCount) != frame.width * frame.height ||
        frame.bytes.isNone || byteFirst frame != 1 ||
        (Int.ofNat (byteLength frame)) != frame.width * frame.height) = false := by
  unfold Model.grabStatus at hstatus
  by_cases h0 :
      ((state != .streaming || timeout == 0) = true)
  · rw [if_pos h0] at hstatus
    cases hstatus
  · rw [if_neg h0] at hstatus
    by_cases h1 :
        ((frame.acquisitionStatus == .notCalled ||
          frame.acquisitionStatus == .badParameter) = true)
    · rw [if_pos h1] at hstatus
      cases hstatus
    · rw [if_neg h1] at hstatus
      by_cases h2 : (frame.acquisitionStatus == .timeout) = true
      · rw [if_pos h2] at hstatus
        cases hstatus
      · rw [if_neg h2] at hstatus
        by_cases h3 : (frame.acquisitionStatus == .outOfMemory) = true
        · rw [if_pos h3] at hstatus
          cases hstatus
        · rw [if_neg h3] at hstatus
          by_cases h4 :
              ((frame.acquisitionStatus == .unsupported ||
                frame.acquisitionStatus == .error) = true)
          · rw [if_pos h4] at hstatus
            cases hstatus
          · rw [if_neg h4] at hstatus
            by_cases h5 : (frame.bufferStatus == 2) = true
            · rw [if_pos h5] at hstatus
              cases hstatus
            · rw [if_neg h5] at hstatus
              by_cases h6 : (frame.bufferStatus != 0) = true
              · rw [if_pos h6] at hstatus
                cases hstatus
              · rw [if_neg h6] at hstatus
                by_cases h7 : (frame.payloadType != 1) = true
                · rw [if_pos h7] at hstatus
                  cases hstatus
                · rw [if_neg h7] at hstatus
                  by_cases h8 : (frame.pixelFormat != 17301505) = true
                  · rw [if_pos h8] at hstatus
                    cases hstatus
                  · rw [if_neg h8] at hstatus
                    by_cases h9 :
                        ((decide (frame.width ≤ 0) ||
                          decide (frame.height ≤ 0)) = true)
                    · rw [if_pos h9] at hstatus
                      cases hstatus
                    · have hdimensions :=
                        bool_eq_false_of_not_true _ h9
                      rw [if_neg h9] at hstatus
                      by_cases h10 :
                          (decide (frame.width * frame.height > 2147483647) = true)
                      · rw [if_pos h10] at hstatus
                        cases hstatus
                      · rw [if_neg h10] at hstatus
                        by_cases h11 :
                            ((frame.sourceSize != Int.toNat (frame.width * frame.height) ||
                              (Int.ofNat frame.byteCount) != frame.width * frame.height ||
                              frame.bytes.isNone || byteFirst frame != 1 ||
                              (Int.ofNat (byteLength frame)) != frame.width * frame.height) = true)
                        · rw [if_pos h11] at hstatus
                          cases hstatus
                        · have hlength :=
                            bool_eq_false_of_not_true _ h11
                          exact ⟨hdimensions, hlength⟩

theorem grab_status_success_bytes (state : CameraState) (timeout : Nat)
    (frame : Observation) (bytes : ByteArrayView)
    (hstatus : Model.grabStatus state timeout frame = .success)
    (hbytes : frame.bytes = some bytes) :
    ∃ w h,
      frame.width = Int.ofNat (Nat.succ w) ∧
      frame.height = Int.ofNat (Nat.succ h) ∧
      decide (frame.width ≤ 0) = false ∧
      decide (frame.height ≤ 0) = false ∧
      frame.byteCount = Nat.succ w * Nat.succ h ∧
      (frame.byteCount == 0) = false ∧
      bytes.first = 1 ∧
      byteLength frame = frame.byteCount := by
  obtain ⟨hdimensions, hlength⟩ :=
    grab_status_success_guards state timeout frame hstatus
  obtain ⟨hwidth, hheight⟩ :=
    bool_or_eq_false_components _ _ hdimensions
  obtain ⟨w, hw⟩ := positive_int_to_nat frame.width hwidth
  obtain ⟨h, hh⟩ := positive_int_to_nat frame.height hheight
  obtain ⟨hlengthPrefix, hlengthLast⟩ :=
    bool_or_eq_false_components _ _ hlength
  obtain ⟨hlengthPrefix, hbyteFirst⟩ :=
    bool_or_eq_false_components _ _ hlengthPrefix
  obtain ⟨hlengthPrefix, hbytesNone⟩ :=
    bool_or_eq_false_components _ _ hlengthPrefix
  obtain ⟨hsourceSize, hbyteCount⟩ :=
    bool_or_eq_false_components _ _ hlengthPrefix
  have hcountInt : (Int.ofNat frame.byteCount : Int) = frame.width * frame.height :=
    int_bne_false_eq _ _ hbyteCount
  have hlengthInt : (Int.ofNat (byteLength frame) : Int) = frame.width * frame.height :=
    int_bne_false_eq _ _ hlengthLast
  rw [hw, hh] at hcountInt hlengthInt
  have hcountNat : frame.byteCount = Nat.succ w * Nat.succ h := by
    have hcast := congrArg Int.toNat hcountInt
    change frame.byteCount = Nat.succ w * Nat.succ h at hcast
    exact hcast
  have hbyteLengthNat : byteLength frame = frame.byteCount := by
    have hcast : Int.ofNat (byteLength frame) = Int.ofNat frame.byteCount :=
      hlengthInt.trans hcountInt.symm
    have hnat := congrArg Int.toNat hcast
    change byteLength frame = frame.byteCount at hnat
    exact hnat
  have hfirstInt : byteFirst frame = 1 := int_bne_false_eq _ _ hbyteFirst
  have hfirst : bytes.first = 1 := by
    unfold byteFirst at hfirstInt
    rw [hbytes] at hfirstInt
    change bytes.first = 1 at hfirstInt
    exact hfirstInt
  have hcountPositive : 0 < frame.byteCount := by
    rw [hcountNat]
    exact Nat.mul_pos (Nat.succ_pos w) (Nat.succ_pos h)
  have hcountNonzero : (frame.byteCount == 0) = false := by
    cases hcount : frame.byteCount with
    | zero =>
        have hfalse : False := by
          rw [hcount] at hcountPositive
          cases hcountPositive
        exact False.elim hfalse
    | succ n => rfl
  exact ⟨w, h, hw, hh, hwidth, hheight, hcountNat, hcountNonzero, hfirst,
    hbyteLengthNat⟩

theorem one_sub_succ_zero : ∀ n : Nat, 1 - Nat.succ n = 0
  | 0 => rfl
  | Nat.succ n => by
      rw [Nat.sub_succ, one_sub_succ_zero n]
      rfl

theorem int_ofNat_succ_sub_one (n : Nat) :
    (Int.ofNat (Nat.succ n) : Int) - 1 = Int.ofNat n := by
  change Int.add (Int.ofNat (Nat.succ n)) (Int.neg (1 : Int)) = Int.ofNat n
  unfold Int.add Int.neg Int.negOfNat
  change Int.subNatNat (Nat.succ n) 1 = Int.ofNat n
  unfold Int.subNatNat
  rw [one_sub_succ_zero, Nat.add_one_sub_one]

theorem byte_last_from_length (last : Int) (count : Nat)
    (hlen : (if last < 1 then 0 else Int.toNat (last - 1 + 1)) = count)
    (hpositive : 0 < count) : last = Int.ofNat count := by
  cases last with
  | ofNat n =>
      cases n with
      | zero =>
          change (if (Int.ofNat 0 : Int) < 1 then 0 else
            Int.toNat (Int.ofNat 0 - 1 + 1)) = count at hlen
          by_cases hlt : (Int.ofNat 0 : Int) < 1
          · rw [if_pos hlt] at hlen
            exact False.elim ((Nat.ne_of_gt hpositive) hlen.symm)
          · rw [if_neg hlt] at hlen
            have hcancel : (Int.ofNat 0 : Int) - 1 + 1 = 0 := rfl
            rw [hcancel] at hlen
            exact False.elim ((Nat.ne_of_gt hpositive) hlen.symm)
      | succ n =>
          change (if (Int.ofNat (Nat.succ n) : Int) < 1 then 0 else
            Int.toNat (Int.ofNat (Nat.succ n) - 1 + 1)) = count at hlen
          by_cases hlt : (Int.ofNat (Nat.succ n) : Int) < 1
          · rw [if_pos hlt] at hlen
            exact False.elim ((Nat.ne_of_gt hpositive) hlen.symm)
          · rw [if_neg hlt] at hlen
            rw [int_ofNat_succ_sub_one] at hlen
            change Nat.succ n = count at hlen
            exact congrArg Int.ofNat hlen
  | negSucc n =>
      change (if (Int.negSucc n : Int) < 1 then 0 else
        Int.toNat (Int.negSucc n - 1 + 1)) = count at hlen
      by_cases hlt : (Int.negSucc n : Int) < 1
      · rw [if_pos hlt] at hlen
        exact False.elim ((Nat.ne_of_gt hpositive) hlen.symm)
      · rw [if_neg hlt] at hlen
        have hcancel : (Int.negSucc n : Int) - 1 + 1 = Int.negSucc n := by
          change Int.add (Int.add (Int.negSucc n) (Int.neg (1 : Int))) 1 =
            Int.negSucc n
          unfold Int.add Int.neg Int.negOfNat
          rfl
        rw [hcancel] at hlen
        change 0 = count at hlen
        exact False.elim ((Nat.ne_of_gt hpositive) hlen.symm)

theorem valid_image_range_bounds (image : Image) (width height x y : Nat)
    (hvalid : Model.validImage image = true)
    (hwidth : (image.map ImageData.width).getD 0 = Int.ofNat (Nat.succ width))
    (hheight : (image.map ImageData.height).getD 0 = Int.ofNat (Nat.succ height))
    (hyRange : imageRangeContains image 1 y = true)
    (hxRange : imageRangeContains image 2 x = true) :
    x < Nat.succ width ∧ y < Nat.succ height := by
  cases image with
  | none =>
      unfold Model.validImage at hvalid
      cases hvalid
  | some data =>
      rcases data with ⟨dataWidth, dataHeight, dataPixels⟩
      cases dataPixels with
      | none =>
          cases hvalid
      | some pixels =>
          change dataWidth = Int.ofNat (Nat.succ width) at hwidth
          change dataHeight = Int.ofNat (Nat.succ height) at hheight
          have hvalid' := hvalid
          change (decide (dataWidth ≥ 1) && decide (dataHeight ≥ 1) &&
            (pixels.firstRow == 0) && (pixels.firstColumn == 0) &&
            (pixels.lastRow == dataHeight - 1) &&
            (pixels.lastColumn == dataWidth - 1)) = true at hvalid'
          rcases bool_and_eq_true_components _ _ hvalid' with
            ⟨hvalidFive, hlastColumnBool⟩
          rcases bool_and_eq_true_components _ _ hvalidFive with
            ⟨_, hlastRowBool⟩
          have hlastRow : pixels.lastRow = Int.ofNat height := by
            calc
              pixels.lastRow = dataHeight - 1 :=
                int_beq_true_eq _ _ hlastRowBool
              _ = Int.ofNat (Nat.succ height) - 1 := by rw [hheight]
              _ = Int.ofNat height := int_ofNat_succ_sub_one height
          have hlastColumn : pixels.lastColumn = Int.ofNat width := by
            have hlastColumnEq :
                pixels.lastColumn = dataWidth - 1 :=
              int_beq_true_eq _ _ hlastColumnBool
            calc
              pixels.lastColumn = dataWidth - 1 := hlastColumnEq
              _ = Int.ofNat (Nat.succ width) - 1 := by rw [hwidth]
              _ = Int.ofNat width := int_ofNat_succ_sub_one width
          change (decide (pixels.firstRow ≤ Int.ofNat y) &&
            decide (Int.ofNat y ≤ pixels.lastRow)) = true at hyRange
          rcases bool_and_eq_true_components _ _ hyRange with
            ⟨_, hyUpperBool⟩
          have hyUpper : Int.ofNat y ≤ pixels.lastRow :=
            of_decide_eq_true hyUpperBool
          rw [hlastRow] at hyUpper
          change (decide (pixels.firstColumn ≤ Int.ofNat x) &&
            decide (Int.ofNat x ≤ pixels.lastColumn)) = true at hxRange
          rcases bool_and_eq_true_components _ _ hxRange with
            ⟨_, hxUpperBool⟩
          have hxUpper : Int.ofNat x ≤ pixels.lastColumn :=
            of_decide_eq_true hxUpperBool
          rw [hlastColumn] at hxUpper
          exact ⟨Nat.lt_succ_of_le (int_ofNat_le_toNat x width hxUpper),
            Nat.lt_succ_of_le (int_ofNat_le_toNat y height hyUpper)⟩

@[simp] theorem valid_observation_agrees (frame : Observation) :
    Model.validObservation frame = Generated.validObservationAda frame := by
  rfl

@[simp] theorem valid_image_agrees (image : Image) :
    Model.validImage image = Generated.validImageAda image := by
  rfl

@[simp] theorem grab_status_agrees (state : CameraState) (timeout : Nat)
    (frame : Observation) :
    Model.grabStatus state timeout frame =
      Generated.grabStatusAda state timeout frame := by
  rfl

@[simp] theorem pixel_at_agrees (frame : Observation) (x y : Nat) :
    Model.pixelAt frame x y = Generated.pixelAtAda frame x y := by
  rfl

theorem grab_pre_agrees (state : CameraState) (handle : Nat) :
    Model.grabPre state handle = Generated.grabPreAda state handle := by
  rfl

theorem grab_post_agrees (state : CameraState) (timeout : Nat) (image : Image)
    (status : FrameStatus) (observation : Observation) :
    Model.grabPost state timeout image status observation ↔
      Generated.grabPostAda state timeout image status observation := by
  unfold Model.grabPost Generated.grabPostAda
  constructor
  · intro h
    rw [valid_observation_agrees, valid_image_agrees, grab_status_agrees] at h
    simp only [pixel_at_agrees] at h
    exact h
  · intro h
    rw [← valid_observation_agrees, ← valid_image_agrees, ← grab_status_agrees] at h
    simp only [← pixel_at_agrees] at h
    exact h

theorem build_frame_post_agrees (state : CameraState) (timeout : Nat)
    (observation : Observation) (image : Image) (status : FrameStatus) :
    Model.buildFramePost state timeout observation image status ↔
      Generated.buildFramePostAda state timeout observation image status := by
  unfold Model.buildFramePost Generated.buildFramePostAda
  constructor
  · intro h
    rw [grab_status_agrees, valid_image_agrees] at h
    simp only [pixel_at_agrees] at h
    exact h
  · intro h
    rw [← grab_status_agrees, ← valid_image_agrees] at h
    simp only [← pixel_at_agrees] at h
    exact h

theorem grab_relation_agrees (state : CameraState) (handle timeout : Nat)
    (image : Image) (status : FrameStatus) (observation : Observation) :
    Model.grabRelation state handle timeout image status observation ↔
      Generated.grabRelationAda state handle timeout image status observation := by
  unfold Model.grabRelation Generated.grabRelationAda
  rw [grab_pre_agrees]
  constructor
  · rintro ⟨hdomain, htimeout, himage, hpre, hpost⟩
    exact ⟨hdomain, htimeout, himage, hpre,
      (grab_post_agrees state timeout image status observation).mp hpost⟩
  · rintro ⟨hdomain, htimeout, himage, hpre, hpost⟩
    exact ⟨hdomain, htimeout, himage, hpre,
      (grab_post_agrees state timeout image status observation).mpr hpost⟩

theorem build_frame_relation_agrees (state : CameraState) (timeout : Nat)
    (observation : Observation) (image : Image) (status : FrameStatus) :
    Model.buildFrameRelation state timeout observation image status ↔
      Generated.buildFrameRelationAda state timeout observation image status := by
  unfold Model.buildFrameRelation Generated.buildFrameRelationAda
  constructor
  · rintro ⟨hdomain, htimeout, himage, hpost⟩
    exact ⟨hdomain, htimeout, himage,
      (build_frame_post_agrees state timeout observation image status).mp hpost⟩
  · rintro ⟨hdomain, htimeout, himage, hpost⟩
    exact ⟨hdomain, htimeout, himage,
      (build_frame_post_agrees state timeout observation image status).mpr hpost⟩

theorem empty_observation_validity_matches_nullness (frame : Observation)
    (hcount : frame.byteCount = 0) :
    Generated.validObservationAda frame = true ↔ frame.bytes.isNone := by
  rw [← valid_observation_agrees]
  unfold Model.validObservation
  have hbeq : (frame.byteCount == 0) = true := by
    rw [hcount]
    rfl
  rw [if_pos hbeq]

theorem pixel_at_null_bytes_returns_zero (frame : Observation) (x y : Nat)
    (hbytes : frame.bytes = none) :
    Generated.pixelAtAda frame x y = byteZero := by
  rw [← pixel_at_agrees]
  unfold Model.pixelAt
  have hguard :
      (decide (frame.width ≤ 0) || decide (frame.height ≤ 0) ||
        frame.byteCount == 0 || frame.bytes.isNone) = true := by
    cases hwidth : decide (frame.width ≤ 0) <;>
      cases hheight : decide (frame.height ≤ 0) <;>
      cases (frame.byteCount == 0) <;>
      rw [hbytes, Option.isNone_none] <;> rfl
  rw [if_pos hguard]
  rfl

theorem pixel_at_reads_byte_content (frame : Observation) (bytes : ByteArrayView)
    (x y : Nat)
    (hbytes : frame.bytes = some bytes)
    (hfirstGuard :
      (decide (frame.width ≤ 0) || decide (frame.height ≤ 0) ||
        frame.byteCount == 0 || frame.bytes.isNone) = false)
    (hsecondGuard :
      (byteFirst frame != 1 || byteLength frame != frame.byteCount ||
        decide (x ≥ Int.toNat frame.width) || decide (y ≥ Int.toNat frame.height)) = false)
    (hindexGuard :
      decide (Int.ofNat y * frame.width + Int.ofNat x ≥ Int.ofNat frame.byteCount) = false)
    (hcontains :
      bytes.first ≤ Int.ofNat
          (Int.toNat (Int.ofNat y * frame.width + Int.ofNat x) + 1) ∧
    Int.ofNat
          (Int.toNat (Int.ofNat y * frame.width + Int.ofNat x) + 1) ≤ bytes.last) :
    Model.pixelAt frame x y =
      bytes.content (Int.toNat (Int.ofNat y * frame.width + Int.ofNat x) + 1) := by
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
  have hindexNot : ¬
      decide (Int.ofNat y * frame.width + Int.ofNat x ≥ Int.ofNat frame.byteCount) = true := by
    rw [hindexGuard]
    intro h
    cases h
  have hread : byteAt frame
      (Int.toNat (Int.ofNat y * frame.width + Int.ofNat x) + 1) =
        bytes.content (Int.toNat (Int.ofNat y * frame.width + Int.ofNat x) + 1) := by
    unfold byteAt
    rw [hbytes]
    change (if bytes.first ≤ Int.ofNat
          (Int.toNat (Int.ofNat y * frame.width + Int.ofNat x) + 1) ∧
        Int.ofNat (Int.toNat (Int.ofNat y * frame.width + Int.ofNat x) + 1) ≤ bytes.last
      then some (bytes.content (Int.toNat (Int.ofNat y * frame.width + Int.ofNat x) + 1))
      else none).getD byteZero =
        bytes.content (Int.toNat (Int.ofNat y * frame.width + Int.ofNat x) + 1)
    rw [if_pos hcontains]
    rfl
  unfold Model.pixelAt
  rw [if_neg hfirstNot, if_neg hsecondNot, if_neg hindexNot, hread]

theorem successful_pixel_reads_byte (state : CameraState) (timeout : Nat)
    (frame : Observation) (image : Image) (bytes : ByteArrayView) (x y : Nat)
    (hstatus : Model.grabStatus state timeout frame = .success)
    (hvalidImage : Model.validImage image = true)
    (himageWidth : (image.map ImageData.width).getD 0 = frame.width)
    (himageHeight : (image.map ImageData.height).getD 0 = frame.height)
    (hbytes : frame.bytes = some bytes)
    (hyImage : imageRangeContains image 1 y = true)
    (hxImage : imageRangeContains image 2 x = true) :
    Model.pixelAt frame x y =
      bytes.content (Int.toNat (Int.ofNat y * frame.width + Int.ofNat x) + 1) := by
  rcases grab_status_success_bytes state timeout frame bytes hstatus hbytes with
    ⟨w, h, hw, hh, hwidth, hheight, hcount, hcountNonzero, hfirst,
      hlength⟩
  have himageWidthNat :
      (image.map ImageData.width).getD 0 = Int.ofNat (Nat.succ w) :=
    himageWidth.trans hw
  have himageHeightNat :
      (image.map ImageData.height).getD 0 = Int.ofNat (Nat.succ h) :=
    himageHeight.trans hh
  rcases valid_image_range_bounds image w h x y hvalidImage himageWidthNat
    himageHeightNat hyImage hxImage with ⟨hxNat, hyNat⟩
  have hfirstGuard :
      (decide (frame.width ≤ 0) || decide (frame.height ≤ 0) ||
        frame.byteCount == 0 || frame.bytes.isNone) = false := by
    rw [hwidth, hheight, hcountNonzero, hbytes]
    rfl
  have hxGuard : decide (x ≥ Int.toNat frame.width) = false := by
    rw [hw]
    change decide (x ≥ Nat.succ w) = false
    cases hdec : decide (x ≥ Nat.succ w) with
    | false => rfl
    | true =>
        have hle : Nat.succ w ≤ x := of_decide_eq_true hdec
        exact False.elim (Nat.not_le_of_gt hxNat hle)
  have hyGuard : decide (y ≥ Int.toNat frame.height) = false := by
    rw [hh]
    change decide (y ≥ Nat.succ h) = false
    cases hdec : decide (y ≥ Nat.succ h) with
    | false => rfl
    | true =>
        have hle : Nat.succ h ≤ y := of_decide_eq_true hdec
        exact False.elim (Nat.not_le_of_gt hyNat hle)
  have hbyteFirst : (byteFirst frame != 1) = false := by
    unfold byteFirst
    rw [hbytes]
    change (bytes.first != 1) = false
    rw [hfirst]
    rfl
  have hlengthGuard : (byteLength frame != frame.byteCount) = false := by
    exact nat_bne_eq_false_of_eq _ _ hlength
  have hsecondGuard :
      (byteFirst frame != 1 || byteLength frame != frame.byteCount ||
        decide (x ≥ Int.toNat frame.width) ||
        decide (y ≥ Int.toNat frame.height)) = false := by
    rw [hbyteFirst, hlengthGuard, hxGuard, hyGuard]
    rfl
  have hrowBound : y * Nat.succ w + x < Nat.succ y * Nat.succ w := by
    calc
      y * Nat.succ w + x < y * Nat.succ w + Nat.succ w :=
        Nat.add_lt_add_left hxNat (y * Nat.succ w)
      _ = Nat.succ y * Nat.succ w := by
        rw [Nat.succ_mul]
  have hrowHeight : Nat.succ y * Nat.succ w ≤ Nat.succ h * Nat.succ w :=
    Nat.mul_le_mul_right (Nat.succ w) (Nat.succ_le_of_lt hyNat)
  have hindexNat :
      y * Nat.succ w + x < frame.byteCount := by
    calc
      y * Nat.succ w + x < Nat.succ y * Nat.succ w := hrowBound
      _ ≤ Nat.succ h * Nat.succ w := hrowHeight
      _ = Nat.succ w * Nat.succ h := Nat.mul_comm _ _
      _ = frame.byteCount := hcount.symm
  have hindexGuard :
      decide (Int.ofNat y * frame.width + Int.ofNat x ≥
        Int.ofNat frame.byteCount) = false := by
    rw [hw]
    have hdec := int_ofNat_lt_decide_ge_false
      (y * Nat.succ w + x) frame.byteCount hindexNat
    change decide (Int.ofNat frame.byteCount ≤
      Int.ofNat (y * Nat.succ w + x)) = false
    exact hdec
  have hindexCast :
      Int.toNat (Int.ofNat y * frame.width + Int.ofNat x) =
        y * Nat.succ w + x := by
    rw [hw]
    rfl
  have hindexLowerNat : 1 ≤ y * Nat.succ w + x + 1 := by
    change Nat.succ 0 ≤ Nat.succ (y * Nat.succ w + x)
    exact Nat.succ_le_succ (Nat.zero_le _)
  have hindexUpperNat :
      y * Nat.succ w + x + 1 ≤ frame.byteCount := by
    change Nat.succ (y * Nat.succ w + x) ≤ frame.byteCount
    exact Nat.succ_le_of_lt hindexNat
  have hpositiveCount : 0 < frame.byteCount := by
    rw [hcount]
    exact Nat.mul_pos (Nat.succ_pos w) (Nat.succ_pos h)
  have hbytesLast : bytes.last = Int.ofNat frame.byteCount := by
    have hlengthRaw :
        (if bytes.last < 1 then 0 else Int.toNat (bytes.last - 1 + 1)) =
          frame.byteCount := by
      unfold byteLength at hlength
      rw [hbytes] at hlength
      change (if bytes.last < bytes.first then 0 else
        Int.toNat (bytes.last - bytes.first + 1)) = frame.byteCount at hlength
      rw [hfirst] at hlength
      exact hlength
    exact byte_last_from_length bytes.last frame.byteCount hlengthRaw hpositiveCount
  have hcontains :
      bytes.first ≤ Int.ofNat
          (Int.toNat (Int.ofNat y * frame.width + Int.ofNat x) + 1) ∧
      Int.ofNat
          (Int.toNat (Int.ofNat y * frame.width + Int.ofNat x) + 1) ≤ bytes.last := by
    rw [hfirst, hbytesLast, hindexCast]
    exact ⟨int_ofNat_le_ofNat 1 _ hindexLowerNat,
      int_ofNat_le_ofNat _ _ hindexUpperNat⟩
  exact pixel_at_reads_byte_content frame bytes x y hbytes
    hfirstGuard hsecondGuard hindexGuard hcontains

theorem grab_success_pixel_reads_row_major_byte (state : CameraState)
    (handle timeout : Nat) (image : Image) (status : FrameStatus)
    (observation : Observation) (bytes : ByteArrayView) (x y : Nat)
    (hrelation : Model.grabRelation state handle timeout image status observation)
    (hstatus : status = .success)
    (hbytes : observation.bytes = some bytes)
    (hyImage : imageRangeContains image 1 y = true)
    (hxImage : imageRangeContains image 2 x = true) :
    imagePixel image y x =
      bytes.content (Int.toNat (Int.ofNat y * observation.width + Int.ofNat x) + 1) := by
  unfold Model.grabRelation at hrelation
  rcases hrelation with ⟨_, _, _, _, hpost⟩
  unfold Model.grabPost at hpost
  subst status
  have himage := hpost.2
  have hsuccess : (FrameStatus.success == .success) = true := rfl
  rw [if_pos hsuccess] at himage
  have hpixel := himage.2 y hyImage x hxImage
  rw [hpixel]
  have hstatusModel : Model.grabStatus state timeout observation = .success := by
    rcases hpost.1.1.2 with hstatusModel | ⟨hmodelSuccess, hstatusOOM⟩
    · exact hstatusModel.symm
    · cases hstatusOOM
  exact successful_pixel_reads_byte state timeout observation image bytes x y
    hstatusModel himage.1.1.1 himage.1.1.2 himage.1.2 hbytes hyImage hxImage

theorem build_frame_success_pixel_reads_row_major_byte (state : CameraState)
    (timeout : Nat) (observation : Observation) (image : Image) (status : FrameStatus)
    (bytes : ByteArrayView) (x y : Nat)
    (hrelation : Model.buildFrameRelation state timeout observation image status)
    (hstatus : status = .success)
    (hbytes : observation.bytes = some bytes)
    (hyImage : imageRangeContains image 1 y = true)
    (hxImage : imageRangeContains image 2 x = true) :
    imagePixel image y x =
      bytes.content (Int.toNat (Int.ofNat y * observation.width + Int.ofNat x) + 1) := by
  unfold Model.buildFrameRelation at hrelation
  rcases hrelation with ⟨_, _, _, hpost⟩
  unfold Model.buildFramePost at hpost
  subst status
  have himage := hpost.2
  have hsuccess : (FrameStatus.success == .success) = true := rfl
  rw [if_pos hsuccess] at himage
  have hpixel := himage.2 y hyImage x hxImage
  rw [hpixel]
  have hstatusModel : Model.grabStatus state timeout observation = .success := by
    rcases hpost.1 with hstatusModel | ⟨hmodelSuccess, hstatusOOM⟩
    · exact hstatusModel.symm
    · cases hstatusOOM
  exact successful_pixel_reads_byte state timeout observation image bytes x y
    hstatusModel himage.1.1.1 himage.1.1.2 himage.1.2 hbytes hyImage hxImage

theorem grab_failure_returns_null (state : CameraState) (handle timeout : Nat)
    (image : Image) (status : FrameStatus) (observation : Observation)
    (hrelation : Model.grabRelation state handle timeout image status observation)
    (hstatus : status ≠ .success) :
    image = none := by
  unfold Model.grabRelation at hrelation
  rcases hrelation with ⟨_, _, _, _, hpost⟩
  unfold Model.grabPost at hpost
  have himage := hpost.2
  cases status with
  | success => exact False.elim (hstatus rfl)
  | badParameter => exact himage
  | timeout => exact himage
  | unsupportedPayload => exact himage
  | unsupportedFormat => exact himage
  | invalidDimensions => exact himage
  | tooLarge => exact himage
  | invalidLength => exact himage
  | outOfMemory => exact himage
  | error => exact himage

theorem build_frame_failure_returns_null (state : CameraState) (timeout : Nat)
    (observation : Observation) (image : Image) (status : FrameStatus)
    (hrelation : Model.buildFrameRelation state timeout observation image status)
    (hstatus : status ≠ .success) :
    image = none := by
  unfold Model.buildFrameRelation at hrelation
  rcases hrelation with ⟨_, _, _, hpost⟩
  unfold Model.buildFramePost at hpost
  have himage := hpost.2
  cases status with
  | success => exact False.elim (hstatus rfl)
  | badParameter => exact himage
  | timeout => exact himage
  | unsupportedPayload => exact himage
  | unsupportedFormat => exact himage
  | invalidDimensions => exact himage
  | tooLarge => exact himage
  | invalidLength => exact himage
  | outOfMemory => exact himage
  | error => exact himage

end CameraLifecycle.Grab
