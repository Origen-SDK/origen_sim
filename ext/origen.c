#include "origen.h"
#include "server.h"

static void origen_init() {
  origen_register_callback(cbStartOfSimulation, origen_startup);

  origen_register_callback(cbEndOfSimulation, origen_shutdown);
}

PLI_INT32 origen_startup(p_cb_data aCallback) {
  vpi_printf("Simulation starting!\n");
  // Start the server to listen for commands from an Origen application and apply them via VPI,
  // this will run until it receives a complete message from the Origen app
  origen_wait_for_set_timeset();
  
  return 0;
}

PLI_INT32 origen_shutdown(p_cb_data aCallback) {
  vpi_printf("Simulation ended!\n");

  return 0;
}


///
/// Registers a very basic VPI callback with reason and handler.
///
static void origen_register_callback(PLI_INT32 aReason, PLI_INT32 (*aHandler)(p_cb_data))
{
    s_cb_data call;

    call.reason    = aReason;
    call.cb_rtn    = aHandler;
    call.obj       = 0;
    call.time      = 0;
    call.value     = 0;
    call.user_data = 0;

    vpi_free_object(vpi_register_cb(&call));
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
