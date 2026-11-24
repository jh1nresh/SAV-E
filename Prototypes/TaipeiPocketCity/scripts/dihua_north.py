"""Illustrated street-facing shop houses immediately north of 迪化街一段89號.

The caller supplies each survey-aligned frontage and the visible street elevation.
U runs left to right from the street, and positive depth projects toward the street.
"""

from math import cos, pi, sin


# 91: 台北通 lists the shop; street photos show the green canvas, brick arches,
# a bronze-gold horizontal plaque, and two bright signs inside the arcade.
# https://id.taipei/tpcd/offers/coupons/52cedf24-4205-45fa-a968-82e1910cbcb0
# https://note.com/noted_laelia/n/ne12d101b20e6
# https://hsu042.pixnet.net/blog/posts/16095029090
#
# 93: the Victorian face, four arched openings and oculus are visible in Hsu,
# figure 5. The city event roster lists 黃裕生藥行.
# https://pimg.1px.tw/hsu042/1682938754-2455372675-g.jpg
# https://www.travel.taipei/file/34265/
#
# 95 and 97: Hsu describes 95 as a Minnan shop house and 97 as ochre brick.
# Roof details and the 97 interior are illustrated from those building types.
# 95 depicts the historic street house with a timber entrance.
# https://hsu042.pixnet.net/blog/posts/16095029090
# https://bwt100.com/index_down.php?hstyle=9&sele=hstyle
# https://www.travel.taipei/file/3890/


def surface(front, corners, color):
    front.quad(*(front.point(*corner) for corner in corners), color)


def arch(front, x, spring, radius, rise, rim, depth, color, glass=None, soffit=None):
    """Build the curved arch with radial masonry and optional glass infill."""
    count = 16
    for index in range(count):
        a = pi * index / count
        b = pi * (index + 1) / count
        inner_a = (x + radius * cos(a), spring + rise * sin(a))
        inner_b = (x + radius * cos(b), spring + rise * sin(b))
        outer_a = (x + (radius + rim) * cos(a), spring + (rise + rim) * sin(a))
        outer_b = (x + (radius + rim) * cos(b), spring + (rise + rim) * sin(b))
        surface(front, ((inner_a[0], depth, inner_a[1]), (outer_a[0], depth, outer_a[1]),
                        (outer_b[0], depth, outer_b[1]), (inner_b[0], depth, inner_b[1])), color)
        if soffit is not None:
            surface(front, ((inner_a[0], depth, inner_a[1]), (inner_b[0], depth, inner_b[1]),
                            (inner_b[0], soffit, inner_b[1]), (inner_a[0], soffit, inner_a[1])), '715044')
            cap = spring + rise + rim + .045
            surface(front, ((outer_a[0], depth, outer_a[1]), (outer_b[0], depth, outer_b[1]),
                            (outer_b[0], depth, cap), (outer_a[0], depth, cap)), color)
        if glass is not None:
            surface(front, ((inner_a[0], depth - .014, spring), (inner_b[0], depth - .014, spring),
                            (inner_b[0], depth - .014, inner_b[1]), (inner_a[0], depth - .014, inner_a[1])), glass)


def window(front, x, floor, width, height, frame, glazing, round_top=False):
    depth = .094
    front.face(x - .055, floor - .08, width + .11, height + .08, depth - .012, frame)
    front.face(x, floor, width, height, depth, '463b35')
    front.face(x + .065, floor + .055, width - .13, height - .11, depth + .013, glazing)
    front.face(x + .083, floor + .09, (width - .13) * .28, height - .18, depth + .022, '9ca69b')
    front.face(x + width * .50 - .023, floor, .046, height, depth + .025, frame)
    for fraction in (.30, .64):
        front.face(x + .015, floor + height * fraction, width - .03, .039, depth + .025, frame)
    front.slab(x - .085, floor - .093, width + .17, .08, .027, .19, frame, 'd8bca1')
    if round_top:
        center = x + width * .5
        spring = floor + height
        arch(front, center, spring, width * .5, width * .33, .082, depth + .006, frame, glazing)
        front.face(x + .03, spring - .031, width - .06, .048, depth + .018, frame)
        for side in (-1, 1):
            surface(front, ((center, depth + .019, spring), (center + width * .29 * side, depth + .019, spring + width * .24),
                            (center + width * .29 * side + .033, depth + .019, spring + width * .24),
                            (center + .033, depth + .019, spring)), frame)


def brickwork(front, bottom, eave, mortar, brick):
    width = front.width
    for row in range(int((eave - bottom) / .185)):
        z = bottom + row * .185
        front.face(.03, z, width - .06, .015, .060, mortar)
        offset = (row % 2) * .24
        for column in range(int((width - .10) / .48)):
            x = .085 + column * .48 + offset
            front.face(x, z + .015, .013, .17, .061, mortar)
            if (column + 2 * row) % 7 == 0:
                front.face(x + .025, z + .028, .29, .136, .062, brick)


def cornice(front, eave, stone, cap):
    width = front.width
    front.slab(.02, eave - .27, width - .04, .13, -.24, .19, stone)
    front.slab(.015, eave - .14, width - .03, .14, -.29, .27, cap)


def pediment(front, center, span, base, rise, fill, cap):
    south = center + span * .5
    north = center - span * .5
    apex = base + rise
    # Two solid triangles meet at the ridge, with a thin projecting rake.
    for side in (north, south):
        surface(front, ((side, .08, base), (center, .08, base),
                        (center, .08, apex), (side, .08, base)), fill)
        surface(front, ((side, .19, base), (center, .19, apex),
                        (center, .19, apex + .09), (side, .19, base + .09)), cap)
        surface(front, ((side, .19, base + .09), (center, .19, apex + .09),
                        (center, -.35, apex + .09), (side, -.35, base + .09)), cap)


def medallion(front, x, z, radius, depth, rim, inset):
    for part in range(20):
        a = 2 * pi * part / 20
        b = 2 * pi * (part + 1) / 20
        x1, z1 = cos(a), sin(a)
        x2, z2 = cos(b), sin(b)
        inner = radius * .78
        surface(front, ((x + radius * x1, depth, z + radius * z1),
                        (x + radius * x2, depth, z + radius * z2),
                        (x + inner * x2, depth, z + inner * z2),
                        (x + inner * x1, depth, z + inner * z1)), rim)
        surface(front, ((x, depth - .012, z), (x + inner * x1, depth - .012, z + inner * z1),
                        (x + inner * x2, depth - .012, z + inner * z2), (x, depth - .012, z)), inset)


def arcade(front, pier, floor, lintel, board, board_color, letters, upper_arch):
    width = front.width
    center = width * .51
    edge = .24
    reveal = -1.47
    front.slab(.01, -.055, width - .02, .079, -2.54, .23, 'ad9a84', floor)
    surface(front, ((.01, .23, .024), (width - .01, .23, .024),
                    (width - .01, .67, -.015), (.01, .67, -.015)), floor)
    for row in range(5):
        depth = .20 - .48 * row
        front.slab(.02, .025, width - .04, .006, depth - .014, depth, 'aa9076')
    for column in range(1, int(width / .53)):
        front.slab(column * .53, .025, .013, .006, -2.48, .23, 'ab947d')
    for x in (0, width - edge):
        front.slab(x, -.025, edge, 3.27, -.36, .09, pier)
        front.slab(x, -.027, edge, .48, -.39, .135, 'aaa08a', 'bfb39b')
        front.slab(x, 2.35, edge, .14, -.40, .16, lintel)
        front.slab(x, .025, edge, 2.59, reveal - .13, reveal + .045, '725342')
    front.slab(.02, 3.19, width - .04, .36, -2.56, .13, lintel)
    if upper_arch:
        radius = width * .5 - edge - .11
        arch(front, width * .5, 2.50, radius, .66, .13, .11, lintel, soffit=-.50)
    else:
        front.slab(.02, 2.94, width - .04, .24, -.19, .16, lintel)
    # The back of the arcade contains the actual shop opening and built-up jambs.
    entry = 1.36
    front.face(.01, .03, width - .02, 2.96, -2.55, '534139')
    front.face(center - entry * .5, .031, entry, 2.32, reveal - .08, '423832')
    for x in (center - entry * .5 - .07, center + entry * .5):
        front.slab(x, .03, .075, 2.42, reveal - .14, reveal + .04, '9c7858')
    front.slab(center - entry * .5 - .076, 2.38, entry + .152, .13, reveal - .16, reveal + .06, 'b39473')
    front.face(center - .49, .03, .98, 2.21, -2.48, '625145')
    front.slab(.32, 2.60, width - .64, .50, reveal -.07, reveal + .13, board_color)
    letter_width = min(width - 1.03, len(board) * .41)
    front.sign(board, (width - letter_width) * .5, 2.72, letter_width, .25, reveal + .142, letters)


def counter(front, x, width, back, face, bays):
    front.slab(x, .025, width, .79, back - .43, back, face, 'd9b584')
    front.slab(x - .025, .80, width + .05, .07, back - .48, back + .04, 'a68460', 'e3ca9d')
    shelf = (width - .13) / bays
    for i in range(bays):
        left = x + .065 + i * shelf
        color = ('b68352', 'c9a267', 'b8664f', '98916a')[i % 4]
        front.slab(left, .87, shelf - .04, .18 + i % 3 * .055, back - .40, back - .035, color, 'e7c68f')
        front.face(left + .022, .92, shelf - .085, .06, back - .03, 'e5cc9f')


def canopy(front, color, edge, bottom=3.00):
    width = front.width
    surface(front, ((.12, .08, bottom + .32), (width - .12, .08, bottom + .32),
                    (width - .12, .78, bottom), (.12, .78, bottom)), color)
    front.face(.12, bottom - .11, width - .24, .11, .783, edge)
    for i in range(1, 8):
        x = .12 + (width - .24) * i / 8
        surface(front, ((x, .08, bottom + .328), (x + .018, .08, bottom + .328),
                        (x + .018, .78, bottom + .008), (x, .78, bottom + .008)), edge)


def make_north(front, number):
    """Build one of the four north-side façades on the caller's wall."""
    w = front.width
    if number == 91:
        # The shared 89/91 shell keeps matching brick and cornice heights.
        eave = 7.29
        front.slab(.012, 3.53, w - .024, eave - 3.53, -4.90, .053, 'a86b57', 'a38f77')
        brickwork(front, 3.61, eave - .48, 'b88269', 'ad725d')
        cornice(front, eave - .04, '92877b', 'c1b29c')
        for i in range(2):
            cell = w * .5
            window(front, (i + .14) * cell, 4.06, cell * .73, 1.32, '9a8c7d', '618188', True)
        front.slab(.06, 6.76, w - .12, .83, -.23, .11, 'af7761')
        medallion(front, w * .50, 7.14, .29, .15, 'c6b39c', '655950')
        for x in (.06, w - .23):
            front.slab(x, 3.48, .17, 4.03, -.05, .17, '79685e', 'b2a08b')
        arcade(front, '9f6c56', 'c6b6a0', '9e806b', '堂生利', '65513d', 'e3bd73', False)
        canopy(front, '497260', '678d75')
        for x in (.29, w - 1.32):
            counter(front, x, 1.02, -.52, 'a88152', 4)
            front.slab(x, 1.98, 1.02, .25, -1.14, -1.04, 'dab554')
            front.sign('蔘藥行', x + .13, 2.043, .76, .11, -1.031, '624d37')
    elif number == 93:
        eave = 7.42
        front.slab(.013, 3.50, w - .026, eave - 3.50, -4.35, .052, 'a97762', '9d8473')
        brickwork(front, 3.56, eave - .20, 'b58d75', 'b58169')
        cornice(front, eave, '9f8d7b', 'c6b298')
        pediment(front, w * .50, w * .80, eave, .94, 'a9755e', '968474')
        medallion(front, w * .50, eave + .32, .21, .115, 'c0ab91', '564d45')
        for i in range(4):
            cell = w * .25
            x = (i + .16) * cell
            window(front, x, 4.16, cell * .66, 1.68, 'b7a089', '607779', True)
            for rail in range(5):
                front.slab(x + .06 + rail * cell * .112, 4.14, .036, .42, .11, .154, '6c6d61')
        arcade(front, 'a46f57', 'ab8b76', '987c68', '黃裕生藥行', '735042', 'edc486', True)
        for x in (.42, w - 1.77):
            counter(front, x, 1.35, -.71, '986745', 5)
        for x in (.63, w - .63):
            medallion(front, x, 2.38, .15, -.24, 'aa5d4b', 'c47753')
    elif number == 95:
        eave = 7.14
        front.slab(.013, 3.48, w - .026, eave - 3.48, -4.74, .054, 'a35e4d', '8d7566')
        brickwork(front, 3.57, eave - .31, 'bc8870', 'b7715a')
        cornice(front, eave, 'a78067', 'c9a88a')
        for i in range(3):
            cell = w / 3
            window(front, (i + .16) * cell, 4.11, cell * .68, 1.55, 'aa8469', '617a6d', True)
        # A shallow tiled hip roof behind the low Minnan parapet.
        for i in range(18):
            x = .03 + i * (w - .06) / 18
            right = .03 + (i + 1) * (w - .06) / 18
            color = ('b07860', '9d6152', 'af6d58')[i % 3]
            surface(front, ((x, .04, eave - .035), (right, .04, eave - .035),
                            (right, -.94, eave + .34), (x, -.94, eave + .34)), color)
            surface(front, ((x, -.94, eave + .34), (right, -.94, eave + .34),
                            (right, -2.00, eave - .035), (x, -2.00, eave - .035)), color)
        front.slab(.05, 4.04, w - .10, .11, -.09, .26, 'c19682')
        arcade(front, 'a3624f', 'a77760', '996b55', '老成記', '86523c', 'f3d194', True)
        # The historic storefront has an interior passage and timber panels at both sides.
        for x in (.34, w - 1.69):
            front.slab(x, .032, 1.34, 2.44, -1.79, -1.65, '805744')
            for column in range(3):
                u = x + .07 + .42 * column
                front.face(u, .24, .34, 1.16, -1.64, 'aa7858')
                front.face(u, 1.48, .34, .78, -1.64, '53443b')
                front.face(u + .16, 1.48, .031, .78, -1.63, 'a87d61')
    elif number == 97:
        eave = 7.02
        front.slab(.013, 3.48, w - .026, eave - 3.48, -4.62, .054, 'b79a69', 'a59275')
        brickwork(front, 3.60, eave - .28, 'a98b62', 'c1a575')
        cornice(front, eave, 'a18a6e', 'd1b992')
        for i in range(2):
            cell = w * .5
            window(front, (i + .16) * cell, 4.14, cell * .68, 1.94, '8c735c', '738573')
        for x in (.12, w * .5 - .09, w - .30):
            front.slab(x, 3.68, .18, eave - 3.99, .038, .143, 'c7ae83')
        front.slab(.03, 6.54, w - .06, .14, -.07, .16, '987c5f')
        arcade(front, 'af966c', 'c4aa89', 'a89373', '正元參藥行', '4f6352', 'efcf8e', False)
        for i in range(4):
            x = .37 + i * .24
            front.slab(x, .031, .20, 1.23, -1.23, -1.13, '805e45')
            for row in range(5):
                front.face(x + .024, .23 + row * .17, .15, .025, -1.12, 'c2a67a')
        counter(front, w - 1.52, 1.18, -.63, '97724e', 3)
