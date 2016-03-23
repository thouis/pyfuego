import pyximport
pyximport.install()

import sys
import go
import numpy as np

stonetochar = {go.EMPTY: ' ',
               go.BLACK: 'X',
               go.WHITE: 'O'}

def load_and_print(filename):
    game = go.PyGoGame(filename.encode('ascii'))
    while not game.at_end():
        game.print_board()
        stones = np.zeros((19, 19), dtype=np.int32)
        libs = np.zeros((19, 19), dtype=np.int32)
        ages = np.zeros((19, 19), dtype=np.int32)
        capture_ct = np.zeros((19, 19), dtype=np.int32)
        atari_ct = np.zeros((19, 19), dtype=np.int32)
        liberties_after = np.zeros((19, 19), dtype=np.int32)
        ladder_capture = np.zeros((19, 19), dtype=np.int32)
        ladder_escape = np.zeros((19, 19), dtype=np.int32)
        sensible = np.zeros((19, 19), dtype=np.int32)

        game.liberties(libs)
        game.black_white_empty(stones)
        game.stone_age(ages)
        game.captures_liberties_selfatari_by_play(capture_ct,
                                                  liberties_after,
                                                  atari_ct)
        game.ladder_capture_escape(ladder_capture,
                                   ladder_escape)
        game.sensibleness(sensible)

        # for row in stones[::-1, :]:
        #    print(" ".join(stonetochar[c] for c in row))
        print("")
        print("libs")
        # print(libs[::-1, :])
        print("")
        print("age")
        # print(ages[::-1, :])
        print("")
        print("capture")
        # print(capture_ct[::-1, :])
        print("self-atari")
        # print(atari_ct[::-1, :])
        print("liberties after move")
        # print(liberties_after[::-1, :])
        print("ladder capture")
        # print(ladder_capture[::-1, :])
        print("ladder_escape")
        #print(ladder_escape[::-1, :])
        print("sensible")
        print(sensible[::-1, :] + (stones[::-1, :] != go.EMPTY))
        print("")
        print("")
        print("")

        game.next_move()


if __name__ == '__main__':
    load_and_print(sys.argv[1])
