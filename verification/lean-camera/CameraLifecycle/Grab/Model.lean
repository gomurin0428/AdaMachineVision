import CameraLifecycle.Grab.Domain

namespace CameraLifecycle.Grab.Model

open CameraLifecycle.Model
open CameraLifecycle.Grab

def validObservation (frame : Observation) : Bool :=
  if frame.byteCount == 0 then
    frame.bytes.isNone
  else
    frame.bytes.isSome &&
    byteFirst frame == 1 &&
    byteLength frame == frame.byteCount &&
    frame.byteCount == frame.sourceSize

def validImage (image : Image) : Bool :=
  image.isSome &&
  (image.bind ImageData.pixels).isSome &&
  decide ((image.map ImageData.width).getD 0 ≥ 1) &&
  decide ((image.map ImageData.height).getD 0 ≥ 1) &&
  imageFirstRow image == 0 &&
  imageFirstColumn image == 0 &&
  imageLastRow image == (image.map ImageData.height).getD 0 - 1 &&
  imageLastColumn image == (image.map ImageData.width).getD 0 - 1

def grabStatus (state : CameraState) (timeout : Nat) (frame : Observation) : FrameStatus :=
  if state != .streaming || timeout == 0 then
    .badParameter
  else if frame.acquisitionStatus == .notCalled || frame.acquisitionStatus == .badParameter then
    .badParameter
  else if frame.acquisitionStatus == .timeout then
    .timeout
  else if frame.acquisitionStatus == .outOfMemory then
    .outOfMemory
  else if frame.acquisitionStatus == .unsupported || frame.acquisitionStatus == .error then
    .error
  else if frame.bufferStatus == 2 then
    .timeout
  else if frame.bufferStatus != 0 then
    .error
  else if frame.payloadType != 1 then
    .unsupportedPayload
  else if frame.pixelFormat != 17301505 then
    .unsupportedFormat
  else if decide (frame.width ≤ 0) || decide (frame.height ≤ 0) then
    .invalidDimensions
  else if decide (frame.width * frame.height > 2147483647) then
    .tooLarge
  else if frame.sourceSize != Int.toNat (frame.width * frame.height) ||
          (Int.ofNat frame.byteCount) != frame.width * frame.height ||
          frame.bytes.isNone ||
          byteFirst frame != 1 ||
          (Int.ofNat (byteLength frame)) != frame.width * frame.height then
    .invalidLength
  else
    .success

def pixelAt (frame : Observation) (x y : Nat) : UInt8 :=
  letI : OfNat UInt8 0 := ⟨byteZero⟩
  if decide (frame.width ≤ 0) || decide (frame.height ≤ 0) ||
      frame.byteCount == 0 || frame.bytes.isNone then
    0
  else if byteFirst frame != 1 || byteLength frame != frame.byteCount ||
          decide (x ≥ Int.toNat frame.width) || decide (y ≥ Int.toNat frame.height) then
    0
  else if decide (Int.ofNat y * frame.width + Int.ofNat x ≥ Int.ofNat frame.byteCount) then
    0
  else
    byteAt frame (Int.toNat (Int.ofNat y * frame.width + Int.ofNat x) + 1)

def grabPre (state : CameraState) (handle : Nat) : Bool :=
  (state == .closed) == (handle == 0)

def grabPost (state : CameraState) (timeout : Nat) (image : Image)
    (status : FrameStatus) (observation : Observation) : Prop :=
  (((validObservation observation = true ∧
    ((state = .streaming ∧ timeout > 0) ↔
      observation.acquisitionStatus ≠ .notCalled)) ∧
    (status = grabStatus state timeout observation ∨
      (grabStatus state timeout observation = .success ∧ status = .outOfMemory))) ∧
  (if state != .streaming || timeout == 0 then
    ((((((((observation.acquisitionStatus = .notCalled ∧
      observation.byteCount = 0) ∧ observation.bytes = none) ∧
      observation.bufferStatus = -1) ∧ observation.payloadType = 0) ∧
      observation.pixelFormat = 0) ∧ observation.width = 0) ∧
      observation.height = 0) ∧ observation.sourceSize = 0)
   else True)) ∧
  (if status == .success then
    (((validImage image = true ∧
      (image.map ImageData.width).getD 0 = observation.width) ∧
      (image.map ImageData.height).getD 0 = observation.height) ∧
    (∀ y, imageRangeContains image 1 y = true →
      ∀ x, imageRangeContains image 2 x = true →
        imagePixel image y x = pixelAt observation x y))
   else image = none)

def buildFramePost (state : CameraState) (timeout : Nat) (observation : Observation)
    (image : Image) (status : FrameStatus) : Prop :=
  (status = grabStatus state timeout observation ∨
    (grabStatus state timeout observation = .success ∧ status = .outOfMemory)) ∧
  (if status == .success then
    (((validImage image = true ∧
      (image.map ImageData.width).getD 0 = observation.width) ∧
      (image.map ImageData.height).getD 0 = observation.height) ∧
    (∀ y, imageRangeContains image 1 y = true →
      ∀ x, imageRangeContains image 2 x = true →
        imagePixel image y x = pixelAt observation x y))
   else image = none)

def grabRelation (state : CameraState) (handle timeout : Nat) (image : Image)
    (status : FrameStatus) (observation : Observation) : Prop :=
  observationDomain observation ∧ timeout ≤ naturalMax ∧ imageDomain image ∧
  grabPre state handle = true ∧
  grabPost state timeout image status observation

def buildFrameRelation (state : CameraState) (timeout : Nat) (observation : Observation)
    (image : Image) (status : FrameStatus) : Prop :=
  observationDomain observation ∧ timeout ≤ naturalMax ∧ imageDomain image ∧
  buildFramePost state timeout observation image status

end CameraLifecycle.Grab.Model
