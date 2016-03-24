import pyximport
pyximport.install()

import h5py
import go
import numpy as np
import sys

NUM_FEATURES = 48
NUM_LABELS = 2  # row, col

h5 = h5py.File(sys.argv[1])

outdata = h5.require_dataset('X',
                             shape=(1, NUM_FEATURES, 19, 19),
                             dtype=np.uint8,
                             chunks=(10, NUM_FEATURES, 19, 19),
                             maxshape=(None, NUM_FEATURES, 19, 19),
                             compression="lzf")
outlabels = h5.require_dataset('y',
                               shape=(1, NUM_LABELS),
                               dtype=np.uint8,
                               chunks=(1000, NUM_LABELS),
                               maxshape=(None, NUM_LABELS))

# Preallocate
stones = np.zeros((19, 19), dtype=np.int32)
libs = np.zeros((19, 19), dtype=np.int32)
ages = np.zeros((19, 19), dtype=np.int32)
capture_ct = np.zeros((19, 19), dtype=np.int32)
atari_ct = np.zeros((19, 19), dtype=np.int32)
liberties_after = np.zeros((19, 19), dtype=np.int32)
ladder_capture = np.zeros((19, 19), dtype=np.int32)
ladder_escape = np.zeros((19, 19), dtype=np.int32)
sensible = np.zeros((19, 19), dtype=np.int32)
features = np.zeros((NUM_FEATURES, 19, 19), dtype=np.uint8)

def calc_features(game):
    game.liberties(libs)
    game.black_white_empty(stones)
    game.stone_age(ages)
    game.captures_liberties_selfatari_by_play(capture_ct,
                                              liberties_after,
                                              atari_ct)
    game.ladder_capture_escape(ladder_capture,
                               ladder_escape)
    game.sensibleness(sensible)

    # 0,1,2 - my stones, their stones, empty
    features[0, ...] = (stones == game.current_player())
    features[1, ...] = (stones == go.opposite(game.current_player()))
    features[2, ...] = (stones == go.EMPTY)

    # 3 - all ones
    features[3, ...] = 1

    # 4-11 - Turns since
    for idx in range(0, 8):
        # XXX - should the last plane be all "old" stones?
        features[idx + 4] = (ages == idx + 1)

    # 12-19 - Liberties of groups
    for idx in range(0, 7):
        features[idx + 12] = (libs == idx + 1)
    features[19] = (libs >= 8)

    # 20-27 - Capture size
    for idx in range(0, 7):
        features[idx + 20] = (capture_ct == idx)
    features[27] = (capture_ct >= 7)

    # 28-35 - Self-atari size
    for idx in range(0, 7):
        features[idx + 28] = (atari_ct == idx)
    features[35] = (atari_ct >= 7)

    # 36-43 - Liberties after move
    for idx in range(0, 7):
        features[idx + 36] = (liberties_after == idx + 1)
    features[43] = (liberties_after >= 8)

    # 44 - Ladder capture move
    features[44] = ladder_capture

    # 45 - Ladder escape move
    features[45] = ladder_escape

    # 46 - Senible - legal and does not fill eyes
    features[46] = sensible

    # 47 - all zeros
    features[47] = 0

    return features

if __name__ == '__main__':
    idx = 0
    for filename in sys.stdin:
        print("Processing {}".format(filename.strip()))

        game = go.PyGoGame(filename.strip())
        while not game.at_end():
            # grow the output
            outdata.resize(idx + 1, 0)
            outlabels.resize(idx + 1, 0)
            outdata[idx, ...] = calc_features(game)
            outlabels[idx, ...] = game.current_move()
            game.next_move()
            idx = idx + 1
        print(idx)
