###############################################################################
##
## Short Empire flying boat for FlightGear.
## Walk view configuration.
##
##  Copyright (C) 2010  Anders Gidenstam  (anders(at)gidenstam.org)
##  This file is licensed under the GPL license v2 or later.
##
###############################################################################

# Constraints
var flightdeckConstraint =
    walkview.makeUnionConstraint(
        [
         # Right hand seat. Sit down when entering.
         walkview.actionConstraint.new
             (walkview.slopingYAlignedPlane.new([  2.3, 0.25, 1.15], 
                                                [  2.6, 0.70, 1.15]),
              func {
                  #print("Seated!");
                  walkview.active_walker().set_eye_height(0.82);
              },
              func(x, y) {
                  # Nothing.
              }),
         # Between the pilots.
         walkview.actionConstraint.new
             (walkview.slopingYAlignedPlane.new([  2.1, -0.25, 0.90], 
                                                [  2.9,  0.25, 0.90]),
              func {
                  #print("Crouching!");
                  walkview.active_walker().set_eye_height(1.30);
              },
              func(x, y) {
                  # Nothing.
              }),
         # Forward flight-deck area.
         walkview.actionConstraint.new
             (walkview.slopingYAlignedPlane.new([  2.9,  0.0, 1.10], 
                                                [  5.0,  0.4, 1.10]),
              func {
                  #print("Crouching!");
                  walkview.active_walker().set_eye_height(1.30);
              },
              func(x, y) {
                  # Nothing.
              }),
         # Astro-hatch area.
         walkview.actionConstraint.new
             (walkview.slopingYAlignedPlane.new([  3.00,  0.25, 1.10], 
                                                [  3.20,  0.50, 1.10]),
              func {
                  #print("Standing!");
                  if (ShortEmpire.astro_hatch.getpos() == 1.0) {
                      walkview.active_walker().set_eye_height(1.70);
                  }
              },
              func(x, y) {
                  # Nothing.
              }),
         # Aft flight-deck area.
         walkview.actionConstraint.new
             (walkview.makeUnionConstraint(
                  [
                   # Aft flight-deck area.
                   walkview.slopingYAlignedPlane.new([  5.0,  0.0, 1.10],
                                                     [  7.9,  0.4, 1.10]),
                   # Mail storage area.
                   walkview.slopingYAlignedPlane.new([  5.0, -0.4, 1.10],
                                                     [  8.0, -0.2, 1.10]),
                   # Doorway.
                   walkview.slopingYAlignedPlane.new([  6.2, -0.2, 1.10],
                                                     [  6.9,  0.0, 1.10])
                  ]),
              func {
                  #print("Standing!");
                  walkview.active_walker().set_eye_height(1.70);
              },
              func(x, y) {
                  # Nothing.
              })
        ]);

# Create the view manager.
var copilot_walker =
    walkview.walker.new("Copilot View",
                        flightdeckConstraint,
                        [walkview.JSBSimPointmass.new(1)]);

