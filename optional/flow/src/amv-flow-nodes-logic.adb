pragma SPARK_Mode (Off);

with Ada.Strings;
with Ada.Strings.Fixed;

with AMV.Flow.JSON;
with AMV.Flow.Values;

package body AMV.Flow.Nodes.Logic is

   use AMV.Flow.Values;

   Large : constant := 1.0E300;

   type Range_Check_Node is new Ks_Flow_Node with record
      Low, High : Real := 0.0;
      Value_In  : Ks_Flow_Value;
      Done      : Boolean := False;
      Pass      : Boolean := False;
   end record;

   overriding function Kind_Id (Node : Range_Check_Node) return String;
   overriding function Ports (Node : Range_Check_Node) return Port_Array;
   overriding function Params (Node : Range_Check_Node) return Param_Array;
   overriding procedure Set_Param
     (Node : in out Range_Check_Node; Name : String; Value : Ks_Flow_Value);
   overriding function Get_Param
     (Node : Range_Check_Node; Name : String) return Ks_Flow_Value;
   overriding procedure Set_Input
     (Node : in out Range_Check_Node; Port : String; Value : Ks_Flow_Value);
   overriding procedure Clear_Inputs (Node : in out Range_Check_Node);
   overriding function Problem (Node : Range_Check_Node) return String;
   overriding procedure Execute (Node : in out Range_Check_Node);
   overriding function Get_Output
     (Node : Range_Check_Node; Port : String) return Ks_Flow_Value;

   overriding function Kind_Id (Node : Range_Check_Node) return String is
     ("RangeCheck");

   overriding function Ports (Node : Range_Check_Node) return Port_Array is
     [In_Port ("Value", Real_Type),
      Out_Port ("Pass", Boolean_Type, "Low <= Value <= High")];

   overriding function Params (Node : Range_Check_Node) return Param_Array is
     [Real_Param_Of ("Low", -Large, Large),
      Real_Param_Of ("High", -Large, Large)];

   overriding procedure Set_Param (Node  : in out Range_Check_Node;
                                   Name  : String;
                                   Value : Ks_Flow_Value) is
   begin
      if Name = "Low" then
         Node.Low := Value.As_Real;
      elsif Name = "High" then
         Node.High := Value.As_Real;
      else
         raise Ks_Flow_Exception with
           "RangeCheck has no parameter """ & Name & """";
      end if;
   end Set_Param;

   overriding function Get_Param (Node : Range_Check_Node; Name : String)
                                  return Ks_Flow_Value is
   begin
      if Name = "Low" then
         return From_Real (Node.Low);
      elsif Name = "High" then
         return From_Real (Node.High);
      end if;
      raise Ks_Flow_Exception with
        "RangeCheck has no parameter """ & Name & """";
   end Get_Param;

   overriding procedure Set_Input (Node  : in out Range_Check_Node;
                                   Port  : String;
                                   Value : Ks_Flow_Value) is
   begin
      if Port /= "Value" then
         raise Ks_Flow_Exception with
           "RangeCheck has no input """ & Port & """";
      end if;
      Node.Value_In := Value;
   end Set_Input;

   overriding procedure Clear_Inputs (Node : in out Range_Check_Node) is
   begin
      Node.Value_In := No_Value;
      Node.Done := False;
   end Clear_Inputs;

   overriding function Problem (Node : Range_Check_Node) return String is
     (if Node.Low > Node.High then "Low is greater than High" else "");

   overriding procedure Execute (Node : in out Range_Check_Node) is
      Value : constant Real := Node.Value_In.As_Real;
   begin
      if Node.Low > Node.High then
         Set_Result (Node, AMV.Tools.Error, "Low is greater than High");
         return;
      end if;
      Node.Done := True;
      Node.Pass := Value >= Node.Low and then Value <= Node.High;
      if not Node.Pass then
         Set_Result
           (Node, AMV.Tools.Reject,
            AMV.Flow.JSON.Number_Image (Value) & " is outside ["
            & AMV.Flow.JSON.Number_Image (Node.Low) & ", "
            & AMV.Flow.JSON.Number_Image (Node.High) & "]");
      end if;
   end Execute;

   overriding function Get_Output (Node : Range_Check_Node; Port : String)
                                   return Ks_Flow_Value is
   begin
      if Port /= "Pass" then
         raise Ks_Flow_Exception with
           "RangeCheck has no output """ & Port & """";
      end if;
      return (if Node.Done then From_Boolean (Node.Pass) else No_Value);
   end Get_Output;

   function Create_Range_Check return Node_Access is (new Range_Check_Node);

   ---------------------------------------------------------------------
   --  And, Or
   ---------------------------------------------------------------------

   Max_Terms : constant := 4;

   type Bool_Array is array (1 .. Max_Terms) of Boolean;

   type Combine_Node (Is_And : Boolean) is new Ks_Flow_Node with record
      Linked : Bool_Array := [others => False];  --  in this run
      Values : Bool_Array := [others => False];  --  False: no value
      Judge  : Boolean := False;
      Done   : Boolean := False;
      Out_V  : Boolean := False;
   end record;

   overriding function Kind_Id (Node : Combine_Node) return String;
   overriding function Ports (Node : Combine_Node) return Port_Array;
   overriding function Params (Node : Combine_Node) return Param_Array;
   overriding procedure Set_Param
     (Node : in out Combine_Node; Name : String; Value : Ks_Flow_Value);
   overriding function Get_Param
     (Node : Combine_Node; Name : String) return Ks_Flow_Value;
   overriding procedure Set_Input
     (Node : in out Combine_Node; Port : String; Value : Ks_Flow_Value);
   overriding procedure Clear_Inputs (Node : in out Combine_Node);
   overriding procedure Execute (Node : in out Combine_Node);
   overriding function Get_Output
     (Node : Combine_Node; Port : String) return Ks_Flow_Value;

   function Term_Name (I : Positive) return String is
     ("In" & Ada.Strings.Fixed.Trim (I'Image, Ada.Strings.Left));

   overriding function Kind_Id (Node : Combine_Node) return String is
     (if Node.Is_And then "And" else "Or");

   overriding function Ports (Node : Combine_Node) return Port_Array is
      Result : Port_Array (1 .. Max_Terms + 1);
   begin
      for I in 1 .. Max_Terms loop
         Result (I) := In_Port (Term_Name (I), Boolean_Type, Required => False,
                                Help => "an input that is not linked does "
                                        & "not count; one with no value is "
                                        & "False");
      end loop;
      Result (Result'Last) :=
        Out_Port ("Out", Boolean_Type,
                  (if Node.Is_And then "every linked input is True"
                   else "a linked input is True"));
      return Result;
   end Ports;

   overriding function Params (Node : Combine_Node) return Param_Array is
     [1 => Boolean_Param_Of
        ("Judge", "on: Out False rejects the run (the flow's verdict)")];

   overriding procedure Set_Param
     (Node : in out Combine_Node; Name : String; Value : Ks_Flow_Value) is
   begin
      if Name /= "Judge" then
         raise Ks_Flow_Exception with
           Kind_Id (Node) & " has no parameter """ & Name & """";
      end if;
      Node.Judge := Value.As_Boolean;
   end Set_Param;

   overriding function Get_Param
     (Node : Combine_Node; Name : String) return Ks_Flow_Value is
   begin
      if Name /= "Judge" then
         raise Ks_Flow_Exception with
           Kind_Id (Node) & " has no parameter """ & Name & """";
      end if;
      return From_Boolean (Node.Judge);
   end Get_Param;

   overriding procedure Set_Input
     (Node : in out Combine_Node; Port : String; Value : Ks_Flow_Value) is
   begin
      for I in 1 .. Max_Terms loop
         if Port = Term_Name (I) then
            Node.Linked (I) := True;
            Node.Values (I) := Value.Has_Value and then Value.As_Boolean;
            return;
         end if;
      end loop;
      raise Ks_Flow_Exception with
        Kind_Id (Node) & " has no input """ & Port & """";
   end Set_Input;

   overriding procedure Clear_Inputs (Node : in out Combine_Node) is
   begin
      Node.Linked := [others => False];
      Node.Values := [others => False];
      Node.Done := False;
   end Clear_Inputs;

   overriding procedure Execute (Node : in out Combine_Node) is
      Any_Linked : Boolean := False;
   begin
      Node.Out_V := Node.Is_And;
      for I in 1 .. Max_Terms loop
         if Node.Linked (I) then
            Any_Linked := True;
            Node.Out_V := (if Node.Is_And then Node.Out_V and Node.Values (I)
                           else Node.Out_V or Node.Values (I));
         end if;
      end loop;
      if not Any_Linked then
         Set_Result (Node, AMV.Tools.Error, "no input is linked");
         return;
      end if;
      Node.Done := True;
      if Node.Judge and then not Node.Out_V then
         Set_Result (Node, AMV.Tools.Reject,
                     (if Node.Is_And then "not every input is True"
                      else "no input is True"));
      end if;
   end Execute;

   overriding function Get_Output
     (Node : Combine_Node; Port : String) return Ks_Flow_Value is
   begin
      if Port /= "Out" then
         raise Ks_Flow_Exception with
           Kind_Id (Node) & " has no output """ & Port & """";
      end if;
      return (if Node.Done then From_Boolean (Node.Out_V) else No_Value);
   end Get_Output;

   function Create_And return Node_Access is
     (new Combine_Node (Is_And => True));
   function Create_Or return Node_Access is
     (new Combine_Node (Is_And => False));

   ---------------------------------------------------------------------
   --  Not
   ---------------------------------------------------------------------

   type Not_Node is new Ks_Flow_Node with record
      In_V  : Boolean := False;
      Done  : Boolean := False;
   end record;

   overriding function Kind_Id (Node : Not_Node) return String is ("Not");
   overriding function Ports (Node : Not_Node) return Port_Array is
     [In_Port ("In", Boolean_Type), Out_Port ("Out", Boolean_Type)];
   overriding function Params (Node : Not_Node) return Param_Array is ([]);
   overriding procedure Set_Param
     (Node : in out Not_Node; Name : String; Value : Ks_Flow_Value);
   overriding function Get_Param
     (Node : Not_Node; Name : String) return Ks_Flow_Value;
   overriding procedure Set_Input
     (Node : in out Not_Node; Port : String; Value : Ks_Flow_Value);
   overriding procedure Clear_Inputs (Node : in out Not_Node);
   overriding procedure Execute (Node : in out Not_Node);
   overriding function Get_Output
     (Node : Not_Node; Port : String) return Ks_Flow_Value;

   overriding procedure Set_Param
     (Node : in out Not_Node; Name : String; Value : Ks_Flow_Value) is
   begin
      raise Ks_Flow_Exception with "Not has no parameter """ & Name & """";
   end Set_Param;

   overriding function Get_Param
     (Node : Not_Node; Name : String) return Ks_Flow_Value is
     (raise Ks_Flow_Exception with "Not has no parameter """ & Name & """");

   overriding procedure Set_Input
     (Node : in out Not_Node; Port : String; Value : Ks_Flow_Value) is
   begin
      if Port /= "In" then
         raise Ks_Flow_Exception with "Not has no input """ & Port & """";
      end if;
      Node.In_V := Value.As_Boolean;
   end Set_Input;

   overriding procedure Clear_Inputs (Node : in out Not_Node) is
   begin
      Node.Done := False;
   end Clear_Inputs;

   overriding procedure Execute (Node : in out Not_Node) is
   begin
      Node.Done := True;
   end Execute;

   overriding function Get_Output
     (Node : Not_Node; Port : String) return Ks_Flow_Value is
   begin
      if Port /= "Out" then
         raise Ks_Flow_Exception with "Not has no output """ & Port & """";
      end if;
      return (if Node.Done then From_Boolean (not Node.In_V) else No_Value);
   end Get_Output;

   function Create_Not return Node_Access is (new Not_Node);

end AMV.Flow.Nodes.Logic;
