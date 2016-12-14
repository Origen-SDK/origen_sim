#ifndef SERVER_H
#define SERVER_H

#include "vpi_user.h"

#define NULL 0

void origen_wait_for_set_timeset(void);
void origen_wait_for_cycle(void);
static void origen_cycle();

#endif
