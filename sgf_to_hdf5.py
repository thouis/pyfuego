import pyximport
pyximport.install()

import threading
import multiprocessing
import h5py
import go
import numpy as np
import sys

NUM_FEATURES = 48
NUM_LABELS = 2  # row, col


def get_current_features(game, write_fn, alphago_compatible=True):
    # preallocate space
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

    # 0,1,2 - my stones, their stones, empty
    write_fn(stones == game.current_player())
    write_fn(stones == go.opposite(game.current_player()))
    write_fn(stones == go.EMPTY)

    # 3 - all ones
    write_fn(1)

    if alphago_compatible:
        # 4-11 - Turns since
        for idx in range(0, 7):
            write_fn(ages == idx + 1)
        write_fn(ages >= 8)
    else:
        for idx in range(8):
            write_fn(0)

    # 12-19 - Liberties of groups
    for idx in range(0, 7):
        write_fn(libs == idx + 1)
    write_fn(libs >= 8)

    # 20-27 - Capture size
    for idx in range(0, 7):
        write_fn(capture_ct == idx)
    write_fn(capture_ct >= 7)

    # 28-35 - Self-atari size
    # 0th plane == 1 stone in atari
    for idx in range(0, 7):
        write_fn(atari_ct == idx + 1)
    write_fn(atari_ct >= 8)

    # 36-43 - Liberties after move
    for idx in range(0, 7):
        write_fn(liberties_after == idx + 1)
    write_fn(liberties_after >= 8)

    # 44 - Ladder capture move
    write_fn(ladder_capture)

    # 45 - Ladder escape move
    write_fn(ladder_escape)

    # 46 - Senible - legal and does not fill eyes
    write_fn(sensible)

    # not really alphago
    write_fn(legal)


def calc_features(game, alphago_compatible=True):
    features = np.empty((game.gamelen(), NUM_FEATURES, 19, 19), dtype=np.uint8)
    cur_player = np.empty((game.gamelen(),), dtype=np.int8)
    cur_move = np.empty((game.gamelen(), 2), dtype=np.int8)

    for move_idx in range(game.gamelen()):
        offset = range(NUM_FEATURES + 1).__iter__()
        def next_feature(val):
            features[move_idx, next(offset), ...] = val

        get_current_features(game, next_feature, alphago_compatible)
        # record player color and move
        cur_player[move_idx] = game.current_player()
        cur_move[move_idx] = game.current_move()

        game.next_move()

    return features, cur_player, cur_move


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


def process_sgf(in_q, out_q):
    while True:
        filename = in_q.get()
        game = go.PyGoGame(filename)
        features, player, moves = calc_features(game)

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
            out_q.put((False, False, False, False))
            continue

        ranks = np.empty_like(player, dtype=np.int32)
        ranks[player == go.BLACK] = rank_black
        ranks[player == go.WHITE] = rank_white
        out_q.put((filename, features, ranks, moves))

def write_hdf5(in_q, h5_out):
    global filecount, num_rejected
    X = h5_out['X']
    y = h5_out['y']
    r = h5_out['ranks']

    names = []
    offsets = []

    while True:
        filename, features, ranks, moves = in_q.get()

        if filename is False:
            num_rejected += 1
            filecount -= 1
            if filecount == 0:
                break
            continue

        num_new = features.shape[0]

        base = X.shape[0]
        X.resize(base + num_new, 0)
        y.resize(base + num_new, 0)
        r.resize(base + num_new, 0)
        X[base:, ...] = features
        y[base:, ...] = moves
        r[base:, ...] = ranks.reshape((-1, 1))

        names.append(filename)
        offsets.append(base)

        filecount -= 1
        if filecount == 0:
            break
        print("in flight", filecount)

    gamenames = h5.require_dataset('gamefiles', (len(names),), dtype=h5py.special_dtype(vlen=bytes))
    gameoffsets = h5.require_dataset('gameoffsets', (len(offsets),), dtype=int)
    gamenames[...] = names
    gameoffsets[...] = offsets
    print("done {}, rejected {}, kept {}".format(sys.argv[1], num_rejected, len(offsets)))

if __name__ == '__main__':
    h5 = h5py.File(sys.argv[1], 'w')
    num_features = NUM_FEATURES
    outdata = h5.require_dataset('X',
                                 shape=(1, num_features, 19, 19),
                                 dtype=np.uint8,
                                 chunks=(16, num_features, 19, 19),
                                 maxshape=(None, num_features, 19, 19))
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

    idx = 0

    num_rejected = 0

    bad_games = ("2008-06-17-26 1150C 1934-01-28a 1934-08-09a 1936-03-29a 1937-03-23a"
                 " 1730WXTYP11 1730WXTYP10 1700JQXG224"
                 " OGS_game_179267 OGS_game_244436").split(' ')

    filename_queue = multiprocessing.Queue()
    features_queue = multiprocessing.Queue()

    for i in range(2 * multiprocessing.cpu_count()):
        t = multiprocessing.Process(target=process_sgf, args=(filename_queue, features_queue))
        t.daemon = True
        t.start()

    writer = threading.Thread(target=write_hdf5, args=(features_queue, h5))
    writer.start()

    filecount = 0
    for filename in sys.stdin:
        if any(bad in filename for bad in bad_games):
            continue

        filename_queue.put(filename.strip().encode('UTF-8'))
        filecount += 1

    writer.join()
