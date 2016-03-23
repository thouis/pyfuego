#cython: language=c++

import numpy as np
cimport numpy as np

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
    ctypedef int SgBlackWhite

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
        int InAtari(SgPoint)
        int NumStones(SgPoint)
        int NuCapturedStones()
        void NeighborBlocks(SgPoint, SgBlackWhite, int, SgPoint [])
        SgBlackWhite ToPlay()
        void Undo()

    # constants
    int SG_EMPTY
    int SG_BLACK
    int SG_WHITE
    int SG_ENDPOINT
    int NEXT

    void fuego_init()
    GoGame *read_game(char *gamefile)
    void print_board(const GoBoard &)

    int SgOppBW(int)
    int SgIsSpecialMove(int)


EMPTY = SG_EMPTY
BLACK = SG_BLACK
WHITE = SG_WHITE

cdef extern from "fuego.cpp" namespace "SgPointUtil":
    SgPoint Pt(int col, int row)
    int Row(SgPoint)
    int Col(SgPoint)

cdef extern from "fuego.cpp" namespace "GoLadderUtil":
    int IsLadderCaptureMove(const GoBoard &, SgPoint, SgPoint)
    int IsLadderEscapeMove(const GoBoard &, SgPoint, SgPoint)

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
        '''number of liberties of each group on the board'''
        cdef:
            int row, col
            SgPoint pt

        assert counts.shape[0] == self.board.Size()
        assert counts.shape[1] == self.board.Size()

        for row in range(counts.shape[0]):
            for col in range(counts.shape[1]):
                pt = Pt(col + 1, row + 1)
                if self.board.IsEmpty(pt):
                    counts[row, col] = 0
                else:
                    counts[row, col] = self.board.NumLiberties(pt)

    cpdef stone_age(self, np.int32_t[:, :] age):
        '''How long ago stones were played'''
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

    cpdef captures_liberties_selfatari_by_play(self,
                                               np.int32_t[:, :] captures,
                                               np.int32_t[:, :] liberties,
                                               np.int32_t[:, :] selfatari):
        '''Capture size after move, liberties after move, and number of stones placed in selfatari'''
        cdef:
            int row, col, libs
            SgPoint pt

        assert captures.shape[0] == self.board.Size()
        assert captures.shape[1] == self.board.Size()
        assert liberties.shape[0] == self.board.Size()
        assert liberties.shape[1] == self.board.Size()
        assert selfatari.shape[0] == self.board.Size()
        assert selfatari.shape[1] == self.board.Size()

        for row in range(captures.shape[0]):
            for col in range(captures.shape[1]):
                pt = Pt(col + 1, row + 1)
                if self.board.IsLegal(pt):
                    self.board.Play(pt)
                    captures[row, col] = self.board.NuCapturedStones()
                    libs = self.board.NumLiberties(pt)
                    liberties[row, col] = libs
                    if libs == 1:
                        selfatari[row, col] = self.board.NumStones(pt)
                    else:
                        selfatari[row, col] = 0
                    self.board.Undo()

    cpdef ladder_capture_escape(self,
                                np.int32_t[:, :] ladder_capture,
                                np.int32_t[:, :] ladder_escape):
        '''Moves which are ladder captures and ladder escapes (as defined by Fuego).'''
        cdef:
            int row, col, idx
            SgPoint pt
            SgPoint neighbors[5]

        assert ladder_capture.shape[0] == self.board.Size()
        assert ladder_capture.shape[1] == self.board.Size()
        assert ladder_escape.shape[0] == self.board.Size()
        assert ladder_escape.shape[1] == self.board.Size()

        for row in range(ladder_capture.shape[0]):
            for col in range(ladder_capture.shape[1]):
                ladder_escape[row, col] = 0
                ladder_capture[row, col] = 0

                pt = Pt(col + 1, row + 1)
                if self.board.IsLegal(pt):
                    # check for prey stones of the opposite color, with 2 or fewer liberties
                    self.board.NeighborBlocks(pt, SgOppBW(self.board.ToPlay()), 2, neighbors)
                    idx = 0
                    while neighbors[idx] != SG_ENDPOINT:
                        if (self.board.NumLiberties(neighbors[idx]) == 2) and IsLadderCaptureMove(dereference(self.board), neighbors[idx], pt):
                            ladder_capture[row, col] = 1
                            break
                        idx += 1

                    # check for ladder escapes
                    self.board.NeighborBlocks(pt, self.board.ToPlay(), 1, neighbors)
                    idx = 0
                    while neighbors[idx] != SG_ENDPOINT:
                        if IsLadderEscapeMove(dereference(self.board), neighbors[idx], pt):
                            ladder_escape[row, col] = 1
                            break
                        idx += 1

fuego_init()
