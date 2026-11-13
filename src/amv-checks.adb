pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with Ada.Exceptions;

package body AMV.Checks is

   package K renames AMV.Kernels;

   procedure Raise_Failure (Status : AMV.Kernels.Ks_Status; Prefix : String)
   with No_Return;
   --  Raises the exception of a failed Status with Prefix & its message.

   procedure Check (Status : AMV.Kernels.Ks_Status) is
      use type K.Int32;
   begin
      if Status.Failure /= K.Failure_None then
         Raise_Failure (Status, "");
      end if;
   end Check;

   procedure Check (Status : AMV.Kernels.Ks_Status; Context : String) is
      use type K.Int32;
   begin
      if Status.Failure /= K.Failure_None then
         Raise_Failure (Status, Context & ": ");
      end if;
   end Check;

   procedure Check_Read (Valid : Boolean; Attribute : String) is
   begin
      if not Valid then
         raise Ks_Image_File_Exception
           with Attribute & ": the stream holds an invalid value";
      end if;
   end Check_Read;

   procedure Stream_Malformed (Attribute : String) is
   begin
      raise Ks_Image_File_Exception
        with Attribute & ": the stream ends early, or holds an unknown "
             & "shape tag or an invalid value";
   end Stream_Malformed;

   procedure Raise_Failure (Status : AMV.Kernels.Ks_Status; Prefix : String)
   is
      use type K.Int32;
   begin
      if Status.Length not in 0 .. K.Max_Message_Length then
         raise Program_Error with "kernel status with an invalid length";
      end if;
      declare
         Message : constant String :=
           Prefix & String (Status.Message (1 .. Natural (Status.Length)));
         Id : constant Ada.Exceptions.Exception_Id :=
           (case Status.Failure is
               when K.Failure_Image_No_Pixels =>
                  Ks_Image_No_Pixels_Exception'Identity,
               when K.Failure_Image_Bad_Selected_Space_Name =>
                  Ks_Image_Bad_Selected_Space_Name_Exception'Identity,
               when K.Failure_Operator_Not_Trained =>
                  Ks_Operator_Not_Trained_Exception'Identity,
               when K.Failure_Transform_Singular =>
                  Ks_Transform_Singular_Exception'Identity,
               when K.Failure_Image_File =>
                  Ks_Image_File_Exception'Identity,
               when K.Failure_Bad_Parameter =>
                  Ks_Bad_Parameter_Exception'Identity,
               when K.Failure_Out_Of_Memory =>
                  Storage_Error'Identity,
               when K.Failure_Other =>
                  Ks_Exception'Identity,
               when K.Failure_Index_Out_Of_Range =>
                  Constraint_Error'Identity,
               when others =>
                  Program_Error'Identity);
      begin
         Ada.Exceptions.Raise_Exception (Id, Message);
      end;
   end Raise_Failure;

end AMV.Checks;
