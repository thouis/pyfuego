cimport numpy as np
import numpy as np

from cython.operator import dereference

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

    cdef cppclass GoRules:
        pass

    cdef cppclass GoBoard:
        GoBoard(int)
        void Init(int, const GoRules &rules)
        int Size()
        GoRules &Rules()
        int GetColor(SgPoint)
        int NumLiberties(SgPoint)
        int IsEmpty(SgPoint)
        int IsLegal(SgPoint)
        void Play(SgPoint)
        int NuCapturedStones()
        void Undo()

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
    cdef GoGame *game
    cdef GoBoard *board
    cdef np.int32_t[:, :] __stone_age

    def __cinit__(self, char *gamefile):
        self.game = read_game(gamefile)
        self.board = new GoBoard(self.game.Board().Size())
        # we need our own copy of the board for checking captures, etc.
        self.board.Init(self.game.Board().Size(), self.game.Board().Rules())

    def __dealloc__(self):
        del self.game
        del self.board

    def __init__(self, gamefile):
        # set up memory for stone age
        self.__stone_age = np.zeros((self.game.Board().Size(), self.game.Board().Size()), dtype=np.int32)

    def print_board(self):
       print_board(dereference(self.board))

    def at_end(self):
        return self.game.EndOfGame() or (not self.game.CanGoInDirection(NEXT))

    cpdef next_move(self):
        cdef int row, col, move
        if self.game.CanGoInDirection(NEXT):
            self.game.GoInDirection(NEXT)

            move = self.game.CurrentMove()

            # update our copy of the board
            self.board.Play(move)

            # update stone age array
            if not SgIsSpecialMove(move):
                col = Col(move)
                row = Row(move)
                self.__stone_age[row - 1, col - 1] = self.game.CurrentMoveNumber()

    cpdef black_white_empty(self, np.int32_t[:, :] bwe):
        ''' sets each value to EMPTY, BLACK, or WHITE '''
        cdef:
            int row, col, c

        assert bwe.shape[0] == self.board.Size()
        assert bwe.shape[1] == self.board.Size()

        for row in range(bwe.shape[0]):
            for col in range(bwe.shape[1]):
                bwe[row, col] = self.board.GetColor(Pt(col + 1, row + 1))

    cpdef liberties(self, np.int32_t[:, :] counts):
        cdef:
            int row, col

        assert counts.shape[0] == self.board.Size()
        assert counts.shape[1] == self.board.Size()

        for row in range(counts.shape[0]):
            for col in range(counts.shape[1]):
                if self.board.IsEmpty(Pt(col + 1, row + 1)):
                    counts[row, col] = 0
                else:
                    counts[row, col] = self.board.NumLiberties(Pt(col + 1, row + 1))

    cpdef stone_age(self, np.int32_t[:, :] age):
        cdef:
            int row, col
            SgPoint pt

        assert age.shape[0] == self.board.Size()
        assert age.shape[1] == self.board.Size()

        for row in range(age.shape[0]):
            for col in range(age.shape[1]):
                pt = Pt(col + 1, row + 1)
                if self.board.IsEmpty(pt):
                    age[row, col] = 0
                else:
                    age[row, col] = self.game.CurrentMoveNumber() - self.__stone_age[row, col] + 1

    cpdef num_captured_by_play(self, np.int32_t[:, :] counts):
        cdef:
            int row, col
            SgPoint pt

        assert counts.shape[0] == self.board.Size()
        assert counts.shape[1] == self.board.Size()

        for row in range(counts.shape[0]):
            for col in range(counts.shape[1]):
                # default = no capture
                counts[row, col] = 0

                pt = Pt(col + 1, row + 1)
                if self.board.IsLegal(pt):
                    self.board.Play(pt)
                    counts[row, col] = self.board.NuCapturedStones()
                    self.board.Undo()

fuego_init()
