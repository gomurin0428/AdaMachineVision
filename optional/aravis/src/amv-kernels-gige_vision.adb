pragma Validity_Checks ("F");

package body AMV.Kernels.GigE_Vision with SPARK_Mode is
   package S renames AMV.Spec.GigE_Vision;

   procedure Lemma_Row_Major_Bound
     (Width, Height : Positive; X, Y : Natural)
   with Ghost,
     Pre => X < Width and then Y < Height,
     Post => T.Int64 (Y) * T.Int64 (Width) + T.Int64 (X)
       < T.Int64 (Height) * T.Int64 (Width);

   procedure Lemma_Row_Major_Bound
     (Width, Height : Positive; X, Y : Natural) is
   begin
      null;
   end Lemma_Row_Major_Bound;

   function Camera_Result (Result : T.Native_Result) return T.Camera_Status
     with Pre => Result /= T.Native_Not_Called,
          Post => Camera_Result'Result = S.Camera_Result (Result)
   is
   begin
      case Result is
         when T.Native_Success => return T.Camera_Success;
         when T.Native_Bad_Parameter | T.Native_Not_Called =>
            return T.Camera_Bad_Parameter;
         when T.Native_Unsupported => return T.Camera_Unsupported;
         when T.Native_Out_Of_Memory => return T.Camera_Out_Of_Memory;
         when T.Native_Timeout | T.Native_Error => return T.Camera_Error;
      end case;
   end Camera_Result;

   function Selector_Is_Valid (Device_ID : String) return Boolean
     with Post => Selector_Is_Valid'Result = S.Valid_Selector (Device_ID)
   is
      Has_Non_Space : Boolean := False;
   begin
      if Device_ID'Length = 0 then
         return False;
      end if;
      for I in Device_ID'Range loop
         pragma Loop_Invariant
           (for all J in Device_ID'Range =>
              (if J < I then Device_ID (J) /= ASCII.NUL));
         pragma Loop_Invariant
           (Has_Non_Space =
              (for some J in Device_ID'Range =>
                 J < I and then Device_ID (J) /= ' '));
         if Device_ID (I) = ASCII.NUL then
            return False;
         end if;
         if Device_ID (I) /= ' ' then
            Has_Non_Space := True;
         end if;
      end loop;
      return Has_Non_Space;
   end Selector_Is_Valid;

   procedure Open
     (State    : in out T.Camera_State;
      Handle   : in out N.Camera_Handle;
      Device_ID : String;
      Status   : out T.Camera_Status;
      Receipt  : out T.Native_Result)
   is
      Old_State : constant T.Camera_State := State;
      New_Handle : N.Camera_Handle;
   begin
      Receipt := T.Native_Not_Called;
      if State /= T.Closed then
         Status := T.Camera_Bad_Parameter;
      elsif not Selector_Is_Valid (Device_ID) then
         Status := T.Camera_Bad_Parameter;
      else
         N.Open (Device_ID, New_Handle, Receipt);
         Status := Camera_Result (Receipt);
         if Receipt = T.Native_Success then
            Handle := New_Handle;
            State := T.Open_Stopped;
         end if;
      end if;
      pragma Assert
        (Status = S.Open_Status (Old_State, Device_ID, Receipt));
      pragma Assert
        (State = S.Open_State (Old_State, Device_ID, Receipt));
   end Open;

   procedure Start
     (State   : in out T.Camera_State;
      Handle  : N.Camera_Handle;
      Status  : out T.Camera_Status;
      Receipt : out T.Native_Result)
   is
      Old_State : constant T.Camera_State := State;
   begin
      Receipt := T.Native_Not_Called;
      if State = T.Closed then
         Status := T.Camera_Bad_Parameter;
      elsif State = T.Streaming then
         Status := T.Camera_Success;
      else
         N.Start (Handle, Receipt);
         Status := Camera_Result (Receipt);
         if Receipt = T.Native_Success then
            State := T.Streaming;
         end if;
      end if;
      pragma Assert (Status = S.Start_Status (Old_State, Receipt));
      pragma Assert (State = S.Start_State (Old_State, Receipt));
   end Start;

   procedure Stop
     (State   : in out T.Camera_State;
      Handle  : N.Camera_Handle;
      Status  : out T.Camera_Status;
      Receipt : out T.Native_Result)
   is
      Old_State : constant T.Camera_State := State;
   begin
      Receipt := T.Native_Not_Called;
      if State /= T.Streaming then
         Status := T.Camera_Success;
      else
         N.Stop (Handle, Receipt);
         Status := Camera_Result (Receipt);
         if Receipt = T.Native_Success then
            State := T.Open_Stopped;
         end if;
      end if;
      pragma Assert (Status = S.Stop_Status (Old_State, Receipt));
      pragma Assert (State = S.Stop_State (Old_State, Receipt));
   end Stop;

   procedure Close
     (State        : in out T.Camera_State;
      Handle       : in out N.Camera_Handle;
      Stop_Receipt : out T.Native_Result)
   is
   begin
      if Handle = N.Null_Handle then
         Stop_Receipt := T.Native_Not_Called;
      else
         N.Close (Handle, State = T.Streaming, Stop_Receipt);
      end if;
      State := T.Closed;
   end Close;

   function Is_Open (State : T.Camera_State) return Boolean is
     (State /= T.Closed);

   function Is_Streaming (State : T.Camera_State) return Boolean is
     (State = T.Streaming);

   function Determine_Frame_Status
     (State   : T.Camera_State;
      Timeout : Natural;
      Frame   : T.Frame_Observation) return T.Frame_Status
   with Post => Determine_Frame_Status'Result = S.Grab_Status
     (State, Timeout, Frame)
   is
      Pixel_Count : T.Int64;
   begin
      if State /= T.Streaming or else Timeout = 0 then
         return T.Frame_Bad_Parameter;
      end if;
      case Frame.Acquisition_Status is
         when T.Native_Not_Called | T.Native_Bad_Parameter =>
            return T.Frame_Bad_Parameter;
         when T.Native_Timeout =>
            return T.Frame_Timeout;
         when T.Native_Out_Of_Memory =>
            return T.Frame_Out_Of_Memory;
         when T.Native_Unsupported | T.Native_Error =>
            return T.Frame_Error;
         when T.Native_Success =>
            null;
      end case;
      if Frame.Buffer_Status = T.Arv_Buffer_Status_Timeout then
         return T.Frame_Timeout;
      elsif Frame.Buffer_Status /= T.Arv_Buffer_Status_Success then
         return T.Frame_Error;
      elsif Frame.Payload_Type /= T.Arv_Payload_Image then
         return T.Frame_Unsupported_Payload;
      elsif Frame.Pixel_Format /= T.Arv_Pixel_Format_Mono_8 then
         return T.Frame_Unsupported_Format;
      elsif Frame.Width <= 0 or else Frame.Height <= 0 then
         return T.Frame_Invalid_Dimensions;
      end if;

      Pixel_Count := T.Int64 (Frame.Width) * T.Int64 (Frame.Height);
      if Pixel_Count > T.Max_Image_Pixels then
         return T.Frame_Too_Large;
      elsif Frame.Source_Size /= T.Unsigned_64 (Pixel_Count)
        or else T.Int64 (Frame.Byte_Count) /= Pixel_Count
        or else Frame.Bytes = null
        or else Frame.Bytes.all'First /= 1
        or else T.Int64 (Frame.Bytes.all'Length) /= Pixel_Count
      then
         return T.Frame_Invalid_Length;
      else
         return T.Frame_Success;
      end if;
   end Determine_Frame_Status;

   procedure Build_Frame
     (State       : T.Camera_State;
      Timeout     : Natural;
      Observation : T.Frame_Observation;
      Image       : out KI.Ks_Image_8_Grey;
      Status      : out T.Frame_Status)
   is
      Image_Status : AMV.Kernels.Ks_Status;
      Width        : Natural;
      Height       : Natural;
   begin
      Image := null;
      Status := Determine_Frame_Status (State, Timeout, Observation);
      if Status /= T.Frame_Success then
         return;
      end if;
      pragma Assert
        (Status = S.Grab_Status (State, Timeout, Observation));
      pragma Assert
        (S.Grab_Status (T.Streaming, 1, Observation) = T.Frame_Success);

      Width := Natural (Observation.Width);
      Height := Natural (Observation.Height);
      pragma Assert (Width > 0 and then Height > 0);
      pragma Assert (T.Int64 (Width) * T.Int64 (Height) =
                       T.Int64 (Observation.Byte_Count));
      KI.Create (Observation.Width, Observation.Height, 0, Image, Image_Status);
      if not AMV.Kernels.Succeeded (Image_Status) then
         pragma Assert
           (Image_Status.Failure = AMV.Kernels.Failure_Out_Of_Memory);
         Status := T.Frame_Out_Of_Memory;
         return;
      end if;

      for Y in 0 .. Height - 1 loop
         for X in 0 .. Width - 1 loop
            Lemma_Row_Major_Bound (Width, Height, X, Y);
            pragma Assert
              (T.Int64 (Y) * T.Int64 (Width) + T.Int64 (X) <
                 T.Int64 (Observation.Byte_Count));
            Image.Pixels (Y, X) := Observation.Bytes.all
              (Positive
                 (Natural
                    (T.Int64 (Y) * T.Int64 (Width)
                     + T.Int64 (X)) + 1));
            pragma Loop_Invariant
              (KI.Valid_Image (Image)
               and then Image.Width = Observation.Width
               and then Image.Height = Observation.Height
               and then
                 (for all J in Image.Pixels'Range (1) =>
                    (if J < Y then
                       (for all K in Image.Pixels'Range (2) =>
                          Image.Pixels (J, K) =
                            S.Pixel_At (Observation, Natural (K), Natural (J)))))
               and then
                 (for all K in Image.Pixels'Range (2) =>
                    (if K <= X then Image.Pixels (Y, K) =
                       S.Pixel_At (Observation, Natural (K), Y))));
         end loop;
         pragma Loop_Invariant
           (KI.Valid_Image (Image)
            and then Image.Width = Observation.Width
            and then Image.Height = Observation.Height
            and then
              (for all J in Image.Pixels'Range (1) =>
                 (if J <= Y then
                    (for all X in Image.Pixels'Range (2) =>
                       Image.Pixels (J, X) =
                         S.Pixel_At (Observation, Natural (X), Natural (J))))));
      end loop;
      Status := T.Frame_Success;
   end Build_Frame;

   procedure Grab
     (State        : T.Camera_State;
      Handle       : N.Camera_Handle;
      Timeout      : Natural;
      Image        : out KI.Ks_Image_8_Grey;
      Status       : out T.Frame_Status;
      Observation  : out T.Frame_Observation)
   is
   begin
      Observation :=
        (Acquisition_Status => T.Native_Not_Called,
         Byte_Count         => 0,
         Bytes              => null,
         Buffer_Status      => -1,
         Payload_Type       => 0,
         Pixel_Format       => 0,
         Width              => 0,
         Height             => 0,
         Source_Size        => 0);
      if State = T.Streaming and then Timeout > 0 then
         N.Acquire (Handle, Positive (Timeout), Observation);
      end if;
      Build_Frame (State, Timeout, Observation, Image, Status);
   end Grab;

end AMV.Kernels.GigE_Vision;
