#ifndef ORIGEN_H
#define ORIGEN_H

#include "vpi_user.h"

static void origen_init();
PLI_INT32 origen_startup(p_cb_data);
PLI_INT32 origen_shutdown(p_cb_data);
static void origen_register_callback(PLI_INT32 aReason, PLI_INT32 (*aHandler)(p_cb_data));

#endif
