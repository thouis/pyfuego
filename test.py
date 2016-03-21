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
        game.liberties(libs)
        game.black_white_empty(stones)
        games.stone_age(ages)
        for row in stones[::-1, :]:
            print(" ".join(stonetochar[c] for c in row))
        print("")
        print("libs")
        print(libs[::-1, :])
        print("")
        print("age")
        print(ages)
        print("")
        print("")
        print("")

        game.next_move()


if __name__ == '__main__':
    load_and_print(sys.argv[1])
