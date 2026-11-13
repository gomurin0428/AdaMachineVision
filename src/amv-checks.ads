--  The one place where the Ada API turns a kernel status into an
--  exception (docs/DESIGN.md section 9).

pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with AMV.Kernels;

private package AMV.Checks is
   pragma Preelaborate;

   procedure Check (Status : AMV.Kernels.Ks_Status);
   --  Returns when Status.Failure is Failure_None. Otherwise raises the
   --  Ks_ exception that corresponds to the failure code (Storage_Error for
   --  Failure_Out_Of_Memory, Constraint_Error for Failure_Index_Out_Of_Range)
   --  with the status message. A code the kernels
   --  never produce raises Program_Error.

   procedure Check (Status : AMV.Kernels.Ks_Status; Context : String);
   --  The same, with the message Context & ": " & the status message
   --  (AMV.Image_File puts the file name in front of the kernel's
   --  messages, which never contain it).

   --  Stream attributes. A composite type that owns heap memory reads
   --  its components into a fresh object and assigns it to the target
   --  only when every component was read (docs/DESIGN.md section 8), so
   --  that a malformed stream leaves the target as it was.

   procedure Check_Read (Valid : Boolean; Attribute : String);
   --  Returns when Valid (the 'Valid of an enumeration, Boolean or
   --  Natural component read with its predefined attribute). Otherwise
   --  raises Ks_Image_File_Exception with the message Attribute & ": the
   --  stream holds an invalid value".

   procedure Stream_Malformed (Attribute : String)
   with No_Return;
   --  Raises Ks_Image_File_Exception with the message Attribute & ": the
   --  stream ends early, or holds an unknown shape tag or an invalid
   --  value" (the handler of Ada.IO_Exceptions.End_Error,
   --  Ada.Tags.Tag_Error and Constraint_Error in a 'Read: a predefined
   --  attribute raises them for a stream that ends early, a class-wide
   --  shape with an unknown tag, and with validity checks on, an invalid
   --  value).

end AMV.Checks;
