###############################################################################
##
## Short S.23 'C'-class Empire flying boat
##
##  Copyright (C) 2010  Anders Gidenstam  (anders(at)gidenstam.org)
##  This file is licensed under the GPL license v2 or later.
##
###############################################################################

###########################################################################
## Initialization and reset.

var init = func(reinit=0) {
    mooring.init(reinit);
    if (getprop("/sim/presets/onground")) {
        settimer(func {
            # Set up an initial mooring location.
            mooring.add_fixed_mooring(geo.aircraft_position(), 0.0);
        }, 0.4);
        # We need the FDM to run in between.
        settimer(func {
            mooring.pick_up_mooring();

            # Add the predefined moorings.
            foreach (var m; EAMS_MOORINGS_EUROPE ~
                            EAMS_MOORINGS_EAST ~
                            EAMS_MOORINGS_SOUTH ~
                            BERMUDA_NEWYORK ~
                            TEAL) {
                var pos = geo.Coord.new().set_latlon(m[1], m[2]);
                mooring.add_fixed_mooring(pos, 0.0, m[0]);
            }
        }, 0.5);
    }

    # Enable Alt+Click to place the mooring mast
    if (!reinit) {
        setlistener("/sim/signals/click", func {
            var click_pos = geo.click_position();
            if (__kbd.alt.getBoolValue()) {
                mooring.add_fixed_mooring(click_pos, 0.0);
            }
        });
    }
}

setlistener("/sim/signals/fdm-initialized", func {
    init();
    setlistener("/sim/signals/reinit", func(reinit) {
        if (!reinit.getValue()) {
            init(reinit=1);
        }
    });
});

###########################################################################
## Mooring location support.
var mooring = {
    ##################################################
    init : func(reinit) {
        me.UPDATE_INTERVAL = 0.0;
        me.MP_ANNOUNCE_INTERVAL = 60.0;
        me.loopid = 0;
        me.last_mp_announce = systime(); 
        ## Hash containing all supported mooring locations.
        ## Format:
        ##   Fixed {position : <coord>, alt_offset : <m>}
        ##   AI    {base : <node>, alt_offset : <m>}
        me.moorings = {};
        me.active_mooring = props.globals.getNode("/fdm/jsbsim/mooring");
        me.model = {local : nil};
        me.selected = "";
        me.reset();
        print("Short Empire Mooring ... Standing by.");
    },
    ##################################################
    add_fixed_mooring : func(pos, alt_offset, name="local") {
        me.moorings[name] = { position   : pos,
                              alt_offset : alt_offset };
        me.display_mooring(name);
        if (name == "local") {
            #announce_fixed_mooring(pos, alt_offset);
        }
    },
    ##################################################
    display_mooring : func(name) {
        if (!contains(me.moorings[name], "position")) return;
        var geo_info = geodinfo(me.moorings[name].position.lat(),
                                me.moorings[name].position.lon());
        if (geo_info == nil) return;
        me.moorings[name].position.set_alt(geo_info[0]);
        # Put a mooring buoy model here. Note the model specific offset.
        if (me.model[name] != nil) me.model[name].remove();
        me.model[name] =
            geo.put_model("Aircraft/Short_Empire/Models/Moorings/buoy.xml",
                          me.moorings[name].position);
    },
    ##################################################
    remove_fixed_mooring : func(name) {
        if (me.model[name] != nil) me.model[name].remove();
        delete(me.moorings, name);
    },
    ##################################################
    add_ai_mooring : func(ai, alt_offset) {
        if (ai == nil) return;
        var name = ai.getNode("callsign").getValue();
        if (name == "") { name = ai.getNode("name").getValue(); }
        me.moorings[name] = { base       : ai,
                              alt_offset : alt_offset };
    },
    ##################################################
    remove_ai_mooring : func(ai) {
        if (ai == nil) return;
        foreach (var name; keys(me.moorings)) {
            if (contains(me.moorings[name], "base") and
                me.moorings[name].base == ai) {
                delete(me.moorings, name);
                return;
            }
        }
    },
    ##################################################
    pick_up_mooring : func {
        if (me.active_mooring.getNode("mooring-connected").getBoolValue())
            return;
        var dist = me.active_mooring.getNode("total-distance-ft").getValue();
        var rope_length =
            me.active_mooring.getNode("rope-length-ft").getValue();
        if (dist < rope_length/FT2M) {
            me.active_mooring.getNode("mooring-connected").setValue(1.0);
            copilot.announce("We picked up the mooring.");
        } else {
            copilot.announce("We are too far from the buoy.");
        }
    },
    ##################################################
    release_mooring : func {
        if (me.active_mooring.getNode("mooring-connected").getValue() >= 1.0) {
            me.active_mooring.getNode("mooring-connected").setValue(0.0);
            copilot.announce("Mooring slipped.");
        }
    },
    ##################################################
    update : func {
        var ac_pos = geo.aircraft_position();
        
        # Compute distance to the current mooring.
        var distance = 1000000;
        var cur_pos  = geo.Coord.new();
        var cur_name = me.selected;
        if (contains(me.moorings, me.selected)) {
            if (contains(me.moorings[me.selected], "position")) {
                cur_pos = geo.Coord.new(me.moorings[me.selected].position);
            } else {
                var ai = me.moorings[me.selected].base;
                cur_pos = geo.Coord.new().set_latlon
                    (ai.getNode("position/latitude-deg").getValue(),
                     ai.getNode("position/longitude-deg").getValue(),
                     FT2M * ai.getNode("position/altitude-ft").getValue());
            }
            distance = cur_pos.distance_to(ac_pos);
        }

        # Break connection if too far way.
        var rope_length =
            me.active_mooring.getNode("rope-length-ft").getValue();
        if (distance > 2.0 * rope_length and
            me.active_mooring.getNode("mooring-connected").getBoolValue()) {
            me.release_mooring();
        }

        # Find the closest mooring position.
        foreach (var name; keys(me.moorings)) {
            var pos = {};
            if (contains(me.moorings[name], "position")) {
                pos = me.moorings[name].position;
            } else {
                var ai = me.moorings[name].base;
                pos = geo.Coord.new().set_latlon
                    (ai.getNode("position/latitude-deg").getValue(),
                     ai.getNode("position/longitude-deg").getValue(),
                     FT2M * ai.getNode("position/altitude-ft").getValue());
            }
            if (pos.direct_distance_to(ac_pos) < distance) {
                cur_name  = name;
                cur_pos   = geo.Coord.new(pos);
                distance  = pos.distance_to(ac_pos);
            }
        }

        if (cur_pos.is_defined()) {
            if (cur_name != me.selected) {
                print("Short Empire Mooring: Switched mooring to " ~
                      cur_name ~ ".");
                me.selected = cur_name;
                me.display_mooring(cur_name);
            }

             # The position might be new, so update active mooring.
            me.active_mooring.getNode("latitude-deg").setValue(cur_pos.lat());
            me.active_mooring.getNode("longitude-deg").setValue(cur_pos.lon());
            # First check if the offset is fixed or a AI/MP property.
            var offset = 0;
            if (dual_control_tools.is_num(me.moorings[name].alt_offset)) {
                offset = me.moorings[name].alt_offset;
            } else {
                offset =
                    me.moorings[name].base.
                    getNode(me.moorings[name].alt_offset).getValue();
            }
            me.active_mooring.getNode("altitude-ft").
                setValue(M2FT * (cur_pos.alt() + offset));
        }

        # Announce local mooring mast.
        var now = systime();
        if (now > me.last_mp_announce + me.MP_ANNOUNCE_INTERVAL) {
            #announce_fixed_mooring(me.moorings["local"].position,
            #                       me.moorings["local"].alt_offset);
            me.last_mp_announce = now;
        }
    },
    ##################################################
    reset : func {
        me.loopid += 1;
        me._loop_(me.loopid);
    },
    ##################################################
    _loop_ : func(id) {
        id == me.loopid or return;
        me.update();
        settimer(func { me._loop_(id); }, me.UPDATE_INTERVAL);
    }
};

###############################################################################
## Hash containing EAMS mooring locations. See also ROUTES.txt.
## Format:
##   [[name, lat, lon]]
var EAMS_MOORINGS_EUROPE =
    [
     ["Hythe 1",               50.872210,   -1.390830],
     ["Hythe 2",               50.872349,   -1.387512],
     ["Bordeaux/Biscarosse",   44.383172,   -1.184227],
     ["Marseille/Marignane",   43.446937,    5.185410],
     ["Rome/Lake Bracciano",   42.113768,   12.187239],
     ["Brindisi",              40.651017,   17.961636],
     ["Corfu",                 39.614731,   19.929714],
     ["Athens/Phaleron Bay",   37.939527,   23.666230],
     ["Heraklion",             35.344386,   25.140345],
     ["Mirabella Bay",         35.200427,   25.723003],
     ["Alexandria",            31.206525,   29.893992]
    ];
var EAMS_MOORINGS_EAST =
    [
     ["Tiberias",              32.804203,   35.545287],
     ["Lake Habbaniyeh",       33.34625,    43.547359],
     ["Basra/Margil",          30.5203,     47.8455],
     ["Kuwait",                29.354583,   47.934932],
     ["Bahrein",               26.201731,   50.695789],
     ["Sharjah",               25.376378,   55.388442],
     ["Jiwani",                25.053374,   61.73589],
     ["Karachi",               24.836513,   67.003797],
     ["Raj Samand",            25.062578,   73.896269],
     ["Gwalior",               26.213821,   77.99263],
     ["Jhansi/Parichha Reservoir", 25.505293,78.755804],
     ["Allahabad",             25.427375,   81.86501],
     ["Calcutta",              22.588625,   88.347534],
     ["Akyab (Sittwe)",        20.138218,   92.902762],
     ["Rangoon (Yangon)",      16.733619,   96.209164],
     ["Bangkok",               13.657976,  100.550448],
     ["Ko Samu (Ko Samui)",     9.5633,    100.054464],
     ["Penang (Pinang)",        5.418251,  100.347887],
     ["Sinagpore/Kallang",      1.302283,  103.870003],
     ["Batavia (Jakarta)",     -6.118777,  106.835255],
     ["Sourabaya (Surabaya)",  -7.18759,   112.733803],
     ["Bima",                  -8.450368,  118.713026],
     ["Koepang (Kupang)",     -10.152625,  123.587474],
     ["Darwin",               -12.473265,  130.846809],
     ["Groote",               -13.953581,  136.411035],
     ["Karumba",              -17.472431,  140.834674],
     ["Townsville",           -19.248107,  146.826745],
     ["Gladstone",            -23.828888,  151.252084],
     ["Brisbane",             -27.427547,  153.128225],
     ["Sydney/Rose Bay",      -33.868387,  151.263121]
    ];
var EAMS_MOORINGS_SOUTH =
    [
     ["Luxor",                 25.7011,     32.6365],
     ["Wadi Halfa",            21.970768,   31.305134],
     ["Khartoum",              15.615081,   32.537642],
     ["Kosti",                 13.185674,   32.665529],
     ["Malakal",                9.5281,     31.6483],
     ["Bor",                    6.225406,   31.539752],
     ["Juba",                   4.834845,   31.617494],
     ["Laropi",                 3.54863,    31.812716],
     ["Butabia",                1.829127,   31.329403],
     ["Kampala/Port Bell",      0.287703,   32.652279],
     ["Kisumu",                -0.0901,     34.7481],
     ["Nairobi/Lake Naivasha", -0.7806,     36.4002],
     ["Mombasa",               -4.0524,     39.6799],
     ["Dar-es-Salaam",         -6.8222,     39.2922],
     ["Lindi",                -10.001025,   39.721466],
     ["Mozambique",           -15.038182,   40.704099],
     ["Beira",                -19.8265,     34.8316],
     # - Lourenco Morques, ?
     ["Durban",               -29.8727,     31.0325]
    ];
var BERMUDA_NEWYORK =
    [
     ["New York/Port Washington", 40.832081, -73.719479],
     ["Bermuda/Darrel's Island",  32.273495, -64.81824]
    ];
var TEAL =
    [
     ["Auckland/Mechanics Bay",  -36.8440,   174.7942],
     ["Wellington/Evans Bay",    -41.3142,   174.8065]
    ];
