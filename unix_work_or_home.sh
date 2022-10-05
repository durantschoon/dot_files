#! /usr/bin/env bash

# my ./aliases will check for the existence of a ~/.HOME or ~/.WORK file to determine which aliases to load

msg="See ~/.aliases for the use of this file"

echo -n "Are you setting up dot files for HOME or WORK [h|w]? "

read -r answer

[[ "$answer" = h* ]] && touch ~/.HOME && echo $msg >> ~/.HOME && echo You are now set up for HOME && exit 0
[[ "$answer" = w* ]] && touch ~/.WORK && echo $msg >> ~/.WORK && echo You are now set up for WORK && exit 0

echo Did not understand your answer && exit 1