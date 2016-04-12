import pyximport
pyximport.install()

import h5py
import go
import numpy as np
import sys

NUM_FEATURES = 48
NUM_LABELS = 2  # row, col

# Preallocate - saves time in calc_features
stones = np.zeros((19, 19), dtype=np.int32)
libs = np.zeros((19, 19), dtype=np.int32)
ages = np.zeros((19, 19), dtype=np.int32)
capture_ct = np.zeros((19, 19), dtype=np.int32)
atari_ct = np.zeros((19, 19), dtype=np.int32)
liberties_after = np.zeros((19, 19), dtype=np.int32)
ladder_capture = np.zeros((19, 19), dtype=np.int32)
ladder_escape = np.zeros((19, 19), dtype=np.int32)
sensible = np.zeros((19, 19), dtype=np.int32)
legal = np.zeros((19, 19), dtype=np.int32)
features = np.zeros((NUM_FEATURES, 19, 19), dtype=np.uint8)

def calc_features(game, alphago_compatible=True):
    game.liberties(libs)
    game.black_white_empty(stones)
    game.stone_age(ages)
    game.captures_liberties_selfatari_by_play(capture_ct,
                                              liberties_after,
                                              atari_ct)
    game.ladder_capture_escape(ladder_capture,
                               ladder_escape)
    game.sensibleness(sensible)
    game.legal(legal)

    offset = range(NUM_FEATURES + 1).__iter__()

    def next_feature(val):
        features[offset.next(), ...] = val

    # 0,1,2 - my stones, their stones, empty
    next_feature(stones == game.current_player())
    next_feature(stones == go.opposite(game.current_player()))
    next_feature(stones == go.EMPTY)

    # 3 - all ones
    next_feature(1)

    if alphago_compatible:
        # 4-11 - Turns since
        for idx in range(0, 7):
            next_feature(ages == idx + 1)
        next_feature(ages >= 8)

    # 12-19 - Liberties of groups
    for idx in range(0, 7):
        next_feature(libs == idx + 1)
    next_feature(libs >= 8)

    # 20-27 - Capture size
    for idx in range(0, 7):
        next_feature(capture_ct == idx)
    next_feature(capture_ct >= 7)

    # 28-35 - Self-atari size
    # 0th plane == 1 stone in atari
    for idx in range(0, 7):
        next_feature(atari_ct == idx + 1)
    next_feature(atari_ct >= 8)

    # 36-43 - Liberties after move
    for idx in range(0, 7):
        next_feature(liberties_after == idx + 1)
    next_feature(liberties_after >= 8)

    # 44 - Ladder capture move
    next_feature(ladder_capture)

    # 45 - Ladder escape move
    next_feature(ladder_escape)

    # 46 - Senible - legal and does not fill eyes
    next_feature(sensible)

    if alphago_compatible:
        # 47 - all zeros
        next_feature(0)
    else:
        next_feature(legal)

    return features[:offset.next(), ...]

def numeric_rank(s, default=None):
    if s.endswith(','):
        s = s[:-1]
    if s == 'Insei':
        s = '1p'
    if s in ('Mingren', 'Meijin', 'Kisei', 'Oza'):
        s = '9p'

    if s[-1] == 'k':
        # 21k == 0
        return 100 * (21 - int(s[:-1]))
    elif s[-1] in 'da':  # "amateur dans"
        # 1d == 2100
        return 2000 + 100 * int(s[:-1])
    elif s[-1] == 'p':
        # 1p = 2700, 30 points between
        return 2700 + 30 * int(s[:-1])
    else:
        print("bad rank {}".format(s))
        return default


if __name__ == '__main__':
    idx = 0
    h5 = h5py.File(sys.argv[1], 'w')

    num_features = NUM_FEATURES - 8
    outdata = h5.require_dataset('X',
                                 shape=(1, num_features, 19, 19),
                                 dtype=np.uint8,
                                 chunks=(16, num_features, 19, 19),
                                 maxshape=(None, num_features, 19, 19),
                                 compression="gzip", shuffle=True)
    outlabels = h5.require_dataset('y',
                                   shape=(1, NUM_LABELS),
                                   dtype=np.int8,
                                   chunks=(1000, NUM_LABELS),
                                   maxshape=(None, NUM_LABELS))
    ranks = h5.require_dataset('ranks',
                               shape=(1, 1),
                               dtype=np.int32,
                               chunks=(1000, 1),
                               maxshape=(None, 1))

    game_indices = []  # for storing where games' moves start
    idx = 0

    num_rejected = 0

    bad_games = ("2008-06-17-26 1150C 1934-01-28a 1934-08-09a 1936-03-29a 1937-03-23a"
                 " 1730WXTYP11 1730WXTYP10 1700JQXG224"
                 " OGS_game_179267 OGS_game_244436").split(' ')
    for filename in sys.stdin:
        if any(bad in filename for bad in bad_games):
            continue

        game = go.PyGoGame(filename.strip().encode('UTF-8'))
        rank_black, rank_white = game.get_ranks()
        rank_black = rank_black.split(' ')[0]
        rank_white = rank_white.split(' ')[0]
        if not rank_black or not rank_white:
            rank_black = rank_white = '5p'  # old games often lack ranks
        try:
            rank_black = numeric_rank(rank_black)
            rank_white = numeric_rank(rank_white)
        except ValueError:
            rank_black = rank_white = numeric_rank('5p') if 'GoGoD' in filename else None

        if not rank_black or not rank_white:
            num_rejected += 1
            continue

        game_indices.append((filename.strip(), idx))

        while not game.at_end():
            # grow the output
            outdata.resize(idx + 1, 0)
            outlabels.resize(idx + 1, 0)
            ranks.resize(idx + 1, 0)
            outdata[idx, ...] = calc_features(game, alphago_compatible=False)
            outlabels[idx, :] = game.current_move()
            ranks[idx, 0] = rank_black if (game.current_player() == go.BLACK) else rank_white
            # game.print_board()
            # print(game.current_move())
            game.next_move()
            idx = idx + 1

    names = h5.require_dataset('gamefiles', (len(game_indices),), dtype=h5py.special_dtype(vlen=bytes))
    offsets = h5.require_dataset('gameoffsets', (len(game_indices),), dtype=int)
    names[...] = [v[0] for v in game_indices]
    offsets[...] = [v[1] for v in game_indices]
    print("done {}, rejected {}, kept {}".format(sys.argv[1], num_rejected, len(game_indices)))
