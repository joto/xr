
// ---- shapefiles ----

shapefile('roads').
    type(LINE).
    column('id', INTEGER, 10).
    column('type', STRING, 32).
    column('name', STRING, 32).
    column('ref', STRING, 16).
    column('oneway', BOOL).
    column('maxspeed', INTEGER, 3).
    column('layer', INTEGER, 2).
    column('bridge', BOOL).
    column('tunnel', BOOL);

shapefile('rails').
    type(LINE).
    column('id', INTEGER, 10).
    column('type', STRING, 32);

// ---- rules ----

way('highway', 'motorway|trunk|primary|motorway_link|trunk_link|primary_link|secondary|tertiary|unclassified|residential|cycleway|footway|service|living_street|pedestrian').
    output('roads').
        attr('type', 'highway').
        attr('ref').
        attr('name').
        attr('oneway').
        attr('maxspeed').
        attr('layer').
        attr('bridge').
        attr('tunnel');

way('railway').
    output('rails').
        attr('type', 'railway');

