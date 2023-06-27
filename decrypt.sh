#!/bin/bash

OUTNAME=$(basename $1 .enc).json
openssl enc -aes-256-cbc -pbkdf2 -iter 1000000 -d -nopad -in $1 -out $OUTNAME
