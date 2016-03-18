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
        int IsEmpty(SgPoint)
        int NumLiberties(SgPoint)
        pass


    int NEXT
    GoGame *read_game(char *gamefile)
    void print_board(const GoBoard &)
    void fuego_init()

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

    cpdef liberties(self, np.int32_t[:, :] counts):
        cdef:
            int i, j
        for i in range(19):
            for j in range(19):
                if self.thisgame.Board().IsEmpty(Pt(i + 1, j + 1)):
                    counts[i, j] = 0
                else:
                    counts[i, j] = self.thisgame.Board().NumLiberties(Pt(i + 1, j + 1))

fuego_init()
