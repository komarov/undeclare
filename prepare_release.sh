#!/bin/bash

rm -R release/*
cp -R develop/* release/
find develop/ -name "*.pm" -print | sed 's/develop\///' | perl -ne 'chomp;`/path_to_undeclare/undeclare.pl < develop/$_ > release/$_`; print "$_ completed\n"'
