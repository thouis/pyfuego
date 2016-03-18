import pyximport
pyximport.install()

import sys
import go
import numpy as np

def load_and_print(filename):
    game = go.PyGoGame(filename.encode('ascii'))
    while not game.at_end():
        game.print_board()
        libs = np.zeros((19, 19), dtype=np.int32)
        game.liberties(libs)
        print (libs.T[::-1, :])
        print ("")

        game.next_move()


if __name__ == '__main__':
    load_and_print(sys.argv[1])
