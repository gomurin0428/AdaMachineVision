with Ada.Exceptions;

with AMV.Checks;
with AMV.Kernels;
with AMV_Test_Support; use AMV_Test_Support;

procedure AMV.Test_Check_Mapping is

   package K renames AMV.Kernels;
   use type K.Int32;
   use type Ada.Exceptions.Exception_Id;

   procedure Expect
     (Failure  : K.Int32;
      Expected : Ada.Exceptions.Exception_Id;
      Name     : String)
   is
      Status : K.Ks_Status;
   begin
      if Failure = K.Failure_None then
         K.Set_Success (Status);
      else
         K.Set_Failure (Status, Failure, "Property.Name is wrong");
      end if;
      AMV.Checks.Check (Status);
      Check (Expected = Ada.Exceptions.Null_Id,
             Name & ": no exception for a successful status");
   exception
      when E : others =>
         Check (Ada.Exceptions.Exception_Identity (E) = Expected,
                Name & ": raised " & Ada.Exceptions.Exception_Name (E));
         Check (Ada.Exceptions.Exception_Message (E)
                  = "Property.Name is wrong",
                Name & ": message is the status message");
   end Expect;

begin
   Section ("kernel status to exception (AMV.Checks)");
   Expect (K.Failure_None, Ada.Exceptions.Null_Id, "Failure_None");
   Expect (K.Failure_Image_No_Pixels,
           Ks_Image_No_Pixels_Exception'Identity, "Image_No_Pixels");
   Expect (K.Failure_Image_Bad_Selected_Space_Name,
           Ks_Image_Bad_Selected_Space_Name_Exception'Identity,
           "Image_Bad_Selected_Space_Name");
   Expect (K.Failure_Operator_Not_Trained,
           Ks_Operator_Not_Trained_Exception'Identity, "Operator_Not_Trained");
   Expect (K.Failure_Transform_Singular,
           Ks_Transform_Singular_Exception'Identity, "Transform_Singular");
   Expect (K.Failure_Image_File,
           Ks_Image_File_Exception'Identity, "Image_File");
   Expect (K.Failure_Bad_Parameter,
           Ks_Bad_Parameter_Exception'Identity, "Bad_Parameter");
   Expect (K.Failure_Out_Of_Memory,
           Storage_Error'Identity, "Out_Of_Memory");
   Expect (K.Failure_Other, Ks_Exception'Identity, "Other");
   Expect (K.Failure_Index_Out_Of_Range,
           Constraint_Error'Identity, "Index_Out_Of_Range");

   --  A status no kernel produces.
   declare
      Status : K.Ks_Status;
   begin
      Status.Failure := 99;
      AMV.Checks.Check (Status);
      Fail ("unknown failure code: no exception");
   exception
      when E : Program_Error =>
         Check (True, "unknown failure code raises Program_Error ("
                & Ada.Exceptions.Exception_Message (E) & ")");
      when E : others =>
         Fail ("unknown failure code raised "
               & Ada.Exceptions.Exception_Name (E));
   end;
end AMV.Test_Check_Mapping;
