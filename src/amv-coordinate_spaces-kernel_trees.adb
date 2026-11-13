pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

package body AMV.Coordinate_Spaces.Kernel_Trees is

   package K renames AMV.Kernels.Coordinate_Spaces;

   Root_Only : aliased constant K.Ks_Coordinate_Space_Tree := (others => <>);
   --  The value of every tree without a box (see the parent's private
   --  part).

   function View
     (Tree : Ks_Coordinate_Space_Tree)
      return not null access constant K.Ks_Coordinate_Space_Tree
   is
     (if Tree.Box = null then Root_Only'Access else Tree.Box);

   function Variable_View
     (Tree : in out Ks_Coordinate_Space_Tree)
      return not null access K.Ks_Coordinate_Space_Tree is
   begin
      if Tree.Box = null then
         Tree.Box := new K.Ks_Coordinate_Space_Tree'(Root_Only);
      end if;
      return Tree.Box;
   end Variable_View;

end AMV.Coordinate_Spaces.Kernel_Trees;
