#include <iostream>
#include <fstream>

#include "SgInit.h"
#include "SgSystem.h"
#include "SgGameReader.h"
#include "SgNode.h"
#include "SgPoint.h"

#include "GoInit.h"
#include "GoGame.h"
#include "GoNodeUtil.h"
#include "GoLadder.h"

#define NEXT SgNode::NEXT

void fuego_init()
{
    SgInit();
    GoInit();
}

GoGame *read_game(char *gamefile)
{
    std::ifstream in(gamefile);
    SgGameReader reader(in);
    SgNode *root = reader.ReadGame();
    GoGame *game = new GoGame();
    game->Init(root);
    GoRules rules;
    rules.SetKomi(GoNodeUtil::GetKomi(game->CurrentNode()));
    rules.SetHandicap(GoNodeUtil::GetHandicap(game->CurrentNode()));
    game->SetRulesGlobal(rules);
    return game;
}

void print_board(const GoBoard &board)
{
    GoWriteBoard(std::cout, board);
}

