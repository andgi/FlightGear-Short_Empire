###############################################################################
##
## Short S.23 'C'-class Empire flying boat
##
##  Copyright (C) 2010 - 2012  Anders Gidenstam  (anders(at)gidenstam.org)
##  This file is licensed under the GPL license v2 or later.
##
###############################################################################

###########################################################################
## Initialization and reset.

var init = func(reinit=0) {
    mooring.init(reinit);
    if (getprop("/sim/presets/onground")) {
        settimer(func {
            if (!mooring.pick_up_mooring()) {
                # No mooring available, set up a local mooring.
                mooring.add_fixed_mooring(geo.aircraft_position(), 0.0);
            }
            # We need the FDM to run in between.
            settimer(func {
                mooring.pick_up_mooring();
            }, 0.5);
        }, 0.4);
    }

    if (!reinit) {
        # Add the predefined moorings.
        foreach (var m; EAMS_MOORINGS_EUROPE ~
                 EAMS_MOORINGS_EAST ~
                 EAMS_MOORINGS_SOUTH ~
                 NORTH_ATLANTIC ~
                 TEAL) {
            var pos = geo.Coord.new().set_latlon(m[1], m[2]);
            mooring.add_fixed_mooring(pos, 0.0, m[0]);
        }


        # Enable Alt+Click to place the mooring
        setlistener("/sim/signals/click", func {
            var click_pos = geo.click_position();
            if (__kbd.alt.getBoolValue()) {
                mooring.add_fixed_mooring(click_pos, 0.0);
            }
        });
    }
}

var _mooring_initialized = 0;
setlistener("/sim/signals/fdm-initialized", func {
    init(_mooring_initialized);
    _mooring_initialized = 1;
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
        if (!reinit) {
            me.moorings = {};
            me.mooring_model  = {local : nil};
            me.fairway_model  = {local : nil};

            me.mooring_model_path =
                me.find_model_path("Short_Empire/Models/Moorings/buoy.xml");
            me.fairway_model_path =
                me.find_model_path("Short_Empire/Models/Moorings/flare_path.xml");
        }
        me.active_mooring = props.globals.getNode("/fdm/jsbsim/mooring");
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
        # Put a mooring buoy model here.
        if (me.mooring_model[name] != nil) me.mooring_model[name].remove();
        me.mooring_model[name] =
            geo.put_model(me.mooring_model_path,
                          me.moorings[name].position);
        # Display the associated fairway, if any.
        if (FAIRWAY[name] != nil) {
            if (me.fairway_model[name] != nil) me.fairway_model[name].remove();
            if (FAIRWAY[name][3] == 0.0) {
                me.fairway_model[name] =
                    geo.put_model
                    (me.fairway_model_path,
                     FAIRWAY[name][1], FAIRWAY[name][2],
                     nil,
                     -getprop("/environment/wind-from-heading-deg"));
            } else {
                me.fairway_model[name] =
                    geo.put_model
                    (me.fairway_model_path,
                     FAIRWAY[name][1], FAIRWAY[name][2],
                     nil,
                     FAIRWAY[name][3]);                
            }
        }
    },
    ##################################################
    remove_fixed_mooring : func(name) {
        if (me.mooring_model[name] != nil) me.mooring_model[name].remove();
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
            setprop("controls/lighting/anchor-light", 1.0);
            copilot.announce("We picked up the mooring.");
            return 1;
        } else {
            copilot.announce("We are too far from the buoy.");
            return 0;
        }
    },
    ##################################################
    release_mooring : func {
        if (me.active_mooring.getNode("mooring-connected").getValue() >= 1.0) {
            me.active_mooring.getNode("mooring-connected").setValue(0.0);
            setprop("controls/lighting/anchor-light", 0.0);
            copilot.announce("Mooring slipped.");
        }
    },
    ##################################################
    # filename should include the aircraft's directory.
    find_model_path : func (filename) {
        # FIXME WORKAROUND: Search for the model in all aircraft dirs.
        var base = "/" ~ filename;
        var file = props.globals.getNode("/sim/fg-root").getValue() ~
            "/Aircraft" ~ base;
        if (io.stat(file) != nil) {
            return file;
        }
        foreach (var d;
                 props.globals.getNode("/sim").getChildren("fg-aircraft")) {
            file = d.getValue() ~ base;
            if (io.stat(file) != nil) {
                return file;
            }
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

        # Announce local mooring.
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
## Lists containing EAMS mooring locations. See also ROUTES.txt.
## Format:
##   [[name, lat, lon]]
var EAMS_MOORINGS_EUROPE =
    [
     ["Hythe 1",                 50.872210,   -1.390830],
     ["Hythe 2",                 50.872349,   -1.387512],
     ["Saint-Nazaire",           47.297423,   -2.134309],
     ["Bordeaux/Biscarosse",     44.383172,   -1.184227],
     ["Macon",                   46.290932,    4.830000],
     ["Marseille/Marignane",     43.446937,    5.185410],
     ["Rome/Lake Bracciano",     42.113768,   12.187239],
     ["Brindisi",                40.652277,   17.959625],
     ["Corfu",                   39.614731,   19.929714],
     ["Athens/Phaleron Bay",     37.939527,   23.666230],
     ["Heraklion",               35.344386,   25.140345],
     ["Mirabella Bay",           35.200427,   25.723003],
     ["Alexandria/East Harbour", 31.196233,   29.872788]
    ];
var EAMS_MOORINGS_EAST =
    [
     ["Tiberias",              32.804,      35.547],
     ["Lake Habbaniyeh",       33.34625,    43.547359],
     ["Basra/Margil",          30.5203,     47.8455],
     ["Kuwait",                29.354583,   47.934932],
     ["Bahrein",               26.240,      50.623],
     ["Dubai",                 25.237,      55.325],
     ["Jiwani",                25.053,      61.723],
     ["Karachi",               24.780,      67.138],
     ["Raj Samand",            25.071,      73.888],
     ["Lake Udaipur",          24.574,      73.680],
     ["Gwalior",               26.214,      77.994],
     ["Jhansi/Parichha Reservoir", 25.505293,78.755804],
     ["Allahabad",             25.425375,   81.86501],
     ["Calcutta",              22.588625,   88.353534],
     ["Akyab (Sittwe)",        20.139,      92.908],
     ["Rangoon (Yangon)",      16.733619,   96.209164],
     ["Bangkok",               13.657976,  100.550448],
     ["Ko Samu (Ko Samui)",     9.5633,    100.054464],
     ["Penang (Pinang)",        5.415,     100.350],
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
     ["Cairo",                 30.0327,     31.222],
     ["Luxor",                 25.7011,     32.6365],
     ["Wadi Halfa",            21.805,      31.300],
     ["Khartoum",              15.606,      32.537],
     ["Kosti",                 13.169,      32.665],
     ["Malakal",                9.528,      31.652],
     ["Bor",                    6.220,      31.543],
     ["Juba",                   4.834,      31.614],
     ["Laropi",                 3.54863,    31.812716],
     ["Butabia",                1.829127,   31.329403],
     ["Kampala/Port Bell",      0.287703,   32.652279],
     ["Kisumu",                -0.090,      34.744],
     ["Nairobi/Lake Naivasha", -0.7806,     36.4002],
     ["Mombasa",               -4.0524,     39.6799],
     ["Dar-es-Salaam",         -6.820,      39.292],
     ["Lindi",                -10.001025,   39.721466],
     ["Mozambique",           -15.038182,   40.704099],
     ["Beira",                -19.826,      34.829],
     ["Inhambane",            -23.8687,     35.3722],
     ["Lourenco Morques",     -25.9689,     32.5376],
     ["Durban",               -29.870,      31.033]
    ];
var NORTH_ATLANTIC =
    [
     ["New York/Port Washington", 40.832081, -73.719479],
     ["Bermuda/Darrel's Island",  32.273,    -64.825],
     ["Foynes",                   52.618,     -9.130],
     ["Botwood",                  49.133,    -55.334]
    ];
var TEAL =
    [
     ["Auckland/Mechanics Bay",  -36.8440,   174.7942],
     ["Wellington/Evans Bay",    -41.3142,   174.8065]
    ];

###############################################################################
## Hash containing fairway locations. See also ROUTES.txt.
## Format:
##   {"mooring : [name, lat, lon, heading]}
var FAIRWAY = {
    # Europe
    "Hythe 1":                 ["Netley",        50.873,   -1.365, 0.0],
    "Hythe 2":                 ["Netley",        50.873,   -1.365, 0.0],
    "Saint-Nazaire":           ["",              47.289,   -2.152, 0.0],
    "Bordeaux/Biscarosse":     ["",              44.379,   -1.186, 0.0],
    "Macon":                   ["",              46.291,    4.831, 5.0],
    "Marseille/Marignane":     ["",              43.452,    5.181, 0.0],
    "Rome/Lake Bracciano":     ["",              42.119,   12.196, 0.0],
    "Brindisi":                ["",              40.651,   17.962, 0.0],
    "Athens/Phaleron Bay":     ["",              37.930,   23.673, 0.0],
    "Mirabella Bay":           ["",              35.210,   25.740, 0.0],
    # Africa
    "Alexandria/East Harbour": ["",              31.193,   29.874,   0.0],
    "Cairo":                   ["",              30.036,   31.225,  10.0],
    "Luxor":                   ["",              25.710,   32.642,  30.0],
    "Wadi Halfa":              ["",              21.810,   31.292,   0.0],
    "Khartoum":                ["",              15.610,   32.537,  90.0],
    "Kosti":                   ["",              13.172,   32.665, 315.0],
    "Malakal":                 ["",               9.528,   31.650, 340.0],
    "Bor":                     ["",               6.225,   31.537, 315.0],
    "Juba":                    ["",               4.834,   31.617,  30.0],
    #"Laropi":                  ["",               3.548,   31.812,  90.0],
    "Butabia":                 ["",               1.837,   31.329,   0.0],
    "Kampala/Port Bell":       ["",               0.280,   32.652,   0.0],
    "Kisumu":                  ["",              -0.094,   34.740,   0.0],
    "Nairobi/Lake Naivasha":   ["",              -0.780,   36.392,   0.0],
    "Mombasa":                 ["",              -4.050,   39.682, 335.0],
    "Dar-es-Salaam":           ["",              -6.823,   39.294,   0.0],
    "Lindi":                   ["",             -10.006,   39.720,   0.0],
    "Mozambique":              ["",             -15.038,   40.710,   0.0],
    "Beira":                   ["",             -19.820,   34.825,   0.0],
    "Inhambane":               ["",             -23.864,   35.363,   0.0],
    "Lourenco Morques":        ["",             -25.965,   32.535,   0.0],
    "Durban":                  ["Congella Bay", -29.873,   31.028,   0.0],
    # Middle East
    "Tiberias":                ["",              32.804,   35.560,   0.0],
    "Lake Habbaniyeh":         ["",              33.338,   43.546,   0.0],
    "Basra/Margil":            ["",              30.530,   47.839, 330.0],
    "Kuwait":                  ["",              29.363,   47.938,   0.0],
    "Bahrein":                 ["",              26.233,   50.624,   0.0],
    "Dubai":                   ["Dubai Creek",   25.230,   55.330, 130.0],
    # India
    "Jiwani":                  ["",              25.057,   61.717,   0.0],
    "Karachi":                 ["Karangi Creek", 24.775,   67.144,   0.0],
    "Raj Samand":              ["",              25.075,   73.882,   0.0],
    "Lake Udaipur":            ["",              24.575,   73.676,   0.0],
    "Gwalior":                 ["",              26.217,   77.989,   0.0],
    "Jhansi/Parichha Reservoir":["",             25.508,   78.768,  75.0],
    "Allahabad":               ["",              25.423,   81.872, 100.0],
    "Calcutta":                ["River Hooghly", 22.593,   88.356,  30.0],
    # Far East
    "Akyab (Sittwe)":          ["",              20.138,   92.913,   0.0],
    "Rangoon (Yangon)":        ["",              16.756,   96.203,   0.0],
    "Bangkok":                 ["",              13.657,  100.550,  95.0],
    "Ko Samu (Ko Samui)":      ["",               9.566,  100.051,   0.0],
    "Penang (Pinang)":         ["",               5.412,  100.353,   0.0],
    "Sinagpore/Kallang":       ["",               1.289,  103.867, 165.0],
    "Batavia (Jakarta)":       ["",              -6.108,  106.835,   0.0],
    "Sourabaya (Surabaya)":    ["",              -7.184,  112.743,   0.0],
    "Bima":                    ["",              -8.444,  118.705,   0.0],
    "Koepang (Kupang)":        ["",             -10.150,  123.579,   0.0],
    # Australia
    "Darwin":                  ["",             -12.471,  130.856,   0.0],
    "Groote":                  ["",             -13.946,  136.407,   0.0],
    "Karumba":                 ["",             -17.469,  140.829, 135.0],
    "Townsville":              ["",             -19.243,  146.822,   0.0],
    "Gladstone":               ["",             -23.816,  151.260,   0.0],
    "Brisbane":                ["",             -27.430,  153.128,  65.0],
    "Sydney/Rose Bay":         ["Rose Bay",     -33.863,  151.260,   0.0],
    # North Atlantic
    "Bermuda/Darrel's Island": ["",              32.271,  -64.840,   0.0],
    "New York/Port Washington":["",              40.828,  -73.719,   0.0],
    "Foynes":                  ["",              52.618,   -9.140,   0.0],
    "Botwood":                 ["",              49.140,  -55.324,   0.0],
    # Teal
    "Auckland/Mechanics Bay":  ["Mechanics Bay",-36.840,  174.805,   0.0],
    "Wellington/Evans Bay":    ["Evans Bay",    -41.309,  174.808,   0.0]
};
