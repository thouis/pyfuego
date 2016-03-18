import pyximport
pyximport.install()

import sys

import go
go.load_and_print(sys.argv[1])
