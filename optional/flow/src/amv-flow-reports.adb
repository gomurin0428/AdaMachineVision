pragma SPARK_Mode (Off);

with Ada.Numerics;
with Ada.Numerics.Long_Elementary_Functions;
with Ada.Strings.Unbounded;

with AMV.Flow.JSON;
with AMV.Flow.Kinds;
with AMV.Flow.Nodes;
with AMV.Images;
with AMV.Shapes;
with AMV.Tools;
with AMV.Transforms;

package body AMV.Flow.Reports is

   use Ada.Strings.Unbounded;
   use AMV.Flow.JSON;
   use AMV.Flow.Nodes;
   use AMV.Flow.Values;

   function Result_Name (R : AMV.Tools.Ks_Tool_Result_Constants)
                         return String is
     (case R is
         when AMV.Tools.Accept_Result => "accept",
         when AMV.Tools.Warning       => "warning",
         when AMV.Tools.Reject        => "reject",
         when AMV.Tools.Error         => "error");

   function Kind_Text (Kind : Param_Kind) return String is
     (case Kind is
         when Real_Param    => "Real",
         when Integer_Param => "Integer",
         when Boolean_Param => "Boolean",
         when Choice_Param  => "Choice",
         when String_Param  => "String",
         when Shape_Param   => "Shape");

   procedure Write_Value (W : in out Writer; Value : Ks_Flow_Value) is
   begin
      if not Value.Has_Value then
         W.Null_Value;
         return;
      end if;
      case Value.Kind is
         when Real_Type    => W.Value (Value.As_Real);
         when Integer_Type => W.Value (Value.As_Integer);
         when Boolean_Type => W.Value (Value.As_Boolean);
         when others       => W.Value (Value.Image);
      end case;
   end Write_Value;

   function Kinds_JSON return String is
      W : Writer;
   begin
      W.Begin_Array;
      for K in 1 .. AMV.Flow.Kinds.Count loop
         declare
            N : Node_Access := AMV.Flow.Kinds.Create (AMV.Flow.Kinds.Kind_Id (K));
         begin
            W.Begin_Object;
            W.Key ("kind");
            W.Value (N.Kind_Id);
            W.Key ("ports");
            W.Begin_Array;
            for P of N.Ports loop
               W.Begin_Object (Inline => True);
               W.Key ("name");
               W.Value (To_String (P.Name));
               W.Key ("direction");
               W.Value (if P.Direction = Input then "in" else "out");
               W.Key ("type");
               W.Value (Type_Name (P.Value_Type));
               W.Key ("required");
               W.Value (P.Direction = Input and then P.Required);
               W.Key ("help");
               W.Value (To_String (P.Help));
               W.End_Object;
            end loop;
            W.End_Array;
            W.Key ("params");
            W.Begin_Array;
            for P of N.Params loop
               W.Begin_Object (Inline => True);
               W.Key ("name");
               W.Value (To_String (P.Name));
               W.Key ("kind");
               W.Value (Kind_Text (P.Kind));
               if P.Kind in Real_Param | Integer_Param then
                  W.Key ("low");
                  W.Value (P.Low);
                  W.Key ("high");
                  W.Value (P.High);
               end if;
               if P.Kind = Choice_Param then
                  W.Key ("choices");
                  W.Begin_Array;
                  declare
                     Choices : constant String := To_String (P.Choices);
                     Start   : Positive := Choices'First;
                  begin
                     for I in Choices'Range loop
                        if Choices (I) = '|' then
                           W.Value (Choices (Start .. I - 1));
                           Start := I + 1;
                        end if;
                     end loop;
                     W.Value (Choices (Start .. Choices'Last));
                  end;
                  W.End_Array;
               end if;
               W.Key ("unit");
               W.Value (To_String (P.Unit));
               W.Key ("help");
               W.Value (To_String (P.Help));
               W.End_Object;
            end loop;
            W.End_Array;
            W.End_Object;
            Free (N);
         end;
      end loop;
      W.End_Array;
      return W.Text;
   end Kinds_JSON;

   function Problems_JSON (Flow : AMV.Flow.Graphs.Ks_Flow) return String is
      W : Writer;
   begin
      W.Begin_Array;
      for P of Flow.Problems loop
         W.Value (P);
      end loop;
      W.End_Array;
      return W.Text;
   end Problems_JSON;

   function Results_JSON (Flow : AMV.Flow.Graphs.Ks_Flow) return String is
      W : Writer;
   begin
      W.Begin_Object;
      W.Key ("result");
      W.Value (Result_Name (Flow.Result));
      W.Key ("message");
      W.Value (Flow.Message);
      W.Key ("nodes");
      W.Begin_Array;
      for I in 1 .. Flow.Node_Count loop
         declare
            Id : constant Positive := Flow.Node_Id_At (I);
            N  : constant Node_Access := Flow.Node (Id);
         begin
            W.Begin_Object;
            W.Key ("id");
            W.Value (Long_Long_Integer (Id));
            W.Key ("state");
            W.Value (case N.State is
                        when Not_Run => "not run",
                        when Ran     => "ran",
                        when Skipped => "skipped");
            W.Key ("result");
            W.Value (Result_Name (N.Result));
            W.Key ("message");
            W.Value (N.Message);
            W.Key ("timeMs");
            W.Value (N.Time_Ms);
            W.Key ("outputs");
            W.Begin_Object (Inline => True);
            for P of N.Ports loop
               if P.Direction = Output then
                  W.Key (To_String (P.Name));
                  Write_Value
                    (W, (if N.State = Ran then N.Get_Output (To_String (P.Name))
                         else No_Value));
               end if;
            end loop;
            W.End_Object;
            W.End_Object;
         end;
      end loop;
      W.End_Array;
      W.Key ("outputs");
      W.Begin_Object;
      for I in 1 .. Flow.Output_Count loop
         W.Key (Flow.Output_Name (I));
         Write_Value (W, Flow.Get_Output (Flow.Output_Name (I)));
      end loop;
      W.End_Object;
      W.End_Object;
      return W.Text;
   end Results_JSON;

   function Node_Image (Flow : AMV.Flow.Graphs.Ks_Flow;
                        Id   : Positive) return AMV.Flow.Values.Ks_Flow_Value
   is
      Value : Ks_Flow_Value;
   begin
      if not Flow.Contains (Id) then
         return No_Value;
      elsif Find_Port (Flow.Node (Id).all, "Image", Input) /= 0 then
         Value := Flow.Value_Into (Id, "Image");
      elsif Find_Port (Flow.Node (Id).all, "Image", Output) /= 0
        and then Flow.Node (Id).State = Ran
      then
         --  A source of images (a camera): what it gave.
         Value := Flow.Node (Id).Get_Output ("Image");
      else
         return No_Value;
      end if;
      return (if Value.Has_Value and then Value.Kind = Image_8_Grey_Type
              then Value else No_Value);
   end Node_Image;

   function Graphics_JSON (Flow : AMV.Flow.Graphs.Ks_Flow;
                           Id   : Positive) return String
   is
      use Ada.Numerics.Long_Elementary_Functions;
      W           : Writer;
      Image_Value : constant Ks_Flow_Value := Node_Image (Flow, Id);

      type Point is record
         X, Y : Real;
      end record;
      type Point_Array is array (Positive range <>) of Point;

      procedure Polygon (Role   : String;
                         To_Px  : AMV.Transforms.Ks_Transform_2D_Linear;
                         Points : Point_Array) is
         PX, PY : Real;
      begin
         W.Begin_Object (Inline => True);
         W.Key ("kind");
         W.Value ("polygon");
         W.Key ("role");
         W.Value (Role);
         W.Key ("points");
         W.Begin_Array;
         for P of Points loop
            To_Px.Map_Point (P.X, P.Y, PX, PY);
            W.Begin_Array;
            W.Value (PX);
            W.Value (PY);
            W.End_Array;
         end loop;
         W.End_Array;
         W.End_Object;
      end Polygon;

      procedure Region (Shape : AMV.Shapes.Ks_Shape'Class;
                        Image : AMV.Images.Ks_Image_8_Grey) is
         To_Px : constant AMV.Transforms.Ks_Transform_2D_Linear :=
           Image.Get_Transform ("#", Shape.Selected_Space_Name);
      begin
         if Shape in AMV.Shapes.Ks_Rectangle'Class then
            declare
               R  : constant AMV.Shapes.Ks_Rectangle :=
                 AMV.Shapes.Ks_Rectangle (Shape);
               HW : constant Real := R.Width / 2.0;
               HH : constant Real := R.Height / 2.0;
            begin
               Polygon ("region", To_Px,
                        [(R.Center_X - HW, R.Center_Y - HH),
                         (R.Center_X + HW, R.Center_Y - HH),
                         (R.Center_X + HW, R.Center_Y + HH),
                         (R.Center_X - HW, R.Center_Y + HH)]);
            end;
         elsif Shape in AMV.Shapes.Ks_Rectangle_Affine'Class then
            declare
               R : constant AMV.Shapes.Ks_Rectangle_Affine :=
                 AMV.Shapes.Ks_Rectangle_Affine (Shape);
            begin
               Polygon ("region", To_Px,
                        [(R.Corner_Origin_X, R.Corner_Origin_Y),
                         (R.Corner_X_X, R.Corner_X_Y),
                         (R.Corner_Opposite_X, R.Corner_Opposite_Y),
                         (R.Corner_Y_X, R.Corner_Y_Y)]);
            end;
         elsif Shape in AMV.Shapes.Ks_Circle'Class then
            declare
               C      : constant AMV.Shapes.Ks_Circle :=
                 AMV.Shapes.Ks_Circle (Shape);
               Points : Point_Array (1 .. 72);
               A      : Real;
            begin
               for I in Points'Range loop
                  A := 2.0 * Ada.Numerics.Pi * Real (I - 1) / 72.0;
                  Points (I) := (C.Center_X + C.Radius * Cos (A),
                                 C.Center_Y + C.Radius * Sin (A));
               end loop;
               Polygon ("region", To_Px, Points);
            end;
         end if;
      end Region;
   begin
      W.Begin_Object;
      if not Image_Value.Has_Value then
         W.Key ("width");
         W.Value (Long_Long_Integer'(0));
         W.Key ("height");
         W.Value (Long_Long_Integer'(0));
         W.Key ("items");
         W.Begin_Array;
         W.End_Array;
         W.End_Object;
         return W.Text;
      end if;
      declare
         Image : constant AMV.Images.Ks_Image_8_Grey := Image_Value.As_Image;
         N     : constant Node_Access := Flow.Node (Id);
      begin
         W.Key ("width");
         W.Value (Long_Long_Integer (Image.Width));
         W.Key ("height");
         W.Value (Long_Long_Integer (Image.Height));
         W.Key ("items");
         W.Begin_Array;
         for P of N.Params loop
            if P.Kind = Shape_Param and then To_String (P.Name) /= "TrainRegion"
            then
               declare
                  Value : constant Ks_Flow_Value :=
                    N.Get_Param (To_String (P.Name));
               begin
                  if Value.Has_Value then
                     Region (Value.As_Shape, Image);
                  end if;
               exception
                  when AMV.Ks_Exception | AMV.Ks_Bad_Parameter_Exception
                     | AMV.Ks_Image_Bad_Selected_Space_Name_Exception =>
                     null;  --  a space this image does not have
               end;
            end if;
         end loop;
         declare
            Marks : Mark_Vectors.Vector;
         begin
            if N.State = Ran then
               N.Add_Pixel_Marks (Marks);
            end if;
            for M of Marks loop
               W.Begin_Object (Inline => True);
               W.Key ("kind");
               if M.Polygon then
                  W.Value ("polygon");
                  W.Key ("role");
                  W.Value ("found");
                  W.Key ("points");
                  W.Begin_Array;
                  for I in 1 .. M.Count loop
                     W.Begin_Array;
                     W.Value (M.X (I));
                     W.Value (M.Y (I));
                     W.End_Array;
                  end loop;
                  W.End_Array;
               else
                  W.Value ("point");
                  W.Key ("role");
                  W.Value ("found");
                  W.Key ("x");
                  W.Value (M.X (1));
                  W.Key ("y");
                  W.Value (M.Y (1));
               end if;
               W.End_Object;
            end loop;
            if not Marks.Is_Empty then
               W.End_Array;
               W.End_Object;
               return W.Text;
            end if;
         end;
         if N.State = Ran then
            declare
               function Output_Of (Name : String) return Ks_Flow_Value is
                 (if Find_Port (N.all, Name, Output) /= 0
                  then N.Get_Output (Name) else No_Value);
               XV : Ks_Flow_Value := Output_Of ("X");
               YV : Ks_Flow_Value := Output_Of ("Y");
               PX, PY : Real;
            begin
               if not (XV.Has_Value and then YV.Has_Value) then
                  XV := Output_Of ("CenterX");
                  YV := Output_Of ("CenterY");
               end if;
               if XV.Has_Value and then YV.Has_Value then
                  Image.Get_Transform ("#", ".").Map_Point
                    (XV.As_Real, YV.As_Real, PX, PY);
                  W.Begin_Object (Inline => True);
                  W.Key ("kind");
                  W.Value ("point");
                  W.Key ("role");
                  W.Value ("found");
                  W.Key ("x");
                  W.Value (PX);
                  W.Key ("y");
                  W.Value (PY);
                  W.End_Object;
               end if;
            end;
         end if;
         W.End_Array;
      end;
      W.End_Object;
      return W.Text;
   end Graphics_JSON;

end AMV.Flow.Reports;
