#ifndef SERVER_H
#define SERVER_H

#include "vpi_user.h"

#define NULL 0

void origen_wait_for_set_timeset(void);
PLI_INT32 origen_wait_for_cycle(p_cb_data);

#endif
