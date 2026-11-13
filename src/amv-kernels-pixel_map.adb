pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with AMV.Kernels.Filter_Inputs;

package body AMV.Kernels.Pixel_Map with SPARK_Mode is

   package FI renames AMV.Kernels.Filter_Inputs;

   procedure Run_Params_Default (Params : out Ks_IP_One_Image_Pixel_Map) is
   begin
      Params := (Map => Identity_Map);
   end Run_Params_Default;

   procedure Execute
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Params : Ks_IP_One_Image_Pixel_Map;
      Output : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status) is
   begin
      Output := null;
      FI.Check_Input (Image, Region, Status);
      if not Succeeded (Status) then
         return;
      end if;
      KI.Create (Image.Width, Image.Height, 0, Output, Status);
      if not Succeeded (Status) then
         --  The size is valid, so only the allocation can fail.
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "PixelMap: not enough memory for the output image");
         return;
      end if;
      for Y in Output.Pixels'Range (1) loop
         for X in Output.Pixels'Range (2) loop
            Output.Pixels (Y, X) :=
              Map_Pixel (Params.Map, Region, Image.Pixels (Y, X), X, Y);
            pragma Loop_Invariant
              (KI.Valid_Image (Output)
               and then Output.Width = Image.Width
               and then Output.Height = Image.Height);
            pragma Loop_Invariant
              (for all J in 0 .. Y - 1
               => (for all I in Output.Pixels'Range (2)
                   => Output.Pixels (J, I)
                        = Map_Pixel (Params.Map, Region,
                                     Image.Pixels (J, I), I, J)));
            pragma Loop_Invariant
              (for all I in 0 .. X
               => Output.Pixels (Y, I)
                    = Map_Pixel (Params.Map, Region, Image.Pixels (Y, I),
                                 I, Y));
         end loop;
         pragma Loop_Invariant
           (KI.Valid_Image (Output)
            and then Output.Width = Image.Width
            and then Output.Height = Image.Height);
         pragma Loop_Invariant
           (for all J in 0 .. Y
            => (for all I in Output.Pixels'Range (2)
                => Output.Pixels (J, I)
                     = Map_Pixel (Params.Map, Region, Image.Pixels (J, I),
                                  I, J)));
      end loop;
      Set_Success (Status);
   end Execute;

   procedure Check_Input_Image
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Status : out Ks_Status) is
   begin
      FI.Check_Image (Image, Status);
   end Check_Input_Image;

end AMV.Kernels.Pixel_Map;
