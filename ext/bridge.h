#ifndef SERVER_H
#define SERVER_H

#include "common.h"

void origen_set_period(char*);
PLI_INT32 origen_wait_for_msg(p_cb_data);
void origen_define_waveforms(char *);

#endif
