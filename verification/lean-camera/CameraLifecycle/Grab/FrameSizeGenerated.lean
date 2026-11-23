import CameraLifecycle.Grab.FrameSizeIR

namespace CameraLifecycle.Grab

def compilerFrameSizeProgram : FrameSizeProgram := {
  dimensions := .orElse (.lessEqual (.width) (.literal (0 : Int))) (.lessEqual (.height) (.literal (0 : Int))),
  product := .multiply .int64 (.cast .int64 (.width)) (.cast .int64 (.height)),
  limit := .greater (.multiply .int64 (.cast .int64 (.width)) (.cast .int64 (.height))) (.literal (2147483647 : Int)),
  invalidLength := .orElse (.orElse (.orElse (.orElse (.sequence (.check .rangeCheck (.less (.multiply .int64 (.cast .int64 (.width)) (.cast .int64 (.height))) (.literal (0 : Int)))) (.notEqual (.cast .unsigned64 (.sourceSize)) (.cast .unsigned64 (.multiply .int64 (.cast .int64 (.width)) (.cast .int64 (.height)))))) (.sequence (.sequence (.check .invalidData (.less (.byteCount) (.literal (0 : Int)))) (.check .invalidData (.less (.byteCount) (.literal (0 : Int))))) (.notEqual (.cast .int64 (.byteCount)) (.multiply .int64 (.cast .int64 (.width)) (.cast .int64 (.height)))))) (.bytesNull)) (.sequence (.check .accessCheck (.bytesNull)) (.notEqual (.byteFirst) (.literal (1 : Int))))) (.sequence (.check .accessCheck (.bytesNull)) (.notEqual (.ifThenElse (.greaterEqual (.byteLast) (.byteFirst)) (.cast .int64 (.cast .integer (.add .size (.subtract .size (.cast .size (.byteLast)) (.cast .size (.byteFirst))) (.literal (1 : Int))))) (.literal (0 : Int))) (.multiply .int64 (.cast .int64 (.width)) (.cast .int64 (.height))))),
  arrayLength := .ifThenElse (.greaterEqual (.byteLast) (.byteFirst)) (.cast .int64 (.cast .integer (.add .size (.subtract .size (.cast .size (.byteLast)) (.cast .size (.byteFirst))) (.literal (1 : Int))))) (.literal (0 : Int)),
  control := .ifThenElse (.orElse (.lessEqual (.width) (.literal (0 : Int))) (.lessEqual (.height) (.literal (0 : Int)))) (.returnStatus .invalidDimensions) (.ifThenElse (.greater (.multiply .int64 (.cast .int64 (.width)) (.cast .int64 (.height))) (.literal (2147483647 : Int))) (.returnStatus .tooLarge) (.ifThenElse (.orElse (.orElse (.orElse (.orElse (.sequence (.check .rangeCheck (.less (.multiply .int64 (.cast .int64 (.width)) (.cast .int64 (.height))) (.literal (0 : Int)))) (.notEqual (.cast .unsigned64 (.sourceSize)) (.cast .unsigned64 (.multiply .int64 (.cast .int64 (.width)) (.cast .int64 (.height)))))) (.sequence (.sequence (.check .invalidData (.less (.byteCount) (.literal (0 : Int)))) (.check .invalidData (.less (.byteCount) (.literal (0 : Int))))) (.notEqual (.cast .int64 (.byteCount)) (.multiply .int64 (.cast .int64 (.width)) (.cast .int64 (.height)))))) (.bytesNull)) (.sequence (.check .accessCheck (.bytesNull)) (.notEqual (.byteFirst) (.literal (1 : Int))))) (.sequence (.check .accessCheck (.bytesNull)) (.notEqual (.ifThenElse (.greaterEqual (.byteLast) (.byteFirst)) (.cast .int64 (.cast .integer (.add .size (.subtract .size (.cast .size (.byteLast)) (.cast .size (.byteFirst))) (.literal (1 : Int))))) (.literal (0 : Int))) (.multiply .int64 (.cast .int64 (.width)) (.cast .int64 (.height)))))) (.returnStatus .invalidLength) (.returnStatus .success))),
  checks := [
  { kind := .range, nodeId := 520, predicate := .less (.multiply .int64 (.cast .int64 (.width)) (.cast .int64 (.height))) (.literal (0 : Int)) },
  { kind := .invalidData, nodeId := 527, predicate := .less (.byteCount) (.literal (0 : Int)) },
  { kind := .invalidData, nodeId := 530, predicate := .less (.byteCount) (.literal (0 : Int)) },
  { kind := .access, nodeId := 470, predicate := .bytesNull },
  { kind := .access, nodeId := 450, predicate := .bytesNull }
  ]
}

def compilerFrameSizeBounds : FrameSizeBounds := {
  naturalMin := (0 : Int),
  naturalMax := (2147483647 : Int),
  positiveMin := (1 : Int),
  positiveMax := (2147483647 : Int),
  integerMin := (-2147483648 : Int),
  integerMax := (2147483647 : Int),
  int32Min := (-2147483648 : Int),
  int32Max := (2147483647 : Int),
  int64Min := (-9223372036854775808 : Int),
  int64Max := (9223372036854775807 : Int),
  unsigned64Max := (18446744073709551615 : Int),
  sizeMin := (0 : Int),
  sizeMax := (4294967295 : Int)
}

def compilerFrameSizeMaxPixels : Int := (2147483647 : Int)
def compilerFrameSizeEnumCodes : List (String × Nat) := [("amv__gige_vision_types__frame_bad_parameter", 1), ("amv__gige_vision_types__frame_error", 9), ("amv__gige_vision_types__frame_invalid_dimensions", 5), ("amv__gige_vision_types__frame_invalid_length", 7), ("amv__gige_vision_types__frame_out_of_memory", 8), ("amv__gige_vision_types__frame_success", 0), ("amv__gige_vision_types__frame_timeout", 2), ("amv__gige_vision_types__frame_too_large", 6), ("amv__gige_vision_types__frame_unsupported_format", 4), ("amv__gige_vision_types__frame_unsupported_payload", 3)]
def compilerFrameSizeStatusCodes : FrameSizeStatusCodes := { invalidDimensions := 5, tooLarge := 6, invalidLength := 7, success := 0 }
def compilerFrameSizeResolvedTypes : List FrameSizeResolvedType := [
  { name := "width", nodeId := 395, typeNodeId := 291, typeName := "int32", lower := (-2147483648 : Int), upper := (2147483647 : Int), representationLower := (-2147483648 : Int), representationUpper := (2147483647 : Int) },
  { name := "height", nodeId := 397, typeNodeId := 291, typeName := "int32", lower := (-2147483648 : Int), upper := (2147483647 : Int), representationLower := (-2147483648 : Int), representationUpper := (2147483647 : Int) },
  { name := "byte_count", nodeId := 580, typeNodeId := 39, typeName := "natural", lower := (0 : Int), upper := (2147483647 : Int), representationLower := (-2147483648 : Int), representationUpper := (2147483647 : Int) },
  { name := "source_size", nodeId := 571, typeNodeId := 569, typeName := "unsigned64", lower := (0 : Int), upper := (18446744073709551615 : Int), representationLower := (0 : Int), representationUpper := (-1 : Int) }
]
def compilerFrameSizeSelectedNodeIds : List (String × Nat) := [("function", 1), ("invalid_dimensions", 351), ("too_large", 364), ("invalid_length", 382), ("check_range_check", 520), ("check_invalid_data", 527), ("check_invalid_data", 530), ("check_access_check", 470), ("check_access_check", 450), ("alias", 366), ("alias", 368), ("alias", 417), ("alias", 423), ("alias", 439), ("alias", 441), ("alias", 488), ("alias", 562)]
def compilerFrameSizeSourceLines : List Nat := [104, 130, 136, 137, 138, 141, 142]
def compilerFrameSizeRawNodeIds : List Nat := [1, 351, 364, 382, 520, 527, 530, 470, 450, 366, 368, 417, 423, 439, 441, 488, 562]
def compilerFrameSizeExpandedChecks : List (String × String) := [
  ("range", "R85s < 0"),
  ("invalidData", "not (unsigned!(frame. byte_count) <= 16#7FFF_FFFF#)"),
  ("invalidData", "not (unsigned!(frame. byte_count) <= 16#7FFF_FFFF#)"),
  ("access", "frame.bytes = null"),
  ("access", "frame.bytes = null")
]
def compilerFrameSizeCompilerVersion : String := "gcc (GNAT-FSF-builds) 16.1.0"
def compilerFrameSizeCompilerTarget : String := "x86_64-pc-linux-gnu"
def compilerFrameSizeFlags : List String := ["-c", "-gnat2022", "-gnatW8", "-ffp-contract=off", "-gnatwa", "-gnatVa", "-O0", "-gnatec=verification/lean-camera/tools/ghost-check.adc", "-gnatG", "-gnatL", "-fdump-tree-original-raw", "-gnatS"]
def compilerFrameSizeSourceName : String := "amv-spec-gige_vision.ads"
def compilerFrameSizeSourceSha256 : String := "10198b770460621ad6d75d7676c78677e8a58c98ebb2f7494b38de224fb24503"
def compilerFrameSizeTypesSha256 : String := "9a48cb1d14a11a93cdc32f423232b6e769dc81b06863f3e5ef8a71e29880530b"
def compilerFrameSizePolicyText : String := "pragma Assertion_Level (Tested);\n\npragma Assertion_Policy\n  (Pre => Check, Post => Check, Ghost => Check,\n   Loop_Invariant => Check, Loop_Variant => Check, Assert => Check,\n   Assert_And_Cut => Check, Contract_Cases => Check,\n   Subprogram_Variant => Check, Dynamic_Predicate => Check,\n   Type_Invariant => Check, Default_Initial_Condition => Check,\n   Tested => Check);"
def compilerFrameSizePolicySha256 : String := "a51181de8cdb6e1c9214d5df4cf7332aad27257fd9905ac6b59422178ed1a56a"
def compilerFrameSizeRawHeader : String := "amv__gige_vision_types__frame_status amv.spec.gige_vision.grab_status (amv__gige_vision_types__camera_state state, natural timeout, struct amv__gige_vision_types__frame_observation & frame)"

end CameraLifecycle.Grab
