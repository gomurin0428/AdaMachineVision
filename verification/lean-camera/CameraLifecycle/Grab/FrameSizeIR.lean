import CameraLifecycle.Grab.Domain

namespace CameraLifecycle.Grab

inductive FrameSizeScalarType where
  | int32
  | natural
  | positive
  | integer
  | int64
  | unsigned64
  | size

inductive FrameSizeFailure where
  | rangeCheck
  | overflowCheck
  | accessCheck
  | invalidData
  | indexCheck
  deriving DecidableEq, Repr

mutual
  inductive FrameSizeExpr : Type where
  | width
  | height
  | byteCount
  | sourceSize
  | byteFirst
  | byteLast
  | literal (value : Int)
  | cast (target : FrameSizeScalarType) (value : FrameSizeExpr)
  | check (failure : FrameSizeFailure) (condition : FrameSizePredicate)
  | checked (failure : FrameSizeFailure) (condition : FrameSizePredicate) (value : FrameSizeExpr)
  | sequence (first : FrameSizeExpr) (second : FrameSizeExpr)
  | multiply (target : FrameSizeScalarType) (left right : FrameSizeExpr)
  | add (target : FrameSizeScalarType) (left right : FrameSizeExpr)
  | subtract (target : FrameSizeScalarType) (left right : FrameSizeExpr)
  | ifThenElse (condition : FrameSizePredicate) (yes no : FrameSizeExpr)

  inductive FrameSizePredicate : Type where
  | bytesNull
  | not (value : FrameSizePredicate)
  | orElse (left right : FrameSizePredicate)
  | andThen (left right : FrameSizePredicate)
  | checked (failure : FrameSizeFailure) (condition : FrameSizePredicate) (value : FrameSizePredicate)
  | sequence (first : FrameSizeExpr) (second : FrameSizePredicate)
  | equal (left right : FrameSizeExpr)
  | notEqual (left right : FrameSizeExpr)
  | less (left right : FrameSizeExpr)
  | lessEqual (left right : FrameSizeExpr)
  | greater (left right : FrameSizeExpr)
  | greaterEqual (left right : FrameSizeExpr)
end

inductive FrameSizeControl where
  | returnStatus (status : FrameStatus)
  | ifThenElse (condition : FrameSizePredicate) (yes no : FrameSizeControl)

inductive FrameSizeCheckKind where
  | range
  | overflow
  | invalidData
  | access
  | index
  deriving DecidableEq, Repr

structure FrameSizeCheck where
  kind : FrameSizeCheckKind
  nodeId : Nat
  predicate : FrameSizePredicate

structure FrameSizeProgram where
  dimensions : FrameSizePredicate
  product : FrameSizeExpr
  limit : FrameSizePredicate
  invalidLength : FrameSizePredicate
  arrayLength : FrameSizeExpr
  control : FrameSizeControl
  checks : List FrameSizeCheck

structure FrameSizeBounds where
  naturalMin : Int
  naturalMax : Int
  positiveMin : Int
  positiveMax : Int
  integerMin : Int
  integerMax : Int
  int32Min : Int
  int32Max : Int
  int64Min : Int
  int64Max : Int
  unsigned64Max : Int
  sizeMin : Int
  sizeMax : Int

structure FrameSizeResolvedType where
  name : String
  nodeId : Nat
  typeNodeId : Nat
  typeName : String
  lower : Int
  upper : Int
  representationLower : Int
  representationUpper : Int

structure FrameSizeStatusCodes where
  invalidDimensions : Nat
  tooLarge : Nat
  invalidLength : Nat
  success : Nat

inductive FrameSizeOutcome where
  | failed (reason : FrameSizeFailure)
  | returned (status : FrameStatus)
  deriving DecidableEq, Repr

def scalarBounds (bounds : FrameSizeBounds) (ty : FrameSizeScalarType) : Int × Int :=
  match ty with
  | .int32 => (bounds.int32Min, bounds.int32Max)
  | .natural => (bounds.naturalMin, bounds.naturalMax)
  | .positive => (bounds.positiveMin, bounds.positiveMax)
  | .integer => (bounds.integerMin, bounds.integerMax)
  | .int64 => (bounds.int64Min, bounds.int64Max)
  | .unsigned64 => (0, bounds.unsigned64Max)
  | .size => (bounds.sizeMin, bounds.sizeMax)

def checkedFrameSizeValue (bounds : FrameSizeBounds) (ty : FrameSizeScalarType)
    (failure : FrameSizeFailure) (value : Int) : Except FrameSizeFailure Int :=
  let (lower, upper) := scalarBounds bounds ty
  if lower ≤ value && value ≤ upper then .ok value else .error failure

mutual
  def evalFrameSizeExpr (bounds : FrameSizeBounds) (frame : Observation)
      (expression : FrameSizeExpr) : Except FrameSizeFailure Int :=
    match expression with
    | .width => .ok frame.width
    | .height => .ok frame.height
    | .byteCount => .ok (Int.ofNat frame.byteCount)
    | .sourceSize => .ok (Int.ofNat frame.sourceSize)
    | .byteFirst =>
        match frame.bytes with
        | none => .error .accessCheck
        | some bytes => .ok bytes.first
    | .byteLast =>
        match frame.bytes with
        | none => .error .accessCheck
        | some bytes => .ok bytes.last
    | .literal value => .ok value
    | .check failure condition => do
        if ← evalFrameSizePredicate bounds frame condition then .error failure else .ok 0
    | .checked failure condition value => do
        if ← evalFrameSizePredicate bounds frame condition then .error failure
        else evalFrameSizeExpr bounds frame value
    | .sequence first second => do
        let _ ← evalFrameSizeExpr bounds frame first
        evalFrameSizeExpr bounds frame second
    | .cast .int64 .byteCount =>
        let value := Int.ofNat frame.byteCount
        if bounds.naturalMin ≤ value && value ≤ bounds.naturalMax then
          checkedFrameSizeValue bounds .int64 .rangeCheck value
        else
          .error .invalidData
    | .cast target value => do
        let value ← evalFrameSizeExpr bounds frame value
        checkedFrameSizeValue bounds target .rangeCheck value
    | .multiply target left right => do
        let left ← evalFrameSizeExpr bounds frame left
        let right ← evalFrameSizeExpr bounds frame right
        checkedFrameSizeValue bounds target .overflowCheck (left * right)
    | .add target left right => do
        let left ← evalFrameSizeExpr bounds frame left
        let right ← evalFrameSizeExpr bounds frame right
        checkedFrameSizeValue bounds target .overflowCheck (left + right)
    | .subtract target left right => do
        let left ← evalFrameSizeExpr bounds frame left
        let right ← evalFrameSizeExpr bounds frame right
        checkedFrameSizeValue bounds target .overflowCheck (left - right)
    | .ifThenElse condition yes no => do
        let condition ← evalFrameSizePredicate bounds frame condition
        if condition then evalFrameSizeExpr bounds frame yes
        else evalFrameSizeExpr bounds frame no
  termination_by structural expression

  def evalFrameSizePredicate (bounds : FrameSizeBounds) (frame : Observation)
      (predicate : FrameSizePredicate) : Except FrameSizeFailure Bool :=
    match predicate with
    | .bytesNull => .ok frame.bytes.isNone
    | .not value => do
        pure !(← evalFrameSizePredicate bounds frame value)
    | .orElse left right => do
        if ← evalFrameSizePredicate bounds frame left then pure true
        else evalFrameSizePredicate bounds frame right
    | .andThen left right => do
        if ← evalFrameSizePredicate bounds frame left then evalFrameSizePredicate bounds frame right
        else pure false
    | .checked failure condition value => do
        if ← evalFrameSizePredicate bounds frame condition then .error failure
        else evalFrameSizePredicate bounds frame value
    | .sequence first second => do
        let _ ← evalFrameSizeExpr bounds frame first
        evalFrameSizePredicate bounds frame second
    | .equal left right => do
        pure ((← evalFrameSizeExpr bounds frame left) == (← evalFrameSizeExpr bounds frame right))
    | .notEqual left right => do
        pure ((← evalFrameSizeExpr bounds frame left) != (← evalFrameSizeExpr bounds frame right))
    | .less left right => do
        pure ((← evalFrameSizeExpr bounds frame left) < (← evalFrameSizeExpr bounds frame right))
    | .lessEqual left right => do
        pure ((← evalFrameSizeExpr bounds frame left) ≤ (← evalFrameSizeExpr bounds frame right))
    | .greater left right => do
        pure ((← evalFrameSizeExpr bounds frame left) > (← evalFrameSizeExpr bounds frame right))
    | .greaterEqual left right => do
        pure ((← evalFrameSizeExpr bounds frame left) ≥ (← evalFrameSizeExpr bounds frame right))
  termination_by structural predicate
end

def evalFrameSizeControl (bounds : FrameSizeBounds) (frame : Observation) :
    FrameSizeControl → Except FrameSizeFailure FrameStatus
  | .returnStatus status => .ok status
  | .ifThenElse condition yes no => do
      if ← evalFrameSizePredicate bounds frame condition then
        evalFrameSizeControl bounds frame yes
      else
        evalFrameSizeControl bounds frame no

def runFrameSizeProgram (program : FrameSizeProgram) (bounds : FrameSizeBounds)
    (frame : Observation) : FrameSizeOutcome :=
  match evalFrameSizeControl bounds frame program.control with
  | .ok status => .returned status
  | .error reason => .failed reason

end CameraLifecycle.Grab
