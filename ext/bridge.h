#ifndef SERVER_H
#define SERVER_H

#include "common.h"

PLI_INT32 bridge_wait_for_msg(p_cb_data);
PLI_INT32 bridge_init_done(p_cb_data data);
void bridge_init(void);

#endif
