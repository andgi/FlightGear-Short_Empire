###############################################################################
##
## Short S.23 'C'-class Empire flying boat
##
##  Copyright (C) 2008 - 2014  Anders Gidenstam  (anders(at)gidenstam.org)
##  This file is licensed under the GPL license v2 or later.
##
###############################################################################

###############################################################################

var astro_hatch = aircraft.door.new("sim/model/doors/astro-hatch", 10.0);

###############################################################################
var ground = func {
    # Send the current ground level to the JSBSim hydrodynamics model.
    setprop("/fdm/jsbsim/hydro/environment/water-level-ft",
            getprop("/position/ground-elev-ft") +
            getprop("/fdm/jsbsim/hydro/environment/wave-amplitude-ft"));

    # Connect the FlightGear wave model to the JSBSim hydrodynamics wave model.
    #setprop("/fdm/jsbsim/hydro/environment/waves-from-deg",
    #        getprop("/environment/wave/angle") - 90.0);
    #setprop("/fdm/jsbsim/hydro/environment/wave-amplitude-ft",
    #        getprop("/environment/wave/amp"));
    # Additional properties:
    #   /environment/wave/dangle
    #   /environment/wave/factor
    #   /environment/wave/freq
    #   /environment/wave/sharp

    # Connect the JSBSim hydrodynamics wave model with the custom water shader.
    setprop("environment/waves/time-sec",
            getprop("/fdm/jsbsim/simulation/sim-time-sec"));
    setprop("environment/waves/from-deg",
            getprop("/fdm/jsbsim/hydro/environment/waves-from-deg"));
    setprop("environment/waves/length-ft",
            getprop("/fdm/jsbsim/hydro/environment/wave-length-ft"));
    setprop("environment/waves/amplitude-ft",
            getprop("/fdm/jsbsim/hydro/environment/wave-amplitude-ft"));
    setprop("environment/waves/angular-frequency-rad_sec",
            getprop("/fdm/jsbsim/hydro/environment/wave/angular-frequency-rad_sec"));
    setprop("environment/waves/wave-number-rad_ft",
            getprop("/fdm/jsbsim/hydro/environment/wave/wave-number-rad_ft"));

    # Temporary and ugly starter handling.
    setprop("/controls/engines/engine[0]/starter",
            getprop("/fdm/jsbsim/propulsion/engine[0]/starter-norm"));
    setprop("/controls/engines/engine[1]/starter",
            getprop("/fdm/jsbsim/propulsion/engine[1]/starter-norm"));
    setprop("/controls/engines/engine[2]/starter",
            getprop("/fdm/jsbsim/propulsion/engine[2]/starter-norm"));
    setprop("/controls/engines/engine[3]/starter",
            getprop("/fdm/jsbsim/propulsion/engine[3]/starter-norm"));

    settimer(ground, 0.0);
}

# Do terrain modelling ourselves.
setprop("sim/fdm/surface/override-level", 1);

var _short_empire_initialized = 0;
setlistener("/sim/signals/fdm-initialized", func {
    if (_short_empire_initialized) return;
    aircraft.livery.init("Aircraft/Short_Empire/Models/Liveries");

    settimer(ground, 0.0);
    print("Hydrodynamics initialized.");
    copilot.init();
    _short_empire_initialized = 1;
});



###############################################################################
# Control wrappers overrides.

# Make n/N set propeller pitch to FINE or COARSE. 
controls.adjPropeller = func (d) {
    controls.adjEngControl("propeller-pitch", (d > 0 ? 10000.0 : -10000.0));
}

var flap_control_p = "controls/flight/flap-motor";

# The flap control is moves the control switch towards in or out.
controls.flapsDown = func(step) {
    if (!step) return;
    var v = getprop(flap_control_p);
    if (step < 0) v -= 1;
    if (step > 0) v += 1;
    if (v < -1) v = -1;
    if (v > 1)  v = 1;
    setprop(flap_control_p, v);
}

controls.startEngine = func(v = 1, which...) {
    if (!v and !size(which))
        return props.setAll("/controls/engines/engine", "starter-cmd", 0);
    if(size(which)) {
        foreach(var i; which)
            foreach(var e; controls.engines)
                if(e.index == i)
                    e.controls.getNode("starter-cmd").setBoolValue(v);
    } else {
        foreach(var e; controls.engines)
            if(e.selected.getValue())
                e.controls.getNode("starter-cmd").setBoolValue(v);
    }
}

###############################################################################
# Debug display - stand in instrumentation.
var debug_display_view_handler = {
    init : func {
        if (contains(me, "left")) return;

        me.left  = screen.display.new(20, 10);
        me.right = screen.display.new(-200, 10);
        me.left.format  = "%.5g";
        me.right.format = "%.5g";
        me.left.add("/orientation/pitch-deg");
        me.left.add("/fdm/jsbsim/hydro/beta-deg");
        #me.left.add("/fdm/jsbsim/hydro/left-float-submersion-ft");
        #me.left.add("/fdm/jsbsim/hydro/right-float-submersion-ft");
        #me.left.add("/fdm/jsbsim/hydro/coefficients/C_V");
        #me.left.add("/fdm/jsbsim/hydro/coefficients/C_Delta");
        #me.left.add("/fdm/jsbsim/hydro/coefficients/C_R");
        #me.left.add("/fdm/jsbsim/hydro/coefficients/C_M");
        me.left.add("/fdm/jsbsim/inertia/cg-x-in");

        me.left.add("/fdm/jsbsim/electrical/bus[0]/voltage-V");
        me.left.add("/fdm/jsbsim/electrical/bus[0]/current-A");
        me.left.add("/fdm/jsbsim/electrical/bus[1]/voltage-V");
        me.left.add("/fdm/jsbsim/electrical/bus[1]/current-A");
        me.left.add("/fdm/jsbsim/electrical/battery/total-current-A");
        me.left.add("/fdm/jsbsim/electrical/voltage-regulators/current-A[0]");
        me.left.add("/fdm/jsbsim/electrical/voltage-regulators/current-A[1]");

        me.right.add("/fdm/jsbsim/propulsion/engine[0]/boost-psi");
        me.right.add("/fdm/jsbsim/propulsion/engine[1]/boost-psi");
        me.right.add("/fdm/jsbsim/propulsion/engine[2]/boost-psi");
        me.right.add("/fdm/jsbsim/propulsion/engine[3]/boost-psi");
        me.right.add("/engines/engine[0]/rpm");
        me.right.add("/engines/engine[1]/rpm");
        me.right.add("/engines/engine[2]/rpm");
        me.right.add("/engines/engine[3]/rpm");
        me.right.add("/fdm/jsbsim/propulsion/engine[0]/power-hp");
        me.right.add("/fdm/jsbsim/propulsion/engine[1]/power-hp");
        me.right.add("/fdm/jsbsim/propulsion/engine[2]/power-hp");
        me.right.add("/fdm/jsbsim/propulsion/engine[3]/power-hp");
        me.right.add("/fdm/jsbsim/propulsion/engine[0]/egt-degF");
        me.right.add("/fdm/jsbsim/propulsion/engine[1]/egt-degF");
        me.right.add("/fdm/jsbsim/propulsion/engine[2]/egt-degF");
        me.right.add("/fdm/jsbsim/propulsion/engine[3]/egt-degF");
        me.right.add("/fdm/jsbsim/fcs/fuel-system/debug/consumption-error-lbs");
        me.shown = 1;
        me.stop();
    },
    start  : func {
        if (!me.shown) {
            me.left.toggle();
            me.right.toggle();
        }
        me.shown = 1;
    },
    stop   : func {
        if (me.shown) {
            me.left.toggle();
            me.right.toggle();
        }
        me.shown = 0;
    }
};

# Install the debug display for some views.
setlistener("/sim/signals/fdm-initialized", func {
    view.manager.register(0, debug_display_view_handler);
    # Do not install it for the copilot as that will override the
    # WalkView view manager.
    #view.manager.register("Copilot View", debug_display_view_handler);
    print("Debug instrumentation ... check");
});

###########################################################################
## Helpful crew announcements by autonomous singleton class.
var copilot = {
    init : func {
        me.UPDATE_INTERVAL = 1.73;
        me.loopid = 0;
        # Landing callouts        
        me.alt_agl_prop =
            props.globals.getNode("fdm/jsbsim/hydro/height-agl-ft");
        me.ground_contact_prop =
            props.globals.getNode("fdm/jsbsim/hydro/coefficients/C_Delta");
        me.alt_agl        = me.alt_agl_prop.getValue();
        me.ground_contact = me.ground_contact_prop.getValue() > 0;
        # Engine monitoring
        me.rpm_prop  = {};
        me.rpm_limit = 2600;
        foreach (var i; [0, 1, 2, 3]) {
            me.rpm_prop[i] =
                props.globals.getNode("/engines/engine[" ~ i ~ "]/rpm");
        }

        me.reset();
        print("Short Empire Crew ... Present and accounted for.");
    },
    update : func {
        # Landing callouts
        var on_ground = me.ground_contact_prop.getValue() > 0;
        if (!me.ground_contact and on_ground) {
            me.announce("Water contact!");
        } elsif (me.ground_contact and !on_ground) {
            me.announce("Lift off!");
        }
        me.ground_contact = on_ground;
        var alt = me.alt_agl_prop.getValue();
        if (!on_ground) {
            for (var i = 5; i <= 100; i += 5) {
                if (alt < i and me.alt_agl > i) {
                    me.announce(i ~ " feet");
                    break;
                }
            }
        }
        me.alt_agl = alt;

        # RPM check.
        var trouble = 0;
        foreach (var i; keys(me.rpm_prop)) {
            if (me.rpm_prop[i].getValue() > me.rpm_limit) {
                trouble = 1;
            }
        }
        if (trouble) {
            me.announce("Engine RPM");
        }
    },
    announce : func(msg) {
        setprop("/sim/messages/copilot", msg);
    },
    reset : func {
        me.loopid += 1;
        me._loop_(me.loopid);
    },
    _loop_ : func(id) {
        id == me.loopid or return;
        me.update();
        settimer(func { me._loop_(id); }, me.UPDATE_INTERVAL);
    }
};

###############################################################################
# About dialog.

var ABOUT_DLG = 0;

var dialog = {
#################################################################
    init : func (x = nil, y = nil) {
        me.x = x;
        me.y = y;
        me.bg = [0, 0, 0, 0.3];    # background color
        me.fg = [[1.0, 1.0, 1.0, 1.0]]; 
        #
        # "private"
        me.title = "About";
        me.dialog = nil;
        me.namenode = props.Node.new({"dialog-name" : me.title });
    },
#################################################################
    create : func {
        if (me.dialog != nil)
            me.close();

        me.dialog = gui.Widget.new();
        me.dialog.set("name", me.title);
        if (me.x != nil)
            me.dialog.set("x", me.x);
        if (me.y != nil)
            me.dialog.set("y", me.y);

        me.dialog.set("layout", "vbox");
        me.dialog.set("default-padding", 0);

        var titlebar = me.dialog.addChild("group");
        titlebar.set("layout", "hbox");
        titlebar.addChild("empty").set("stretch", 1);
        titlebar.addChild("text").set
            ("label",
             "About");
        var w = titlebar.addChild("button");
        w.set("pref-width", 16);
        w.set("pref-height", 16);
        w.set("legend", "");
        w.set("default", 0);
        w.set("key", "esc");
        w.setBinding("nasal", "ShortEmpire.dialog.destroy(); ");
        w.setBinding("dialog-close");
        me.dialog.addChild("hrule");

        var content = me.dialog.addChild("group");
        content.set("layout", "vbox");
        content.set("halign", "center");
        content.set("default-padding", 5);
        props.globals.initNode("sim/about/text",
             "Short S.23 'C'-class Empire flying boat for FlightGear\n" ~
             "Copyright (C) 2008 - 2014  Anders Gidenstam, Ron Jensen, AJ MacLeod\n\n" ~
             "FlightGear flight simulator\n" ~
             "Copyright (C) 1996 - 2014  http://www.flightgear.org\n\n" ~
             "This is free software, and you are welcome to\n" ~
             "redistribute it under certain conditions.\n" ~
             "See the GNU GENERAL PUBLIC LICENSE Version 2 for the details.",
             "STRING");
        var text = content.addChild("textbox");
        text.set("halign", "fill");
        #text.set("slider", 20);
        text.set("pref-width", 400);
        text.set("pref-height", 300);
        text.set("editable", 0);
        text.set("property", "sim/about/text");

        #me.dialog.addChild("hrule");

        fgcommand("dialog-new", me.dialog.prop());
        fgcommand("dialog-show", me.namenode);
    },
#################################################################
    close : func {
        fgcommand("dialog-close", me.namenode);
    },
#################################################################
    destroy : func {
        ABOUT_DLG = 0;
        me.close();
        delete(gui.dialog, "\"" ~ me.title ~ "\"");
    },
#################################################################
    show : func {
        if (!ABOUT_DLG) {
            ABOUT_DLG = 1;
            me.init(400, getprop("/sim/startup/ysize") - 500);
            me.create();
        }
    }
};
###############################################################################

# Popup the about dialog.
var about = func {
    dialog.show();
}
