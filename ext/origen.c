///
/// This is the top-level file for compilation, it basically deals with bootstrapping
/// this extension into the simulation
///
#include "origen.h"
#include "bridge.h"
#include "client.h"

static void origen_register_callback(PLI_INT32 aReason, PLI_INT32 (*aHandler)(p_cb_data));
static void origen_init(void);

static void origen_init() {
  origen_register_callback(cbStartOfSimulation, origen_startup);

  origen_register_callback(cbEndOfSimulation, origen_shutdown);
}


/// Returns the value of the given argument, or NULL if not supplied
///   origen_get_arg("-socket");   # => "/tmp/sim.sock"
char * origen_get_arg(char *arg) {
  s_vpi_vlog_info info;
  vpi_get_vlog_info(&info);
  
  for (PLI_INT32 i = 0; i < info.argc; i++) {
    if (strcmp(info.argv[i], arg) == 0) {
      return info.argv[i + 1];
    }
  }
  return NULL;
}


/// Called at the beginning of the simulation, this connects to the Origen application and then
/// enters the main process loop
PLI_INT32 origen_startup(p_cb_data data) {
  UNUSED(data);
  vpi_printf("Simulation started!\n");

  int err = origen_connect(origen_get_arg("-socket"));

  if (err) {
    vpi_printf("ERROR: Couldn't connect to Origen app!\n");
    return err;
  }

  // Start the server to listen for commands from an Origen application and apply them via VPI,
  // this will run until it receives a complete message from the Origen app
  origen_define_waveforms("1%clock%0%D%50%0%END");
  origen_wait_for_msg(NULL);
  
  return 0;
}


PLI_INT32 origen_shutdown(p_cb_data data) {
  UNUSED(data);
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
void (*vlog_startup_routines[])(void) = { origen_init, 0 };

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
