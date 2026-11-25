pragma Assertion_Policy (Ghost => Check);

with Ada.Unchecked_Deallocation;
with System;
with AMV.GigE_Vision_Bayer;
with AMV.GigE_Vision_Native;
with AMV.GigE_Vision_Types;
with AMV.Kernels;
with AMV.Kernels.GigE_Vision;
with AMV.Kernels.Images;
with AMV.Spec.GigE_Vision;

package body Test_GigE_Vision_Fixtures is
   package N  renames AMV.GigE_Vision_Native;
   package T  renames AMV.GigE_Vision_Types;
   package K  renames AMV.Kernels.GigE_Vision;
   package KI renames AMV.Kernels.Images;
   package S  renames AMV.Spec.GigE_Vision;

   use type T.Camera_State;
   use type T.Native_Result;
   use type T.Camera_Status;
   use type T.Frame_Status;
   use type T.Pixel;
   use type T.Byte_Array_Access;
   use type T.Int32;
   use type N.Camera_Handle;
   use type KI.Ks_Image_8_Grey;

   type Pixel_Matrix is array (Natural range <>, Natural range <>) of T.Pixel;

   Good_Bytes : aliased T.Byte_Array := [11, 22, 33, 44, 55, 66];
   Truncated_Bytes : aliased T.Byte_Array := [1, 2, 3, 4, 5];
   Excess_Bytes : aliased T.Byte_Array := [1, 2, 3, 4, 5, 6, 7];
   Non_Native_Sentinel : constant N.Camera_Handle := System'To_Address (1);

   procedure Free_Bytes is new Ada.Unchecked_Deallocation
     (T.Byte_Array, T.Byte_Array_Access);

   procedure Check (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Check;

   function Good_Observation return T.Frame_Observation is
     ((Acquisition_Status => T.Native_Success,
       Byte_Count => 6,
       Bytes => Good_Bytes'Access,
       Buffer_Status => T.Arv_Buffer_Status_Success,
       Payload_Type => T.Arv_Payload_Image,
       Pixel_Format => T.Arv_Pixel_Format_Mono_8,
       Width => 3,
       Height => 2,
       Source_Size => 6));

   procedure Check_Frame_Status
     (Observation : T.Frame_Observation;
      Expected    : T.Frame_Status;
      Message     : String;
      State       : T.Camera_State := T.Streaming;
      Timeout     : Natural := 1)
   is
      Image  : KI.Ks_Image_8_Grey := null;
      Status : T.Frame_Status;
   begin
      pragma Check
        (Ghost,
         S.Grab_Status (State, Timeout, Observation) = Expected,
         Message & ": independent specification");
      K.Build_Frame (State, Timeout, Observation, Image, Status);
      Check (Status = Expected, Message & ": production kernel status");
      Check (Image = null, Message & ": failed frame has no image");
   end Check_Frame_Status;

   procedure Run_Status_Examples is
      Frame : T.Frame_Observation := Good_Observation;
   begin
      Frame.Acquisition_Status := T.Native_Error;
      Frame.Buffer_Status := T.Arv_Buffer_Status_Timeout;
      Frame.Payload_Type := 0;
      Check_Frame_Status
        (Frame, T.Frame_Bad_Parameter, "invalid state precedes native error",
         T.Closed);
      Check_Frame_Status
        (Frame, T.Frame_Bad_Parameter, "zero timeout precedes native error",
         T.Streaming, 0);
      Check_Frame_Status
        (Frame, T.Frame_Error, "native error precedes buffer and payload");

      Frame := Good_Observation;
      Frame.Acquisition_Status := T.Native_Not_Called;
      Check_Frame_Status
        (Frame, T.Frame_Bad_Parameter, "not-called acquisition result");

      Frame := Good_Observation;
      Frame.Acquisition_Status := T.Native_Bad_Parameter;
      Check_Frame_Status
        (Frame, T.Frame_Bad_Parameter, "native bad-parameter result");

      Frame := Good_Observation;
      Frame.Acquisition_Status := T.Native_Timeout;
      Frame.Buffer_Status := -1;
      Frame.Payload_Type := 0;
      Check_Frame_Status
        (Frame, T.Frame_Timeout, "native timeout precedes buffer and payload");

      Frame := Good_Observation;
      Frame.Acquisition_Status := T.Native_Out_Of_Memory;
      Check_Frame_Status
        (Frame, T.Frame_Out_Of_Memory, "native allocation failure");

      Frame := Good_Observation;
      Frame.Acquisition_Status := T.Native_Unsupported;
      Check_Frame_Status
        (Frame, T.Frame_Error, "native unsupported result");

      Frame := Good_Observation;
      Frame.Buffer_Status := T.Arv_Buffer_Status_Timeout;
      Frame.Payload_Type := 0;
      Check_Frame_Status
        (Frame, T.Frame_Timeout, "buffer timeout precedes payload");

      Frame := Good_Observation;
      Frame.Buffer_Status := -1;
      Frame.Payload_Type := 0;
      Check_Frame_Status
        (Frame, T.Frame_Error, "bad buffer status precedes payload");

      Frame := Good_Observation;
      Frame.Payload_Type := 0;
      Frame.Pixel_Format := 0;
      Check_Frame_Status
        (Frame, T.Frame_Unsupported_Payload, "unsupported payload");

      Frame := Good_Observation;
      Frame.Payload_Type := T.Arv_Payload_Image_Extended_Chunk;
      Check_Frame_Status
        (Frame, T.Frame_Unsupported_Payload, "image with extended chunks");

      Frame := Good_Observation;
      Frame.Pixel_Format := 0;
      Frame.Width := -1;
      Check_Frame_Status
        (Frame, T.Frame_Unsupported_Format, "format precedes dimensions");

      Frame := Good_Observation;
      Frame.Width := -1;
      Check_Frame_Status
        (Frame, T.Frame_Invalid_Dimensions, "negative width");

      Frame := Good_Observation;
      Frame.Width := 46_341;
      Frame.Height := 46_341;
      Check_Frame_Status
        (Frame, T.Frame_Too_Large, "dimension product exceeds limit");

      Frame := Good_Observation;
      Frame.Bytes := Truncated_Bytes'Access;
      Frame.Byte_Count := 5;
      Frame.Source_Size := 5;
      Check_Frame_Status
        (Frame, T.Frame_Invalid_Length, "truncated source bytes");

      Frame := Good_Observation;
      Frame.Bytes := Excess_Bytes'Access;
      Frame.Byte_Count := 7;
      Frame.Source_Size := 7;
      Check_Frame_Status
        (Frame, T.Frame_Invalid_Length, "excess source bytes");

      Frame := Good_Observation;
      Frame.Source_Size := 7;
      Check_Frame_Status
        (Frame, T.Frame_Invalid_Length, "inconsistent source size");

      Frame := Good_Observation;
      Frame.Bytes := null;
      Check_Frame_Status
        (Frame, T.Frame_Invalid_Length, "null source bytes");
   end Run_Status_Examples;

   procedure Run_Spec_And_Lifecycle_Examples is
      State   : T.Camera_State := T.Closed;
      Handle  : N.Camera_Handle := N.Null_Handle;
      Status  : T.Camera_Status;
      Receipt : T.Native_Result;
      Nul_Selector : constant String := "127.0.0.1" & ASCII.NUL & "suffix";
   begin
      pragma Check (Ghost, not S.Valid_Selector (""), "empty selector");
      pragma Check (Ghost, not S.Valid_Selector ("   "), "blank selector");
      pragma Check (Ghost, not S.Valid_Selector (Nul_Selector), "NUL selector");
      pragma Check (Ghost, S.Valid_Selector ("127.0.0.1"), "loopback selector");

      pragma Check
        (Ghost,
         S.Camera_Result (T.Native_Success) = T.Camera_Success,
         "native success camera mapping");
      pragma Check
        (Ghost,
         S.Camera_Result (T.Native_Unsupported) = T.Camera_Unsupported,
         "native unsupported camera mapping");
      pragma Check
        (Ghost,
         S.Camera_Result (T.Native_Out_Of_Memory) = T.Camera_Out_Of_Memory,
         "native allocation camera mapping");
      pragma Check
        (Ghost,
         S.Camera_Result (T.Native_Timeout) = T.Camera_Error,
         "native timeout camera mapping");
      pragma Check
        (Ghost,
         S.Open_Status (T.Closed, "127.0.0.1", T.Native_Not_Called)
           = T.Camera_Error,
         "open not-called status");
      pragma Check
        (Ghost,
         (S.Open_State (T.Closed, "127.0.0.1", T.Native_Success)
            = T.Open_Stopped),
         "successful open state");
      pragma Check
        (Ghost,
         S.Open_State (T.Closed, "127.0.0.1", T.Native_Error) = T.Closed,
         "failed open state");
      pragma Check
        (Ghost,
         S.Start_State (T.Open_Stopped, T.Native_Success) = T.Streaming,
         "successful start state");
      pragma Check
        (Ghost,
         S.Stop_State (T.Streaming, T.Native_Error) = T.Streaming,
         "failed stop retains streaming state");
      pragma Check
        (Ghost,
         (S.Start_Status (T.Closed, T.Native_Not_Called)
            = T.Camera_Bad_Parameter),
         "closed start status");
      pragma Check
        (Ghost,
         S.Start_Status (T.Streaming, T.Native_Not_Called) = T.Camera_Success,
         "idempotent start status");
      pragma Check
        (Ghost,
         S.Stop_Status (T.Open_Stopped, T.Native_Not_Called) = T.Camera_Success,
         "idempotent stop status");
      pragma Check
        (Ghost,
         S.Stop_Status (T.Streaming, T.Native_Not_Called) = T.Camera_Error,
         "streaming stop not-called status");

      K.Open (State, Handle, "", Status, Receipt);
      Check (Status = T.Camera_Bad_Parameter, "empty selector status");
      Check (Receipt = T.Native_Not_Called, "empty selector is not dispatched");
      Check (State = T.Closed and Handle = N.Null_Handle,
             "empty selector preserves camera state");

      K.Open (State, Handle, "   ", Status, Receipt);
      Check (Status = T.Camera_Bad_Parameter, "blank selector status");
      Check (Receipt = T.Native_Not_Called, "blank selector is not dispatched");

      K.Open (State, Handle, Nul_Selector, Status, Receipt);
      Check (Status = T.Camera_Bad_Parameter, "NUL selector status");
      Check (Receipt = T.Native_Not_Called, "NUL selector is not dispatched");

      State := T.Open_Stopped;
      Handle := Non_Native_Sentinel;
      K.Open (State, Handle, "127.0.0.1", Status, Receipt);
      Check (Status = T.Camera_Bad_Parameter, "open on existing state");
      Check (Receipt = T.Native_Not_Called, "invalid open is not dispatched");

      State := T.Closed;
      Handle := N.Null_Handle;
      K.Start (State, Handle, Status, Receipt);
      Check (Status = T.Camera_Bad_Parameter, "start while closed");
      Check (Receipt = T.Native_Not_Called, "closed start is not dispatched");

      State := T.Streaming;
      Handle := Non_Native_Sentinel;
      K.Start (State, Handle, Status, Receipt);
      Check (Status = T.Camera_Success and Receipt = T.Native_Not_Called,
             "start is idempotent while streaming");
      K.Start (State, Handle, Status, Receipt);
      Check (Status = T.Camera_Success and Receipt = T.Native_Not_Called,
             "repeated start remains idempotent");
      Check (State = T.Streaming, "idempotent start preserves state");

      State := T.Open_Stopped;
      K.Stop (State, Handle, Status, Receipt);
      Check (Status = T.Camera_Success and Receipt = T.Native_Not_Called,
             "stop is idempotent while stopped");
      K.Stop (State, Handle, Status, Receipt);
      Check (Status = T.Camera_Success and Receipt = T.Native_Not_Called,
             "repeated stop remains idempotent");
      Check (State = T.Open_Stopped, "idempotent stop preserves state");

      State := T.Closed;
      Handle := N.Null_Handle;
      K.Close (State, Handle, Receipt);
      Check (State = T.Closed and Handle = N.Null_Handle,
             "close on null handle is local");
      Check (Receipt = T.Native_Not_Called, "close without a handle is not dispatched");
      K.Close (State, Handle, Receipt);
      Check (State = T.Closed and Receipt = T.Native_Not_Called,
             "repeated close remains local");
   end Run_Spec_And_Lifecycle_Examples;

   procedure Run_Pixel_And_Ownership_Example is
      Source : T.Byte_Array_Access :=
        new T.Byte_Array'(1 => 11, 2 => 22, 3 => 33, 4 => 44, 5 => 55, 6 => 66);
      Observation : T.Frame_Observation :=
        (Acquisition_Status => T.Native_Success,
         Byte_Count => 6,
         Bytes => Source,
         Buffer_Status => T.Arv_Buffer_Status_Success,
         Payload_Type => T.Arv_Payload_Image,
         Pixel_Format => T.Arv_Pixel_Format_Mono_8,
         Width => 3,
         Height => 2,
         Source_Size => 6);
      Expected : constant Pixel_Matrix (0 .. 1, 0 .. 2) :=
        [[11, 22, 33], [44, 55, 66]];
      Image  : KI.Ks_Image_8_Grey := null;
      Status : T.Frame_Status;
      Image_Status : AMV.Kernels.Ks_Status;
   begin
      Check (T.Valid_Observation (Observation), "valid 3x2 observation");
      pragma Check
        (Ghost,
         S.Grab_Status (T.Streaming, 1, Observation) = T.Frame_Success,
         "3x2 observation status");
      for Y in Expected'Range (1) loop
         for X in Expected'Range (2) loop
            pragma Check
              (Ghost,
               S.Pixel_At (Observation, X, Y) = Expected (Y, X),
               "worked row-major specification pixel");
         end loop;
      end loop;

      K.Build_Frame (T.Streaming, 1, Observation, Image, Status);
      Check (Status = T.Frame_Success, "3x2 production frame succeeds");
      Check (KI.Valid_Image (Image), "production image handle is valid");
      Check (Image.Width = 3 and Image.Height = 2,
             "production image dimensions are 3x2");
      for Y in Expected'Range (1) loop
         for X in Expected'Range (2) loop
            Check (Image.Pixels.all (Y, X) = Expected (Y, X),
                   "production row-major pixel mapping");
         end loop;
      end loop;

      for Index in Source.all'Range loop
         Source.all (Index) := 0;
      end loop;
      for Y in Expected'Range (1) loop
         for X in Expected'Range (2) loop
            Check (Image.Pixels.all (Y, X) = Expected (Y, X),
                   "image is independent after source mutation");
         end loop;
      end loop;

      Free_Bytes (Source);
      Observation.Bytes := null;
      Check (Source = null, "source bytes are freed");
      for Y in Expected'Range (1) loop
         for X in Expected'Range (2) loop
            Check (Image.Pixels.all (Y, X) = Expected (Y, X),
                   "image is independent after source release");
         end loop;
      end loop;

      KI.Destroy (Image, Image_Status);
      Check (AMV.Kernels.Succeeded (Image_Status), "destroy fixture image");
      Check (Image = null, "fixture image handle is released");
   end Run_Pixel_And_Ownership_Example;

   procedure Run_Bayer_Examples is
      package B renames AMV.GigE_Vision_Bayer;

      Square : aliased T.Byte_Array := [10, 20, 30, 40];
      Wide   : aliased T.Byte_Array := [10, 20, 30, 40, 50, 60];
      Image  : KI.Ks_Image_8_Grey := null;
      Status : T.Frame_Status;
      Image_Status : AMV.Kernels.Ks_Status;

      function Bayer_Observation
        (Pixel_Format  : T.Unsigned_32;
         Bytes         : T.Byte_Array_Access;
         Width, Height : T.Int32) return T.Frame_Observation is
        ((Acquisition_Status => T.Native_Success,
          Byte_Count => Bytes.all'Length,
          Bytes => Bytes,
          Buffer_Status => T.Arv_Buffer_Status_Success,
          Payload_Type => T.Arv_Payload_Image,
          Pixel_Format => Pixel_Format,
          Width => Width,
          Height => Height,
          Source_Size => T.Unsigned_64 (Bytes.all'Length)));

      procedure Check_Uniform
        (Pixel_Format : T.Unsigned_32; Expected : T.Pixel; Name : String) is
      begin
         B.Build_Grey
           (Bayer_Observation (Pixel_Format, Square'Unchecked_Access, 2, 2),
            Image, Status);
         Check (Status = T.Frame_Success, Name & " 2x2 frame succeeds");
         for Y in 0 .. 1 loop
            for X in 0 .. 1 loop
               Check (Image.Pixels.all (Y, X) = Expected,
                      Name & " 2x2 window luma");
            end loop;
         end loop;
         KI.Destroy (Image, Image_Status);
      end Check_Uniform;

      procedure Check_Status
        (Frame : T.Frame_Observation; Expected : T.Frame_Status;
         Message : String) is
      begin
         Check (B.Frame_Status (Frame) = Expected, Message & ": status");
         B.Build_Grey (Frame, Image, Status);
         Check (Status = Expected and then Image = null,
                Message & ": no image");
      end Check_Status;

      Frame : T.Frame_Observation;
      --  R G R / G B G (RGGB, 3x2): the last column reuses the window of
      --  column 1 and both rows the window of row 0.
      Wide_Expected : constant Pixel_Matrix (0 .. 1, 0 .. 2) :=
        [[26, 38, 38], [26, 38, 38]];
   begin
      --  The window 10 20 / 30 40 read as each layout:
      --  (77 R + 75 (G1 + G2) + 29 B + 128) / 256.
      Check_Uniform (B.Arv_Pixel_Format_Bayer_RG_8, 22, "BayerRG8");
      Check_Uniform (B.Arv_Pixel_Format_Bayer_GR_8, 24, "BayerGR8");
      Check_Uniform (B.Arv_Pixel_Format_Bayer_GB_8, 26, "BayerGB8");
      Check_Uniform (B.Arv_Pixel_Format_Bayer_BG_8, 28, "BayerBG8");

      B.Build_Grey
        (Bayer_Observation
           (B.Arv_Pixel_Format_Bayer_RG_8, Wide'Unchecked_Access, 3, 2),
         Image, Status);
      Check (Status = T.Frame_Success, "BayerRG8 3x2 frame succeeds");
      Check (Image.Width = 3 and Image.Height = 2, "Bayer image is 3x2");
      for Y in Wide_Expected'Range (1) loop
         for X in Wide_Expected'Range (2) loop
            Check (Image.Pixels.all (Y, X) = Wide_Expected (Y, X),
                   "Bayer edge windows move inwards");
         end loop;
      end loop;
      KI.Destroy (Image, Image_Status);

      Check (B.Is_Bayer_8 (B.Arv_Pixel_Format_Bayer_GB_8)
             and then not B.Is_Bayer_8 (T.Arv_Pixel_Format_Mono_8),
             "Bayer8 format recognition");

      Frame := Bayer_Observation
        (T.Arv_Pixel_Format_Mono_8, Wide'Unchecked_Access, 3, 2);
      Check_Status (Frame, T.Frame_Unsupported_Format, "Mono8 is not Bayer8");

      Frame := Bayer_Observation
        (B.Arv_Pixel_Format_Bayer_GB_8, Wide'Unchecked_Access, 6, 1);
      Check_Status (Frame, T.Frame_Invalid_Dimensions, "Bayer8 one row");

      Frame := Bayer_Observation
        (B.Arv_Pixel_Format_Bayer_GB_8, Wide'Unchecked_Access, 3, 2);
      Frame.Payload_Type := T.Arv_Payload_Image_Extended_Chunk;
      Check_Status (Frame, T.Frame_Unsupported_Payload, "Bayer8 chunk data");

      Frame := Bayer_Observation
        (B.Arv_Pixel_Format_Bayer_GB_8, Wide'Unchecked_Access, 2, 2);
      Check_Status (Frame, T.Frame_Invalid_Length, "Bayer8 excess bytes");

      Frame := Bayer_Observation
        (B.Arv_Pixel_Format_Bayer_GB_8, Wide'Unchecked_Access, 46_341, 46_341);
      Check_Status (Frame, T.Frame_Too_Large, "Bayer8 too large");
   end Run_Bayer_Examples;

   procedure Run is
   begin
      Run_Spec_And_Lifecycle_Examples;
      Run_Status_Examples;
      Run_Pixel_And_Ownership_Example;
      Run_Bayer_Examples;
   end Run;
end Test_GigE_Vision_Fixtures;
