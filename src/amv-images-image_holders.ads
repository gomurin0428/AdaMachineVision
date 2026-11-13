--  An optional image of any type, as used for a tool's input that
--  VisionPro declares as ICogImage (CogImageConvertTool.InputImage): an
--  empty holder means "no image" (VisionPro's null), which the tools
--  treat as an image without pixels.
--
--     Tool.Input_Image := AMV.Images.Image_Holders.To_Holder (Colour);
--     Tool.Input_Image.Clear;
--
--  The holder keeps a copy of the image, which shares the pixels with the
--  image it was made from (AMV.Images: assignment shares pixels).

pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with Ada.Containers.Indefinite_Holders;

package AMV.Images.Image_Holders is new Ada.Containers.Indefinite_Holders
  (Element_Type => AMV.Images.Ks_Image'Class);
