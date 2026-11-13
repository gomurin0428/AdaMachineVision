--  A reference-counted holder of a kernel handle, for the Ada API
--  (docs/DESIGN.md 9.1 and 9.3).
--
--  The kernels never share a handle (plan A): every handle has one owner.
--  The Ada API keeps a handle it only reads (the results of a tool run, a
--  trained pattern that is replaced as a whole) in a Holder, so that
--  copies of the object holding it (a tool, a results object) share the
--  handle instead of duplicating it. The last holder to go frees the
--  handle with Destroy. Copies are safe across tasks (the counter is
--  atomic) as long as nobody changes the handle: a holder gives out the
--  handle for reading only.
--
--  Streams: a Holder writes nothing and reads back as an empty holder
--  (docs/DESIGN.md 7: the predefined attributes would copy the pointer).
--  A type that must keep its handle's data in a stream defines stream
--  attributes of its own that store the data by value.
--
--  Use: instantiate it with the kernel's handle type and a procedure that
--  frees a handle and sets it to Null_Handle:
--
--     procedure Destroy (Handle : in out KB.Ks_Blob_Results);
--     package Results_Holders is new AMV.Shared_Handles
--       (KB.Ks_Blob_Results, null, Destroy);

pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

private with Ada.Finalization;
private with Ada.Streams;

generic
   type Handle_Type is private;
   Null_Handle : Handle_Type;
   with procedure Destroy (Handle : in out Handle_Type);
   --  Frees Handle (nothing for Null_Handle) and sets it to Null_Handle.
   --  It must not raise.
package AMV.Shared_Handles is

   type Holder is private;
   --  Holds a handle or nothing (empty, the default).

   function Is_Empty (Item : Holder) return Boolean;
   --  True when Item holds no handle.

   function Get (Item : Holder) return Handle_Type;
   --  The handle Item holds (Null_Handle when it is empty). It stays valid
   --  as long as Item (or a copy of it) holds it. Read it only: do not
   --  destroy it, change it or store it elsewhere.

   procedure Set (Item : in out Holder; Handle : Handle_Type);
   --  Item takes Handle over (the caller must not use it to free or change
   --  it any more) and lets go of what it held before. Item becomes empty
   --  for Null_Handle. When the shared counter cannot be allocated, Handle
   --  is destroyed, Item is left empty and Storage_Error is raised.

   procedure Clear (Item : in out Holder);
   --  Item lets go of its handle and becomes empty.

private

   type Reference_Count is new Integer with Atomic;

   type Shared_Record is limited record
      References : aliased Reference_Count := 1;
      Handle     : Handle_Type;
   end record;

   type Shared_Access is access Shared_Record;

   type Holder is new Ada.Finalization.Controlled with record
      Shared : Shared_Access;
      --  Null when the holder is empty.
   end record;

   overriding procedure Adjust (Item : in out Holder);
   overriding procedure Finalize (Item : in out Holder);

   procedure Write_Holder
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : Holder);
   procedure Read_Holder
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Holder);

   for Holder'Write use Write_Holder;
   for Holder'Read use Read_Holder;

end AMV.Shared_Handles;
