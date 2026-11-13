--  An optional region of any type, as used for a tool's Region property:
--  an empty holder means "no region" (VisionPro's null), which tools treat
--  as the whole image.
--
--     Tool.Region := AMV.Shapes.Region_Holders.To_Holder (Rect);
--     Tool.Region.Clear;

pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with Ada.Containers.Indefinite_Holders;

package AMV.Shapes.Region_Holders is new Ada.Containers.Indefinite_Holders
  (Element_Type => AMV.Shapes.Ks_Region'Class);
