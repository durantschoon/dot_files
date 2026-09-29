#! /usr/bin/env bash

# my ./aliases will check for the existence of a ~/.HOME or ~/.WORK file to determine which aliases to load

file_msg="See ~/.aliases for the use of this file"

# Idempotent: a marker file already present means this was answered before.
[[ -e ~/.HOME ]] && echo "Already set up for HOME (~/.HOME exists)" && exit 0
[[ -e ~/.WORK ]] && echo "Already set up for WORK (~/.WORK exists)" && exit 0

echo -n "Are you setting up dot files for HOME or WORK [h|w]? "

read -r answer

[[ "$answer" = h* ]] && echo "$file_msg" > ~/.HOME && echo You are now set up for HOME && exit 0
[[ "$answer" = w* ]] && echo "$file_msg" > ~/.WORK && echo You are now set up for WORK && exit 0

echo Did not understand your answer && exit 1
