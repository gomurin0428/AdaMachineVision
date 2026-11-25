pragma SPARK_Mode (Off);

with Ada.Containers.Indefinite_Vectors;
with Ada.Containers.Vectors;

with AMV.Flow.Nodes.Imaging;
with AMV.Flow.Nodes.Logic;
with AMV.Flow.Nodes.Logging;
with AMV.Flow.Nodes.Vision;

package body AMV.Flow.Kinds is

   package Name_Vectors is new Ada.Containers.Indefinite_Vectors
     (Positive, String);
   package Maker_Vectors is new Ada.Containers.Vectors
     (Positive, Constructor);

   Names  : Name_Vectors.Vector;
   Makers : Maker_Vectors.Vector;

   procedure Register (Kind_Id : String; Make : not null Constructor) is
   begin
      if not Valid_Name (Kind_Id) then
         raise Ks_Flow_Exception with
           "not a valid kind name: """ & Kind_Id & """";
      elsif Names.Contains (Kind_Id) then
         raise Ks_Flow_Exception with
           "the kind """ & Kind_Id & """ is already registered";
      end if;
      Names.Append (Kind_Id);
      Makers.Append (Make);
   end Register;

   function Count return Natural is (Natural (Names.Length));

   function Kind_Id (Index : Positive) return String is (Names (Index));

   function Exists (Kind_Id : String) return Boolean is
     (Names.Contains (Kind_Id));

   function Create (Kind_Id : String) return AMV.Flow.Nodes.Node_Access is
      Index : constant Natural := Names.Find_Index (Kind_Id);
   begin
      if Index = Name_Vectors.No_Index then
         raise Ks_Flow_Exception with
           "unknown node kind """ & Kind_Id & """";
      end if;
      return Makers (Index).all;
   end Create;

begin
   Register ("ShapeMatch", AMV.Flow.Nodes.Vision.Create_Shape_Match'Access);
   Register ("Fixture", AMV.Flow.Nodes.Vision.Create_Fixture'Access);
   Register ("Caliper", AMV.Flow.Nodes.Vision.Create_Caliper'Access);
   Register ("Blob", AMV.Flow.Nodes.Vision.Create_Blob'Access);
   Register ("Circularity",
             AMV.Flow.Nodes.Vision.Create_Circularity'Access);
   Register ("PolarUnwrap",
             AMV.Flow.Nodes.Imaging.Create_Polar_Unwrap'Access);
   Register ("Morphology", AMV.Flow.Nodes.Imaging.Create_Morphology'Access);
   Register ("RangeCheck", AMV.Flow.Nodes.Logic.Create_Range_Check'Access);
   Register ("CsvLog", AMV.Flow.Nodes.Logging.Create_Csv_Log'Access);
end AMV.Flow.Kinds;
