import CameraLifecycle.Generated

namespace CameraLifecycle

open Model

@[simp] theorem camera_result_agrees (result : NativeResult) :
    Model.cameraResult result = Generated.cameraResult result := by
  cases result <;> rfl

@[simp] theorem camera_result_pre_agrees (result : NativeResult) :
    Model.cameraResultPre result = Generated.cameraResultPre result := by
  cases result <;> rfl

@[simp] theorem open_status_agrees (state : CameraState) (selectorValid : Bool)
    (result : NativeResult) :
    Model.openStatus state selectorValid result =
      Generated.openStatus state selectorValid result := by
  cases state <;> cases selectorValid <;> cases result <;> rfl

@[simp] theorem open_state_agrees (state : CameraState) (selectorValid : Bool)
    (result : NativeResult) :
    Model.openState state selectorValid result =
      Generated.openState state selectorValid result := by
  cases state <;> cases selectorValid <;> cases result <;> rfl

@[simp] theorem start_status_agrees (state : CameraState)
    (result : NativeResult) :
    Model.startStatus state result = Generated.startStatus state result := by
  cases state <;> cases result <;> rfl

@[simp] theorem start_state_agrees (state : CameraState)
    (result : NativeResult) :
    Model.startState state result = Generated.startState state result := by
  cases state <;> cases result <;> rfl

@[simp] theorem stop_status_agrees (state : CameraState)
    (result : NativeResult) :
    Model.stopStatus state result = Generated.stopStatus state result := by
  cases state <;> cases result <;> rfl

@[simp] theorem stop_state_agrees (state : CameraState)
    (result : NativeResult) :
    Model.stopState state result = Generated.stopState state result := by
  cases state <;> cases result <;> rfl

@[simp] theorem is_open_agrees (state : CameraState) :
    Model.isOpen state = Generated.isOpen state := by
  cases state <;> rfl

@[simp] theorem is_streaming_agrees (state : CameraState) :
    Model.isStreaming state = Generated.isStreaming state := by
  cases state <;> rfl

theorem open_pre_agrees (oldState : CameraState) (oldHandle : Nat) :
    Model.openPre oldState oldHandle = Generated.openPre oldState oldHandle := by
  rfl

theorem start_pre_agrees (oldState : CameraState) (handle : Nat) :
    Model.startPre oldState handle = Generated.startPre oldState handle := by
  rfl

theorem stop_pre_agrees (oldState : CameraState) (handle : Nat) :
    Model.stopPre oldState handle = Generated.stopPre oldState handle := by
  rfl

theorem close_pre_agrees (oldState : CameraState) (oldHandle : Nat) :
    Model.closePre oldState oldHandle = Generated.closePre oldState oldHandle := by
  rfl

theorem open_relation_agrees : ∀ oldState oldHandle selectorValid newState
    newHandle status receipt,
    Model.openRelation oldState oldHandle selectorValid newState newHandle
      status receipt ↔
    Generated.openRelation oldState oldHandle selectorValid newState newHandle
      status receipt := by
  intro oldState oldHandle selectorValid newState newHandle status receipt
  unfold Model.openRelation Generated.openRelation
  have preEq := open_pre_agrees oldState oldHandle
  have postEq :
      Model.openPost oldState oldHandle selectorValid newState newHandle status receipt =
        Generated.openPost oldState oldHandle selectorValid newState newHandle status receipt := by
    unfold Model.openPost Generated.openPost
    rw [open_status_agrees, open_state_agrees]
  rw [preEq, postEq]

theorem start_relation_agrees : ∀ oldState handle newState status receipt,
    Model.startRelation oldState handle newState status receipt ↔
    Generated.startRelation oldState handle newState status receipt := by
  intro oldState handle newState status receipt
  unfold Model.startRelation Generated.startRelation
  have preEq := start_pre_agrees oldState handle
  have postEq :
      Model.startPost oldState newState status receipt =
        Generated.startPost oldState newState status receipt := by
    unfold Model.startPost Generated.startPost
    rw [start_status_agrees, start_state_agrees]
  rw [preEq, postEq]

theorem stop_relation_agrees : ∀ oldState handle newState status receipt,
    Model.stopRelation oldState handle newState status receipt ↔
    Generated.stopRelation oldState handle newState status receipt := by
  intro oldState handle newState status receipt
  unfold Model.stopRelation Generated.stopRelation
  have preEq := stop_pre_agrees oldState handle
  have postEq :
      Model.stopPost oldState newState status receipt =
        Generated.stopPost oldState newState status receipt := by
    unfold Model.stopPost Generated.stopPost
    rw [stop_status_agrees, stop_state_agrees]
  rw [preEq, postEq]

theorem close_relation_agrees : ∀ oldState oldHandle newState newHandle receipt,
    Model.closeRelation oldState oldHandle newState newHandle receipt ↔
    Generated.closeRelation oldState oldHandle newState newHandle receipt := by
  intro oldState oldHandle newState newHandle receipt
  unfold Model.closeRelation Generated.closeRelation
  have preEq := close_pre_agrees oldState oldHandle
  have postEq :
      Model.closePost oldState oldHandle newState newHandle receipt =
        Generated.closePost oldState oldHandle newState newHandle receipt := by
    unfold Model.closePost Generated.closePost
    rfl
  rw [preEq, postEq]

theorem is_open_relation_agrees : ∀ state result,
    Model.isOpenRelation state result ↔ Generated.isOpenRelation state result := by
  intro state result
  unfold Model.isOpenRelation Generated.isOpenRelation Generated.isOpenPost
  rw [is_open_agrees]

theorem is_streaming_relation_agrees : ∀ state result,
    Model.isStreamingRelation state result ↔
      Generated.isStreamingRelation state result := by
  intro state result
  unfold Model.isStreamingRelation Generated.isStreamingRelation
    Generated.isStreamingPost
  rw [is_streaming_agrees]

theorem open_status_camera_result_calls_respect_pre :
    ∀ state selectorValid result,
      Generated.openStatusCameraResultCallGuard state selectorValid result = true →
        Generated.cameraResultPre result = true := by
  intro state selectorValid result
  cases state <;> cases selectorValid <;> cases result <;> decide

theorem start_status_camera_result_calls_respect_pre :
    ∀ state result,
      Generated.startStatusCameraResultCallGuard state result = true →
        Generated.cameraResultPre result = true := by
  intro state result
  cases state <;> cases result <;> decide

theorem stop_status_camera_result_calls_respect_pre :
    ∀ state result,
      Generated.stopStatusCameraResultCallGuard state result = true →
        Generated.cameraResultPre result = true := by
  intro state result
  cases state <;> cases result <;> decide

end CameraLifecycle
