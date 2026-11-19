pragma Validity_Checks ("F");

package body AMV.Kernels with SPARK_Mode is

   procedure Set_Success (Status : out Ks_Status) is
   begin
      Status := (Failure => Failure_None,
                 Length  => 0,
                 Message => [others => ASCII.NUL]);
   end Set_Success;

   procedure Set_Failure
     (Status  : out Ks_Status;
      Failure : Failure_Code;
      Message : String)
   is
      Length : constant Natural :=
        Natural'Min (Message'Length, Max_Message_Length);
   begin
      Status := (Failure => Failure,
                 Length  => Int32 (Length),
                 Message => [others => ASCII.NUL]);
      for I in 1 .. Length loop
         pragma Loop_Invariant (Status.Failure = Failure
                                and then Status.Length = Int32 (Length));
         Status.Message (I) := Message (Message'First + (I - 1));
      end loop;
   end Set_Failure;

   function Get_ABI_Version return Int32 is (ABI_Version);

end AMV.Kernels;
