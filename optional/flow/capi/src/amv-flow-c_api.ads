pragma SPARK_Mode (Off);

with Interfaces;
with Interfaces.C;
with Interfaces.C.Strings;
with System;

--  The C API of AMV Flow (optional/flow/include/amv_flow.h): every
--  function there, exported from this package. Exceptions never cross it:
--  they become the status's failure and message.

package AMV.Flow.C_API is

   use Interfaces;
   use Interfaces.C;
   use Interfaces.C.Strings;

   C_ABI_Version      : constant := 1;  --  AMVF_ABI_VERSION
   Max_Message_Length : constant := 1023;

   Failure_None          : constant := 0;
   Failure_Flow          : constant := 1;
   Failure_Bad_Argument  : constant := 2;
   Failure_AMV           : constant := 3;
   Failure_Out_Of_Memory : constant := 4;
   Failure_Internal      : constant := 5;

   type Amvf_Status is record
      Failure : Integer_32;
      Length  : Integer_32;
      Message : char_array (0 .. Max_Message_Length);
   end record
     with Convention => C;

   function Abi_Version return Integer_32
     with Export, Convention => C, External_Name => "amvf_abi_version";

   procedure Kinds_JSON
     (Buffer : System.Address; Capacity : Integer_64;
      Needed : out Integer_64; Status : out Amvf_Status)
     with Export, Convention => C, External_Name => "amvf_kinds_json";

   function Flow_Create (Status : out Amvf_Status) return System.Address
     with Export, Convention => C, External_Name => "amvf_flow_create";

   procedure Flow_Destroy (Flow : System.Address)
     with Export, Convention => C, External_Name => "amvf_flow_destroy";

   procedure Flow_Load
     (Flow : System.Address; Path : chars_ptr; Status : out Amvf_Status)
     with Export, Convention => C, External_Name => "amvf_flow_load";

   procedure Flow_Save
     (Flow : System.Address; Path : chars_ptr; Status : out Amvf_Status)
     with Export, Convention => C, External_Name => "amvf_flow_save";

   procedure Flow_To_JSON
     (Flow   : System.Address; Buffer : System.Address;
      Capacity : Integer_64; Needed : out Integer_64;
      Status : out Amvf_Status)
     with Export, Convention => C, External_Name => "amvf_flow_to_json";

   procedure Flow_From_JSON
     (Flow   : System.Address; Text : chars_ptr; Base_Directory : chars_ptr;
      Status : out Amvf_Status)
     with Export, Convention => C, External_Name => "amvf_flow_from_json";

   procedure Flow_Set_Base_Directory
     (Flow : System.Address; Directory : chars_ptr; Status : out Amvf_Status)
     with Export, Convention => C,
          External_Name => "amvf_flow_set_base_directory";

   function Flow_Add_Node
     (Flow : System.Address; Kind : chars_ptr; X, Y : double;
      Status : out Amvf_Status) return Integer_64
     with Export, Convention => C, External_Name => "amvf_flow_add_node";

   procedure Flow_Remove_Node
     (Flow : System.Address; Node : Integer_64; Status : out Amvf_Status)
     with Export, Convention => C, External_Name => "amvf_flow_remove_node";

   procedure Flow_Set_Node_Position
     (Flow : System.Address; Node : Integer_64; X, Y : double;
      Status : out Amvf_Status)
     with Export, Convention => C,
          External_Name => "amvf_flow_set_node_position";

   procedure Flow_Set_Node_Name
     (Flow : System.Address; Node : Integer_64; Name : chars_ptr;
      Status : out Amvf_Status)
     with Export, Convention => C, External_Name => "amvf_flow_set_node_name";

   procedure Flow_Link
     (Flow : System.Address; From, To : chars_ptr; Status : out Amvf_Status)
     with Export, Convention => C, External_Name => "amvf_flow_link";

   procedure Flow_Unlink
     (Flow : System.Address; To : chars_ptr; Status : out Amvf_Status)
     with Export, Convention => C, External_Name => "amvf_flow_unlink";

   procedure Flow_Set_Param_JSON
     (Flow : System.Address; Node : Integer_64; Name, Value_JSON : chars_ptr;
      Status : out Amvf_Status)
     with Export, Convention => C,
          External_Name => "amvf_flow_set_param_json";

   procedure Flow_Add_Input
     (Flow : System.Address; Name, Type_Name : chars_ptr;
      Status : out Amvf_Status)
     with Export, Convention => C, External_Name => "amvf_flow_add_input";

   procedure Flow_Add_Output
     (Flow : System.Address; Name, Type_Name : chars_ptr;
      Status : out Amvf_Status)
     with Export, Convention => C, External_Name => "amvf_flow_add_output";

   procedure Flow_Problems_JSON
     (Flow   : System.Address; Buffer : System.Address;
      Capacity : Integer_64; Needed : out Integer_64;
      Status : out Amvf_Status)
     with Export, Convention => C, External_Name => "amvf_flow_problems_json";

   procedure Flow_Set_Input_Image_8
     (Flow   : System.Address; Input : chars_ptr;
      Width, Height, Stride : Integer_32; Pixels : System.Address;
      Status : out Amvf_Status)
     with Export, Convention => C,
          External_Name => "amvf_flow_set_input_image_8";

   procedure Flow_Set_Input_Image_File
     (Flow : System.Address; Input, Path : chars_ptr;
      Status : out Amvf_Status)
     with Export, Convention => C,
          External_Name => "amvf_flow_set_input_image_file";

   procedure Flow_Run (Flow : System.Address; Status : out Amvf_Status)
     with Export, Convention => C, External_Name => "amvf_flow_run";

   procedure Flow_Results_JSON
     (Flow   : System.Address; Buffer : System.Address;
      Capacity : Integer_64; Needed : out Integer_64;
      Status : out Amvf_Status)
     with Export, Convention => C, External_Name => "amvf_flow_results_json";

   procedure Node_Graphics_JSON
     (Flow   : System.Address; Node : Integer_64; Buffer : System.Address;
      Capacity : Integer_64; Needed : out Integer_64;
      Status : out Amvf_Status)
     with Export, Convention => C, External_Name => "amvf_node_graphics_json";

   procedure Node_Image_BGRA
     (Flow   : System.Address; Node : Integer_64; Buffer : System.Address;
      Capacity : Integer_64; Width, Height : out Integer_32;
      Status : out Amvf_Status)
     with Export, Convention => C, External_Name => "amvf_node_image_bgra";

end AMV.Flow.C_API;
