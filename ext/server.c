#include "server.h"
#include "client.h"
#include <stdint.h>

static int period_in_ns;
static void origen_cycle();
static void origen_drive_pin(char *, int);

/// This is called first upon a simulation start and it will block until it receives
/// a set_timeset message from Origen
void origen_set_timeset(int p_in_ns) {
  period_in_ns = p_in_ns;
}

static void origen_drive_pin(char * name, int val) {
  s_vpi_value v = {vpiIntVal, {0}};
  vpiHandle pin;

  char * net = (char *) malloc(1 + strlen("tb.")+ strlen(name));
  strcpy(net, "tb.");
  strcat(net, name);

  pin = vpi_handle_by_name(net, NULL);
  v.value.integer = val;
  vpi_put_value(pin, &v, NULL, vpiNoDelay);
  free(net);
}


/// Waits and responds to instructions from Origen (to set pin states).
/// When Origen requests a cycle, time will be advanced and this func will be called again.
PLI_INT32 origen_wait_for_msg(p_cb_data data) {
  int max_msg_len = 100;
  char msg[max_msg_len];
  int err;
  char *opcode, *arg1, *arg2, *arg3;

  while(1) {

    err = origen_get(max_msg_len, msg);
    if (err) {
      return 1;
    }

    opcode = strtok(msg, ":");

    switch(*opcode) {
      // Set Period
      //   1:100
      case '1' :
        origen_set_timeset(100);
        break;
      // Drive Pin
      //   2:clock:0
      //   2:clock:1
      case '2' :
        arg1 = strtok(NULL, ":");
        arg2 = strtok(NULL, ":");
        origen_drive_pin(arg1, arg2[0] - '0');
        break;
      // Cycle
      //   3:
      case '3' :
        origen_cycle();
        return 0;
      // Complete
      //   Z:
      case 'Z' :
        return 0;
      default :
        vpi_printf("ERROR: Illegal opcode received!\n");
        return 1;
    }
  }
}


/// Advances time by 1 cycle, at which point origen_wait_for_cycle will be called again
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
