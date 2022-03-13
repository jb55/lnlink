//
//  lightninglink.h
//  lightninglink
//
//  Created by William Casarin on 2022-01-07.
//

#ifndef lightninglink_h
#define lightninglink_h

#include "lnsocket.h"
#include "commando.h"
#include "bech32.h"

void fd_do_zero(fd_set *);
void fd_do_set(int, fd_set *);

#endif /* lightninglink_h */
