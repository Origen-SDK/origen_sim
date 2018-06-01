///
/// This is the top-level file for compilation, it basically deals with bootstrapping
/// this extension into the simulation
///
#include "origen.h"
#include "bridge.h"
#include "client.h"
#include <string.h>

static void register_callback(PLI_INT32 aReason, PLI_INT32 (*aHandler)(p_cb_data));
static void init(void);

static void init() {
  register_callback(cbStartOfSimulation, origen_startup);

  register_callback(cbEndOfSimulation, origen_shutdown);
}


/// Returns the value of the given argument, or NULL if not supplied.
/// This example: 
///
///   get_arg("socket");   # => "/tmp/sim.sock"
///
/// Will work for the arguement passed in either of these formats:
///
///   -socket /tmp/sim.sock
///   +socket+/tmp/sim.sock
char * get_arg(char *arg) {
  s_vpi_vlog_info info;
  vpi_get_vlog_info(&info);
  char * pch;
  char * return_value;

  char * minus_arg = (char *) malloc(strlen(arg) + 16);
  strcpy(minus_arg, "-");
  strcat(minus_arg, arg);
  char * plus_arg = (char *) malloc(strlen(arg) + 16);
  strcpy(plus_arg, "+");
  strcat(plus_arg, arg);
  
  for (PLI_INT32 i = 0; i < info.argc; i++) {
    if (strcmp(info.argv[i], minus_arg) == 0) {
      return_value = info.argv[i + 1];
      goto DONE;
    }
    pch = strstr(info.argv[i], plus_arg);
    if (pch) {
      return_value = info.argv[i] + strlen(plus_arg) + 1;
      goto DONE;
    }
  }
  return_value = NULL;

  DONE: 
    free(minus_arg);
    free(plus_arg);
    return return_value;
}


/// Called at the beginning of the simulation, this connects to the Origen application and then
/// enters the main process loop
PLI_INT32 origen_startup(p_cb_data data) {
  UNUSED(data);
  //vpi_printf("Simulation started!\n");

  int err = client_connect(get_arg("socket"));

  if (err) {
    vpi_printf("ERROR: Couldn't connect to Origen app!\n");
    return err;
  }

  // Start the server to listen for commands from an Origen application and apply them via VPI,
  // this will run until it receives a complete message from the Origen app
  return bridge_init();
}


PLI_INT32 origen_shutdown(p_cb_data data) {
  UNUSED(data);
  //vpi_printf("Simulation ended!\n");

  return 0;
}

/// Function to call the init PLI's init function
/// Some toolchains will call this automatically, some will not
/// Available here for those which do not automatically call init() for each PLI 
PLI_INT32 bootstrap(p_cb_data data) {
  vpi_printf("Origen Bootstrap Called!\n");
  init();
  return 0;
}

///
/// Registers a very basic VPI callback with reason and handler.
///
static void register_callback(PLI_INT32 aReason, PLI_INT32 (*aHandler)(p_cb_data))
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
/// Bootstrap vector, make the simulator execute init() on startup
///
void (*vlog_startup_routines[])(void) = { init, 0 };
