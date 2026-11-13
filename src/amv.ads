--  AdaMachineVision (AMV)
--
--  A machine vision library whose public interface follows the object model
--  and naming of the Cognex VisionPro .NET API, mapped to Ada conventions
--  (see docs/DESIGN.md and docs/API_MAPPING.md). The implementation behind
--  that interface is independent. AMV is not affiliated with or endorsed by
--  Cognex Corporation; "Cognex" and "VisionPro" are trademarks of Cognex
--  Corporation.

package AMV with SPARK_Mode is
   pragma Pure;

   Version : constant String := "0.1.0";

   subtype Real is Long_Float;
   --  Coordinates, lengths, angles (always radians), scores and times.

   --  Exceptions. Each is raised with a message naming the property or
   --  argument at fault. Tool Run never propagates them: it records them in
   --  the tool's Run_Status instead (see AMV.Tools).

   Ks_Exception : exception;
   --  A failure that has no more specific exception below.

   Ks_Image_No_Pixels_Exception : exception;
   --  An image that must hold pixels was never allocated (for example a
   --  tool's InputImage was not set).

   Ks_Image_Bad_Selected_Space_Name_Exception : exception;
   --  A coordinate space name does not exist in the image's coordinate
   --  space tree, or is malformed.

   Ks_Operator_Not_Trained_Exception : exception;
   --  A pattern, calibration or other trainable object is used before it
   --  was trained successfully (VisionPro: CogOperatorNotTrainedException).

   Ks_Transform_Singular_Exception : exception;
   --  A transform that has to be inverted is singular.

   Ks_Image_File_Exception : exception;
   --  An image file cannot be opened, read, written or decoded, or an
   --  image (or pixel region) read from a stream is malformed.

   Ks_Bad_Parameter_Exception : exception;
   --  A parameter value is outside its valid range or inconsistent with
   --  other parameters. It stands for .NET's System.ArgumentException,
   --  which VisionPro raises for a bad argument (VisionPro has no Cog
   --  exception of its own for this). An index beyond a collection raises
   --  Constraint_Error instead.

end AMV;
