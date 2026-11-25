pragma SPARK_Mode (Off);

package body AMV.Flow is

   function Type_Name (Value_Type : Ks_Flow_Value_Type) return String is
   begin
      case Value_Type is
         when Real_Type         => return "Real";
         when Integer_Type      => return "Integer";
         when Boolean_Type      => return "Boolean";
         when String_Type       => return "String";
         when Image_8_Grey_Type => return "Image_8_Grey";
         when Transform_Type    => return "Transform";
         when Shape_Type        => return "Shape";
      end case;
   end Type_Name;

   function Type_Of (Name : String) return Ks_Flow_Value_Type is
   begin
      for T in Ks_Flow_Value_Type loop
         if Type_Name (T) = Name then
            return T;
         end if;
      end loop;
      raise Ks_Flow_Exception with "unknown type """ & Name & """";
   end Type_Of;

   function Valid_Name (Name : String) return Boolean is
   begin
      if Name'Length = 0 or else Name'Length > Max_Name_Length then
         return False;
      end if;
      for C of Name loop
         if C = '.' or else C = '"' or else C = '\'
           or else Character'Pos (C) < 32 or else Character'Pos (C) = 127
         then
            return False;
         end if;
      end loop;
      return True;
   end Valid_Name;

end AMV.Flow;
