cimport numpy as np
import numpy as np

from libcpp.string cimport string


cdef extern from "fuego.cpp":
    cdef cppclass GoGame:
        GoBoard &Board() const
        int CurrentMoveNumber()
        int CurrentMove()
        int EndOfGame() const
        int CanGoInDirection(int dir)
        void GoInDirection(int dir)

    ctypedef int SgPoint

    cdef cppclass GoBoard:
        int Size()
        int GetColor(SgPoint)
        int NumLiberties(SgPoint)
        int IsEmpty(SgPoint)

    # constants
    int SG_EMPTY
    int SG_BLACK
    int SG_WHITE
    int NEXT

    void fuego_init()
    GoGame *read_game(char *gamefile)
    void print_board(const GoBoard &)

    int SgIsSpecialMove(int)

EMPTY = SG_EMPTY
BLACK = SG_BLACK
WHITE = SG_WHITE

cdef extern from "fuego.cpp" namespace "SgPointUtil":
    SgPoint Pt(int col, int row)
    int Row(SgPoint)
    int Col(SgPoint)


cdef class PyGoGame:
    cdef GoGame *thisgame
    cdef np.int32_t[:, :] __stone_age

    def __cinit__(self, char *gamefile):
        self.thisgame = read_game(gamefile)
    def __dealloc__(self):
        del self.thisgame

    def __init__(self, gamefile):
        # set up memory for stone age
        self.__stone_age = np.zeros((self.thisgame.Board().Size(), self.thisgame.Board().Size()), dtype=np.int32)

    def print_board(self):
       print_board(self.thisgame.Board())

    def at_end(self):
        return self.thisgame.EndOfGame() or (not self.thisgame.CanGoInDirection(NEXT))

    cpdef next_move(self):
        cdef int last_move
        if self.thisgame.CanGoInDirection(NEXT):
            self.thisgame.GoInDirection(NEXT)

            # update stone age array
            last_move = self.thisgame.CurrentMove()
            if not SgIsSpecialMove(last_move):
                col = Col(last_move)
                row = Row(last_move)
                self.__stone_age[row - 1, col - 1] = self.thisgame.CurrentMoveNumber()

    cpdef black_white_empty(self, np.int32_t[:, :] bwe):
        ''' sets each value to EMPTY, BLACK, or WHITE '''
        cdef:
            int row, col, c

        assert bwe.shape[0] == self.thisgame.Board().Size()
        assert bwe.shape[1] == self.thisgame.Board().Size()

        for row in range(bwe.shape[0]):
            for col in range(bwe.shape[1]):
                bwe[row, col] = self.thisgame.Board().GetColor(Pt(col + 1, row + 1))

    cpdef liberties(self, np.int32_t[:, :] counts):
        cdef:
            int row, col

        assert counts.shape[0] == self.thisgame.Board().Size()
        assert counts.shape[1] == self.thisgame.Board().Size()

        for row in range(counts.shape[0]):
            for col in range(counts.shape[1]):
                if self.thisgame.Board().IsEmpty(Pt(col + 1, row + 1)):
                    counts[row, col] = 0
                else:
                    counts[row, col] = self.thisgame.Board().NumLiberties(Pt(col + 1, row + 1))

    cpdef stone_age(self, np.in32_t[:, :] age):
        age[...] = self.__stone_age[...]

    cpdef num_captured_by_play(self, np.in32_t[:, :] num):
        cdef:
            int i, j

        assert counts.shape[0] == self.thisgame.Board().Size()
        assert counts.shape[1] == self.thisgame.Board().Size()

        for i in range(counts.shape[0]):
            for j in range(counts.shape[1]):
                

fuego_init()
