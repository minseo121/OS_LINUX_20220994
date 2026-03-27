#!/bin/bash
for i in {1..20} # 반복문
do
 useradd -m -s /bin/bash "student$i" # 홈, bash쉘 지정
 echo "student$i:password!" | chpasswd
 # 보안 설정 추가: 첫 로그인 시 비번 변경 강제
 chage -d 0 "student$i"
done
