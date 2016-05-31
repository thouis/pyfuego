import pyximport
pyximport.install()

from sgf_to_hdf5 import get_current_features, NUM_FEATURES
import go
import numpy as np
from predictor import Predictor

# gtp coords are letters *** except I ***, number (from lower left)
board_letters = "abcdefghjklmnopqrstuvwxyz"


class Player(object):
    def __init__(self, filename):
        self.gamestate = go.PyGoGame("".encode('ascii'))
        self.predictor = Predictor(filename)

    def clear(self):
        self.gamestate = go.PyGoGame("".encode('ascii'))

    def size(self):
        return 19

    def move(self, color, move):
        color = go.BLACK if (color[0].lower() == 'b') else go.WHITE
        if move.lower() == 'pass':
            self.gamestate.make_move(color, -1, -1)
        else:
            row = int(move[1:])
            col = 1 + board_letters.index(move[0].lower())
            self.gamestate.make_move(color, row, col)

    def genmove(self, color):
        self.gamestate.rewind()
        # play game to end
        for idx in range(self.gamestate.gamelen()):
            self.gamestate.next_move()

        self.gamestate.set_to_play(go.BLACK if (color[0].lower() == 'b') else go.WHITE)

        features = np.zeros((NUM_FEATURES, 19, 19), dtype=np.uint8)
        offset = range(NUM_FEATURES + 1).__iter__()

        def next_feature(val):
            features[next(offset), ...] = val

        get_current_features(self.gamestate, next_feature)

        predictions = self.predictor.predict(features).ravel()
        predictions_board = predictions[:361].reshape((19, 19))

        # mask to legal moves - will modify predictions as well
        legal = features[-1, ...]
        # print(legal.shape, features.shape, predictions_board)
        predictions_board[legal == 0] = 0

        # apply temperature
        probs = np.exp(predictions - predictions.max())  # pin most likely prediction to 1.0
        probs **= 0.9  # slightly warm temp ==> more random behavior
        probs /= probs.sum()

        # choose a random legal move
        move = np.random.choice(362, p=probs)
        if move == 361:
            return 'pass'
        else:
            row = move // 19 + 1
            col = move % 19 + 1
            return "{:d} {:d}".format(col, row)
