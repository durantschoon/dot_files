#! /usr/bin/env bash

echo -n "Are you setting up dot files for HOME or WORK [h|w]? "

read -r answer

[[ "$answer" = h* ]] && touch ~/.HOME && echo "See ~/.aliases for the use of this file" >> ~/.HOME && echo You are now set up for HOME && exit 0
[[ "$answer" = w* ]] && touch ~/.WORK && echo "See ~/.aliases for the use of this file" >> ~/.WORK && echo You are now set up for WORK && exit 0

echo Did not understand your answer && exit 1