#include <stdio.h>
#include <unistd.h>

int main() {
    pid_t pid = fork();

    if (pid == 0) {
        // 자식 프로세스
        printf("자식 PID %d: 3초 후 종료합니다\n", getpid());
        sleep(3);
        printf("자식 종료\n");
        _exit(0);

    } else if (pid > 0) {
        // 부모 프로세스
        printf("부모 PID %d: 자식 %d 생성함\n", getpid(), pid);
        printf("부모는 wait() 하지 않고 무한 대기 중...\n");

        while (1) {
            sleep(1);
        }

    } else {
        perror("fork 실패");
        return 1;
    }

    return 0;
}