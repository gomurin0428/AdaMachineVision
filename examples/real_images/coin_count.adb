--  Counting coins in a photograph: a top-hat (IP One Image) flattens the
--  uneven background, then a blob tool with a fixed threshold finds the
--  coins.
--
--     coin_count
--
--  It reads coins.bmp (the scikit-image sample "coins", 384 x 303; see
--  README.md here for where the images come from), prints the coins, and
--  writes two pictures into the current directory:
--
--     coin_count_steps.bmp    the input, what a threshold of the input
--                             alone finds, the top-hat, and the coins
--     coin_count_result.bmp   the coins, outlined and numbered

with Ada.Command_Line;
with Ada.Exceptions;
with Ada.Text_IO;

with AMV;
with AMV.Blob;
with AMV.Image_Processing.IP_One_Image;
with AMV.Images;
with AMV.Tools;

with Example_Draw;
with Example_Support;

procedure Coin_Count is

   use Ada.Text_IO;
   use AMV;
   use AMV.Blob;
   use AMV.Image_Processing.IP_One_Image;
   use type AMV.Tools.Ks_Tool_Result_Constants;

   function Image (Value : Real; Aft : Natural := 1) return String
     renames Example_Support.Image;

   function Number (Value : Natural) return String is
     (Value'Image (2 .. Value'Image'Last));

   procedure Outline_All
     (Onto    : in out Example_Draw.Picture;
      Results : Ks_Blob_Results;
      Ink     : Example_Draw.Colour;
      Width   : Real);
   --  The boundary of every blob that passed the tool's filter.

   procedure Outline_All
     (Onto    : in out Example_Draw.Picture;
      Results : Ks_Blob_Results;
      Ink     : Example_Draw.Colour;
      Width   : Real)
   is
      Blobs : constant Ks_Blob_Result_Collection'Class := Results.Get_Blobs;
   begin
      for I in 0 .. Blobs.Count - 1 loop
         Example_Draw.Outline
           (Onto, Results.Get_Boundary (Integer (Blobs.Item (I).ID)), Ink,
            Width);
      end loop;
   end Outline_All;

   Input : AMV.Images.Ks_Image_8_Grey;
   Plain : Ks_Blob_Tool;
   IP    : Ks_IP_One_Image_Tool;
   Hat   : Ks_IP_One_Image_Operator := New_Operator (Grey_Morphology_NxM);
   Tool  : Ks_Blob_Tool;

begin
   Input := Example_Support.Real_Image ("coins.bmp");

   --  A first try, to show the problem: light blobs of the input itself,
   --  with the threshold computed from the histogram (the default). The
   --  background is brighter at the top than at the bottom, so the top
   --  of the background comes out as one blob together with the coins on
   --  it, while the dark sides of the bottom coins are lost.
   Plain.Input_Image := Input;
   Plain.Run_Params.Segmentation_Params.Polarity := Code (Light_Blobs);
   Add (Plain.Run_Params.Run_Time_Measures,
        Blob_Measure (Area, Filter, Include_Blobs_In_Range, 600.0, 1.0E9));
   Plain.Run;

   --  The top-hat: the image minus its grey opening by a square larger
   --  than any coin. The opening removes the coins and keeps the
   --  background, so the difference keeps the coins on a flat, dark
   --  background.
   IP.Input_Image := Input;
   Hat.Grey_Morphology_NxM.Operation := Code (Original_Minus_Open);
   Hat.Grey_Morphology_NxM.Kernel_Width := 75;
   Hat.Grey_Morphology_NxM.Kernel_Height := 75;
   Add (IP.Operators, Hat);
   IP.Run;

   --  The coins: light blobs of the top-hat above a fixed threshold, of
   --  600 to 6000 square pixels and roughly round (the elongation, the
   --  ratio of the principal second moments, is 1 for a disc).
   Tool.Input_Image := IP.Output_Image;
   Tool.Run_Params.Segmentation_Params.Polarity := Code (Light_Blobs);
   Tool.Run_Params.Segmentation_Params.Mode := Code (Hard_Fixed_Threshold);
   Tool.Run_Params.Segmentation_Params.Hard_Fixed_Threshold := 60;
   Add (Tool.Run_Params.Run_Time_Measures,
        Blob_Measure (Area, Filter, Include_Blobs_In_Range, 600.0, 6000.0));
   Add (Tool.Run_Params.Run_Time_Measures,
        Blob_Measure (Elongation, Filter, Include_Blobs_In_Range, 1.0, 1.6));
   Tool.Run;

   if Plain.Run_Status.Result /= AMV.Tools.Accept_Result
     or else IP.Run_Status.Result /= AMV.Tools.Accept_Result
     or else Tool.Run_Status.Result /= AMV.Tools.Accept_Result
   then
      Put_Line ("a tool failed: " & AMV.Tools.Message (Tool.Run_Status));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;

   declare
      Coins  : constant Ks_Blob_Result_Collection'Class :=
        Tool.Results.Get_Blobs;
      Steps  : Example_Draw.Picture;
      First  : Example_Draw.Picture := Example_Draw.Create (Input);
      Second : Example_Draw.Picture := Example_Draw.Create (Input);
      Third  : Example_Draw.Picture :=
        Example_Draw.Create (IP.Output_Image);
      Fourth : Example_Draw.Picture :=
        Example_Draw.Create (IP.Output_Image);
      Result : Example_Draw.Picture :=
        Example_Draw.Create (Input, Scale => 2.0);
   begin
      Put_Line
        ("a threshold of the input alone:"
         & Natural'Image (Plain.Results.Get_Blobs.Count)
         & " blobs of 600 pixels or more, the largest of "
         & Number (Natural (Plain.Results.Get_Blobs.Item (0).Area))
         & " pixels");
      Put_Line ("after the top-hat:" & Coins.Count'Image & " coins");

      --  The coins come sorted by area, the largest first (the default).
      for I in 0 .. Coins.Count - 1 loop
         declare
            Coin : constant Ks_Blob_Result := Coins.Item (I);
         begin
            Put_Line
              ("coin " & Number (I + 1) & " at ("
               & Image (Coin.Center_Of_Mass_X) & ", "
               & Image (Coin.Center_Of_Mass_Y) & "): area "
               & Number (Natural (Coin.Area)) & ", elongation "
               & Image (Coin.Elongation, 2));
            Example_Draw.Outline
              (Result, Tool.Results.Get_Boundary (Integer (Coin.ID)),
               Example_Draw.Green, Width => 2.0);
            Example_Draw.Text
              (Result, Coin.Center_Of_Mass_X, Coin.Center_Of_Mass_Y,
               Number (I + 1), Example_Draw.Yellow,
               DX => -6 * Number (I + 1)'Length - 1, DY => -9);
         end;
      end loop;
      Example_Draw.Caption
        (Result, 0, Number (Coins.Count) & " COINS (TOP-HAT, THEN BLOB)");
      Example_Draw.Write (Result, "coin_count_result.bmp");

      Example_Draw.Caption (First, 0, "1 INPUT");
      Outline_All (Second, Plain.Results, Example_Draw.Red, 1.5);
      Example_Draw.Caption
        (Second, 0, "2 BLOB ON THE INPUT: WRONG", Example_Draw.Red);
      Example_Draw.Caption (Third, 0, "3 TOP-HAT 75 X 75");
      Outline_All (Fourth, Tool.Results, Example_Draw.Green, 1.5);
      Example_Draw.Caption
        (Fourth, 0, "4 BLOB ON THE TOP-HAT: " & Number (Coins.Count)
         & " COINS", Example_Draw.Green);
      Steps :=
        Example_Draw.Above
          (Example_Draw.Beside (First, Second),
           Example_Draw.Beside (Third, Fourth));
      Example_Draw.Write (Steps, "coin_count_steps.bmp");
      Put_Line ("wrote coin_count_steps.bmp and coin_count_result.bmp");
   end;
exception
   when E : Example_Support.Missing_Image =>
      Put_Line (Ada.Exceptions.Exception_Message (E));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
end Coin_Count;
