#ifndef SERVER_H
#define SERVER_H

#include "common.h"

void bridge_set_period(char*);
PLI_INT32 bridge_wait_for_msg(p_cb_data);
PLI_INT32 bridge_init_done(p_cb_data data);
void bridge_define_waveforms(char *);
void bridge_init(void);

#endif
