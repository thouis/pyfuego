#cython: language=c++
#cython: wraparound=False,boundscheck=False,initializedcheck=False

import numpy as np
cimport numpy as np
cimport cython

from cython.operator import dereference

from libcpp.string cimport string

# External functions, from Fuego and fuego.cpp
cdef extern from "fuego.cpp":
    cdef cppclass GoGame:
        GoBoard &Board() const
        int CurrentMove()
        int EndOfGame() const
        int CanGoInDirection(int dir)
        void GoInDirection(int dir)
        void GoToNode(SgNode *)
        const SgNode &Root()
        void AddMove(int, int)
        void SetToPlay(int)
        const SgNode *CurrentNode()

    cdef cppclass SgNode:
        int HasProp(int)
        int GetStringProp(int, string *)
        int NodePlayer()

    ctypedef int SgPoint
    ctypedef int SgBlackWhite

    cdef cppclass GoRules:
        pass

    cdef cppclass GoBoard:
        GoBoard(int)
        void Init(int, const GoRules &rules)
        int Size() nogil
        GoRules &Rules()
        SgBlackWhite ToPlay() nogil
        int GetColor(SgPoint) nogil
        int NumLiberties(SgPoint) nogil
        int IsEmpty(SgPoint) nogil
        int IsLegal(SgPoint) nogil
        void Play(SgPoint) nogil
        void Play(SgPoint, int) nogil
        int InAtari(SgPoint) nogil
        int NumStones(SgPoint) nogil
        int NuCapturedStones() nogil
        void NeighborBlocks(SgPoint, SgBlackWhite, int, SgPoint []) nogil
        void Undo() nogil
        void SetToPlay(int)

    # constants
    int SG_EMPTY
    int SG_BLACK
    int SG_WHITE
    int SG_ENDPOINT
    int SG_PASS
    int NEXT, PREV
    int SG_PROP_RANK_BLACK, SG_PROP_RANK_WHITE

    void fuego_init()
    GoGame *read_game(char *gamefile, GoBoard *b)
    void print_board(const GoBoard &)
    void print_game(const GoGame &)

    int SgOppBW(int) nogil
    int SgIsSpecialMove(int)

cdef extern from "fuego.cpp" namespace "SgPointUtil":
    SgPoint Pt(int col, int row) nogil
    int Row(SgPoint) nogil
    int Col(SgPoint) nogil

cdef extern from "fuego.cpp" namespace "GoLadderUtil":
    int IsLadderCaptureMove(const GoBoard &, SgPoint, SgPoint) nogil
    int IsLadderEscapeMove(const GoBoard &, SgPoint, SgPoint) nogil

cdef extern from "fuego.cpp" namespace "GoEyeUtil":
    int IsSinglePointEye2(const GoBoard &, SgPoint, SgBlackWhite) nogil

# called on module import
if SG_PROP_RANK_BLACK == 0:
    fuego_init()

# these have to come after the initp
EMPTY = SG_EMPTY
BLACK = SG_BLACK
WHITE = SG_WHITE
BLACK_RANK = SG_PROP_RANK_BLACK
WHITE_RANK = SG_PROP_RANK_WHITE


cpdef opposite(color):
   return BLACK if (color == WHITE) else WHITE

# Wrapper for an SGF game
cdef class PyGoGame:
    cdef GoGame *game
    cdef GoBoard *board
    cdef np.int32_t[:, :] __stone_age
    cdef int game_len
    cpdef int movenumber
    cpdef int invalid

    def __cinit__(self, char *gamefile):
        # we need our own copy of the board for checking captures, etc.
        self.board = new GoBoard(19)
        if gamefile[0] != 0:
            self.game = read_game(gamefile, self.board)
        else:
            self.game = new GoGame()
        self.movenumber = 0
        self.invalid = 0

    def __dealloc__(self):
        del self.game
        del self.board

    def __init__(self, gamefile):
        # set up memory for stone age
        self.__stone_age = np.zeros((self.game.Board().Size(), self.game.Board().Size()), dtype=np.int32)
        self.game_len = 0
        while self.game.CanGoInDirection(NEXT):
            self.game.GoInDirection(NEXT)
            self.game_len += 1
        self.game.GoToNode(& self.game.Root())

    def print_board(self):
       print_board(dereference(self.board))

    def at_end(self):
        return (self.invalid
                or self.game.EndOfGame()
                or (not self.game.CanGoInDirection(NEXT)))

    cpdef get_ranks(self):
        cdef:
           string br, wr
           bytes black_rank, white_rank

        black_rank = white_rank = "".encode()
        if self.game.Root().HasProp(BLACK_RANK):
            self.game.Root().GetStringProp(BLACK_RANK, &br)
            black_rank = br
        if self.game.Root().HasProp(WHITE_RANK):
            self.game.Root().GetStringProp(WHITE_RANK, &wr)
            white_rank = wr
        return black_rank.decode('ascii'), white_rank.decode('ascii')

    cpdef gamelen(self):
        return self.game_len

    cpdef current_move(self):
        cdef int move = SG_PASS
        if self.game.CanGoInDirection(NEXT):
            self.game.GoInDirection(NEXT)
            move = self.game.CurrentMove()
            self.game.GoInDirection(PREV)
        if SgIsSpecialMove(move):
            return (-1, -1)
        return (Row(move) - 1, Col(move) - 1)

    cpdef next_move(self):
        cdef int row, col, move
        if self.game.CanGoInDirection(NEXT):
            self.game.GoInDirection(NEXT)

            move = self.game.CurrentMove()
            # deal with bad SGFs by setting an invalid flag
            if not self.board.IsLegal(move):
                self.invalid = 1
                return

            # update our copy of the board
            self.board.Play(move, self.game.CurrentNode().NodePlayer())

            # update stone age array
            self.movenumber += 1
            if not SgIsSpecialMove(move):
                col = Col(move)
                row = Row(move)
                self.__stone_age[row - 1, col - 1] = self.movenumber

    cpdef current_player(self):
        return self.board.ToPlay()

    cpdef black_white_empty(self, np.int32_t[:, :] bwe):
        ''' sets each value to EMPTY, BLACK, or WHITE '''
        cdef:
            int row, col
            SgPoint p

        with nogil:
            for row in range(bwe.shape[0]):
                for col in range(bwe.shape[1]):
                    p = Pt(col + 1, row + 1)
                    bwe[row, col] = self.board.GetColor(p)

    cpdef liberties(self, np.int32_t[:, :] counts):
        '''number of liberties of each group on the board'''
        cdef:
            int row, col
            SgPoint pt

        with nogil:
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

        with nogil:
            for row in range(age.shape[0]):
                for col in range(age.shape[1]):
                    pt = Pt(col + 1, row + 1)
                    if self.board.IsEmpty(pt):
                        age[row, col] = 0
                    else:
                        age[row, col] = self.movenumber - self.__stone_age[row, col] + 1

    cpdef captures_liberties_selfatari_by_play(self,
                                               np.int32_t[:, :] captures,
                                               np.int32_t[:, :] liberties,
                                               np.int32_t[:, :] selfatari):
        '''Capture size after move, liberties after move, and number of stones placed in selfatari'''
        cdef:
            int row, col, libs
            SgPoint pt

        with nogil:
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
                    else:
                        captures[row, col] = liberties[row, col] = selfatari[row, col] = 0

    cpdef ladder_capture_escape(self,
                                np.int32_t[:, :] ladder_capture,
                                np.int32_t[:, :] ladder_escape):
        '''Moves which are ladder captures and ladder escapes (as defined by Fuego).'''
        cdef:
            int row, col, idx
            SgPoint pt
            SgPoint neighbors[5]

        with nogil:
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

    cpdef sensibleness(self,
                       np.int32_t[:, :] sensible):
        '''Moves which don't fill our own eyes.'''
        cdef:
            int row, col, idx
            SgPoint pt

        with nogil:
            for row in range(sensible.shape[0]):
                for col in range(sensible.shape[1]):
                    pt = Pt(col + 1, row + 1)
                    if self.board.IsLegal(pt):
                        sensible[row, col] = not IsSinglePointEye2(dereference(self.board), pt, self.board.ToPlay())
                    else:
                        sensible[row, col] = 0

    cpdef legal(self, np.int32_t[:, :] legal):
        '''Moves which are legal.'''
        cdef:
            int row, col, idx
            SgPoint pt

        with nogil:
            for row in range(legal.shape[0]):
                for col in range(legal.shape[1]):
                    pt = Pt(col + 1, row + 1)
                    legal[row, col] = 1 if self.board.IsLegal(pt) else 0

    cpdef make_move(self, int color, int row, int col):
        cdef:
            int move
        move = Pt(col, row) if (row > 0) else SG_PASS
        self.game.AddMove(move, color)
        self.game_len += 1

    def rewind(self):
        self.game.GoToNode(& self.game.Root())
        self.board.Init(self.game.Board().Size(),
                        self.game.Board().Rules())
        self.board.SetToPlay(self.game.Board().ToPlay())

    cpdef set_to_play(self, int to_play):
        self.game.SetToPlay(to_play)
        self.board.SetToPlay(to_play)
