pragma SPARK_Mode (Off);

--  Node kinds that make one image from another with AMV's image
--  processing tools. Each Create function returns a new node of its kind
--  (AMV.Flow.Kinds lists them by name).
--
--  PolarUnwrap (AMV.Image_Processing.Polar_Unwrap)
--     in   Image : Image_8_Grey
--     out  Image : Image_8_Grey (the annulus unwrapped: x along the angle
--          from AngleStart, y along the radius from Radius to Radius *
--          RadialScale)
--     params  Region (a CircularAnnulusSection in the image's selected
--             space: to follow a part, put a Fixture before it, fed by
--             the Pose of ShapeMatch or Circularity, and give the region
--             in the part's space)
--     The annulus must lie inside the image (else Error): leave out the
--     part of a circle that the image cuts with AngleStart and AngleSpan.
--     A new node's region is a full annulus about (100, 100), radii 50 to
--     90, to be dragged into place in the editor.
--
--  Morphology (AMV.Image_Processing.IP_One_Image, Grey_Morphology_NxM)
--     in   Image : Image_8_Grey
--     out  Image : Image_8_Grey
--     params  Operation (Erode | Dilate | Open | Close | DilateMinusErode
--             | CloseMinusOriginal | OriginalMinusOpen), KernelWidth,
--             KernelHeight (odd, 1 .. 1001: the flat rectangle the
--             operation uses)
--     CloseMinusOriginal makes dark features narrower than the kernel
--     light on black (a cut, a scratch, a crack: then Blob finds them);
--     OriginalMinusOpen does the same for light features.

package AMV.Flow.Nodes.Imaging is

   function Create_Polar_Unwrap return Node_Access;
   function Create_Morphology return Node_Access;

end AMV.Flow.Nodes.Imaging;
