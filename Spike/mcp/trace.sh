#!/bin/sh
# usage: trace.sh <tracefile> <server binary>  — records raw stdio frames in both directions.
T="$1"; shift
tee -a "$T.in" | "$@" | tee -a "$T.out"
