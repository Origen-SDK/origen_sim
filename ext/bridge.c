///
/// This implements the bridge between Origen and the simulation, it implements a
/// simple string-based message protocol for communicating between the two domains
///
#include "bridge.h"
#include "client.h"
#include <stdint.h>
#include <stdlib.h>

static int period_in_ns;
static void origen_cycle(void);
static void origen_drive_pin(char*, char*);
static void origen_drive_pin_in_future(char*, char*, int);

/// This is called first upon a simulation start and it will block until it receives
/// a set_timeset message from Origen
void origen_set_period(char * p_in_ns) {
  int p = (int) strtol(p_in_ns, NULL, 10);
  vpi_printf("Period: %d\n", p);
  period_in_ns = p;
}


/// Immediately drives the given pin to the given state
static void origen_drive_pin(char * name, char * val) {
  s_vpi_value v = {vpiIntVal, {0}};
  vpiHandle pin;

  char * net = (char *) malloc(4 + strlen(name));
  strcpy(net, "tb.");
  strcat(net, name);

  pin = vpi_handle_by_name(net, NULL);
  v.value.integer = val[0] - '0';
  vpi_put_value(pin, &v, NULL, vpiNoDelay);
  free(net);
}


/// Callback handler to implement origen_drive_pin_in_future
PLI_INT32 origen_drive_pin_cb(p_cb_data data) {
  char *pin, *value;
  pin = strtok(data->user_data, "%");
  value = strtok(NULL, "%");
  origen_drive_pin(pin, value);
  free(data->user_data);
  return 0;
}


/// Drives the given pin to the given state after the given delay
static void origen_drive_pin_in_future(char * name, char * val, int delay_in_ns) {
  s_cb_data call;
  s_vpi_time time;

  char * data = (char *) malloc(3 + strlen(name));
  strcpy(data, name);
  strcat(data, "%");
  strcat(data, val);

  time.type = vpiSimTime;
  time.high = (uint32_t)(0);
  time.low  = (uint32_t)(delay_in_ns);

  call.reason    = cbAfterDelay;
  call.cb_rtn    = origen_drive_pin_cb;
  call.obj       = 0;
  call.time      = &time;
  call.value     = 0;
  call.user_data = data;

  vpi_free_object(vpi_register_cb(&call));
}


/// Waits and responds to instructions from Origen (to set pin states).
/// When Origen requests a cycle, time will be advanced and this func will be called again.
PLI_INT32 origen_wait_for_msg(p_cb_data data) {
  UNUSED(data);
  int max_msg_len = 100;
  char msg[max_msg_len];
  int err;
  char *opcode, *arg1, *arg2;

  while(1) {

    err = origen_get(max_msg_len, msg);
    if (err) {
      vpi_printf("ERROR: Failed to receive from Origen!\n");
      return 1;
    }

    opcode = strtok(msg, "%");

    switch(*opcode) {
      // Set Period
      //   1%100
      case '1' :
        arg1 = strtok(NULL, "%");
        origen_set_period(arg1);
        break;
      // Drive Pin
      //   2%clock%0
      //   2%clock%1
      case '2' :
        arg1 = strtok(NULL, "%");
        arg2 = strtok(NULL, "%");
        origen_drive_pin(arg1, arg2);
        // Return clk to low half way through the cycle
        if (strcmp(arg1, "clock") == 0) {
          origen_drive_pin_in_future(arg1, "0", period_in_ns / 2);
        }
        break;
      // Cycle
      //   3%
      case '3' :
        origen_cycle();
        return 0;
      // Sync-up
      //   Y%
      case 'Y' :
        origen_put("OK!\n");
        break;
      // Complete
      //   Z%
      case 'Z' :
        return 0;
      default :
        vpi_printf("ERROR: Illegal opcode received!\n");
        return 1;
    }
  }
}


/// Registers a callback after a cycle period, the main server loop should unblock
/// after calling this to allow the simulation to proceed for a cycle
static void origen_cycle() {
  s_cb_data call;
  s_vpi_time time;

  time.type = vpiSimTime;
  time.high = (uint32_t)(0);
  time.low  = (uint32_t)(period_in_ns);

  call.reason    = cbAfterDelay;
  call.cb_rtn    = origen_wait_for_msg;
  call.obj       = 0;
  call.time      = &time;
  call.value     = 0;
  call.user_data = 0;

  vpi_free_object(vpi_register_cb(&call));
}
