#!/usr/bin/env bash

# Function to detect the lib is loaded. Demo:
#   declare -F ls_linux_func_dummy >/dev/null || { LOAD BLOCK }
ls_linux_func_dummy() { :; }

# https://stackoverflow.com/a/2705678
escape_sed_expr()  { sed -e 's/[]\/$*.^[]/\\&/g' <<< "${1-$(cat)}"; }
escape_sed_repl()  { sed -e 's/[\/&]/\\&/g' <<< "${1-$(cat)}"; }
