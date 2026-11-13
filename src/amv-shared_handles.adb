pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with Ada.Unchecked_Deallocation;
with System.Atomic_Operations.Integer_Arithmetic;

package body AMV.Shared_Handles is

   package Counters is new System.Atomic_Operations.Integer_Arithmetic
     (Atomic_Type => Reference_Count);

   procedure Free is new Ada.Unchecked_Deallocation
     (Shared_Record, Shared_Access);

   function Is_Empty (Item : Holder) return Boolean is
     (Item.Shared = null);

   function Get (Item : Holder) return Handle_Type is
     (if Item.Shared = null then Null_Handle else Item.Shared.Handle);

   procedure Set (Item : in out Holder; Handle : Handle_Type) is
      Owned : Handle_Type := Handle;
   begin
      Clear (Item);
      if Handle = Null_Handle then
         return;
      end if;
      Item.Shared := new Shared_Record;
      Item.Shared.Handle := Handle;
   exception
      when Storage_Error =>
         Destroy (Owned);
         raise;
   end Set;

   procedure Clear (Item : in out Holder) is
   begin
      Finalize (Item);
   end Clear;

   overriding procedure Adjust (Item : in out Holder) is
   begin
      if Item.Shared /= null then
         Counters.Atomic_Add (Item.Shared.References, 1);
      end if;
   end Adjust;

   overriding procedure Finalize (Item : in out Holder) is
      Shared : Shared_Access := Item.Shared;
   begin
      Item.Shared := null;
      if Shared /= null
        and then Counters.Atomic_Fetch_And_Subtract (Shared.References, 1)
                 = 1
      then
         Destroy (Shared.Handle);
         Free (Shared);
      end if;
   end Finalize;

   procedure Write_Holder
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : Holder)
   is
      pragma Unreferenced (Stream, Item);
   begin
      null;
   end Write_Holder;

   procedure Read_Holder
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Holder)
   is
      pragma Unreferenced (Stream);
   begin
      Clear (Item);
   end Read_Holder;

end AMV.Shared_Handles;
