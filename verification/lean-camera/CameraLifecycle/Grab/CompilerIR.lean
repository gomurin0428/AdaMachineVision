namespace CameraLifecycle.Grab

inductive ScalarType where
  | natural
  | positive
  | integer
  | int32
  | int64
  deriving DecidableEq, Repr

structure ScalarBounds where
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
  deriving DecidableEq, Repr

inductive ScalarExpr where
  | x
  | y
  | width
  | height
  | arrayFirst
  | arrayLast
  | literal (value : Int)
  | cast (target : ScalarType) (value : ScalarExpr)
  | add (resultType : ScalarType) (left right : ScalarExpr)
  | mul (resultType : ScalarType) (left right : ScalarExpr)
  deriving DecidableEq, Repr

structure ScalarEnvironment where
  x : Nat
  y : Nat
  width : Int
  height : Int
  first : Int
  last : Int
  deriving DecidableEq, Repr

inductive ScalarPredicate where
  | not (predicate : ScalarPredicate)
  | inRange (value lower upper : ScalarExpr)
  | equal (left right : ScalarExpr)
  deriving DecidableEq, Repr

inductive ScalarFailure where
  | range
  | overflow
  deriving DecidableEq, Repr

inductive IndexFailure where
  | expressionRange
  | expressionOverflow
  | naturalRange
  | incrementOverflow
  | positiveRange
  | arrayIndex
  deriving DecidableEq, Repr

inductive IndexOutcome where
  | failure (kind : IndexFailure)
  | value (index : Int)
  deriving DecidableEq, Repr

def ScalarBounds.forType (bounds : ScalarBounds) (ty : ScalarType) : Int × Int :=
  match ty with
  | .natural => (bounds.naturalMin, bounds.naturalMax)
  | .positive => (bounds.positiveMin, bounds.positiveMax)
  | .integer => (bounds.integerMin, bounds.integerMax)
  | .int32 => (bounds.int32Min, bounds.int32Max)
  | .int64 => (bounds.int64Min, bounds.int64Max)

def checkedValue (bounds : ScalarBounds) (ty : ScalarType) (value : Int)
    (failure : ScalarFailure) : Except ScalarFailure Int :=
  let (lower, upper) := bounds.forType ty
  if lower ≤ value ∧ value ≤ upper then .ok value else .error failure

def evalScalar (bounds : ScalarBounds) (env : ScalarEnvironment) : ScalarExpr → Except ScalarFailure Int
  | .x => .ok (Int.ofNat env.x)
  | .y => .ok (Int.ofNat env.y)
  | .width => .ok env.width
  | .height => .ok env.height
  | .arrayFirst => .ok env.first
  | .arrayLast => .ok env.last
  | .literal value => .ok value
  | .cast target value => do
      let value ← evalScalar bounds env value
      checkedValue bounds target value .range
  | .add resultType left right => do
      let left ← evalScalar bounds env left
      let right ← evalScalar bounds env right
      checkedValue bounds resultType (left + right) .overflow
  | .mul resultType left right => do
      let left ← evalScalar bounds env left
      let right ← evalScalar bounds env right
      checkedValue bounds resultType (left * right) .overflow

def evalPredicate (bounds : ScalarBounds) (env : ScalarEnvironment) :
    ScalarPredicate → Except ScalarFailure Bool
  | .not predicate => do
      let result ← evalPredicate bounds env predicate
      .ok (!result)
  | .inRange value lower upper => do
      let value ← evalScalar bounds env value
      let lower ← evalScalar bounds env lower
      let upper ← evalScalar bounds env upper
      .ok (decide (lower ≤ value) && decide (value ≤ upper))
  | .equal left right => do
      let left ← evalScalar bounds env left
      let right ← evalScalar bounds env right
      .ok (left == right)

def finishIndex (bounds : ScalarBounds) (row first last : Int) : IndexOutcome :=
  let (naturalMin, naturalMax) := bounds.forType .natural
  if row < naturalMin ∨ naturalMax < row then .failure .naturalRange
  else if row + 1 < bounds.integerMin ∨ bounds.integerMax < row + 1 then
    .failure .incrementOverflow
  else if row + 1 < bounds.positiveMin ∨ bounds.positiveMax < row + 1 then
    .failure .positiveRange
  else if ¬(first ≤ row + 1 ∧ row + 1 ≤ last) then .failure .arrayIndex
  else .value (row + 1)

def finishCompilerIndex (bounds : ScalarBounds) (row : Except ScalarFailure Int)
    (first last : Int) : IndexOutcome :=
  match row with
  | .error .range => .failure .expressionRange
  | .error .overflow => .failure .expressionOverflow
  | .ok value => finishIndex bounds value first last

def compilerIndex (bounds : ScalarBounds) (env : ScalarEnvironment)
    (row : ScalarExpr) (first last : Int) : IndexOutcome :=
  finishCompilerIndex bounds (evalScalar bounds env row) first last

def interpretCompilerIndex (bounds : ScalarBounds) (env : ScalarEnvironment)
    (row : ScalarExpr) (naturalFailure overflowFailure arrayFailure : ScalarPredicate)
    (indexValue : ScalarExpr) : IndexOutcome :=
  match evalScalar bounds env row with
  | .error .range => .failure .expressionRange
  | .error .overflow => .failure .expressionOverflow
  | .ok _ =>
    match evalPredicate bounds env naturalFailure with
    | .error .range => .failure .expressionRange
    | .error .overflow => .failure .expressionOverflow
    | .ok true => .failure .naturalRange
    | .ok false =>
      match evalPredicate bounds env overflowFailure with
      | .error .range => .failure .expressionRange
      | .error .overflow => .failure .expressionOverflow
      | .ok true => .failure .incrementOverflow
      | .ok false =>
        match evalPredicate bounds env arrayFailure with
        | .error .range => .failure .positiveRange
        | .error .overflow => .failure .incrementOverflow
        | .ok true => .failure .arrayIndex
        | .ok false =>
          match evalScalar bounds env indexValue with
          | .error .range => .failure .positiveRange
          | .error .overflow => .failure .incrementOverflow
          | .ok value => .value value

def mathematicalRow (env : ScalarEnvironment) : Int :=
  (Int.ofNat env.y) * env.width + Int.ofNat env.x

def mathematicalIndex (bounds : ScalarBounds) (env : ScalarEnvironment)
    (first last : Int) : IndexOutcome :=
  finishIndex bounds (mathematicalRow env) first last

end CameraLifecycle.Grab
