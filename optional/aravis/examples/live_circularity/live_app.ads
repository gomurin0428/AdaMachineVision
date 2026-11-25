--  The live circularity window: connects to a GigE Vision camera through
--  AMV.GigE_Vision, shows its frames live and measures the circularity of
--  the largest object in each frame (Circularity_Measure).
package Live_App is

   procedure Run;
   --  Opens the window and returns when it is closed. A first command-line
   --  argument is taken as the camera's address and connected at once.

end Live_App;
