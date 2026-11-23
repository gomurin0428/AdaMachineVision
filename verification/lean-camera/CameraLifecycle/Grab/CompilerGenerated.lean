import CameraLifecycle.Grab.CompilerIR

namespace CameraLifecycle.Grab

def compilerNaturalMin : Nat := 0
def compilerNaturalMax : Nat := 2147483647
def compilerPositiveMin : Nat := 1
def compilerPositiveMax : Nat := 2147483647
def compilerIntegerMin : Int := (-2147483648 : Int)
def compilerIntegerMax : Int := (2147483647 : Int)
def compilerWidthMin : Int := (-2147483648 : Int)
def compilerWidthMax : Int := (2147483647 : Int)
def compilerWidthTypeName : String := "amv__gige_vision_types__int32"
def compilerInt64Min : Int := (-9223372036854775808 : Int)
def compilerInt64Max : Int := (9223372036854775807 : Int)
def compilerArrayIndexMin : Int := 0
def compilerArrayIndexMax : Int := 18446744073709551615
def compilerArrayIndexPrecision : Nat := 64
def compilerVersion : String := "gcc (GNAT-FSF-builds) 16.1.0"
def compilerTarget : String := "x86_64-pc-linux-gnu"
def compilerExecutable : String := "gcc"
def compilerBuildFlags : List String := ["-c", "-gnat2022", "-gnatW8", "-ffp-contract=off", "-gnatwa", "-gnatVa", "-O0", "-gnatec=verification/lean-camera/tools/ghost-check.adc", "-I<scratch-output>", "-Ioptional/aravis/src", "-Isrc"]
def compilerTreeFlags : List String := ["-gnatG", "-gnatL", "-fdump-tree-original-raw"]
def compilerStandardFlags : List String := ["-gnatS"]
def compilerPolicy : String := "pragma Assertion_Level (Tested);  pragma Assertion_Policy   (Pre => Check, Post => Check, Ghost => Check,    Loop_Invariant => Check, Loop_Variant => Check, Assert => Check,    Assert_And_Cut => Check, Contract_Cases => Check,    Subprogram_Variant => Check, Dynamic_Predicate => Check,    Type_Invariant => Check, Default_Initial_Condition => Check,    Tested => Check);"
def compilerPolicyPath : String := "verification/lean-camera/tools/ghost-check.adc"
def compilerPolicySha256 : String := "c4c8733e5cd49254b4891e168a20b1f221bf6a89c867785f97eb686a0810f13f"
def compilerBounds : ScalarBounds := {
  naturalMin := (0 : Int),
  naturalMax := (2147483647 : Int),
  positiveMin := (1 : Int),
  positiveMax := (2147483647 : Int),
  integerMin := (-2147483648 : Int),
  integerMax := (2147483647 : Int),
  int32Min := (-2147483648 : Int),
  int32Max := (2147483647 : Int),
  int64Min := (-9223372036854775808 : Int),
  int64Max := (9223372036854775807 : Int)
}
def compilerPixelAtSource : String := "amv-spec-gige_vision.ads:149"
def compilerPixelAtHeader : String := "amv__gige_vision_types__pixel amv.spec.gige_vision.pixel_at (struct amv__gige_vision_types__frame_observation & frame, natural x, natural y)"
def compilerSelectedNodeIds : List (String × Nat) := [("function_decl", 1), ("outer_guard", 28), ("layout_guard", 62), ("row_guard", 207), ("row_temporary", 417), ("return_row", 462), ("natural_check_condition", 216), ("natural_check_call", 293), ("array_check_condition", 219), ("array_check_call", 296), ("array_lower_test", 364), ("array_upper_test", 365), ("overflow_condition", 464), ("overflow_test", 491), ("overflow_true_branch_call", 513), ("array_return", 220), ("array_ref", 368), ("returned_index_cast", 428), ("returned_index_type", 315), ("returned_index_add", 471), ("byte_array_domain", 170), ("byte_array_domain_min", 237), ("byte_array_domain_max", 238), ("array_lower_bound", 423), ("array_upper_bound", 424), ("return_row_conversion", 497), ("return_index_increment", 498), ("return_array_type", 119), ("return_pixel_type", 9), ("guard_row_tree_0", 207), ("guard_row_tree_1", 272), ("guard_row_tree_2", 273), ("guard_row_tree_3", 272), ("guard_row_tree_4", 343), ("guard_row_tree_5", 272), ("guard_row_tree_6", 189), ("guard_row_tree_7", 34), ("guard_row_tree_8", 261), ("guard_row_tree_9", 344), ("guard_row_tree_10", 272), ("guard_row_tree_11", 410), ("guard_row_tree_12", 55), ("guard_row_tree_13", 459), ("guard_row_tree_14", 23), ("guard_row_tree_15", 6), ("guard_row_tree_16", 13), ("guard_row_tree_17", 12), ("guard_row_tree_18", 57), ("guard_row_tree_19", 55), ("guard_row_tree_20", 71), ("guard_row_tree_21", 274), ("guard_row_tree_22", 272), ("guard_row_tree_23", 195), ("guard_row_tree_24", 34), ("guard_row_tree_25", 265), ("return_row_tree_0", 462), ("return_row_tree_1", 272), ("return_row_tree_2", 489), ("return_row_tree_3", 272), ("return_row_tree_4", 510), ("return_row_tree_5", 272), ("return_row_tree_6", 189), ("return_row_tree_7", 34), ("return_row_tree_8", 261), ("return_row_tree_9", 511), ("return_row_tree_10", 272), ("return_row_tree_11", 525), ("return_row_tree_12", 55), ("return_row_tree_13", 533), ("return_row_tree_14", 23), ("return_row_tree_15", 6), ("return_row_tree_16", 13), ("return_row_tree_17", 12), ("return_row_tree_18", 57), ("return_row_tree_19", 55), ("return_row_tree_20", 71), ("return_row_tree_21", 490), ("return_row_tree_22", 272), ("return_row_tree_23", 195), ("return_row_tree_24", 34), ("return_row_tree_25", 265)]
def compilerRowNodeIds : List Nat := [207, 462]
def compilerRowExpr0 : ScalarExpr := .add .int64 (.mul .int64 (.cast .int64 (.y)) (.cast .int64 (.width))) (.cast .int64 (.x))
def compilerRowExpr1 : ScalarExpr := .add .int64 (.mul .int64 (.cast .int64 (.y)) (.cast .int64 (.width))) (.cast .int64 (.x))
def compilerNaturalFailurePredicate : ScalarPredicate := .not (.inRange (compilerRowExpr1) (.literal 0) (.literal 2147483647))
def compilerOverflowFailurePredicate : ScalarPredicate := .equal (.cast .integer (.add .int64 (.mul .int64 (.cast .int64 (.y)) (.cast .int64 (.width))) (.cast .int64 (.x)))) (.literal 2147483647)
def compilerArrayFailurePredicate : ScalarPredicate := .not (.inRange (.cast .integer (.cast .positive (.add .integer (.cast .natural (compilerRowExpr1)) (.literal 1)))) .arrayFirst .arrayLast)
def compilerIndexValueExpr : ScalarExpr := .cast .integer (.cast .positive (.add .integer (.cast .natural (compilerRowExpr1)) (.literal 1)))
def compilerRawCheckCalls : List (Nat × String) := [(79, "Access_Check"), (137, "Invalid_Data"), (140, "Invalid_Data"), (143, "Invalid_Data"), (146, "Invalid_Data"), (149, "Invalid_Data"), (152, "Invalid_Data"), (228, "Invalid_Data"), (278, "Access_Check"), (281, "Invalid_Data"), (284, "Invalid_Data"), (287, "Invalid_Data"), (290, "Invalid_Data"), (293, "Range_Check"), (296, "Index_Check"), (333, "Range_Check"), (336, "Invalid_Data"), (396, "Range_Check"), (399, "Invalid_Data"), (440, "Access_Check"), (443, "Invalid_Data"), (513, "Overflow_Check")]
def compilerCheckRoutines : List String := ["Access_Check", "Invalid_Data", "Invalid_Data", "Invalid_Data", "Invalid_Data", "Invalid_Data", "Invalid_Data", "Invalid_Data", "Access_Check", "Invalid_Data", "Invalid_Data", "Invalid_Data", "Invalid_Data", "Range_Check", "Index_Check", "Range_Check", "Invalid_Data", "Range_Check", "Invalid_Data", "Access_Check", "Invalid_Data", "Overflow_Check"]
def compilerCheckPredicates : List String := [
  "range check failed: not (R132s in 0 .. 16#7FFF_FFFF#)",
  "index check failed: not (integer(positive(natural(R132s) {+} 1)) in R133s .. R134s)"
]
def compilerExpandedSourceLines : List Nat := [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 176]

end CameraLifecycle.Grab
