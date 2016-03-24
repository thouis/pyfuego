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
#include "GoEyeUtil.h"

#define NEXT SgNode::NEXT

void fuego_init()
{
    SgInit();
    GoInit();
}

static GoBoardUpdater updater;

GoGame *read_game(char *gamefile, GoBoard *board)
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

    board->Init(game->Board().Size(), game->Board().Rules());
    updater.Update(root, *board);

    return game;
}

void print_board(const GoBoard &board)
{
    GoWriteBoard(std::cout, board);
}

