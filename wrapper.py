#!/usr/bin/python -u
import sys

import player

def eprint(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)
    sys.stderr.flush()

# gtp coords are letters *** except I ***, number (from lower left)
board_letters = "abcdefghjklmnopqrstuvwxyz"
# note that sgf uses two letters from upper left, and includes I
sgf_letters = "abcdefghijklmnopqrstuvwxyz"


class Wrapper(object):
    def __init__(self, player):
        self.size = 19
        self.komi_val = 6.5
        self.player = player

    def boardsize(self, arg):
        self.size = int(arg)
        assert self.size == self.player.size()
        print("=")

    def clear_board(self):
        self.player.clear()
        print("=")

    def set_free_handicap(self, *args):
        for loc in args:
            self.player.move("B", loc)
        print("=")

    def komi(self, arg):
        self.komi_val = float(arg)
        print("=")

    def play(self, colorname, xy):
        c = "B" if colorname.lower().startswith('b') else "W"
        self.player.move(c, xy)
        print("=")

    def genmove(self, arg):
        result = self.player.genmove("B" if arg.lower().startswith('b') else "W")
        eprint("RECEIVED from genmove %s\n" % result)
        if result.strip() == "pass":
            print("= pass")
        elif result.strip() == "resign":
            print("= resign")
        else:
            x, y = result.strip().split(' ')
            tosend = "= %s%d" % (board_letters[int(x) - 1], int(y))
            eprint("SENDING " + tosend + "\n")
            print(tosend)
        sys.stdout.flush()

    def showboard(self):
        print("= ")

    def name(self):
        print("= Resnet32")

    def protocol_version(self):
        print("= 2")

    def version(self):
        print("= 0.1.12")

    def command_list(self):
        for s in ["boardsize",
                  "clear_board",
                  "genmove",
                  "list_commands",
                  "name",
                  "play",
                  "protocol_version",
                  "set_free_handicap",
                  "showboard",
                  "komi",
                  "version"]:
            print(s)

    def __call__(self, command_str):
        parts = command_str.split(" ")
        command = parts[0]
        args = parts[1:]
        eprint((command_str, command, args))
        if hasattr(self, command):
            getattr(self, command)(*args)
            print("")
        else:
            print("? Unknown command: %s" % command)
            sys.exit(0)


if __name__ == "__main__":
    wrapper = Wrapper(player.Player(sys.argv[1]))

    sys.stderr.write("STARTING WRAPPER\n")
    while True:
        l = sys.stdin.readline()
        sys.stderr.write("received command " + l)
        sys.stderr.flush()
        wrapper(l.strip())
