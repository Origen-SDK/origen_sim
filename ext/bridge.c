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
static long repeat;

typedef struct Event {
  int time;
  char data;
} Event;

typedef struct Waveform {
  char * pin;
  Event events[10];
} Waveform;

static Waveform * waveforms = NULL;
static int number_of_waveforms = 0;

/// Example waveform message:
///   "2%clock%0%D%25%0%50%D%75%0%END%tck%0%D%50%0%END"
void origen_define_waveforms(char * waves) {
  char *token;

  if (waveforms) {
    // TODO: Should free the memory for the pin names first
    free(waveforms);
    number_of_waveforms = 0;
  }

  // strtok needs a writable copy of waves
  char * mywaves = (char *) malloc(strlen(waves) + 1);
  strcpy(mywaves, waves);

  // First in the stream is the amount of pins that have waveforms, get it and prepare
  // the space for them
  token = strtok(mywaves, "%");
  number_of_waveforms = (int)strtol(token, NULL, 10);
  waveforms = (Waveform *) malloc(number_of_waveforms * sizeof(Waveform));

  for (int i = 0; i < number_of_waveforms; i++) {
    token = strtok(NULL, "%");
    waveforms[i].pin = (char *) malloc(strlen(token) + 1);
    strcpy(waveforms[i].pin, token);

    int x = 0;
    token = strtok(NULL, "%");
    while (strcmp(token, "END") != 0) {
      waveforms[i].events[x].time = (int)strtol(token, NULL, 10);
      token = strtok(NULL, "%");
      waveforms[i].events[x].data = token[0];
      token = strtok(NULL, "%");
      x++;
    }
    waveforms[i].events[x].data = 'S'; // Indicate that there are no more events
  }
  free(mywaves);
}


void register_waveform_events() {
  if (waveforms) {
    for (int i = 0; i < number_of_waveforms; i++) {
      char * f0 = (char *) malloc(strlen(waveforms[i].pin) + 4);
      char * f1 = (char *) malloc(strlen(waveforms[i].pin) + 4);
      strcpy(f0, waveforms[i].pin);
      strcpy(f1, waveforms[i].pin);
      strcat(f0, "_f0");
      strcat(f1, "_f1");

      origen_drive_pin(f0, "0");
      origen_drive_pin(f1, "0");

      int x = 0;

      while (waveforms[i].events[x].data != 'S') {
        switch(waveforms[i].events[x].data) {
          case '0' :
            origen_drive_pin_in_future(f0, "1", waveforms[i].events[x].time);
            origen_drive_pin_in_future(f1, "0", waveforms[i].events[x].time);
            break;
          case '1' :
            origen_drive_pin_in_future(f0, "0", waveforms[i].events[x].time);
            origen_drive_pin_in_future(f1, "1", waveforms[i].events[x].time);
            break;
          default :
            origen_drive_pin_in_future(f0, "0", waveforms[i].events[x].time);
            origen_drive_pin_in_future(f1, "0", waveforms[i].events[x].time);
            break;
        }
        x++;
      }
      free(f0);
      free(f1);
    }
  }
}


/// This is called first upon a simulation start and it will block until it receives
/// a set_timeset message from Origen
void origen_set_period(char * p_in_ns) {
  int p = (int) strtol(p_in_ns, NULL, 10);
  period_in_ns = p;
}


/// Immediately drives the given pin to the given state
static void origen_drive_pin(char * name, char * val) {
  s_vpi_value v = {vpiIntVal, {0}};
  vpiHandle pin;

  char * net = (char *) malloc(6 + strlen(name));
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

  char * data = (char *) malloc(strlen(name) + 3);
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
        char * pin_d = (char *) malloc(strlen(arg1) + 3);
        strcpy(pin_d, arg1);
        strcat(pin_d, "_d");
        origen_drive_pin(pin_d, arg2);
        break;
      // Cycle
      //   3%
      case '3' :
        arg1 = strtok(NULL, "%");
        repeat = strtol(arg1, NULL, 10) - 1;
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


PLI_INT32 origen_cycle_cb(p_cb_data data) {
  UNUSED(data);
  repeat = repeat - 1;
  origen_cycle();
  return 0;
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
  call.obj       = 0;
  call.time      = &time;
  call.value     = 0;
  call.user_data = 0;

  if (repeat) {
    call.cb_rtn    = origen_cycle_cb;
  } else {
    call.cb_rtn    = origen_wait_for_msg;
  }

  vpi_free_object(vpi_register_cb(&call));

  register_waveform_events();
}
