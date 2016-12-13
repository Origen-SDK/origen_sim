#include "vpi_user.h"


static void origen_init() {
  vpi_printf("Yo, we are live!!\n");
}


///
/// Bootstrap vector, make the simulator execute origen_init() on startup
///
void (*vlog_startup_routines[])() = { origen_init, 0 };

#if defined(CVER) || defined(VCS) || defined(NCSIM)
    void vlog_startup_routines_bootstrap()
    {
        unsigned int i;
        for (i = 0; vlog_startup_routines[i]; i++)
        {
            vlog_startup_routines[i]();
        }
    }
#endif
