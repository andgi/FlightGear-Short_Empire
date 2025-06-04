###############################################################################
##
## Short S.23 'C'-class Empire flying boat
##
##  Copyright (C) 2010 - 2012, 2025  Anders Gidenstam  (anders(at)gidenstam.org)
##  Copyright (C) 2024 - 2025        Ludovic Brenta
##  This file is licensed under the GPL license v2 or later.
##
###############################################################################

# Do terrain modelling ourselves.
setprop("sim/fdm/surface/override-level", 1);

var mooring = {
    moorings : { },
    # Hash of { Coord, model } objects, indexed by name, containing all supported mooring locations.  The models are added on demand
    # only.

    fairway_model : {},   # Optional model showing where to take off. Indexed by name.
    selected : "",        # The name of the selected mooring; indexes into the "moorings" and "fairway_model" above.
    listener : nil,       # When not nil, listens for /sim/signals/fdm-initialized.

    active_mooring : nil,
    mooring_connected : nil,
    # Two property nodes used to communicate with jsbsim and initialized after the FDM is initialized for the second time.

    select_nearest_as_we_fly : nil
    # A timer started after the second FDM initialization.  Periodically updates me.selected so it always designates the mooring point
    # nearest to the aicraft.
};

mooring.init = func() {
    # This runs exactly once, immediately on startup.  Initializes static data.
    me.mooring_model_path =
        me.find_model_path("Short_Empire/Models/Moorings/buoy.xml");
    me.fairway_model_path =
        me.find_model_path("Short_Empire/Models/Moorings/flare_path.xml");

    # Add the predefined moorings.
    foreach (var m; EAMS_MOORINGS_EUROPE ~
             EAMS_MOORINGS_EAST ~
             EAMS_MOORINGS_SOUTH ~
             NORTH_ATLANTIC ~
             TEAL ~
             FICTIONAL) {
        var pos = geo.Coord.new();
        if (size (m) == 4) { # has altitude in m
            pos.set_latlon(m[1], m[2], m[3]);
        }
        else {
            pos.set_latlon(m[1], m[2]);
        }
        me.moorings[m[0]] = { position : pos, model : nil };
    }

    # Enable Alt+Click to place the mooring and select it immediately.
    setlistener("/sim/signals/click", func () {
        if (__kbd.alt.getBoolValue()) {
            var pos = geo.click_position();
            me.selected = "alt+click";
            # Remove any existing buoy model.
            if (contains (me.moorings, me.selected) and me.moorings[me.selected].model != nil) {
                me.moorings[me.selected].model.remove();
            }
            me.moorings[me.selected] = { position : pos, model : nil };
            me.display_selected_mooring();
        }
    });

    print("Short Empire Mooring ... Standing by.");
    me.listener = setlistener ("/sim/signals/fdm-initialized", func () {
            removelistener (me.listener); me.listener = nil; # Run this just once.
            me.choose_and_teleport();
        });
};

mooring.display_selected_mooring = func() {
    var geo_info = geodinfo(me.moorings[me.selected].position.lat(),
                            me.moorings[me.selected].position.lon());
    if (geo_info != nil) {
        me.moorings[me.selected].position.set_alt(geo_info[0]);
    }
    # Put a mooring buoy model here.
    me.moorings[me.selected].model = geo.put_model(me.mooring_model_path, me.moorings[me.selected].position);
    # Display the associated fairway, if any.
    if (FAIRWAY[me.selected] != nil) {
        if (me.fairway_model[me.selected] != nil) me.fairway_model[me.selected].remove();
        var heading = FAIRWAY[me.selected][3];
        if (heading == 0.0) {
            heading = -getprop("/environment/wind-from-heading-deg");
        }
        me.fairway_model[me.selected] = geo.put_model (me.fairway_model_path,
                                                       FAIRWAY[me.selected][1],
                                                       FAIRWAY[me.selected][2],
                                                       me.moorings[me.selected].position.alt() or 0,
                                                       heading);
    }
    # Tell the FDM about our new mooring position.
    me.active_mooring.getNode("latitude-deg").setValue(me.moorings[me.selected].position.lat());
    me.active_mooring.getNode("longitude-deg").setValue(me.moorings[me.selected].position.lon());
    me.active_mooring.getNode("altitude-ft").setValue(M2FT * me.moorings[me.selected].position.alt());
};

mooring.pick_up_mooring = func {
    if (me.mooring_connected.getBoolValue())
        return;
    var dist = me.active_mooring.getNode("total-distance-ft").getValue();
    var rope_length =
        me.active_mooring.getNode("rope-length-ft").getValue();
    if (dist < rope_length/FT2M) {
        me.mooring_connected.toggleBoolValue();
        setprop("controls/lighting/anchor-light", 1.0);
        copilot.announce("We picked up the mooring.");
        return 1;
    } else {
        copilot.announce("We are too far from the buoy.");
        return 0;
    }
};

mooring.release_mooring = func {
    if (! me.mooring_connected.getBoolValue())
        return;
    me.mooring_connected.toggleBoolValue();
    setprop("controls/lighting/anchor-light", 0.0);
    copilot.announce("Mooring slipped.");
};

mooring.find_model_path = func (filename) {
    # filename should include the aircraft's directory.
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
};

mooring.select_nearest = func (in_flight=0) {
    # Find the nearest mooring position, write its name in me.selected.
    var ac_pos = geo.aircraft_position();
    var previously_selected = me.selected;

    distance = 20000000; # metres
    foreach (var name; keys(me.moorings)) {
        var m = me.moorings[name];
        var d = m.position.direct_distance_to (ac_pos);
        if (d < distance) {
            distance = d;
            me.selected = name;
        }
    }
    if (me.selected == "") {
        copilot.announce ("BUG: could not find any mooring on the earth!");
    }
    else if (me.selected != previously_selected) {
        copilot.announce ("Nearest mooring at " ~ me.selected);
        if (in_flight) {
            me.display_selected_mooring();
        }
    }
};

mooring.choose_and_teleport = func {
    # This runs exactly once, after the FDM is initialized for the first time.
    me.select_nearest();

    me.active_mooring = props.globals.getNode("/fdm/jsbsim/mooring");
    me.mooring_connected = me.active_mooring.initNode ("mooring-connected", 0, "BOOL", 1);

    # Reposition to the selected mooring. No, don't do this unless very near!
    #var presets = props.globals.getNode("/sim/presets");
    #presets.getChild("latitude-deg").setValue(me.moorings[me.selected].position.lat());
    #presets.getChild("longitude-deg").setValue(me.moorings[me.selected].position.lon());
    #presets.getChild("altitude-ft").setValue(me.moorings[me.selected].position.alt());
    #presets.getChild("heading-deg").setValue(0);
    #presets.getChild("airport-id").setValue("");
    #presets.getChild("airspeed-kt").setValue(0);
    #fgcommand("reposition");
    # The repositioning re-initializes the FDM; shedule the final adjustments to happen after that:
    me.listener = setlistener ("/sim/signals/fdm-initialized", func () {
        removelistener (me.listener); me.listener = nil; # We want to run just once.
        me.after_teleport();
    });
};

mooring.after_teleport = func () {
    me.display_selected_mooring();
    me.pick_up_mooring();
    me.select_nearest_as_we_fly = maketimer (5.0, me, func { me.select_nearest(1); });
    me.select_nearest_as_we_fly.start();
};

###############################################################################
## Lists containing EAMS mooring locations. See also ROUTES.txt.
## Format:
##   [[name, lat, lon, optional_alt_in_m ]]
var EAMS_MOORINGS_EUROPE =
    [
     ["Hythe 1",                 50.872210,   -1.390830],
     ["Hythe 2",                 50.872349,   -1.387512],
     ["Saint-Nazaire",           47.297423,   -2.134309],
     ["Bordeaux/Biscarosse",     44.383172,   -1.184227],
     ["Macon",                   46.290932,    4.830000],
     ["Marseille/Marignane",     43.447937,    5.185410],
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
     ["Tiberias",              32.804,      35.547, -222],
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
     ["Vaal Dam",             -26.89472,    28.1200, 1486], # altitude in m
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
var FICTIONAL =
    [
     ["Bastia etang de Bigulia",  42.5841, 9.4987,   0 ], # near LFKB
     ["Friedrichshafen",          47.6500, 9.4900, 391 ], # near EDNY on lake Constance, altitude in m
     # Canadian West Coast
     ["Victoria Inner Harbour",   48.4260, -123.3900, 0], # Near CYYJ
     ["Vancouver Harbour",        49.2920, -123.1180, 0], # Near CYVR
     # Alaska and Aleutian Islands, east to west:
     ["Juneau Harbor",            58.2950, -134.4075, 0], # Near PAJN
     ["Anchorage/Lake Hood",      61.1835, -149.8755, 0], # Near PANC, PALH
     ["Kodiak Station",           57.7290, -152.5228, 0], # Near PADQ
     ["Nelson Lagoon",            55.9800, -161.1800, 0], # Near PAOU
     ["Cold Bay/Blinn Lake Seabase", 55.2516272, -162.7534044, 0 ], # Near PACD
     ["Akutan Seaplane Base",     54.1313, -165.7794, 0], # KQA, visible in the launcher but not in the map
     ["Unalaska Dutch Harbor",    53.8787, -166.5471, 0], # Near PADU
     ["Nikolski Air Station",     52.9410, -168.8620, 0], # PAKO
     ["Adak Sweeper Cove",        51.8565, -176.6405, 0], # Near PADK
     ["Attu Casco Cove",          52.8103,  173.1720, 0]  # PATU, west of the date line
    ];

###############################################################################
## Hash containing fairway locations. See also ROUTES.txt.
## Format:
##   {"mooring" : [name, lat, lon, heading]}
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

mooring.init (); # even before the FDM is initialized: all of this is static henceforth.

mooring.dump_one = func (i, arr) {
    print("    <wp n=\"" ~ i ~ "\">");
    print("      <type type=\"string\">basic</type>");
    print("      <ident type=\"string\">" ~ arr[0] ~ "</ident>");
    print("      <lat type=\"double\">" ~ arr[1] ~ "</lat>");
    print("      <lon type=\"double\">" ~ arr[2] ~ "</lon>");
    print("    </wp>");
};

mooring.dump_forward = func (arr) {
    for (var i=0; i < size(arr); i += 1) {
        me.dump_one (i, arr[i]);
    }
};

mooring.dump_backward = func (arr) {
    for (var i=size(arr); i > 0; i -= 1) {
        me.dump_one (1 + size(arr) - i, arr[i-1]);
    }
};

mooring.dump = func () {
    print ("-------- southampton-alexandria -----------");
    me.dump_forward (EAMS_MOORINGS_EUROPE);
    print ("-------- alexandria-southampton -----------");
    me.dump_backward (EAMS_MOORINGS_EUROPE);
    print ("-------- alexandria-durban -----------");
    me.dump_forward (EAMS_MOORINGS_SOUTH);
    print ("-------- durban-alexandria -----------");
    me.dump_backward (EAMS_MOORINGS_SOUTH);
    print ("-------- alexandria-sydney -----------");
    me.dump_forward (EAMS_MOORINGS_EAST);
    print ("-------- sydney-alexandria -----------");
    me.dump_backward (EAMS_MOORINGS_EAST);
};
