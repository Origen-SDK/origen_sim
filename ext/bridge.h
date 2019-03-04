#ifndef SERVER_H
#define SERVER_H

#include "common.h"

PLI_INT32 bridge_wait_for_msg(p_cb_data);
PLI_INT32 bridge_init(void);
PLI_INT32 bridge_on_error(PLI_BYTE8*);
PLI_INT32 bridge_on_miscompare(PLI_BYTE8*);
void bridge_register_system_tasks(void);

#endif
