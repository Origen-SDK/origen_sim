#ifndef SERVER_H
#define SERVER_H

#include "vpi_user.h"

#define NULL 0

void origen_set_timeset(int);
PLI_INT32 origen_wait_for_msg(p_cb_data);

#endif
