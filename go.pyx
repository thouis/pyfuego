cimport numpy as np
import numpy as np

from libcpp.string cimport string

cdef extern from "fuego.cpp":
    cdef cppclass GoGame:
        GoBoard &Board() const
        int EndOfGame() const
        int CanGoInDirection(int dir)
        void GoInDirection(int dir)

    cdef cppclass SgPoint:
        pass

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

    GoGame *read_game(char *gamefile)
    void print_board(const GoBoard &)
    void fuego_init()

EMPTY = SG_EMPTY
BLACK = SG_BLACK
WHITE = SG_WHITE

cdef extern from "fuego.cpp" namespace "SgPointUtil":
    SgPoint Pt(int, int)


cdef class PyGoGame:
    cdef GoGame *thisgame
    def __cinit__(self, char *gamefile):
        self.thisgame = read_game(gamefile)
    def __dealloc__(self):
        del self.thisgame
    def print_board(self):
       print_board(self.thisgame.Board())
    def at_end(self):
        return self.thisgame.EndOfGame() or (not self.thisgame.CanGoInDirection(NEXT))
    def next_move(self):
        if self.thisgame.CanGoInDirection(NEXT):
            self.thisgame.GoInDirection(NEXT)

    cpdef black_white_empty(self, np.int32_t[:, :] bwe):
        ''' sets each value to EMPTY, BLACK, or WHITE '''
        cdef:
            int i, j, c

        assert bwe.shape[0] == self.thisgame.Board().Size()
        assert bwe.shape[1] == self.thisgame.Board().Size()

        for i in range(bwe.shape[0]):
            for j in range(bwe.shape[1]):
                bwe[i, j] = self.thisgame.Board().GetColor(Pt(i + 1, j + 1))

    cpdef liberties(self, np.int32_t[:, :] counts):
        cdef:
            int i, j

        assert counts.shape[0] == self.thisgame.Board().Size()
        assert counts.shape[1] == self.thisgame.Board().Size()

        for i in range(counts.shape[0]):
            for j in range(counts.shape[1]):
                if self.thisgame.Board().IsEmpty(Pt(i + 1, j + 1)):
                    counts[i, j] = 0
                else:
                    counts[i, j] = self.thisgame.Board().NumLiberties(Pt(i + 1, j + 1))

fuego_init()
