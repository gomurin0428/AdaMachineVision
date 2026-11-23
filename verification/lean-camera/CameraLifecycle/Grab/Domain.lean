import CameraLifecycle.Model

namespace CameraLifecycle.Grab

open CameraLifecycle.Model

def naturalMax : Nat := 2147483647
def int32Min : Int := -2147483648
def int32Max : Int := 2147483647
def byteZero : UInt8 := UInt8.ofFin ⟨0, Nat.zero_lt_succ 255⟩

inductive FrameStatus where
  | success
  | badParameter
  | timeout
  | unsupportedPayload
  | unsupportedFormat
  | invalidDimensions
  | tooLarge
  | invalidLength
  | outOfMemory
  | error
  deriving DecidableEq, BEq, Repr

structure ByteArrayView where
  first : Int
  last : Int
  content : Nat → UInt8

structure Observation where
  acquisitionStatus : NativeResult
  byteCount : Nat
  bytes : Option ByteArrayView
  bufferStatus : Int
  payloadType : Nat
  pixelFormat : Nat
  width : Int
  height : Int
  sourceSize : Nat

structure PixelMatrix where
  firstRow : Int
  lastRow : Int
  firstColumn : Int
  lastColumn : Int
  content : Nat → Nat → UInt8

structure ImageData where
  width : Int
  height : Int
  pixels : Option PixelMatrix

abbrev Image := Option ImageData

def int32Domain (value : Int) : Prop :=
  int32Min ≤ value ∧ value ≤ int32Max

def observationDomain (frame : Observation) : Prop :=
  frame.byteCount ≤ naturalMax ∧
  int32Domain frame.bufferStatus ∧
  frame.payloadType < 2^32 ∧
  frame.pixelFormat < 2^32 ∧
  int32Domain frame.width ∧
  int32Domain frame.height ∧
  frame.sourceSize < 2^64 ∧
  (match frame.bytes with
   | none => True
   | some bytes =>
       int32Domain bytes.first ∧ int32Domain bytes.last ∧
       (bytes.last < bytes.first ∨ 0 < bytes.first))

def imageDomain (image : Image) : Prop :=
  match image with
  | none => True
  | some data =>
      int32Domain data.width ∧ int32Domain data.height ∧
      (match data.pixels with
       | none => True
       | some pixels =>
           int32Domain pixels.firstRow ∧ int32Domain pixels.lastRow ∧
           int32Domain pixels.firstColumn ∧ int32Domain pixels.lastColumn ∧
           (pixels.lastRow < pixels.firstRow ∨ 0 ≤ pixels.firstRow) ∧
           (pixels.lastColumn < pixels.firstColumn ∨ 0 ≤ pixels.firstColumn))

def byteFirst (frame : Observation) : Int :=
  (frame.bytes.map ByteArrayView.first).getD 0

def byteLength (frame : Observation) : Nat :=
  match frame.bytes with
  | none => 0
  | some bytes =>
      if bytes.last < bytes.first then 0 else Int.toNat (bytes.last - bytes.first + 1)

def byteAt (frame : Observation) (index : Nat) : UInt8 :=
  (frame.bytes.bind fun bytes =>
      if bytes.first ≤ Int.ofNat index ∧ Int.ofNat index ≤ bytes.last then
        some (bytes.content index)
      else none).getD byteZero

def imageFirstRow (image : Image) : Int :=
  ((image.bind ImageData.pixels).map PixelMatrix.firstRow).getD 0

def imageLastRow (image : Image) : Int :=
  ((image.bind ImageData.pixels).map PixelMatrix.lastRow).getD 0

def imageFirstColumn (image : Image) : Int :=
  ((image.bind ImageData.pixels).map PixelMatrix.firstColumn).getD 0

def imageLastColumn (image : Image) : Int :=
  ((image.bind ImageData.pixels).map PixelMatrix.lastColumn).getD 0

def imagePixel (image : Image) (row column : Nat) : UInt8 :=
  ((image.bind ImageData.pixels).bind fun pixels =>
    if pixels.firstRow ≤ Int.ofNat row ∧ Int.ofNat row ≤ pixels.lastRow ∧
       pixels.firstColumn ≤ Int.ofNat column ∧ Int.ofNat column ≤ pixels.lastColumn
    then some (pixels.content row column) else none).getD byteZero

def imageRangeContains (image : Image) (axis index : Nat) : Bool :=
  if axis = 1 then
    decide (imageFirstRow image ≤ Int.ofNat index) &&
    decide (Int.ofNat index ≤ imageLastRow image)
  else
    decide (imageFirstColumn image ≤ Int.ofNat index) &&
    decide (Int.ofNat index ≤ imageLastColumn image)

end CameraLifecycle.Grab
