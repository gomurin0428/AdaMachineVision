import CameraLifecycle.Model

namespace CameraLifecycle.Generated

open CameraLifecycle.Model

def cameraResult (result : NativeResult) : CameraStatus :=
  match result with
  | .notCalled => .badParameter
  | .success => .success
  | .timeout => .error
  | .badParameter => .badParameter
  | .unsupported => .unsupported
  | .outOfMemory => .outOfMemory
  | .error => .error

def cameraResultPre (result : NativeResult) : Bool :=
  ((result) != (.notCalled))


def openStatus (state : CameraState) (selectorValid : Bool) (result : NativeResult) : CameraStatus :=
  (if ((((state) != (.closed))) || ((!(selectorValid)))) then .badParameter else (if ((result) == (.notCalled)) then .error else cameraResult (result)))


def openState (state : CameraState) (selectorValid : Bool) (result : NativeResult) : CameraState :=
  (if ((((((state) == (.closed))) && (selectorValid))) && (((result) == (.success)))) then .openStopped else state)


def startStatus (state : CameraState) (result : NativeResult) : CameraStatus :=
  (if ((state) == (.closed)) then .badParameter else (if ((state) == (.streaming)) then .success else (if ((result) == (.notCalled)) then .error else cameraResult (result))))


def startState (state : CameraState) (result : NativeResult) : CameraState :=
  (if ((((state) == (.openStopped))) && (((result) == (.success)))) then .streaming else state)


def stopStatus (state : CameraState) (result : NativeResult) : CameraStatus :=
  (if ((state) != (.streaming)) then .success else (if ((result) == (.notCalled)) then .error else cameraResult (result)))


def stopState (state : CameraState) (result : NativeResult) : CameraState :=
  (if ((((state) == (.streaming))) && (((result) == (.success)))) then .openStopped else state)


def isOpen (state : CameraState) : Bool :=
  ((state) != (.closed))


def isStreaming (state : CameraState) : Bool :=
  ((state) == (.streaming))


def openStatusCameraResultCallGuard (state : CameraState) (selectorValid : Bool) (result : NativeResult) : Bool :=
  (!(((((((state) != (.closed))) || ((!(selectorValid))))) || (((result) == (.notCalled))))))


def startStatusCameraResultCallGuard (state : CameraState) (result : NativeResult) : Bool :=
  (!(((((((state) == (.closed))) || (((state) == (.streaming))))) || (((result) == (.notCalled))))))


def stopStatusCameraResultCallGuard (state : CameraState) (result : NativeResult) : Bool :=
  (!(((((state) != (.streaming))) || (((result) == (.notCalled))))))


def openPre (oldState : CameraState) (oldHandle : Nat) : Bool :=
  ((((oldState) == (.closed))) == (((oldHandle) == (0))))


def openPost (oldState : CameraState) (oldHandle : Nat) (selectorValid : Bool) (newState : CameraState) (newHandle : Nat) (status : CameraStatus) (receipt : NativeResult) : Bool :=
  ((((((((status) == (openStatus (oldState) (selectorValid) (receipt)))) && (((newState) == (openState (oldState) (selectorValid) (receipt)))))) && (((((receipt) == (.notCalled))) == (((((oldState) != (.closed))) || ((!(selectorValid))))))))) && ((if ((((((receipt) == (.success))) && (((oldState) == (.closed))))) && (selectorValid)) then ((newHandle) != (0)) else ((newHandle) == (oldHandle)))))


def openRelation (oldState : CameraState) (oldHandle : Nat) (selectorValid : Bool) (newState : CameraState) (newHandle : Nat) (status : CameraStatus) (receipt : NativeResult) : Prop :=
  openPre (oldState) (oldHandle) = true ∧ openPost (oldState) (oldHandle) (selectorValid) (newState) (newHandle) (status) (receipt) = true


def startPre (oldState : CameraState) (handle : Nat) : Bool :=
  ((((oldState) == (.closed))) == (((handle) == (0))))


def startPost (oldState : CameraState) (newState : CameraState) (status : CameraStatus) (receipt : NativeResult) : Bool :=
  ((((((status) == (startStatus (oldState) (receipt)))) && (((newState) == (startState (oldState) (receipt)))))) && (((((receipt) == (.notCalled))) == (((oldState) != (.openStopped))))))


def startRelation (oldState : CameraState) (handle : Nat) (newState : CameraState) (status : CameraStatus) (receipt : NativeResult) : Prop :=
  startPre (oldState) (handle) = true ∧ startPost (oldState) (newState) (status) (receipt) = true


def stopPre (oldState : CameraState) (handle : Nat) : Bool :=
  ((((oldState) == (.closed))) == (((handle) == (0))))


def stopPost (oldState : CameraState) (newState : CameraState) (status : CameraStatus) (receipt : NativeResult) : Bool :=
  ((((((status) == (stopStatus (oldState) (receipt)))) && (((newState) == (stopState (oldState) (receipt)))))) && (((((receipt) == (.notCalled))) == (((oldState) != (.streaming))))))


def stopRelation (oldState : CameraState) (handle : Nat) (newState : CameraState) (status : CameraStatus) (receipt : NativeResult) : Prop :=
  stopPre (oldState) (handle) = true ∧ stopPost (oldState) (newState) (status) (receipt) = true


def closePre (oldState : CameraState) (oldHandle : Nat) : Bool :=
  ((((oldState) == (.closed))) == (((oldHandle) == (0))))


def closePost (oldState : CameraState) (_oldHandle : Nat) (newState : CameraState) (newHandle : Nat) (receipt : NativeResult) : Bool :=
  ((((((newState) == (.closed))) && (((newHandle) == (0))))) && ((if ((oldState) == (.closed)) then ((receipt) == (.notCalled)) else (if ((oldState) == (.streaming)) then ((receipt) != (.notCalled)) else true))))


def closeRelation (oldState : CameraState) (oldHandle : Nat) (newState : CameraState) (newHandle : Nat) (receipt : NativeResult) : Prop :=
  closePre (oldState) (oldHandle) = true ∧ closePost (oldState) (oldHandle) (newState) (newHandle) (receipt) = true


def isOpenPost (state : CameraState) (result : Bool) : Bool :=
  ((result) == (isOpen (state)))


def isOpenRelation (state : CameraState) (result : Bool) : Prop :=
  isOpenPost (state) (result) = true


def isStreamingPost (state : CameraState) (result : Bool) : Bool :=
  ((result) == (isStreaming (state)))


def isStreamingRelation (state : CameraState) (result : Bool) : Prop :=
  isStreamingPost (state) (result) = true


end CameraLifecycle.Generated
