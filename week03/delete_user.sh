#!/bin/bash
for i in {6..20}
do
    userdel -r "student$i"
done
