#!/bin/bash
# 반복문 시작
for i in {1..5}
do
 sudo usermod -aG dev_team1 "student$i"
 echo "student$i 를 dev_team1에 추가 완료"
done
echo "모든 작업이 완료되었습니다."
