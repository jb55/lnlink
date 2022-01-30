//
//  lightninglink.c
//  lightninglink
//
//  Created by William Casarin on 2022-01-07.
//

#include "lightninglink.h"
#include <sys/select.h>


void fd_do_set(int socket, fd_set *set) {
    FD_SET(socket, set);
}

void fd_do_zero(fd_set *set) {
    FD_ZERO(set);
}
