pragma SPARK_Mode (Off);

with AMV.Flow.Nodes;

--  The node kinds by name: the built-in ones (AMV.Flow.Nodes.Vision and
--  AMV.Flow.Nodes.Logic) and any added with Register.

package AMV.Flow.Kinds is

   type Constructor is access function return AMV.Flow.Nodes.Node_Access;

   procedure Register (Kind_Id : String; Make : not null Constructor);
   --  Adds a kind (Ks_Flow_Exception for a name already taken or not a
   --  valid name).

   function Count return Natural;
   function Kind_Id (Index : Positive) return String;
   --  The kinds, built-in ones first, in the order they were added.

   function Exists (Kind_Id : String) return Boolean;

   function Create (Kind_Id : String) return AMV.Flow.Nodes.Node_Access;
   --  A new node of the kind; Ks_Flow_Exception for an unknown kind.

end AMV.Flow.Kinds;
