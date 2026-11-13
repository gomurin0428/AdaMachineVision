--  The kernel record behind a Ks_Coordinate_Space_Tree, for the packages
--  of the Ada API that pass a tree to kernel entry points (AMV.Images
--  passes an image's tree to the ks_image_* entry points of
--  AMV.Kernels.Images) and for programs that mix the Ada API with the C
--  API. Not part of the VisionPro-like API.

pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with AMV.Kernels.Coordinate_Spaces;

package AMV.Coordinate_Spaces.Kernel_Trees is
   pragma Preelaborate;

   function View
     (Tree : Ks_Coordinate_Space_Tree)
      return not null access constant
        AMV.Kernels.Coordinate_Spaces.Ks_Coordinate_Space_Tree;
   --  The tree's kernel record (C: ks_coordinate_space_tree), for reading.
   --  Valid until Tree is next changed, assigned or finalized.

   function Variable_View
     (Tree : in out Ks_Coordinate_Space_Tree)
      return not null access
        AMV.Kernels.Coordinate_Spaces.Ks_Coordinate_Space_Tree;
   --  The same, for changing Tree through the kernel's entry points (which
   --  keep it valid). Valid until Tree is next assigned or finalized.

end AMV.Coordinate_Spaces.Kernel_Trees;
