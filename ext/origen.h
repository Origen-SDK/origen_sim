#ifndef ORIGEN_H
#define ORIGEN_H

#include "common.h"
#include "defines.h"

PLI_INT32 origen_startup(p_cb_data);
PLI_INT32 origen_shutdown(p_cb_data);
#ifdef ORIGEN_VCS
PLI_INT32 origen_vcs_init(PLI_BYTE8*);
#endif
PLI_INT32 origen_init(p_cb_data);
PLI_INT32 bootstrap(p_cb_data);

#endif
