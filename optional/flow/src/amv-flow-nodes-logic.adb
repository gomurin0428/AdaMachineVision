pragma SPARK_Mode (Off);

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

end AMV.Flow.Nodes.Logic;
