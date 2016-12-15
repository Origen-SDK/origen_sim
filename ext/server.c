#include "server.h"
#include <stdint.h>

static int period_in_ns;
static int x = 0;
static void origen_cycle();

/// This is called first upon a simulation start and it will block until it receives
/// a set_timeset message from Origen
void origen_wait_for_set_timeset() {

  period_in_ns = 100;

  origen_wait_for_cycle(NULL);
}


/// Waits and responds to instructions from Origen (to set pin states).
/// When Origen requests a cycle, time will be advanced and this func will be called again.
PLI_INT32 origen_wait_for_cycle(p_cb_data data) {
  s_vpi_value v = {vpiIntVal, {0}};

  vpiHandle reset;
  reset = vpi_handle_by_name("tb.reset", NULL);

  vpiHandle clock;
  clock = vpi_handle_by_name("tb.clock", NULL);

  if (x < 10) {
    v.value.integer = 1;
  } else {
    v.value.integer = 0;
  }
  vpi_put_value(reset, &v, NULL, vpiNoDelay);

  if (x % 2) {
    v.value.integer = 1;
  } else {
    v.value.integer = 0;
  }
  vpi_put_value(clock, &v, NULL, vpiNoDelay);

  // Run the simulation for 100 cycles
  if (x < 100) {
    x += 1;
    origen_cycle();
  }
  return 0;
}


/// Advances time by 1 cycle, at which point origen_wait_for_cycle will be called again
static void origen_cycle() {
    s_cb_data call;
    s_vpi_time time;

    time.type = vpiSimTime;
    time.high = (uint32_t)(0);
    time.low  = (uint32_t)(period_in_ns);

    call.reason    = cbAfterDelay;
    call.cb_rtn    = origen_wait_for_cycle;
    call.obj       = 0;
    call.time      = &time;
    call.value     = 0;
    call.user_data = 0;

    vpi_free_object(vpi_register_cb(&call));
}
